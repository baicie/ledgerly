# Multi-device sync integration tests

This directory exercises `SyncService` against an in-process fake server
across two simulated devices. It covers the seven invariants documented
in `docs/design/phase-3.2-multi-device-sync-integration.md`:

| # | Scenario |
|---|----------|
| 1 | A creates → B pulls |
| 2 | B creates → A pulls |
| 3 | A & B create independently → eventual consistency |
| 4 | Two devices edit the same transaction → conflict surfaces |
| 5 | Cold-start B pulls everything via bootstrap |
| 6 | Replay same `mutationId` is a no-op (idempotency) |
| 7 | Multiple sync rounds advance the cursor monotonically |

## Files

| File | Role |
|------|------|
| `fake_sync_server.dart` | In-memory server that implements the v1 sync contract (push, pull, bootstrap) with idempotency and failure-injection hooks |
| `fake_sync_api.dart` | `SyncApi` subclass that delegates to `FakeSyncServer` |
| `fake_auth_gateway.dart` | `AuthGateway` implementation with a pre-baked session |
| `two_device_harness.dart` | Boots two devices (each with its own in-memory Drift DB) sharing one `FakeSyncServer` |
| `multi_device_sync_test.dart` | The seven scenarios |

## Running locally

The suite is a Flutter **integration test** (it lives next to
`app_test.dart` and `journey_test.dart` so CI's `integration` job picks it
up via `flutter test -d chrome integration_test/`).

```bash
cd apps/client

# Linux / macOS host VM — no device flag needed
flutter test integration_test/sync/

# Headless Flutter VM (matches the CI integration job)
flutter test -d flutter-tester integration_test/sync/

# Windows desktop — requires Developer Mode to be enabled in Windows
# settings so Flutter can create plugin symlinks.
flutter test -d windows integration_test/sync/
```

> The tests are plain `test()` cases (no widget tree), so they don't need
> a Flutter engine — but `flutter test integration_test/...` still
> requires a device target on Windows because of how Flutter bundles
> plugin symlinks for that runner.

## Running in CI

The `integration` job in `.github/workflows/ci.yml` runs the sync suite
against the headless Flutter tester:

```bash
flutter test -d flutter-tester integration_test/sync/
```

The widget-level `app_test.dart` and `journey_test.dart` remain device
integration checks because their provider and platform setup is not
supported by the headless sync runner.
