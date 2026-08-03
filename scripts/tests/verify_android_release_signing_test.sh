#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
verifier="$repo_root/scripts/verify_android_release_signing.sh"
test_dir="$(mktemp -d)"
trap 'rm -rf "$test_dir"' EXIT

expected_digest="0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF"
printf '%s\n' "$expected_digest" > "$test_dir/expected.sha256"
printf 'fake apk\n' > "$test_dir/app.apk"

cat > "$test_dir/apksigner" <<'FAKE_APKSIGNER'
#!/usr/bin/env bash
set -euo pipefail

if [[ "${FAKE_VERIFY_FAILURE:-false}" == "true" ]]; then
  exit 1
fi

printf 'Verifies\n'
printf '  Signer #1 certificate sha-256 digest: %s\n' "${FAKE_DIGEST:?}"
if [[ "${FAKE_SECOND_SIGNER:-false}" == "true" ]]; then
  printf '  Signer #2 certificate SHA-256 digest: %s\n' "$FAKE_DIGEST"
fi
FAKE_APKSIGNER
chmod 700 "$test_dir/apksigner"

run_verifier() {
  APKSIGNER="$test_dir/apksigner" \
    FAKE_DIGEST="${FAKE_DIGEST:-$expected_digest}" \
    FAKE_SECOND_SIGNER="${FAKE_SECOND_SIGNER:-false}" \
    FAKE_VERIFY_FAILURE="${FAKE_VERIFY_FAILURE:-false}" \
    "$verifier" "$test_dir/expected.sha256" "$test_dir/app.apk"
}

run_verifier >/dev/null

if FAKE_DIGEST="FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF" run_verifier >/dev/null 2>&1; then
  echo "expected a mismatched certificate digest to fail" >&2
  exit 1
fi

if FAKE_SECOND_SIGNER=true run_verifier >/dev/null 2>&1; then
  echo "expected an APK with multiple signers to fail" >&2
  exit 1
fi

printf 'not-a-digest\n' > "$test_dir/expected.sha256"
if run_verifier >/dev/null 2>&1; then
  echo "expected an invalid pinned digest to fail" >&2
  exit 1
fi
printf '%s\n' "$expected_digest" > "$test_dir/expected.sha256"

if FAKE_VERIFY_FAILURE=true run_verifier >/dev/null 2>&1; then
  echo "expected apksigner verification failure to fail" >&2
  exit 1
fi

if APKSIGNER="$test_dir/apksigner" FAKE_DIGEST="$expected_digest" \
  "$verifier" "$test_dir/expected.sha256" "$test_dir/missing.apk" >/dev/null 2>&1; then
  echo "expected a missing APK to fail" >&2
  exit 1
fi

echo "Android release signing verifier tests passed"
