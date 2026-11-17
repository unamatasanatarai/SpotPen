#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
project_dir="$(cd "${script_dir}/.." && pwd)"
cd "$project_dir"

source "${script_dir}/config.sh"

sdk_path="$(xcrun --show-sdk-path 2>/dev/null || true)"
if [[ -z "$sdk_path" ]]; then
    printf '%s\n' "Error: Failed to obtain SDK path from xcrun" >&2
    exit 1
fi

if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    printf '%s\n' "Error: VERSION file must contain a version like 1.2.3 (found '${VERSION}')" >&2
    exit 1
fi

# Every build increments BUILD_NUMBER; the file is the single source of truth.
if [[ "$BUILD_NUMBER" =~ ^[0-9]+$ ]]; then
    build_number=$((10#$BUILD_NUMBER + 1))
else
    build_number=1
fi
printf '%s\n' "$build_number" >"$build_num_file"
export BUILD_NUMBER="$build_number"

build_dir="build"
app_name="${APP_NAME}"
bundle_id="${BUNDLE_ID}"
app_dir="${build_dir}/${app_name}.app"
contents_dir="${app_dir}/Contents"
macos_dir="${contents_dir}/MacOS"
resources_dir="${contents_dir}/Resources"

# Start from an empty bundle so files removed from Resources/ do not linger.
rm -rf "$app_dir"
mkdir -p "$macos_dir" "$resources_dir"

if [[ -d "Resources" ]]; then
    cp -R Resources/. "${resources_dir}/"
fi

if [[ -f "VERSION" ]]; then
    cp "VERSION" "${resources_dir}/VERSION"
fi
printf '%s\n' "$build_number" >"${resources_dir}/BUILD_NUMBER"

sources=()
while IFS= read -r file; do
    sources+=("$file")
done < <(find Sources/App -type f -name "*.swift" | sort)

# Universal binary: one slice per architecture, merged with lipo, so the same app runs
# natively on Apple silicon and Intel Macs. Override with ARCHS="arm64" for a quick local build.
read -r -a archs <<<"${ARCHS}"
obj_dir="${build_dir}/obj"
rm -rf "$obj_dir"
mkdir -p "$obj_dir"

slices=()
for arch in "${archs[@]}"; do
    printf '%s\n' "Compiling ${app_name} v${VERSION} (Build ${BUILD_NUMBER}) for ${arch} (${#sources[@]} source files)..."
    swiftc -sdk "$sdk_path" \
        -target "${arch}-apple-macos${MIN_MACOS_VERSION}" \
        -O \
        -whole-module-optimization \
        -Xlinker -dead_strip \
        "${sources[@]}" \
        -o "${obj_dir}/${app_name}-${arch}"
    slices+=("${obj_dir}/${app_name}-${arch}")
done

executable="${macos_dir}/${app_name}"
rm -f "$executable"
lipo -create "${slices[@]}" -output "$executable"
lipo "$executable" -verify_arch "${archs[@]}"
printf '%s\n' "Architectures: $(lipo -archs "$executable")"
rm -rf "$obj_dir"

printf '%s\n' "Generating ${app_name} Info.plist..."
cat <<EOF >"${contents_dir}/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>${app_name}</string>
    <key>CFBundleIdentifier</key>
    <string>${bundle_id}</string>
    <key>CFBundleName</key>
    <string>${app_name}</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>${VERSION}</string>
    <key>CFBundleVersion</key>
    <string>${BUILD_NUMBER}</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon.icns</string>
    <key>CFBundleIconName</key>
    <string>AppIcon</string>
    <key>LSMinimumSystemVersion</key>
    <string>${MIN_MACOS_VERSION}</string>
    <key>LSUIElement</key>
    <${LS_UI_ELEMENT}/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSHumanReadableCopyright</key>
    <string>${COPYRIGHT}</string>
</dict>
</plist>
EOF

# SpotPen needs no privacy (TCC) permissions, so the default designated requirement is used.
# Never pin it to the bundle identifier alone: anyone can ad-hoc sign code with that identifier
# and would inherit any permission granted to the app.
if [[ -n "${SIGN_IDENTITY:-}" ]]; then
    printf '%s\n' "Signing ${app_name} bundle with '${SIGN_IDENTITY}' (hardened runtime)..."
    codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$app_dir"
else
    printf '%s\n' "Signing ${app_name} bundle (ad-hoc; set SIGN_IDENTITY for a Developer ID signature)..."
    codesign --force --sign - "$app_dir"
fi
codesign --verify --strict "$app_dir"

printf '%s\n' "Refreshing macOS LaunchServices cache..."
touch "$app_dir"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f -R "$app_dir" >/dev/null 2>&1 || true
qlmanage -r cache >/dev/null 2>&1 || true

printf '%s\n' "✅ Build complete:"
printf '%s\n' "   - ${app_dir}"
