#!/usr/bin/env bash
# Create and push a v* tag to trigger GitHub Release + GHCR.
#
# Usage:
#   ./scripts/release.sh 0.0.1
#   ./scripts/release.sh v0.0.1
#   ./scripts/release.sh 0.0.1 --dry-run
#   ./scripts/release.sh 0.0.1 --message "First public release"
#
# Env:
#   RELEASE_BRANCH   default: main
#   RELEASE_REMOTE   default: origin
#   SKIP_UP_TO_DATE  if set, skip requiring local branch == remote tip
set -euo pipefail

REMOTE="${RELEASE_REMOTE:-origin}"
BRANCH="${RELEASE_BRANCH:-main}"
DRY_RUN=0
MSG=""
VERSION_RAW=""

usage() {
  sed -n '2,12p' "$0" | sed 's/^# \?//'
  exit "${1:-0}"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help) usage 0 ;;
    --dry-run) DRY_RUN=1; shift ;;
    -m|--message) MSG="${2:?}"; shift 2 ;;
    -*)
      echo "unknown flag: $1" >&2
      usage 1
      ;;
    *)
      if [[ -n "$VERSION_RAW" ]]; then
        echo "unexpected argument: $1" >&2
        usage 1
      fi
      VERSION_RAW="$1"
      shift
      ;;
  esac
done

[[ -n "$VERSION_RAW" ]] || { echo "version required, e.g. 0.0.1" >&2; usage 1; }

# Normalize to tag name vX.Y.Z (optional pre-release / build suffix)
VERSION="${VERSION_RAW#v}"
if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+([.-][0-9A-Za-z.-]+)?$ ]]; then
  echo "invalid semver: $VERSION_RAW (expected X.Y.Z)" >&2
  exit 1
fi
TAG="v${VERSION}"
MSG="${MSG:-Release ${TAG}}"

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "not a git repository" >&2
  exit 1
fi

current="$(git branch --show-current)"
if [[ "$current" != "$BRANCH" ]]; then
  echo "must be on ${BRANCH} (currently: ${current:-detached})" >&2
  echo "  git checkout ${BRANCH} && git pull --ff-only ${REMOTE} ${BRANCH}" >&2
  exit 1
fi

if [[ -n "$(git status --porcelain)" ]]; then
  echo "working tree not clean; commit or stash first" >&2
  git status --short
  exit 1
fi

echo "==> fetch ${REMOTE}"
git fetch "$REMOTE" --tags --prune

if [[ -z "${SKIP_UP_TO_DATE:-}" ]]; then
  local_sha="$(git rev-parse HEAD)"
  remote_sha="$(git rev-parse "${REMOTE}/${BRANCH}")"
  if [[ "$local_sha" != "$remote_sha" ]]; then
    echo "local ${BRANCH} (${local_sha:0:7}) != ${REMOTE}/${BRANCH} (${remote_sha:0:7})" >&2
    echo "  git pull --ff-only ${REMOTE} ${BRANCH}" >&2
    exit 1
  fi
fi

if git rev-parse "$TAG" >/dev/null 2>&1; then
  echo "tag already exists locally: $TAG" >&2
  exit 1
fi

if git ls-remote --exit-code --tags "$REMOTE" "refs/tags/${TAG}" >/dev/null 2>&1; then
  echo "tag already exists on ${REMOTE}: $TAG" >&2
  exit 1
fi

echo "==> release plan"
echo "    branch: ${BRANCH} @ $(git rev-parse --short HEAD)"
echo "    tag:    ${TAG}"
echo "    message:${MSG}"
echo "    effect: push tag → Actions Release (clients + GHCR)"
echo "            deploy is NOT automatic; see docs/runbooks/release.md"

if [[ "$DRY_RUN" -eq 1 ]]; then
  echo "==> dry-run: no tag created"
  exit 0
fi

echo "==> create annotated tag ${TAG}"
git tag -a "$TAG" -m "$MSG"

echo "==> push ${TAG} to ${REMOTE}"
git push "$REMOTE" "$TAG"

owner_repo="$(git remote get-url "$REMOTE" | sed -E 's#.*(github\.com[:/])##;s#\.git$##')"
echo
echo "OK: ${TAG} pushed"
echo "  Actions:  https://github.com/${owner_repo}/actions/workflows/release.yml"
echo "  Release:  https://github.com/${owner_repo}/releases/tag/${TAG}"
echo "  Deploy:   Actions → Release → Run workflow → check deploy"
echo "         or ./scripts/deploy_remote.sh"
