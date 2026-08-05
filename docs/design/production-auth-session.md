# Production Auth Session

* Branch: `codex/production-auth-session`
* ADR: [011 Auth Security Privacy](../adr/011-auth-security-privacy.md)
* Status: Complete

## Goal

Deliver the complete client authentication boundary for Ledgerly: registration,
login, startup session recovery, guarded routes, stable per-install device
identity, automatic access-token refresh, logout revocation, and platform-safe
refresh-token storage.

This work keeps authentication state separate from the local-first ledger. A
user who is signed out cannot enter the application shell, but ledger and sync
data stay in the local database and are not deleted by logout.

## Security Contract

### Native

* Access tokens exist only in `AuthRepository` memory.
* Refresh tokens and the generated device ID are stored with
  `flutter_secure_storage`, backed by Keychain/Keystore on supported mobile
  platforms.
* Refresh requests send the refresh token in JSON. A successful rotation
  replaces the stored token before the refreshed session is exposed.
* Logout calls the authenticated API, revokes the server session, and clears
  local authentication material even when the network call fails.

### Web

* Login and refresh use `sessionMode: cookie`.
* The server sets the refresh token as a `Secure`, `HttpOnly`, `SameSite=Strict`
  cookie scoped to `/v1/auth`; the JSON response omits `refreshToken`.
* Dio sends credentialed browser requests. JavaScript never reads or stores the
  refresh token.
* Only the non-secret device ID is persisted in browser local storage.
* A non-secret signed-out marker suppresses cookie restore after an offline
  logout; a successful login clears the marker.
* Logout revokes the active session and expires the refresh cookie.

### Shared

* Access tokens are attached by an authorized Dio instance.
* A 401 starts one shared refresh operation. Concurrent failed requests await
  that operation and each original request is retried at most once.
* A late 401 from the previous access token reuses the already-rotated token
  instead of rotating again. Session epochs prevent a late refresh response
  from restoring authentication after logout.
* Refresh failure clears the in-memory access token and persisted session
  material and moves routing state to signed out.
* Passwords and tokens are never logged.

## HTTP Contract

Existing native JSON clients remain compatible.

* `POST /v1/auth/login` accepts optional `sessionMode: "cookie"`.
* `POST /v1/auth/refresh` accepts either `refreshToken` or cookie mode. Missing,
  mixed, or unsupported credentials return a stable 400/401 API error.
* Cookie-mode login and refresh omit `refreshToken` from the response body and
  rotate the cookie atomically with the server session.
* PostgreSQL claims a refresh token and creates its replacement in one
  transaction. Only one concurrent rotation can succeed, and tokens idle for
  30 days are rejected.
* `POST /v1/auth/logout` remains access-token authenticated and always expires
  the cookie in its response.
* Authentication request bodies are limited to 16 KiB. Token responses use
  `Cache-Control: no-store` and `Pragma: no-cache`.
* Credentialed CORS uses explicit origins from `CORS_ALLOWED_ORIGINS`; wildcard
  origins are never combined with credentials. Production requires at least
  one HTTPS origin when browser sessions are enabled.

## Client Configuration

The user-selected API origin is persisted on the installation. An optional
`LEDGERLY_API_BASE_URL` Dart define supplies only the initial default and never
overrides a saved value.

* When no saved or embedded origin exists, Debug and Release builds enter
  local-only mode without attempting authentication or synchronization.
* A persisted blank value explicitly selects local-only mode and overrides an
  embedded default.
* Release builds accept HTTPS origins by default, with no user info, query,
  fragment, or non-root path, and reject loopback hosts. Native private-network
  HTTP remains available; native builds may explicitly set
  `LEDGERLY_API_REQUIRE_HTTPS=false` to accept public HTTP. Web builds continue
  to require HTTPS for secure refresh cookies.
* Release Web requires the default HTTPS port because cookies are host-scoped
  but not port-scoped. Native clients may use custom HTTPS ports.
* Signed-out users can change the origin from the authentication screen.
  Signed-in users can change it from Settings, which logs out from the old
  origin before persisting the replacement.
* Clearing the origin switches to local-only mode. The Drift ledger remains
  available and remote-only actions stay inactive.
* Native refresh tokens, Web signed-out markers, and device IDs are namespaced
  by origin. Web refresh cookies are host-only. A successful switch rebuilds
  the endpoint-keyed dependency scope.
* Invalid saved configuration returns to setup instead of silently contacting
  another host.

The server reads:

* `CORS_ALLOWED_ORIGINS`: comma-separated absolute HTTP(S) origins.
* `AUTH_COOKIE_SECURE`: defaults to true in production and false in local
  development. Production rejects false.

## Client States and Routing

`AuthController` owns one of these states: local, restoring, signed out,
authenticating, authenticated, or failure. Local state has no authentication
gateway. Remote startup obtains the stable per-origin device ID and attempts
refresh without touching Drift tokens.

* `/auth` contains login and registration modes.
* Local mode enters the application shell directly. Remote mode redirects all
  application-shell routes to `/auth` unless authenticated.
* An authenticated user visiting `/auth` redirects to `/feed`.
* Guarded deep links retain a validated same-origin return location through
  startup restore and login.
* Settings exposes the current storage mode and optional API origin. Logout is
  available only in remote mode.

## Data Migration

Drift schema version 4 removes `access_token` and `refresh_token` from
`sync_states`. The migration recreates the table with only sync metadata and
does not copy legacy token columns. `LedgerRepository` receives the stable
device ID rather than defining a process-wide constant.

The first sync binds the local ledger to the authenticated remote book and
resets its pull cursor. A later login for a different remote book cannot
silently rebind or upload the retained local ledger.

## Acceptance Tests

* Server tests prove native JSON compatibility, cookie attributes, body token
  omission, cookie refresh rotation, stale-cookie rejection, logout revocation,
  cookie expiry, bounded auth payloads, stable session-mode errors, atomic
  PostgreSQL rotation, idle expiry, and explicit credentialed CORS
  configuration.
* Client unit tests prove endpoint validation, native/web session-store
  semantics, startup restore, failed restore, logout cleanup, one-flight
  refresh, stale-response handling, one retry per request, refresh-failure
  sign-out, and cross-account sync protection.
* Widget tests prove login/register validation, guarded navigation, signed-in
  routing, visible failure feedback, and logout.
* Drift migration tests prove legacy token values are discarded.
* Flutter analyze/test, Rust fmt/clippy/test, Web release build, and a live
  register/login/refresh/logout flow pass before merge.

## Source Notes

Implementation follows the official package and framework guidance:

* flutter_secure_storage package and platform support:
  <https://pub.dev/packages/flutter_secure_storage>
* Dio interceptor and queued-interceptor behavior:
  <https://github.com/cfug/dio/blob/main/dio/README.md#interceptors>
* axum-extra `CookieJar` response-part behavior:
  <https://docs.rs/axum-extra/latest/axum_extra/extract/cookie/struct.CookieJar.html>
* tower-http credentialed CORS configuration:
  <https://docs.rs/tower-http/latest/tower_http/cors/struct.CorsLayer.html>

## Rollback

The server migration adds indexes only, so a previous server image can run
against the migrated database. Client schema version 4 intentionally removes
legacy plaintext token columns; rolling a migrated client installation back to
a schema-v3 binary is unsupported. Release rollback should therefore publish a
forward client fix while the server can be reverted independently.
