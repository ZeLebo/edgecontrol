#!/bin/zsh
set -euo pipefail

cd "${0:A:h:h}"
mkdir -p .build/cache
export CLANG_MODULE_CACHE_PATH="$PWD/.build/cache/clang"
export SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/cache/swift"

swift build "$@" -c release --arch arm64 --cache-path "$PWD/.build/cache"
binary_dir="$(swift build "$@" -c release --arch arm64 --show-bin-path --cache-path "$PWD/.build/cache")"
app_path="$PWD/build/EdgeControl.app"
mkdir -p "$app_path/Contents/MacOS" "$app_path/Contents/Resources"
cp Resources/Info.plist "$app_path/Contents/Info.plist"
# Replace the inode so an already running instance keeps its original executable.
cp "$binary_dir/EdgeControl" "$app_path/Contents/MacOS/EdgeControl.new"
mv -f "$app_path/Contents/MacOS/EdgeControl.new" "$app_path/Contents/MacOS/EdgeControl"
# Remove build-toolchain search paths; retain system Swift runtime search paths.
packaged_binary="$app_path/Contents/MacOS/EdgeControl"
while IFS= read -r runtime_path; do
  if [[ "$runtime_path" == *".xctoolchain/"* ]]; then
    xcrun install_name_tool -delete_rpath "$runtime_path" "$packaged_binary"
  fi
done < <(otool -l "$packaged_binary" | awk '
  /cmd LC_RPATH/ { wanted = 1; next }
  wanted && /path / {
    sub(/^[[:space:]]*path[[:space:]]+/, "")
    sub(/[[:space:]]*\(offset [0-9]+\).*$/, "")
    print
    wanted = 0
  }')
xcrun strip -S -x "$app_path/Contents/MacOS/EdgeControl"
plutil -lint "$app_path/Contents/Info.plist"
codesign --force --sign - --identifier local.edgecontrol.app "$app_path"
codesign --verify --strict "$app_path"
print "Built: $app_path"
