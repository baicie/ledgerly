#!/usr/bin/env bash

set -euo pipefail

die() {
  echo "Android signing verification failed: $*" >&2
  exit 1
}

if [[ $# -lt 2 ]]; then
  die "usage: $0 <expected-certificate-sha256-file> <apk> [<apk> ...]"
fi

fingerprint_file="$1"
shift

[[ -s "$fingerprint_file" ]] || die "missing certificate fingerprint file: $fingerprint_file"

expected_fingerprint="$(tr -d '[:space:]:-' < "$fingerprint_file" | tr '[:lower:]' '[:upper:]')"
[[ "$expected_fingerprint" =~ ^[0-9A-F]{64}$ ]] || \
  die "pinned certificate fingerprint must contain exactly 64 hexadecimal characters"

if [[ -n "${APKSIGNER:-}" ]]; then
  apksigner="$APKSIGNER"
elif command -v apksigner >/dev/null 2>&1; then
  apksigner="$(command -v apksigner)"
else
  android_sdk_root="${ANDROID_SDK_ROOT:-${ANDROID_HOME:-}}"
  [[ -n "$android_sdk_root" ]] || die "set APKSIGNER or ANDROID_SDK_ROOT"
  apksigner="$(find "$android_sdk_root/build-tools" -type f -name apksigner 2>/dev/null | sort | tail -n 1)"
fi

[[ -n "${apksigner:-}" && -x "$apksigner" ]] || die "could not find an executable apksigner"

for apk in "$@"; do
  [[ -s "$apk" ]] || die "missing or empty APK: $apk"

  if ! verification_output="$("$apksigner" verify --verbose --print-certs "$apk")"; then
    die "apksigner rejected $apk"
  fi

  signer_digests="$(
    printf '%s\n' "$verification_output" |
      awk '
        {
          lowercase_line = tolower($0)
          marker = "certificate sha-256 digest:"
          marker_position = index(lowercase_line, marker)
          if (marker_position > 0) {
            print substr($0, marker_position + length(marker))
          }
        }
      '
  )"
  signer_count="$(printf '%s\n' "$signer_digests" | awk 'NF { count++ } END { print count + 0 }')"
  if [[ "$signer_count" -ne 1 ]]; then
    printf 'apksigner output for %s:\n%s\n' "$apk" "$verification_output" >&2
    die "$apk must have exactly one signing certificate; found $signer_count"
  fi

  actual_fingerprint="$(printf '%s' "$signer_digests" | tr -d '[:space:]:-' | tr '[:lower:]' '[:upper:]')"
  [[ "$actual_fingerprint" =~ ^[0-9A-F]{64}$ ]] || die "apksigner returned an invalid SHA-256 digest for $apk"
  [[ "$actual_fingerprint" == "$expected_fingerprint" ]] || \
    die "$apk certificate is $actual_fingerprint; expected $expected_fingerprint"

  printf 'Verified Android signing certificate for %s: %s\n' "$apk" "$actual_fingerprint"
done
