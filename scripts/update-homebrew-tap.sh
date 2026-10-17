#!/usr/bin/env bash
set -euo pipefail

# Loom — Automated Homebrew Tap Cask Generator & Tap Sync
# Generates Casks/chaiwithcode-loom.rb and synchronizes chaiwithcode/homebrew-tap.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="${1:-${VERSION:-1.0}}"
SHA256="${2:-${SHA256:-}}"
SYNC_TAP="${SYNC_TAP:-0}"

for arg in "$@"; do
    if [[ "${arg}" == "--sync" ]]; then
        SYNC_TAP=1
    fi
done

DIST_DIR="${ROOT_DIR}/dist"

if [[ -z "${SHA256}" || "${SHA256}" == "--sync" ]]; then
    SHA_FILE="${DIST_DIR}/Loom-${VERSION}-macOS.zip.sha256"
    if [[ -f "${SHA_FILE}" ]]; then
        SHA256=$(awk '{print $1}' "${SHA_FILE}")
    else
        echo "ERROR: SHA-256 not provided and ${SHA_FILE} not found." >&2
        echo "Usage: $0 <version> [sha256] [--sync]" >&2
        exit 1
    fi
fi

generate_cask_ruby() {
    local ver="$1"
    local sha="$2"
    cat <<EOF
cask "chaiwithcode-loom" do
  version "${ver}"
  sha256 "${sha}"

  url "https://github.com/chaiwithcode/Loom/releases/download/v#{version}/Loom-#{version}-macOS.zip"
  name "Loom"
  desc "Monitor for local AI coding agents"
  homepage "https://github.com/chaiwithcode/Loom"

  auto_updates true
  depends_on macos: :sonoma

  app "Loom.app"

  zap trash: [
    "~/Library/Application Support/com.chaiwithcode.loom",
    "~/Library/Caches/com.chaiwithcode.loom",
    "~/Library/HTTPStorages/com.chaiwithcode.loom",
    "~/Library/Preferences/com.chaiwithcode.loom.plist",
    "~/Library/Saved Application State/com.chaiwithcode.loom.savedState",
  ]
end
EOF
}

# 1. Stage in dist/
mkdir -p "${DIST_DIR}"
LOCAL_DIST_CASK="${DIST_DIR}/chaiwithcode-loom.rb"
generate_cask_ruby "${VERSION}" "${SHA256}" > "${LOCAL_DIST_CASK}"
echo "==> Staged local cask at ${LOCAL_DIST_CASK}"

# 2. Stage in homebrew-tap/ working tree if present
LOCAL_REPO_TAP="${ROOT_DIR}/homebrew-tap"
if [[ -d "${LOCAL_REPO_TAP}/Casks" ]]; then
    generate_cask_ruby "${VERSION}" "${SHA256}" > "${LOCAL_REPO_TAP}/Casks/chaiwithcode-loom.rb"
    echo "==> Staged cask in local workspace at ${LOCAL_REPO_TAP}/Casks/chaiwithcode-loom.rb"
fi

# 3. Synchronize with remote chaiwithcode/homebrew-tap if --sync is requested
if [[ "${SYNC_TAP}" == "1" ]] || [[ -n "${HOMEBREW_TAP_TOKEN:-}" ]]; then
    echo "==> Synchronizing with remote GitHub tap chaiwithcode/homebrew-tap..."
    TAP_WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/loom-tap-sync.XXXXXX")"
    trap 'rm -rf "${TAP_WORK_DIR}"' EXIT INT TERM

    # Check if chaiwithcode/homebrew-tap exists on GitHub
    TAP_REPO="chaiwithcode/homebrew-tap"
    REPO_EXISTS=0
    if command -v gh >/dev/null 2>&1; then
        if gh repo view "${TAP_REPO}" >/dev/null 2>&1; then
            REPO_EXISTS=1
        fi
    fi

    if [[ "${REPO_EXISTS}" == "0" ]]; then
        echo "==> Tap repository ${TAP_REPO} does not exist remotely. Creating..."
        if command -v gh >/dev/null 2>&1; then
            gh repo create "${TAP_REPO}" --public --description "Official Homebrew tap for ChaiWithCode projects"
        else
            echo "ERROR: GitHub CLI 'gh' is required to create ${TAP_REPO}" >&2
            exit 1
        fi
        
        # Clone newly created repo
        git clone "https://github.com/${TAP_REPO}.git" "${TAP_WORK_DIR}/homebrew-tap"
        cd "${TAP_WORK_DIR}/homebrew-tap"
        
        # Initialize default branch and copy staged template files
        mkdir -p Casks
        if [[ -f "${LOCAL_REPO_TAP}/README.md" ]]; then
            cp "${LOCAL_REPO_TAP}/README.md" .
        fi
        generate_cask_ruby "${VERSION}" "${SHA256}" > Casks/chaiwithcode-loom.rb
        git checkout -b main 2>/dev/null || true
        git add .
        git commit -m "feat(init): initialize tap with Loom ${VERSION}"
        git push -u origin main
        echo "==> Initialized and pushed ${TAP_REPO} with Loom ${VERSION} cask."
    else
        # Existing repository
        if [[ -n "${HOMEBREW_TAP_TOKEN:-}" ]]; then
            git clone "https://x-access-token:${HOMEBREW_TAP_TOKEN}@github.com/${TAP_REPO}.git" "${TAP_WORK_DIR}/homebrew-tap"
        else
            git clone "https://github.com/${TAP_REPO}.git" "${TAP_WORK_DIR}/homebrew-tap"
        fi
        cd "${TAP_WORK_DIR}/homebrew-tap"

        mkdir -p Casks
        generate_cask_ruby "${VERSION}" "${SHA256}" > Casks/chaiwithcode-loom.rb

        if git diff --quiet Casks/chaiwithcode-loom.rb; then
            echo "==> Cask in ${TAP_REPO} is already up-to-date with version ${VERSION}."
            exit 0
        fi

        # Check if direct push to main succeeds, otherwise create PR
        git add Casks/chaiwithcode-loom.rb
        git commit -m "chore(cask): update Loom to ${VERSION}"
        
        if git push origin main 2>/dev/null; then
            echo "==> Directly updated Casks/chaiwithcode-loom.rb on main in ${TAP_REPO}."
        else
            echo "==> Direct push failed or branch protected; opening Pull Request..."
            BRANCH_NAME="update-loom-${VERSION}"
            git checkout -b "${BRANCH_NAME}"
            git push -u origin "${BRANCH_NAME}"
            if command -v gh >/dev/null 2>&1; then
                gh pr create \
                    --repo "${TAP_REPO}" \
                    --title "Update Loom to ${VERSION}" \
                    --body "Automated release update for Loom version \`${VERSION}\`.
- Artifact: \`Loom-${VERSION}-macOS.zip\`
- SHA-256: \`${SHA256}\`
- Release URL: https://github.com/chaiwithcode/Loom/releases/tag/v${VERSION}" \
                    --base main \
                    --head "${BRANCH_NAME}"
            fi
            echo "==> Successfully created Pull Request in ${TAP_REPO}."
        fi
    fi
fi
