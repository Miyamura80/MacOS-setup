#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
project_dir="$PWD"
mkdir -p .build
fixture_dir="$(mktemp -d "$PWD/.build/install-check.XXXXXX")"
trap 'rm -rf "$fixture_dir"' EXIT
applications_dir="$fixture_dir/User Applications"
mkdir -p "$applications_dir" "$fixture_dir/other-cwd" "$fixture_dir/bin"
ln -s "$project_dir/scripts/install.sh" "$fixture_dir/bin/install-usagebar"
ln -s bin/install-usagebar "$fixture_dir/install-usagebar"
printf 'keep\n' > "$applications_dir/Keep Me.txt"
(
    cd "$fixture_dir/other-cwd"
    "$fixture_dir/install-usagebar" --no-launch --applications-dir '../User Applications'
)
test -x "$applications_dir/UsageBar.app/Contents/MacOS/UsageBar"
codesign --verify --strict "$applications_dir/UsageBar.app"
printf 'obsolete\n' > "$applications_dir/UsageBar.app/obsolete-resource.txt"
"$project_dir/scripts/install.sh" --no-launch --applications-dir "$applications_dir"
test ! -e "$applications_dir/UsageBar.app/obsolete-resource.txt"
test "$(cat "$applications_dir/Keep Me.txt")" = keep
codesign --verify --strict "$applications_dir/UsageBar.app"
"$applications_dir/UsageBar.app/Contents/MacOS/UsageBar" --render-preview "$fixture_dir/previews"
for preview in light dark tray; do test -s "$fixture_dir/previews/$preview.png"; done
if "$project_dir/scripts/install.sh" --applications-dir >/dev/null 2>&1; then
    echo "Installer accepted a missing destination argument." >&2
    exit 1
fi
if "$project_dir/scripts/install.sh" --applications-dir --no-launch >/dev/null 2>&1; then
    echo "Installer accepted a flag instead of a destination." >&2
    exit 1
fi
echo 'Verified first install, upgrade, spaces/relative paths and symlink chains, unrelated files, and installed SVG resources without launching or accessing accounts.'
