# Release hook for grel / ggrel (sourced from the repository root).
#   ggrel 1.2.0            # generate notes with Gemini and release
#   ggrel 1.2.0 --dry-run  # preview only
#
# grel order: TEST_CMD -> write + commit VERSION -> BUILD_CMD -> check RELEASE_ASSETS
#             -> tag v<version> -> push branch and tag -> gh release with the assets.
# ${version} is substituted by grel, so it must stay literal here (single quotes).

APP_NAME='SpotPen'

TEST_CMD='./scripts/test.sh'

# 1. Build the universal app and the styled DMG (reads VERSION, which grel has just committed).
# 2. Refuse to ship if the bundle reports a different version.
# 3. Write the SHA-256 checksum that is attached next to the DMG.
# 4. Commit the BUILD_NUMBER the build incremented, so the tag includes the shipped build
#    number and the tree stays clean for the next release.
BUILD_CMD='set -euo pipefail
./scripts/build_dmg.sh
built="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" build/SpotPen.app/Contents/Info.plist)"
[[ "$built" == "${version}" ]] || { echo "Built app reports version $built, expected ${version}" >&2; exit 1; }
(cd build && shasum -a 256 "SpotPen-${version}.dmg" > "SpotPen-${version}.dmg.sha256")
if ! git diff --quiet -- BUILD_NUMBER; then
    git commit -m "chore(release): build $(tr -d "[:space:]" < BUILD_NUMBER) for v${version}" -- BUILD_NUMBER
fi'

RELEASE_ASSETS=(
    'build/SpotPen-${version}.dmg'
    'build/SpotPen-${version}.dmg.sha256'
)
