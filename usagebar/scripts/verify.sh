#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
for script in ../install_script.sh scripts/build.sh scripts/install.sh scripts/test-install.sh; do
    bash -n "$script"
done
./scripts/test.sh
./scripts/build.sh
source_dir="$PWD"
binary_dir="$(swift build -c release --show-bin-path)"
resource_bundle="$binary_dir/UsageBar_UsageBar.bundle"
verification_dir="$(mktemp -d "${TMPDIR:-/tmp}/usagebar-verify.XXXXXX")"
backup_bundle="$verification_dir/build-resources.bundle"
cleanup() {
    if [ -e "$backup_bundle" ]; then mv "$backup_bundle" "$resource_bundle"; fi
    rm -rf "$verification_dir"
}
trap cleanup EXIT
# Hide SwiftPM's original bundle so even older absolute-path accessors cannot mask bad packaging.
ditto dist/UsageBar.app "$verification_dir/UsageBar.app"
mv "$resource_bundle" "$backup_bundle"
(
    cd "$verification_dir"
    ./UsageBar.app/Contents/MacOS/UsageBar --render-preview "$verification_dir/previews"
    codesign --verify --strict UsageBar.app
)
for preview in light dark tray; do test -s "$verification_dir/previews/$preview.png"; done
test "$(plutil -extract LSUIElement raw -o - dist/UsageBar.app/Contents/Info.plist)" = true
ditto "$verification_dir/previews" "$source_dir/.build/previews"
# Restore SwiftPM resources before the installer performs its own cached build.
mv "$backup_bundle" "$resource_bundle"
./scripts/test-install.sh
printf 'Verified regression suite, release bundle, relocated SVG resources, and light/dark/tray rendering.\n'
