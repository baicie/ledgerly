# Multi-stage build for ledger-server (API + worker binary).
FROM rust:bookworm AS builder
WORKDIR /app
COPY server/ ./
RUN cargo build --release --bin ledger-server

FROM debian:bookworm-slim AS runtime
RUN apt-get update \
  && apt-get install -y --no-install-recommends ca-certificates curl libssl3 \
  && rm -rf /var/lib/apt/lists/* \
  && useradd --system --create-home --uid 10001 ledgerly
WORKDIR /app
COPY --from=builder /app/target/release/ledger-server /usr/local/bin/ledger-server
USER ledgerly
ENV LEDGER_LISTEN=0.0.0.0:8080 \
    OBJECT_STORE_DIR=/var/lib/ledgerly/objects \
    RUST_LOG=info
EXPOSE 8080
VOLUME ["/var/lib/ledgerly/objects"]
HEALTHCHECK --interval=15s --timeout=3s --start-period=10s --retries=3 \
  CMD curl -sf http://127.0.0.1:8080/health/live || exit 1
ENTRYPOINT ["/usr/local/bin/ledger-server"]
CMD ["all"]
