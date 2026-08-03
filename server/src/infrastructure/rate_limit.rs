//! Simple in-process token-bucket rate limit by client IP.

use std::collections::HashMap;
use std::sync::{Arc, Mutex};
use std::task::{Context, Poll};
use std::time::Instant;

use axum::extract::ConnectInfo;
use axum::http::{Request, StatusCode};
use axum::response::{IntoResponse, Response};
use futures_util::future::BoxFuture;
use tower::{Layer, Service};

#[derive(Clone)]
pub struct RateLimitLayer {
    pub rps: u32,
    pub auth_rps: u32,
    state: Arc<Mutex<HashMap<String, Bucket>>>,
}

impl RateLimitLayer {
    pub fn new(rps: u32, auth_rps: u32) -> Self {
        Self {
            rps: rps.max(1),
            auth_rps: auth_rps.max(1),
            state: Arc::new(Mutex::new(HashMap::new())),
        }
    }
}

#[derive(Clone)]
struct Bucket {
    tokens: f64,
    last: Instant,
    capacity: f64,
}

impl<S> Layer<S> for RateLimitLayer {
    type Service = RateLimitService<S>;

    fn layer(&self, inner: S) -> Self::Service {
        RateLimitService {
            inner,
            rps: self.rps,
            auth_rps: self.auth_rps,
            state: self.state.clone(),
        }
    }
}

#[derive(Clone)]
pub struct RateLimitService<S> {
    inner: S,
    rps: u32,
    auth_rps: u32,
    state: Arc<Mutex<HashMap<String, Bucket>>>,
}

impl<S, ReqBody> Service<Request<ReqBody>> for RateLimitService<S>
where
    S: Service<Request<ReqBody>, Response = Response> + Clone + Send + 'static,
    S::Future: Send + 'static,
    S::Error: Send + 'static,
    ReqBody: Send + 'static,
{
    type Response = Response;
    type Error = S::Error;
    type Future = BoxFuture<'static, Result<Self::Response, Self::Error>>;

    fn poll_ready(&mut self, cx: &mut Context<'_>) -> Poll<Result<(), Self::Error>> {
        self.inner.poll_ready(cx)
    }

    fn call(&mut self, req: Request<ReqBody>) -> Self::Future {
        let mut inner = self.inner.clone();
        let state = self.state.clone();
        let path = req.uri().path().to_string();
        let is_auth = path.starts_with("/v1/auth/");
        let limit = if is_auth { self.auth_rps } else { self.rps };
        let ip = req
            .extensions()
            .get::<ConnectInfo<std::net::SocketAddr>>()
            .map(|c| c.0.ip().to_string())
            .unwrap_or_else(|| "unknown".into());
        let key = format!("{ip}:{}", if is_auth { "auth" } else { "api" });

        Box::pin(async move {
            let allowed = {
                let mut map = state.lock().unwrap();
                let now = Instant::now();
                let bucket = map.entry(key).or_insert_with(|| Bucket {
                    tokens: limit as f64,
                    last: now,
                    capacity: limit as f64,
                });
                let elapsed = now.duration_since(bucket.last).as_secs_f64();
                bucket.tokens = (bucket.tokens + elapsed * limit as f64).min(bucket.capacity);
                bucket.last = now;
                if bucket.tokens >= 1.0 {
                    bucket.tokens -= 1.0;
                    true
                } else {
                    false
                }
            };
            if !allowed {
                return Ok((StatusCode::TOO_MANY_REQUESTS, "rate limit exceeded").into_response());
            }
            inner.call(req).await
        })
    }
}
