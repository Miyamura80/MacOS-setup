#!/bin/bash
set -euo pipefail

usage() {
    echo "Usage: $0 [--applications-dir DIRECTORY] [--no-launch]"
    echo "Build and install UsageBar (default: ~/Applications), then open it."
}

applications_dir="$HOME/Applications"
launch_app=1
while [ "$#" -gt 0 ]; do
    case "$1" in
        --applications-dir)
            if [ "$#" -lt 2 ] || [ -z "$2" ]; then usage >&2; exit 64; fi
            case "$2" in --*) usage >&2; exit 64 ;; esac
            applications_dir="$2"
            shift 2
            ;;
        --no-launch) launch_app=0; shift ;;
        --help|-h) usage; exit 0 ;;
        *) usage >&2; exit 64 ;;
    esac
done

if [ "$(uname -s)" != Darwin ]; then
    echo "UsageBar requires macOS 14 or later." >&2
    exit 1
fi
macos_version="$(sw_vers -productVersion)"
if [ "${macos_version%%.*}" -lt 14 ]; then
    echo "UsageBar requires macOS 14 or later (found $macos_version)." >&2
    exit 1
fi
if ! command -v swift >/dev/null 2>&1 || ! swift_version="$(swift --version 2>&1)"; then
    echo "Install Apple's Command Line Tools with xcode-select --install, then rerun this installer." >&2
    exit 1
fi
swift_major="$(printf '%s\n' "$swift_version" | sed -nE 's/.*Swift version ([0-9]+).*/\1/p' | head -n 1)"
if [ -z "$swift_major" ] || [ "$swift_major" -lt 6 ]; then
    echo "UsageBar needs Swift 6+. Update Xcode or Apple's Command Line Tools, then rerun this installer." >&2
    exit 1
fi

# Resolve relative destinations against the caller's directory, before the build changes cwd.
case "$applications_dir" in /*) ;; *) applications_dir="$PWD/$applications_dir" ;; esac
installer_source="${BASH_SOURCE[0]}"
while [ -L "$installer_source" ]; do
    installer_dir="$(cd -P "$(dirname "$installer_source")" && pwd)"
    installer_source="$(readlink "$installer_source")"
    case "$installer_source" in /*) ;; *) installer_source="$installer_dir/$installer_source" ;; esac
done
project_dir="$(cd -P "$(dirname "$installer_source")/.." && pwd)"
"$project_dir/scripts/build.sh"
mkdir -p "$applications_dir"
applications_dir="$(cd "$applications_dir" && pwd)"
staging_dir="$(mktemp -d "$applications_dir/.usagebar-install.XXXXXX")"
trap 'rm -rf "$staging_dir"' EXIT
staged_app="$staging_dir/UsageBar.app"
installed_app="$applications_dir/UsageBar.app"
ditto "$project_dir/dist/UsageBar.app" "$staged_app"
codesign --verify --strict "$staged_app"
# Stage on the destination volume, so first install and upgrades use atomic publication.
swiftc "$project_dir/scripts/BundlePublication.swift" "$project_dir/scripts/PublishMain.swift" -o "$staging_dir/publish"
"$staging_dir/publish" "$staged_app" "$installed_app"
codesign --verify --strict "$installed_app"
echo "Installed: $installed_app"

if [ "$launch_app" -eq 1 ]; then
    open "$installed_app"
    echo "UsageBar opened. If an older copy is already running, quit it and reopen the installed app to load this version."
fi
echo "Setup: enable Launch at Login in UsageBar's options menu if desired."
echo "Accounts: sign in with codex login and Claude Code /login; allow Keychain access from UsageBar if requested."
