#!/usr/bin/env bash
# ==============================================================================
# scripts/release-local.sh — Build, Package, and Publish Nectar from Local Machine
#
# Builds Nectar in Release configuration on Apple Silicon macOS, archives the
# iOS application, packages an unsigned IPA, computes SHA-256 checksum,
# publishes the GitHub Release via gh CLI, and updates AltStore source.json on
# the gh-pages branch (same workflow pattern as Ambrosia).
#
# Usage:
#   ./scripts/release-local.sh <version> [--skip-tests] [--dry-run] [--prerelease] [--notes "text"]
#
# Example:
#   ./scripts/release-local.sh 0.2.3 --dry-run
#   ./scripts/release-local.sh 0.2.3
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

APP_NAME="Nectar"
EXPECTED_USER="kyrielie"
EXPECTED_EMAIL="83477979+kyrielie@users.noreply.github.com"
REPO_SLUG="kyrielie/nectar"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info()  { echo -e "${BLUE}==>${NC} $1"; }
log_ok()    { echo -e "    ${GREEN}[✓]${NC} $1"; }
log_warn()  { echo -e "    ${YELLOW}[!]${NC} $1"; }
log_err()   { echo -e "    ${RED}[✗]${NC} $1" >&2; }

# Parse arguments
VERSION=""
SKIP_TESTS=0
DRY_RUN=0
PRERELEASE=0
CUSTOM_NOTES=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --skip-tests)
      SKIP_TESTS=1
      shift
      ;;
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    --prerelease)
      PRERELEASE=1
      shift
      ;;
    --notes)
      CUSTOM_NOTES="${2:?--notes requires a text argument}"
      shift 2
      ;;
    -h|--help)
      cat << 'EOF'
Usage: ./scripts/release-local.sh <version> [options]

Arguments:
  <version>       Semantic version to release (e.g. 0.2.3 or v0.2.3)
  --skip-tests    Skip pre-flight test suite and SwiftLint
  --dry-run       Build IPA and checksum locally without pushing commit, creating release, or updating gh-pages
  --prerelease    Mark release as pre-release on GitHub
  --notes TEXT    Custom release notes string
  -h, --help      Show this help message
EOF
      exit 0
      ;;
    *)
      if [ -z "$VERSION" ]; then
        VERSION="${1#v}"
        shift
      else
        log_err "Unknown argument: $1"
        exit 1
      fi
      ;;
  esac
done

if [ -z "$VERSION" ]; then
  log_err "Release version required (e.g. 0.2.3 or v0.2.3)."
  echo "Run '$0 --help' for usage." >&2
  exit 1
fi

if ! [[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  log_err "Version '$VERSION' must follow semantic versioning (X.Y.Z)."
  exit 1
fi

TAG="v${VERSION}"

echo "======================================================================"
echo " Nectar Local Release Pipeline: ${TAG}"
echo "======================================================================"

# ------------------------------------------------------------------------------
# 1. Identity & Auth Checks
# ------------------------------------------------------------------------------
log_info "Verifying GitHub CLI authentication and Git attribution..."

CURRENT_GH_USER=$(gh api user --jq '.login' 2>/dev/null || echo "")
if [ "$CURRENT_GH_USER" != "$EXPECTED_USER" ]; then
  log_warn "Active gh account is '$CURRENT_GH_USER' (expected '$EXPECTED_USER'). Switching..."
  gh auth switch --user "$EXPECTED_USER"
  gh auth setup-git
  log_ok "Switched gh active account to '$EXPECTED_USER'."
else
  log_ok "gh CLI authenticated as '$EXPECTED_USER'."
fi

git config user.name "$EXPECTED_USER"
git config user.email "$EXPECTED_EMAIL"
log_ok "Git author config aligned to $EXPECTED_USER <$EXPECTED_EMAIL>."

# ------------------------------------------------------------------------------
# 2. Pre-flight Tests & Linting
# ------------------------------------------------------------------------------
if [ "$SKIP_TESTS" -eq 1 ]; then
  log_warn "Skipping pre-flight tests (--skip-tests specified)."
else
  log_info "Regenerating Xcode project from project.yml (xcodegen generate)..."
  xcodegen generate >/dev/null
  log_info "Running test suite and SwiftLint (./test.sh -q)..."
  if ! ./test.sh -q; then
    log_err "Tests or SwiftLint failed. Aborting release."
    exit 1
  fi
  log_ok "All tests and SwiftLint passed."
fi

# ------------------------------------------------------------------------------
# 3. Version & Project Synchronization
# ------------------------------------------------------------------------------
log_info "Synchronizing Xcode project for release ${TAG}..."
xcodegen generate >/dev/null
log_ok "Xcode project regenerated."

# ------------------------------------------------------------------------------
# 4. Release Build (iOS Archive -> Unsigned IPA)
# ------------------------------------------------------------------------------
BUILD_DIR="${TMPDIR:-/tmp}/nectar-release-build"
ARCHIVE_PATH="$BUILD_DIR/Nectar.xcarchive"
PAYLOAD_DIR="$BUILD_DIR/Payload"
DIST_DIR="$REPO_ROOT/dist"
IPA_PATH="$DIST_DIR/Nectar-unsigned.ipa"
SHA_PATH="$DIST_DIR/Nectar-unsigned.ipa.sha256"

rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR" "$DIST_DIR"

log_info "Reading project version settings..."
base_project_version=$(xcodebuild -showBuildSettings \
  -project NetNewsWire.xcodeproj \
  -scheme Nectar-iOS \
  -destination "generic/platform=iOS" 2>/dev/null \
  | grep -m1 '^\s*CURRENT_PROJECT_VERSION' | awk -F'= ' '{print $2}')
base_project_version="${base_project_version:-7108}"

# Fetch highest buildVersion suffix from origin/gh-pages source.json
highest_build_suffix=$(python3 -c "
import json, subprocess
try:
    raw = subprocess.check_output(['git', 'show', 'origin/gh-pages:source.json'], stderr=subprocess.DEVNULL)
    data = json.loads(raw)
    suffixes = [int(v['buildVersion'].split('.')[-1]) for app in data.get('apps', []) for v in app.get('versions', []) if '.' in v.get('buildVersion', '')]
    print(max(suffixes) if suffixes else 0)
except Exception:
    print(0)
" 2>/dev/null || echo 0)

next_suffix=$((highest_build_suffix + 1))
build_version="${base_project_version}.${next_suffix}"
log_ok "Build version determined: ${build_version} (base: ${base_project_version}, run: ${next_suffix})"

log_info "Building release archive (MARKETING_VERSION=${VERSION}, CURRENT_PROJECT_VERSION=${build_version})..."
xcodebuild \
  -project NetNewsWire.xcodeproj \
  -scheme Nectar-iOS \
  -destination "generic/platform=iOS" \
  -archivePath "$ARCHIVE_PATH" \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CURRENT_PROJECT_VERSION="$build_version" \
  MARKETING_VERSION="$VERSION" \
  CODE_SIGN_IDENTITY="" \
  AD_HOC_CODE_SIGNING_ALLOWED=YES \
  archive >/dev/null

APP_PATH=$(find "$ARCHIVE_PATH/Products/Applications" -maxdepth 1 -name "*.app" -print -quit)
if [ -z "$APP_PATH" ] || [ ! -d "$APP_PATH" ]; then
  log_err "No .app found in $ARCHIVE_PATH/Products/Applications."
  exit 1
fi
log_ok "Built iOS app bundle: $APP_PATH"

log_info "Packaging unsigned IPA into $IPA_PATH..."
mkdir -p "$PAYLOAD_DIR/Payload"
cp -R "$APP_PATH" "$PAYLOAD_DIR/Payload/"
rm -f "$IPA_PATH"
(cd "$PAYLOAD_DIR" && zip -qr "$IPA_PATH" "Payload")
log_ok "Created IPA: $(du -sh "$IPA_PATH" | cut -f1)"

log_info "Computing SHA-256 checksum..."
shasum -a 256 "$IPA_PATH" > "$SHA_PATH"
SHA_VAL=$(awk '{print $1}' "$SHA_PATH")
log_ok "SHA-256: $SHA_VAL"

min_os_version=$(xcodebuild -showBuildSettings \
  -project NetNewsWire.xcodeproj \
  -scheme Nectar-iOS \
  -destination "generic/platform=iOS" \
  MARKETING_VERSION="$VERSION" 2>/dev/null \
  | grep -m1 '^\s*IPHONEOS_DEPLOYMENT_TARGET' | awk -F'= ' '{print $2}')
min_os_version="${min_os_version:-17.0}"
log_ok "Minimum deployment target: iOS ${min_os_version}"

# ------------------------------------------------------------------------------
# 5. Dry-Run Check
# ------------------------------------------------------------------------------
if [ "$DRY_RUN" -eq 1 ]; then
  log_ok "Dry run complete! Release assets available locally:"
  echo "    IPA:           $IPA_PATH"
  echo "    SHA256:        $SHA_PATH"
  echo "    Build Version: $build_version"
  echo "    Min iOS:       $min_os_version"
  rm -rf "$BUILD_DIR"
  exit 0
fi

# ------------------------------------------------------------------------------
# 6. Git Tagging & GitHub Release Publishing
# ------------------------------------------------------------------------------
if git rev-parse -q --verify "refs/tags/$TAG" >/dev/null; then
  log_ok "Git tag $TAG already exists locally."
else
  log_info "Creating git tag ${TAG}..."
  git tag "$TAG"
  git push origin "refs/tags/$TAG"
  log_ok "Pushed tag $TAG to origin."
fi

log_info "Publishing GitHub Release ${TAG}..."
prerelease_flag=""
if [ "$PRERELEASE" -eq 1 ]; then
  prerelease_flag="--prerelease"
fi

if gh release view "$TAG" >/dev/null 2>&1; then
  log_info "Release $TAG already exists on GitHub. Uploading assets with --clobber..."
  gh release upload "$TAG" "$IPA_PATH" "$SHA_PATH" --clobber
  log_ok "Uploaded assets to existing release $TAG."
else
  log_info "Creating new GitHub Release $TAG..."
  if [ -n "$CUSTOM_NOTES" ]; then
    gh release create "$TAG" "$IPA_PATH" "$SHA_PATH" \
      --title "$TAG" \
      --notes "$CUSTOM_NOTES" \
      $prerelease_flag
  else
    gh release create "$TAG" "$IPA_PATH" "$SHA_PATH" \
      --title "$TAG" \
      --generate-notes \
      $prerelease_flag
  fi
  log_ok "Created GitHub Release $TAG."
fi

# ------------------------------------------------------------------------------
# 7. Update AltStore source.json on gh-pages
# ------------------------------------------------------------------------------
log_info "Updating AltStore source.json on gh-pages branch..."
PAGES_DIR="${TMPDIR:-/tmp}/nectar-gh-pages"
rm -rf "$PAGES_DIR"

ORIGIN_URL=$(git remote get-url origin)
git clone --branch gh-pages --single-branch "$ORIGIN_URL" "$PAGES_DIR" >/dev/null 2>&1 || {
  log_warn "Failed to clone existing gh-pages branch. Initializing fresh gh-pages branch..."
  mkdir -p "$PAGES_DIR"
  (cd "$PAGES_DIR" && git init -b gh-pages && git remote add origin "$ORIGIN_URL")
}

release_json=$(gh api "repos/${REPO_SLUG}/releases/tags/${TAG}")
release_date=$(echo "$release_json" | jq -r '.published_at')
release_body=$(echo "$release_json" | jq -r '.body // ""')
download_url="https://github.com/${REPO_SLUG}/releases/download/${TAG}/Nectar-unsigned.ipa"
size_bytes=$(stat -f %z "$IPA_PATH" 2>/dev/null || wc -c < "$IPA_PATH" | tr -d ' ')

VERSION="$VERSION" \
BUILD_VERSION="$build_version" \
RELEASE_DATE="$release_date" \
RELEASE_NOTES="$release_body" \
DOWNLOAD_URL="$download_url" \
SIZE_BYTES="$size_bytes" \
MIN_OS_VERSION="$min_os_version" \
MARKETING_VERSION_DISPLAY="$VERSION" \
NOTES_ONLY_REFRESH="false" \
python3 "$REPO_ROOT/scripts/update_source.py" \
  --template="$REPO_ROOT/appstore/source.template.json" \
  --existing="$PAGES_DIR/source.json" \
  --output="$PAGES_DIR/source.json" \
  --screenshots-dir="$REPO_ROOT/appstore/screenshots"

if [ -f "$REPO_ROOT/appstore/icon.png" ]; then
  cp "$REPO_ROOT/appstore/icon.png" "$PAGES_DIR/icon.png"
fi

if [ -d "$REPO_ROOT/appstore/screenshots" ] && [ "$(ls -A "$REPO_ROOT/appstore/screenshots" 2>/dev/null)" ]; then
  rm -rf "$PAGES_DIR/screenshots"
  cp -R "$REPO_ROOT/appstore/screenshots" "$PAGES_DIR/screenshots"
fi

cd "$PAGES_DIR"
git add -A
if ! git diff --cached --quiet; then
  git config user.name "$EXPECTED_USER"
  git config user.email "$EXPECTED_EMAIL"
  git commit -m "Publish ${TAG} to source.json"
  for attempt in 1 2 3; do
    if git push origin gh-pages >/dev/null 2>&1; then
      log_ok "Successfully pushed updated source.json to gh-pages."
      break
    fi
    log_warn "Push rejected (attempt $attempt); rebasing onto gh-pages..."
    git pull --rebase origin gh-pages >/dev/null 2>&1 || true
  done
else
  log_ok "source.json already up-to-date on gh-pages."
fi

cd "$REPO_ROOT"
rm -rf "$BUILD_DIR" "$PAGES_DIR"

echo "======================================================================"
echo -e "${GREEN} Release ${TAG} published successfully!${NC}"
echo " Release URL: https://github.com/${REPO_SLUG}/releases/tag/${TAG}"
echo " Asset:       $IPA_PATH"
echo " SHA-256:     $SHA_VAL"
echo " AltStore:    https://kyrielie.github.io/nectar/source.json"
echo "======================================================================"
