#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
project_dir="$(cd "${script_dir}/.." && pwd)"
cd "$project_dir"

source "${script_dir}/config.sh"

work_dir="$(mktemp -d "${TMPDIR:-/tmp}/spotpen-dmg.XXXXXX")"
trap 'rm -rf "$work_dir"' EXIT

build_dir="build"
app_bundle="${build_dir}/${APP_NAME}.app"
dmg_name="${APP_NAME}-${VERSION}.dmg"
dmg_path="${build_dir}/${dmg_name}"
tmp_dmg="${build_dir}/tmp_rw.dmg"

# Always rebuild so the packaged app matches the current VERSION file.
"${script_dir}/build.sh"

app_plist="${app_bundle}/Contents/Info.plist"
icon_name="$(/usr/libexec/PlistBuddy -c "Print :CFBundleIconFile" "$app_plist" 2>/dev/null || true)"
icon_name="${icon_name:-AppIcon}"
[[ "$icon_name" == *.icns ]] || icon_name="${icon_name}.icns"
app_icon="${app_bundle}/Contents/Resources/${icon_name}"
if [[ ! -f "$app_icon" ]]; then
    printf '%s\n' "Error: App icon not found: ${app_icon}" >&2
    exit 1
fi

dmg_icon="${project_dir}/Resources/DmgIcon.icns"
if [[ ! -f "$dmg_icon" ]]; then
    dmg_icon="$app_icon"
fi

# Detach a leftover mount of *our* scratch image from an interrupted run. Volumes that
# merely share the app's name (e.g. a user's own "SpotPen" disk) are left alone.
tmp_dmg_abs="${project_dir}/${tmp_dmg}"
image_path=""
while IFS= read -r line; do
    if [[ "$line" =~ ^image-path[[:space:]]*:[[:space:]]*(.*)$ ]]; then
        image_path="${BASH_REMATCH[1]}"
    elif [[ "$image_path" == "$tmp_dmg_abs" && "$line" =~ (/Volumes/.*)$ ]]; then
        hdiutil detach "${BASH_REMATCH[1]}" -force >/dev/null 2>&1 || true
    fi
done < <(hdiutil info 2>/dev/null || true)

printf '%s\n' "Creating styled DMG package for ${APP_NAME} v${VERSION}..."
rm -rf "${build_dir}/dmg_root" "$tmp_dmg" "$dmg_path"
mkdir -p "${build_dir}/dmg_root/.background"

if [[ -f "Resources/dmg_background.png" ]]; then
    cp "Resources/dmg_background.png" "${build_dir}/dmg_root/.background/background.png"
    if [[ -f "Resources/dmg_background@2x.png" ]]; then
        tiffutil -cathidpicheck "Resources/dmg_background.png" "Resources/dmg_background@2x.png" -out "${build_dir}/dmg_root/.background/background.tiff" >/dev/null 2>&1 || cp "Resources/dmg_background.png" "${build_dir}/dmg_root/.background/background.tiff"
    else
        cp "Resources/dmg_background.png" "${build_dir}/dmg_root/.background/background.tiff"
    fi
fi

cp -R "$app_bundle" "${build_dir}/dmg_root/"
ln -s /Applications "${build_dir}/dmg_root/Applications"
# Included up front so the image is sized for it; reapplied after the Finder layout.
cp "$dmg_icon" "${build_dir}/dmg_root/.VolumeIcon.icns"

hdiutil create -volname "${APP_NAME}" -srcfolder "${build_dir}/dmg_root" -fs HFS+ -format UDRW -ov "$tmp_dmg" >/dev/null

attach_file="${work_dir}/hdiutil_attach.txt"
hdiutil attach -readwrite -noverify -noautoopen "$tmp_dmg" >"$attach_file" 2>/dev/null

# The attach output only lists this image. Its volume may be "SpotPen 1" if another
# "SpotPen" volume is already mounted, so use the real mount point and name.
mount_point=""
while IFS= read -r line; do
    if [[ "$line" =~ (/Volumes/.+)$ ]]; then
        mount_point="${BASH_REMATCH[1]}"
        mount_point="${mount_point%"${mount_point##*[![:space:]]}"}"
        break
    fi
done <"$attach_file"
volume_name="${mount_point##*/}"

if [[ -z "$mount_point" || ! -d "$mount_point" ]]; then
    printf '%s\n' "Error: Failed to identify disk image mount point" >&2
    exit 1
fi

osascript <<APPLESCRIPT >/dev/null 2>&1 || true
tell application "Finder"
    tell disk "${volume_name}"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set the bounds of container window to {300, 120, 960, 520}
        set theViewOptions to the icon view options of container window
        set arrangement of theViewOptions to not arranged
        set icon size of theViewOptions to 100
        if exists file ".background:background.tiff" then
            set background picture of theViewOptions to file ".background:background.tiff"
        end if
        set position of item "${APP_NAME}.app" of container window to {180, 200}
        set position of item "Applications" of container window to {480, 200}
        update without registering applications
        delay 1
        close
    end tell
end tell
APPLESCRIPT

# Use the dmg icon as the mounted volume icon. This must run after the Finder
# layout step, which removes .VolumeIcon.icns and clears the custom icon flag.
cp "$dmg_icon" "${mount_point}/.VolumeIcon.icns"
SetFile -c icnC "${mount_point}/.VolumeIcon.icns" 2>/dev/null || true
if ! SetFile -a C "$mount_point" 2>/dev/null; then
    # Fallback without Xcode tools: set kHasCustomIcon in the Finder flags.
    xattr -wx com.apple.FinderInfo \
        "0000000000000000040000000000000000000000000000000000000000000000" "$mount_point"
fi

sync
hdiutil detach "$mount_point" >/dev/null 2>&1 || hdiutil detach -force "$mount_point" >/dev/null 2>&1

hdiutil convert "$tmp_dmg" -format UDZO -imagekey zlib-level=9 -ov -o "$dmg_path" >/dev/null
rm -rf "${build_dir}/dmg_root" "$tmp_dmg"

# Use the dmg icon for the .dmg file itself in Finder.
osascript -l JavaScript - "$dmg_icon" "$dmg_path" <<'JXA' >/dev/null 2>&1 || true
ObjC.import('AppKit');
function run(argv) {
    const icon = $.NSImage.alloc.initWithContentsOfFile(argv[0]);
    return $.NSWorkspace.sharedWorkspace.setIconForFileOptions(icon, argv[1], 0);
}
JXA

# Optional distribution signing and notarization (requires an Apple Developer account):
#   SIGN_IDENTITY="Developer ID Application: Name (TEAMID)"
#   NOTARY_PROFILE=<profile stored with: xcrun notarytool store-credentials>
if [[ -n "${SIGN_IDENTITY:-}" ]]; then
    printf '%s\n' "Signing ${dmg_name}..."
    codesign --force --timestamp --sign "$SIGN_IDENTITY" "$dmg_path"
    if [[ -n "${NOTARY_PROFILE:-}" ]]; then
        printf '%s\n' "Notarizing ${dmg_name} (this can take a few minutes)..."
        xcrun notarytool submit "$dmg_path" --keychain-profile "$NOTARY_PROFILE" --wait
        xcrun stapler staple "$dmg_path"
    fi
elif [[ -n "${NOTARY_PROFILE:-}" ]]; then
    printf '%s\n' "Error: NOTARY_PROFILE requires SIGN_IDENTITY (Developer ID)." >&2
    exit 1
else
    printf '%s\n' "Note: ${dmg_name} is ad-hoc signed and not notarized; Gatekeeper will warn on other Macs."
fi

printf '%s\n' "✅ DMG created successfully: ${dmg_path}"
