#!/usr/bin/env bash
set -euo pipefail

# Loom — Canonical Release CLI Entry Point
# Production-grade local-first release orchestrator using macOS Keychain, notarytool,
# Sparkle 2, GitHub CLI, and Homebrew tap.
#
# Usage:
#   ./scripts/release.sh --check
#   ./scripts/release.sh <version> --prepare [--skip-notarization]
#   ./scripts/release.sh <version> --publish [--yes]

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

# Load optional local release configuration
if [[ -f "${ROOT_DIR}/.release.local" ]]; then
    # shellcheck source=/dev/null
    source "${ROOT_DIR}/.release.local"
fi

# Default notarization profile
NOTARY_PROFILE="${NOTARY_PROFILE:-${NOTARY_KEYCHAIN_PROFILE:-AC_PASSWORD}}"
export NOTARY_PROFILE

print_header() {
    echo "=========================================================="
    echo "Loom Release Orchestrator — Local-First Pipeline"
    echo "=========================================================="
}

print_usage() {
    echo "Usage:"
    echo "  $0 --check"
    echo "      Inspect all prerequisites non-destructively."
    echo ""
    echo "  $0 <version> --prepare [--skip-notarization]"
    echo "      Build, sign, notarize, staple, package canonical ZIP,"
    echo "      compute SHA-256, sign Sparkle appcast, and stage Homebrew cask."
    echo ""
    echo "  $0 <version> --publish [--yes]"
    echo "      Prompt for confirmation, create & push Git tag v<version>,"
    echo "      publish GitHub Release, verify uploaded asset checksum,"
    echo "      synchronize Homebrew tap, and deploy Sparkle update feed."
    echo "=========================================================="
}

# -----------------------------------------------------------------------------
# Mode 1: Check / Preflight Audit
# -----------------------------------------------------------------------------
run_check() {
    print_header
    echo "==> Running non-destructive prerequisite preflight audit..."
    echo ""

    local pass_count=0
    local warn_count=0
    local fail_count=0

    # 1. Git branch & working tree
    echo -n "Checking Git status... "
    local current_branch
    current_branch="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")"
    local git_status_dirty
    git_status_dirty="$(git status --porcelain 2>/dev/null || true)"

    if [[ "${current_branch}" != "main" ]]; then
        echo "[WARN] (on branch '${current_branch}', recommended 'main')"
        ((warn_count++))
    elif [[ -n "${git_status_dirty}" ]]; then
        echo "[WARN] (working tree has uncommitted changes)"
        ((warn_count++))
    else
        echo "[PASS] (branch: main, clean working tree)"
        ((pass_count++))
    fi

    # 2. Version configuration in scripts/build-app.sh
    echo -n "Checking marketing version... "
    local build_ver
    build_ver="$(grep -A 1 'CFBundleShortVersionString' scripts/build-app.sh 2>/dev/null | grep '<string>' | sed -E 's/.*<string>(.*)<\/string>.*/\1/' || true)"
    if [[ -n "${build_ver}" ]]; then
        echo "[PASS] (scripts/build-app.sh specifies ${build_ver})"
        ((pass_count++))
    else
        echo "[FAIL] (unable to read CFBundleShortVersionString from scripts/build-app.sh)"
        ((fail_count++))
    fi

    # 3. Required CLI Tools
    local tools=("swift" "codesign" "xcrun" "ditto" "shasum" "gh" "brew")
    for tool in "${tools[@]}"; do
        echo -n "Checking tool '${tool}'... "
        if command -v "${tool}" >/dev/null 2>&1; then
            echo "[PASS]"
            ((pass_count++))
        else
            echo "[FAIL] ('${tool}' command not found in PATH)"
            ((fail_count++))
        fi
    done

    # 4. Developer ID in macOS Keychain
    echo -n "Checking Developer ID in macOS Keychain... "
    local dev_id
    dev_id="$(security find-identity -v -p codesigning 2>/dev/null | grep "Developer ID Application:" | head -n 1 | sed -E 's/.*"([^"]+)".*/\1/' || true)"
    if [[ -n "${dev_id}" ]]; then
        echo "[PASS] (${dev_id})"
        ((pass_count++))
    else
        echo "[FAIL] (No 'Developer ID Application' certificate found in login Keychain)"
        echo "       Ensure your Apple Developer ID certificate is installed in Keychain Access."
        ((fail_count++))
    fi

    # 5. Apple Notary Profile
    echo -n "Checking notarytool profile '${NOTARY_PROFILE}'... "
    if xcrun notarytool history --keychain-profile "${NOTARY_PROFILE}" >/dev/null 2>&1; then
        echo "[PASS] (Keychain profile '${NOTARY_PROFILE}' validated via notarytool history)"
        ((pass_count++))
    else
        echo "[WARN] (Failed to validate notary profile '${NOTARY_PROFILE}')"
        echo "       Ensure credentials profile exists in Keychain or override via NOTARY_PROFILE."
        ((warn_count++))
    fi

    # 6. Sparkle 2 Ed25519 Private Key in Keychain
    echo -n "Checking Sparkle Ed25519 key in Keychain... "
    local sparkle_bin
    sparkle_bin="$("${ROOT_DIR}/scripts/fetch-sparkle-tools.sh" 2>/dev/null || true)"
    if [[ -x "${sparkle_bin}/generate_keys" ]]; then
        local extracted_pubkey
        extracted_pubkey="$("${sparkle_bin}/generate_keys" -p 2>/dev/null || true)"
        local expected_pubkey
        expected_pubkey="$(grep -A 1 'SUPublicEDKey' Resources/Info.plist 2>/dev/null | grep '<string>' | sed -E 's/.*<string>(.*)<\/string>.*/\1/' || true)"
        if [[ -n "${extracted_pubkey}" && "${extracted_pubkey}" == "${expected_pubkey}" ]]; then
            echo "[PASS] (public key matches Info.plist: ${extracted_pubkey:0:12}...)"
            ((pass_count++))
        elif [[ -n "${extracted_pubkey}" ]]; then
            echo "[WARN] (key found but differs from Info.plist: ${extracted_pubkey} vs ${expected_pubkey})"
            ((warn_count++))
        else
            echo "[FAIL] (No Ed25519 key found in Keychain under https://sparkle-project.org)"
            ((fail_count++))
        fi
    else
        echo "[FAIL] (Sparkle tooling not available)"
        ((fail_count++))
    fi

    # 7. GitHub CLI Authentication
    echo -n "Checking GitHub CLI authentication... "
    if command -v gh >/dev/null 2>&1; then
        if gh auth status >/dev/null 2>&1; then
            local gh_user
            gh_user="$(gh api user -q .login 2>/dev/null || echo "authenticated")"
            echo "[PASS] (logged in as '${gh_user}')"
            ((pass_count++))
        else
            echo "[FAIL] (gh CLI is not authenticated. Run 'gh auth login')"
            ((fail_count++))
        fi
    else
        echo "[FAIL] (gh CLI not installed)"
        ((fail_count++))
    fi

    echo ""
    echo "----------------------------------------------------------"
    echo "Audit Summary: ${pass_count} passed, ${warn_count} warnings, ${fail_count} failures."
    if [[ "${fail_count}" -eq 0 ]]; then
        echo "Status: System is READY for local release operations."
    else
        echo "Status: BLOCKING ERRORS detected. Please address failures above."
        exit 1
    fi
    echo "=========================================================="
}

# -----------------------------------------------------------------------------
# Mode 2: Prepare Release
# -----------------------------------------------------------------------------
run_prepare() {
    local version="$1"
    shift
    local skip_notarization=0
    for arg in "$@"; do
        if [[ "${arg}" == "--skip-notarization" ]]; then
            skip_notarization=1
        fi
    done

    print_header
    echo "==> Preparing release v${version}..."
    echo ""

    # Validate version format (e.g. 1.0 or 0.2.0)
    if [[ ! "${version}" =~ ^[0-9]+\.[0-9]+(\.[0-9]+)?(-[a-zA-Z0-9.]+)?$ ]]; then
        echo "ERROR: Invalid version format: '${version}' (expected X.Y or X.Y.Z)" >&2
        exit 1
    fi

    # Check git tag collision
    if git rev-parse "v${version}" >/dev/null 2>&1; then
        echo "WARNING: Git tag 'v${version}' already exists locally." >&2
        echo "         Local preparation proceeding (publishing will enforce tag uniqueness)." >&2
    fi

    if command -v gh >/dev/null 2>&1; then
        if gh release view "v${version}" >/dev/null 2>&1; then
            echo "WARNING: GitHub Release 'v${version}' already exists remotely." >&2
            echo "         Local preparation proceeding (publishing will enforce release uniqueness)." >&2
        fi
    fi

    # Run tests first
    echo "==> Step 1: Running automated test suite..."
    swift test --disable-sandbox --skip 'testRealAntigravityDiscoverySmokeTest'

    # Build and package
    echo "==> Step 2: Executing release packager pipeline..."
    local pkg_args=("${version}")
    if [[ "${skip_notarization}" -eq 1 ]]; then
        pkg_args+=("--skip-notarization")
    fi
    bash "${ROOT_DIR}/scripts/release-package.sh" "${pkg_args[@]}"

    local canonical_zip="${ROOT_DIR}/dist/Loom-${version}-macOS.zip"
    local canonical_dmg="${ROOT_DIR}/dist/Loom-${version}.dmg"
    local sums_file="${ROOT_DIR}/dist/SHA256SUMS.txt"
    local appcast_file="${ROOT_DIR}/dist/appcast.xml"
    local cask_file="${ROOT_DIR}/dist/chaiwithcode-loom.rb"

    if [[ ! -f "${canonical_zip}" || ! -f "${canonical_dmg}" || ! -f "${sums_file}" ]]; then
        echo "ERROR: Packaging failed to produce canonical release artifacts (ZIP, DMG, or SHA256SUMS.txt)!" >&2
        exit 1
    fi

    local zip_sha
    zip_sha="$(grep "Loom-${version}-macOS.zip" "${sums_file}" 2>/dev/null | awk '{print $1}' || true)"
    local dmg_sha
    dmg_sha="$(grep "Loom-${version}.dmg" "${sums_file}" 2>/dev/null | awk '{print $1}' || true)"

    if [[ -z "${zip_sha}" || -z "${dmg_sha}" ]]; then
        echo "ERROR: SHA256SUMS.txt missing ZIP or DMG entry for version ${version}!" >&2
        exit 1
    fi

    local zip_size
    zip_size="$(wc -c < "${canonical_zip}" | tr -d ' ')"
    local dmg_size
    dmg_size="$(wc -c < "${canonical_dmg}" | tr -d ' ')"

    echo ""
    echo "=========================================================="
    echo "PRE-PUBLISH VERIFICATION SUMMARY"
    echo "=========================================================="
    echo "Version:         ${version}"
    echo "Tag to create:   v${version}"
    echo "Canonical ZIP:   ${canonical_zip}"
    echo "ZIP Size:        ${zip_size} bytes"
    echo "ZIP SHA:         ${zip_sha}"
    echo "Canonical DMG:   ${canonical_dmg}"
    echo "DMG Size:        ${dmg_size} bytes"
    echo "DMG SHA:         ${dmg_sha}"
    if [[ -f "${appcast_file}" ]]; then
        echo "Sparkle Appcast: ${appcast_file} (signed)"
    fi
    if [[ -f "${cask_file}" ]]; then
        echo "Homebrew Cask:   ${cask_file} (staged)"
    fi
    echo ""
    echo "Next Action:"
    echo "  To publish this release to GitHub, Sparkle, and Homebrew, run:"
    echo "    ./scripts/release.sh ${version} --publish"
    echo "=========================================================="
}

# -----------------------------------------------------------------------------
# Mode 3: Publish Release
# -----------------------------------------------------------------------------
run_publish() {
    local version="$1"
    shift
    local auto_yes=0
    for arg in "$@"; do
        if [[ "${arg}" == "--yes" || "${arg}" == "-y" ]]; then
            auto_yes=1
        fi
    done

    print_header
    echo "==> Initiating publish workflow for release v${version}..."
    echo ""

    local dist_dir="${ROOT_DIR}/dist"
    local canonical_zip="${dist_dir}/Loom-${version}-macOS.zip"
    local canonical_dmg="${dist_dir}/Loom-${version}.dmg"
    local sums_file="${dist_dir}/SHA256SUMS.txt"
    local appcast_file="${dist_dir}/appcast.xml"

    # Verify artifacts exist
    if [[ ! -f "${canonical_zip}" || ! -f "${canonical_dmg}" || ! -f "${sums_file}" ]]; then
        echo "ERROR: Prepared release artifacts not found for version ${version}!" >&2
        echo "Required: ${canonical_zip}, ${canonical_dmg}, and ${sums_file}" >&2
        echo "Please run './scripts/release.sh ${version} --prepare' first." >&2
        exit 1
    fi

    # Verify SHA-256 integrity for BOTH ZIP and DMG
    echo "==> Verifying artifact checksum integrity..."
    local expected_zip_sha
    expected_zip_sha="$(grep "Loom-${version}-macOS.zip" "${sums_file}" 2>/dev/null | awk '{print $1}' || true)"
    local computed_zip_sha
    computed_zip_sha="$(shasum -a 256 "${canonical_zip}" | awk '{print $1}')"

    if [[ -z "${expected_zip_sha}" || "${expected_zip_sha}" != "${computed_zip_sha}" ]]; then
        echo "FATAL: Checksum mismatch for ${canonical_zip}!" >&2
        echo "Expected: ${expected_zip_sha}" >&2
        echo "Actual:   ${computed_zip_sha}" >&2
        echo "Artifact may have been corrupted or rebuilt. Aborting publish!" >&2
        exit 1
    fi

    local expected_dmg_sha
    expected_dmg_sha="$(grep "Loom-${version}.dmg" "${sums_file}" 2>/dev/null | awk '{print $1}' || true)"
    local computed_dmg_sha
    computed_dmg_sha="$(shasum -a 256 "${canonical_dmg}" | awk '{print $1}')"

    if [[ -z "${expected_dmg_sha}" || "${expected_dmg_sha}" != "${computed_dmg_sha}" ]]; then
        echo "FATAL: Checksum mismatch for ${canonical_dmg}!" >&2
        echo "Expected: ${expected_dmg_sha}" >&2
        echo "Actual:   ${computed_dmg_sha}" >&2
        echo "Artifact may have been corrupted or rebuilt. Aborting publish!" >&2
        exit 1
    fi

    if gh release view "v${version}" >/dev/null 2>&1; then
        echo "Notice: GitHub Release 'v${version}' already exists remotely; canonical assets will be published/attached."
    fi

    echo ""
    echo "----------------------------------------------------------"
    echo "Target Release:   v${version}"
    echo "Artifact (ZIP):   ${canonical_zip}"
    echo "ZIP SHA:          ${computed_zip_sha}"
    echo "Artifact (DMG):   ${canonical_dmg}"
    echo "DMG SHA:          ${computed_dmg_sha}"
    echo "Destination:      GitHub Releases, Sparkle Pages, Homebrew Tap"
    echo "----------------------------------------------------------"
    echo ""

    # Confirmation prompt
    if [[ "${auto_yes}" -eq 0 ]]; then
        read -r -p "Are you sure you want to publish Loom v${version}? (Type 'yes' to proceed): " confirmation
        if [[ "${confirmation}" != "yes" && "${confirmation}" != "y" ]]; then
            echo "Publish aborted by user."
            exit 0
        fi
    fi

    # Step 1: Create and push git tag if needed
    echo "==> Step 1: Checking Git tag v${version}..."
    if ! git rev-parse "v${version}" >/dev/null 2>&1; then
        echo "    Creating local git tag v${version}..."
        git tag -a "v${version}" -m "Release v${version}"
    fi
    if ! git ls-remote --tags origin "refs/tags/v${version}" | grep -q "refs/tags/v${version}"; then
        echo "    Pushing git tag v${version} to origin..."
        git push origin "v${version}"
    else
        echo "    Git tag v${version} already exists on origin."
    fi

    # Step 2: Publish canonical assets to GitHub Release
    echo "==> Step 2: Publishing release assets to GitHub Release v${version}..."
    local release_assets=("${canonical_zip}" "${canonical_dmg}" "${sums_file}")
    if [[ -f "${appcast_file}" ]]; then
        release_assets+=("${appcast_file}")
    fi

    local notes_file="${dist_dir}/RELEASE_NOTES_v${version}.md"
    if gh release view "v${version}" >/dev/null 2>&1; then
        echo "    Attaching canonical assets to existing GitHub Release v${version}..."
        gh release upload "v${version}" "${release_assets[@]}" --clobber
        if [[ -f "${notes_file}" ]]; then
            gh release edit "v${version}" --notes-file "${notes_file}" || true
        fi
    else
        echo "    Creating new GitHub Release v${version}..."
        if [[ -f "${notes_file}" ]]; then
            gh release create "v${version}" "${release_assets[@]}" \
                --title "v${version}" \
                --notes-file "${notes_file}"
        else
            gh release create "v${version}" "${release_assets[@]}" \
                --title "v${version}" \
                --generate-notes
        fi
    fi

    # Step 3: Verify uploaded assets on GitHub
    echo "==> Step 3: Verifying uploaded assets on GitHub..."
    local zip_download_url="https://github.com/chaiwithcode/Loom/releases/download/v${version}/Loom-${version}-macOS.zip"
    local dmg_download_url="https://github.com/chaiwithcode/Loom/releases/download/v${version}/Loom-${version}.dmg"
    local verify_zip_tmp
    verify_zip_tmp="$(mktemp "${TMPDIR:-/tmp}/loom-verify-zip.XXXXXX.zip")"
    local verify_dmg_tmp
    verify_dmg_tmp="$(mktemp "${TMPDIR:-/tmp}/loom-verify-dmg.XXXXXX.dmg")"
    trap 'rm -f "${verify_zip_tmp}" "${verify_dmg_tmp}"' EXIT INT TERM

    echo "    Downloading and verifying ZIP asset..."
    curl -fsSL "${zip_download_url}" -o "${verify_zip_tmp}"
    local uploaded_zip_sha
    uploaded_zip_sha="$(shasum -a 256 "${verify_zip_tmp}" | awk '{print $1}')"
    if [[ "${uploaded_zip_sha}" != "${computed_zip_sha}" ]]; then
        echo "FATAL: Uploaded ZIP SHA-256 does not match canonical ZIP SHA-256!" >&2
        echo "Canonical: ${computed_zip_sha}" >&2
        echo "Uploaded:  ${uploaded_zip_sha}" >&2
        exit 1
    fi
    echo "==> Verified uploaded ZIP artifact checksum: ${uploaded_zip_sha} (MATCH)"

    echo "    Downloading and verifying DMG asset..."
    curl -fsSL "${dmg_download_url}" -o "${verify_dmg_tmp}"
    local uploaded_dmg_sha
    uploaded_dmg_sha="$(shasum -a 256 "${verify_dmg_tmp}" | awk '{print $1}')"
    if [[ "${uploaded_dmg_sha}" != "${computed_dmg_sha}" ]]; then
        echo "FATAL: Uploaded DMG SHA-256 does not match canonical DMG SHA-256!" >&2
        echo "Canonical: ${computed_dmg_sha}" >&2
        echo "Uploaded:  ${uploaded_dmg_sha}" >&2
        exit 1
    fi
    echo "==> Verified uploaded DMG artifact checksum: ${uploaded_dmg_sha} (MATCH)"

    rm -f "${verify_zip_tmp}" "${verify_dmg_tmp}"
    trap - EXIT INT TERM

    # Step 4: Synchronize Homebrew Tap (strictly with ZIP SHA)
    echo "==> Step 4: Updating Homebrew tap chaiwithcode/homebrew-tap..."
    bash "${ROOT_DIR}/scripts/update-homebrew-tap.sh" "${version}" "${computed_zip_sha}" --sync

    # Step 5: Deploy Sparkle Appcast update on GitHub Pages
    echo "==> Step 5: Triggering and verifying Sparkle Appcast update on GitHub Pages..."
    local pages_failed=0
    local pages_workflow="pages.yml"

    if ! gh workflow view "${pages_workflow}" >/dev/null 2>&1; then
        echo "ERROR: Workflow '${pages_workflow}' not found or inaccessible in GitHub Actions." >&2
        pages_failed=1
    else
        # Verify workflow supports manual dispatch (workflow_dispatch)
        if ! gh workflow view "${pages_workflow}" --yaml 2>/dev/null | grep -q "workflow_dispatch"; then
            echo "ERROR: Workflow '${pages_workflow}' does not configure 'workflow_dispatch' trigger." >&2
            pages_failed=1
        else
            local existing_status
            existing_status="$(gh run list --workflow "${pages_workflow}" --limit 1 --json status -q '.[0].status' 2>/dev/null || true)"
            local run_id=""

            if [[ "${existing_status}" == "queued" || "${existing_status}" == "in_progress" ]]; then
                run_id="$(gh run list --workflow "${pages_workflow}" --limit 1 --json databaseId -q '.[0].databaseId' 2>/dev/null || true)"
                echo "    Detected running Pages workflow (ID: ${run_id}). Watching..."
            else
                echo "    Dispatching GitHub Pages workflow '${pages_workflow}'..."
                if ! gh workflow run "${pages_workflow}"; then
                    echo "ERROR: Failed to dispatch '${pages_workflow}' via gh CLI." >&2
                    pages_failed=1
                else
                    echo "    Waiting for workflow run to start..."
                    sleep 5
                    run_id="$(gh run list --workflow "${pages_workflow}" --limit 1 --json databaseId -q '.[0].databaseId' 2>/dev/null || true)"
                fi
            fi

            if [[ -n "${run_id}" && "${pages_failed}" -eq 0 ]]; then
                echo "    Watching Pages deployment run ${run_id}..."
                if ! gh run watch "${run_id}" --exit-status; then
                    echo "ERROR: Pages workflow run ${run_id} failed!" >&2
                    pages_failed=1
                fi
            fi
        fi
    fi

    # Step 6: Verify public Sparkle Appcast feed
    local appcast_url="https://chaiwithcode.github.io/Loom/appcast.xml"
    echo "==> Step 6: Verifying public Sparkle Appcast feed at ${appcast_url}..."
    local feed_verified=0
    local max_attempts=12
    local attempt=1

    while [[ "${attempt}" -le "${max_attempts}" ]]; do
        echo "    Checking public feed (attempt ${attempt}/${max_attempts})..."
        local feed_content
        feed_content="$(curl -sSL --max-time 10 "${appcast_url}" 2>/dev/null || true)"
        if [[ -n "${feed_content}" ]] && \
           echo "${feed_content}" | grep -q "<sparkle:shortVersionString>${version}</sparkle:shortVersionString>" && \
           echo "${feed_content}" | grep -q "https://github.com/chaiwithcode/Loom/releases/download/v${version}/Loom-${version}-macOS.zip"; then
            feed_verified=1
            echo "==> Public Sparkle feed successfully verified for v${version}."
            break
        fi
        sleep 5
        ((attempt++))
    done

    if [[ "${feed_verified}" -eq 0 ]]; then
        echo "ERROR: Public Sparkle feed did not advertise v${version} within timeout." >&2
        pages_failed=1
    fi

    # Report final publish outcome
    if [[ "${pages_failed}" -ne 0 ]]; then
        echo ""
        echo "=========================================================="
        echo "PARTIAL FAILURE: Release v${version} partially published!"
        echo "  • GitHub Release: SUCCESS (https://github.com/chaiwithcode/Loom/releases/tag/v${version})"
        echo "  • Homebrew Tap:   SUCCESS (chaiwithcode/homebrew-tap)"
        echo "  • Sparkle Pages:  FAILED (Update feed did not update or failed verification)"
        echo ""
        echo "Recovery Steps:"
        echo "  1. Inspect workflow:   gh run list --workflow ${pages_workflow}"
        echo "  2. Manually trigger:   gh workflow run ${pages_workflow}"
        echo "  3. Verify public feed: curl -sSL ${appcast_url} | grep '${version}'"
        echo "=========================================================="
        exit 1
    fi

    echo ""
    echo "=========================================================="
    echo "SUCCESS: Loom v${version} successfully published!"
    echo "Release:   https://github.com/chaiwithcode/Loom/releases/tag/v${version}"
    echo "Appcast:   ${appcast_url}"
    echo "Homebrew:  brew install --cask chaiwithcode/tap/chaiwithcode-loom"
    echo "=========================================================="
}

# -----------------------------------------------------------------------------
# Main CLI Dispatcher
# -----------------------------------------------------------------------------
main() {
    if [[ $# -eq 0 ]]; then
        print_usage
        exit 1
    fi

    case "$1" in
        --check|check)
            run_check
            ;;
        --help|-h|help)
            print_usage
            ;;
        *)
            local ver="$1"
            shift
            if [[ $# -eq 0 ]]; then
                echo "ERROR: Missing action for version ${ver}. Specify --prepare or --publish." >&2
                print_usage
                exit 1
            fi
            case "$1" in
                --prepare|prepare)
                    shift
                    run_prepare "${ver}" "$@"
                    ;;
                --publish|publish)
                    shift
                    run_publish "${ver}" "$@"
                    ;;
                *)
                    echo "ERROR: Unknown command '$1'" >&2
                    print_usage
                    exit 1
                    ;;
            esac
            ;;
    esac
}

main "$@"
