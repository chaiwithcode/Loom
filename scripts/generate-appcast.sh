#!/usr/bin/env bash
set -euo pipefail

# Loom — Generate and validate Sparkle 2 appcast feed
# Uses official Sparkle generate_appcast tool and verifies feed integrity.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BIN_DIR="$("${ROOT_DIR}/scripts/fetch-sparkle-tools.sh")"

VERSION="${1:-${VERSION:-1.0}}"
DIST_DIR="${2:-${DIST_DIR:-${ROOT_DIR}/dist}}"
OUTPUT_APPCAST="${3:-${OUTPUT_APPCAST:-${DIST_DIR}/appcast.xml}}"
BASE_URL="https://github.com/chaiwithcode/Loom/releases/download/v${VERSION}/"

CANONICAL_ZIP="${DIST_DIR}/Loom-${VERSION}-macOS.zip"

if [[ ! -f "${CANONICAL_ZIP}" ]]; then
    echo "Error: Canonical release artifact not found at: ${CANONICAL_ZIP}" >&2
    echo "Please build and package the release ZIP before generating the appcast." >&2
    exit 1
fi

STAGING_DIR="$(mktemp -d "${TMPDIR:-/tmp}/loom-appcast-staging.XXXXXX")"
trap 'rm -rf "${STAGING_DIR}"' EXIT INT TERM

cp -p "${CANONICAL_ZIP}" "${STAGING_DIR}/"

# Include release notes if available (Sparkle attaches matching .md/.html notes)
if [[ -f "${DIST_DIR}/RELEASE_NOTES_v${VERSION}.md" ]]; then
    cp -p "${DIST_DIR}/RELEASE_NOTES_v${VERSION}.md" "${STAGING_DIR}/Loom-${VERSION}-macOS.md"
elif [[ -f "${ROOT_DIR}/docs/RELEASE_NOTES_v${VERSION}.md" ]]; then
    cp -p "${ROOT_DIR}/docs/RELEASE_NOTES_v${VERSION}.md" "${STAGING_DIR}/Loom-${VERSION}-macOS.md"
fi

# Clean any legacy sparkle:releaseNotesLink elements from existing appcast
if [[ -f "${OUTPUT_APPCAST}" ]]; then
    python3 - "${OUTPUT_APPCAST}" <<'EOF'
import sys
import xml.etree.ElementTree as ET

path = sys.argv[1]
try:
    tree = ET.parse(path)
    root = tree.getroot()
    changed = False
    for item in root.findall(".//item"):
        for elem in item.findall("{http://www.andymatuschak.org/xml-namespaces/sparkle}releaseNotesLink"):
            item.remove(elem)
            changed = True
    if changed:
        tree.write(path, encoding="utf-8", xml_declaration=True)
except Exception:
    pass
EOF
fi

echo "==> Generating Sparkle appcast for version ${VERSION}..."

if [[ -n "${SPARKLE_PRIVATE_KEY:-}" ]]; then
    echo "==> Signing appcast with private EdDSA key from environment..."
    printf '%s' "${SPARKLE_PRIVATE_KEY}" | "${BIN_DIR}/generate_appcast" \
        --ed-key-file - \
        --download-url-prefix "${BASE_URL}" \
        --full-release-notes-url "https://github.com/chaiwithcode/Loom/releases" \
        --embed-release-notes \
        -o "${OUTPUT_APPCAST}" \
        "${STAGING_DIR}"
else
    echo "==> Signing appcast with private EdDSA key from Keychain..."
    "${BIN_DIR}/generate_appcast" \
        --download-url-prefix "${BASE_URL}" \
        --full-release-notes-url "https://github.com/chaiwithcode/Loom/releases" \
        --embed-release-notes \
        -o "${OUTPUT_APPCAST}" \
        "${STAGING_DIR}"
fi

echo "==> Validating generated appcast XML..."
python3 - "${OUTPUT_APPCAST}" "${VERSION}" <<'EOF'
import sys
import xml.etree.ElementTree as ET

appcast_path = sys.argv[1]
expected_version = sys.argv[2]

try:
    tree = ET.parse(appcast_path)
    root = tree.getroot()
except Exception as e:
    sys.exit(f"ERROR: Failed to parse {appcast_path} as XML: {e}")

channel = root.find("channel")
if channel is None:
    sys.exit("ERROR: <channel> element not found in appcast.xml")

items = channel.findall("item")
if not items:
    sys.exit("ERROR: No <item> entries found in appcast.xml")

sparkle_ns = "http://www.andymatuschak.org/xml-namespaces/sparkle"

found = False
for item in items:
    enclosure = item.find("enclosure")
    if enclosure is None:
        continue

    url = enclosure.get("url", "")
    length = enclosure.get("length", "")
    ed_sig = enclosure.get(f"{{{sparkle_ns}}}edSignature", "")
    short_ver = enclosure.get(f"{{{sparkle_ns}}}shortVersionString", "")
    ver = enclosure.get(f"{{{sparkle_ns}}}version", "")

    if not url.startswith("https://github.com/chaiwithcode/Loom/releases/download/"):
        sys.exit(f"ERROR: Enclosure URL does not match release pattern: {url}")
    if not url.endswith(f"Loom-{expected_version}-macOS.zip"):
        continue

    if not ed_sig:
        sys.exit("ERROR: Missing sparkle:edSignature attribute on enclosure")
    if not length or int(length) <= 0:
        sys.exit(f"ERROR: Invalid enclosure length: {length}")

    # Verify no broken releaseNotesLink pointing to Pages markdown
    rel_notes_link = item.find(f"{{{sparkle_ns}}}releaseNotesLink")
    if rel_notes_link is not None and rel_notes_link.text:
        sys.exit(f"ERROR: Disallowed sparkle:releaseNotesLink found: {rel_notes_link.text}")

    # Verify fullReleaseNotesLink points to GitHub Releases
    full_notes_link = item.find(f"{{{sparkle_ns}}}fullReleaseNotesLink")
    if full_notes_link is None or full_notes_link.text != "https://github.com/chaiwithcode/Loom/releases":
        sys.exit(f"ERROR: Missing or invalid sparkle:fullReleaseNotesLink (expected https://github.com/chaiwithcode/Loom/releases)")

    # Verify embedded description is present with markdown format
    desc = item.find("description")
    if desc is None or not (desc.text and desc.text.strip()):
        sys.exit("ERROR: Missing embedded <description> in appcast item")
    desc_format = desc.get(f"{{{sparkle_ns}}}format", "")
    if desc_format != "markdown":
        sys.exit(f"ERROR: Expected description format='markdown', found '{desc_format}'")

    found = True
    print(f"  Verified appcast item: version={short_ver or ver} (build={ver})")
    print(f"  Enclosure URL: {url}")
    print(f"  Length: {length} bytes")
    print(f"  EdDSA Signature: {ed_sig[:16]}... (present)")
    print(f"  Full Release Notes Link: {full_notes_link.text}")
    print(f"  Embedded Description: {len(desc.text)} characters (markdown)")
    break

if not found:
    sys.exit(f"ERROR: No valid enclosure found for version {expected_version}")

print("==> Appcast XML validation passed successfully.")
EOF

echo "==> Successfully generated verified appcast at: ${OUTPUT_APPCAST}"
