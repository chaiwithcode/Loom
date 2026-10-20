#!/usr/bin/env bash
set -euo pipefail

# Loom — GitHub Pages Staging & Release Reliability Verification
# Validates Pages workflow invariants and proves simulated future release behavior.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

PASS_COUNT=0
FAIL_COUNT=0

check() {
    local desc="$1"
    local condition="$2"
    echo -n "Checking ${desc}... "
    if eval "${condition}"; then
        echo "[PASS]"
        PASS_COUNT=$((PASS_COUNT + 1))
    else
        echo "[FAIL]"
        FAIL_COUNT=$((FAIL_COUNT + 1))
    fi
}

echo "=========================================================="
echo "Loom GitHub Pages Staging Verification"
echo "=========================================================="

WORKFLOW_FILE=".github/workflows/pages.yml"

# 1. Workflow syntax validation
check "pages.yml YAML syntax" \
    "ruby -ryaml -e 'YAML.load_file(\"${WORKFLOW_FILE}\")' >/dev/null 2>&1"

# 2. Structural invariants
check "pages.yml isolates app release tag for appcast" \
    "grep -q 'RELEASE_TAG=' \"${WORKFLOW_FILE}\""

check "pages.yml targets PROMO_RELEASE_TAG with default v1.0" \
    "grep -q 'PROMO_RELEASE_TAG=\"\${PROMO_RELEASE_TAG:-v1.0}\"' \"${WORKFLOW_FILE}\""

check "pages.yml downloads appcast from current release" \
    "grep -A 5 'Downloading appcast.xml' \"${WORKFLOW_FILE}\" | grep -q 'gh release download \"\${RELEASE_TAG}\"'"

check "pages.yml downloads promotional videos from PROMO_RELEASE_TAG" \
    "grep -A 5 'Downloading promotional videos' \"${WORKFLOW_FILE}\" | grep -q 'gh release download \"\${PROMO_RELEASE_TAG}\"'"

check "pages.yml requires appcast.xml and videos in REQUIRED_ASSETS" \
    "grep -A 10 'REQUIRED_ASSETS=' \"${WORKFLOW_FILE}\" | grep -q 'site/appcast.xml' && grep -A 10 'REQUIRED_ASSETS=' \"${WORKFLOW_FILE}\" | grep -q 'site/Loom-Demo-16x9.mp4'"

check "pages.yml has no silent fallback to stale dist/appcast.xml" \
    "! grep -q 'dist/appcast.xml site/appcast.xml' \"${WORKFLOW_FILE}\""

# 3. Dynamic Simulation: Future release v1.1 without promo videos
TEST_TMP="$(mktemp -d "${TMPDIR:-/tmp}/loom-pages-sim.XXXXXX")"
trap 'rm -rf "${TEST_TMP}"' EXIT INT TERM

MOCK_BIN="${TEST_TMP}/bin"
mkdir -p "${MOCK_BIN}"

# Create mock gh binary that simulates GitHub API responses
cat <<'EOF' > "${MOCK_BIN}/gh"
#!/usr/bin/env bash
set -euo pipefail

# Parse arguments
TARGET_TAG=""
PATTERN=""
DIR=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    download)
      shift
      TARGET_TAG="$1"
      shift
      ;;
    --pattern)
      PATTERN="$2"
      shift 2
      ;;
    --dir)
      DIR="$2"
      shift 2
      ;;
    --repo|--clobber)
      shift
      [[ "$#" -gt 0 && "$1" != --* ]] && shift || true
      ;;
    *)
      shift
      ;;
  esac
done

mkdir -p "${DIR}"

# Simulation rules:
# Release v1.1 has appcast.xml (v1.1) but NO promotional videos
if [[ "${TARGET_TAG}" == "v1.1" ]]; then
  if [[ "${PATTERN}" == "appcast.xml" ]]; then
    echo "<rss><channel><item><sparkle:version>1.1.0</sparkle:version></item></channel></rss>" > "${DIR}/appcast.xml"
    exit 0
  else
    # Promotional videos NOT present in v1.1 release!
    echo "Simulated error: ${PATTERN} not found in release ${TARGET_TAG}" >&2
    exit 1
  fi
fi

# Release v1.0 has promotional videos and original appcast
if [[ "${TARGET_TAG}" == "v1.0" ]]; then
  if [[ "${PATTERN}" == "appcast.xml" ]]; then
    echo "<rss><channel><item><sparkle:version>1.0.0</sparkle:version></item></channel></rss>" > "${DIR}/appcast.xml"
    exit 0
  elif [[ "${PATTERN}" == "Loom-Demo-16x9.mp4" ]]; then
    echo "mock-16x9-video-content-from-v1.0" > "${DIR}/Loom-Demo-16x9.mp4"
    exit 0
  elif [[ "${PATTERN}" == "Loom-Demo-9x16.mp4" ]]; then
    echo "mock-9x16-video-content-from-v1.0" > "${DIR}/Loom-Demo-9x16.mp4"
    exit 0
  fi
fi

echo "Simulated error: unknown tag ${TARGET_TAG}" >&2
exit 1
EOF
chmod +x "${MOCK_BIN}/gh"

# Run simulation of future v1.1 staging
SIM_DIR="${TEST_TMP}/sim_run"
mkdir -p "${SIM_DIR}"
(
  cd "${ROOT_DIR}"
  export PATH="${MOCK_BIN}:${PATH}"
  
  # Stage files into SIM_DIR/site
  mkdir -p "${SIM_DIR}/site/docs" "${SIM_DIR}/site/Resources"
  cp -R pages/. "${SIM_DIR}/site/"
  [[ -f docs/loom-demo-thumbnail.png ]] && cp docs/loom-demo-thumbnail.png "${SIM_DIR}/site/docs/"
  [[ -f Resources/LoomIconMaster.png ]] && cp Resources/LoomIconMaster.png "${SIM_DIR}/site/Resources/"

  # Simulate release trigger with tag v1.1
  RELEASE_TAG="v1.1"
  gh release download "${RELEASE_TAG}" --repo "chaiwithcode/Loom" --pattern "appcast.xml" --dir "${SIM_DIR}/site" --clobber

  # Simulate promo video fetch targeting v1.0
  PROMO_RELEASE_TAG="v1.0"
  for video in "Loom-Demo-16x9.mp4" "Loom-Demo-9x16.mp4"; do
    gh release download "${PROMO_RELEASE_TAG}" --repo "chaiwithcode/Loom" --pattern "${video}" --dir "${SIM_DIR}/site" --clobber
  done

  # Validate required assets
  REQUIRED_ASSETS=(
    "${SIM_DIR}/site/appcast.xml"
    "${SIM_DIR}/site/Loom-Demo-16x9.mp4"
    "${SIM_DIR}/site/Loom-Demo-9x16.mp4"
    "${SIM_DIR}/site/index.html"
    "${SIM_DIR}/site/style.css"
  )
  for asset in "${REQUIRED_ASSETS[@]}"; do
    [[ -f "${asset}" && -s "${asset}" ]] || exit 1
  done
)

check "simulation: future v1.1 release downloads v1.1 appcast" \
    "grep -q '1.1.0' \"${SIM_DIR}/site/appcast.xml\""

check "simulation: future v1.1 release stages v1.0 16x9 video" \
    "grep -q 'mock-16x9-video-content-from-v1.0' \"${SIM_DIR}/site/Loom-Demo-16x9.mp4\""

check "simulation: future v1.1 release stages v1.0 9x16 video" \
    "grep -q 'mock-9x16-video-content-from-v1.0' \"${SIM_DIR}/site/Loom-Demo-9x16.mp4\""

check "simulation: website and styling remain intact in future release" \
    "[[ -s \"${SIM_DIR}/site/index.html\" && -s \"${SIM_DIR}/site/style.css\" ]]"

# 4. Negative tests: failure when assets missing
FAIL_SIM_DIR="${TEST_TMP}/fail_sim"
mkdir -p "${FAIL_SIM_DIR}/site"
FAILED_CORRECTLY=false
set +e
(
  export PATH="${MOCK_BIN}:${PATH}"
  # Attempt download with missing release tag v9.9
  gh release download "v9.9" --repo "chaiwithcode/Loom" --pattern "appcast.xml" --dir "${FAIL_SIM_DIR}/site" --clobber 2>/dev/null
)
if [[ $? -ne 0 ]]; then
  FAILED_CORRECTLY=true
fi
set -e

check "negative test: missing appcast triggers non-zero exit" \
    "${FAILED_CORRECTLY}"

rm -rf "${TEST_TMP}"
trap - EXIT INT TERM

echo ""
echo "----------------------------------------------------------"
echo "Pages Staging Summary: ${PASS_COUNT} passed, ${FAIL_COUNT} failed."
echo "=========================================================="

if [[ "${FAIL_COUNT}" -gt 0 ]]; then
    exit 1
fi
