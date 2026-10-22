#!/bin/zsh
set -euo pipefail

project_dir="${0:A:h:h}"
app_version="2.0.0"
version="5.0.1"
platform_tools_version="37.0.1"
platform_tools_sha="ee39ad5967e95c2a07f04dbcbde96b1a0c916ba376096db5d2f498b7727a5d1d"
platform_tools_adb_sha="1811e253b21b12cbfda7201ebaf86c10e7ddcb5c606a7a81f7c82b4c429c2d3b"
platform_tools_notice_sha="356cc66516060e4da6bdc53e6f0bbb8e8101673f326b73c68d535eddd04dd7b1"
platform_tools_url="https://dl.google.com/android/repository/platform-tools_r${platform_tools_version}-darwin.zip"
system_scrcpy=false
if [[ "${1:-}" == "--system-scrcpy" ]]; then
  system_scrcpy=true
elif [[ -n "${1:-}" ]]; then
  print -u2 "Usage: $0 [--system-scrcpy]"
  exit 1
fi

work_dir="$(mktemp -d)"
download_cache="/tmp/droidmirror-download-cache"
mkdir -p "$download_cache"
trap 'rm -rf "$work_dir"' EXIT

build_binary() {
  local target_arch="$1"
  local output="$2"
  swiftc \
    -sdk /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk \
    -target "${target_arch}-apple-macosx13.0" \
    -module-cache-path "$work_dir/module-cache-${target_arch}" \
    -Xfrontend -disable-interface-lock \
    -parse-as-library \
    -O \
    "$project_dir"/Sources/DroidMirror/*.swift \
    -o "$output"
}

print "Building DroidMirror with the installed Command Line Tools..."
build_binary arm64 "$work_dir/DroidMirror-arm64"
build_binary x86_64 "$work_dir/DroidMirror-x86_64"
lipo -create \
  "$work_dir/DroidMirror-arm64" \
  "$work_dir/DroidMirror-x86_64" \
  -output "$work_dir/DroidMirror"
package_arch="universal"

adb_path="$work_dir/platform-tools/platform-tools/adb"
adb_notice_path="$work_dir/platform-tools/platform-tools/NOTICE.txt"
existing_adb_path="$project_dir/dist/DroidMirror.app/Contents/Resources/bin/adb"
existing_adb_notice_path="$project_dir/dist/DroidMirror.app/Contents/Resources/ANDROID_PLATFORM_TOOLS_NOTICE.txt"

if [[ -x "$existing_adb_path" ]] \
  && [[ -f "$existing_adb_notice_path" ]] \
  && [[ "$(shasum -a 256 "$existing_adb_path" | awk '{print $1}')" == "$platform_tools_adb_sha" ]] \
  && [[ "$(shasum -a 256 "$existing_adb_notice_path" | awk '{print $1}')" == "$platform_tools_notice_sha" ]]; then
  print "Reusing verified Android Platform Tools ${platform_tools_version}..."
  mkdir -p "${adb_path:h}"
  cp "$existing_adb_path" "$adb_path"
  cp "$existing_adb_notice_path" "$adb_notice_path"
else
  print "Downloading Android Platform Tools ${platform_tools_version}..."
  platform_archive="$work_dir/platform-tools.zip"
  curl --http1.1 -L --fail --silent --show-error \
    --retry 3 --retry-delay 2 --connect-timeout 20 --max-time 300 \
    "$platform_tools_url" -o "$platform_archive"
  actual_platform_sha="$(shasum -a 256 "$platform_archive" | awk '{print $1}')"
  if [[ "$actual_platform_sha" != "$platform_tools_sha" ]]; then
    print -u2 "Platform Tools checksum mismatch. Expected $platform_tools_sha, got $actual_platform_sha"
    exit 1
  fi
  unzip -q "$platform_archive" \
    platform-tools/adb platform-tools/NOTICE.txt \
    -d "$work_dir/platform-tools"
fi

bundle_scrcpy() {
  local release_arch="$1"
  local runtime_arch="$2"
  local expected_sha="$3"
  local destination="$4"
  local archive_name="scrcpy-macos-${release_arch}-v${version}.tar.gz"
  local download_url="https://github.com/Genymobile/scrcpy/releases/download/v${version}/${archive_name}"
  local archive_path="$download_cache/$archive_name"
  local extract_dir="$work_dir/scrcpy-${runtime_arch}"

  if [[ -x "$work_dir/existing-scrcpy/$runtime_arch/scrcpy" ]]; then
    print "Reusing bundled scrcpy ${version} for ${runtime_arch}..."
    mkdir -p "$destination"
    cp -R "$work_dir/existing-scrcpy/$runtime_arch/." "$destination/"
    return
  fi

  print "Downloading scrcpy ${version} for ${runtime_arch}..."
  curl --http1.1 -L --fail --silent --show-error -C - \
    --retry 10 --retry-all-errors --retry-delay 2 --connect-timeout 20 \
    --speed-limit 1024 --speed-time 60 \
    "$download_url" -o "$archive_path"
  local actual_sha="$(shasum -a 256 "$archive_path" | awk '{print $1}')"
  if [[ "$actual_sha" != "$expected_sha" ]]; then
    print -u2 "scrcpy checksum mismatch. Expected $expected_sha, got $actual_sha"
    exit 1
  fi

  mkdir -p "$extract_dir"
  tar -xzf "$archive_path" -C "$extract_dir"
  local scrcpy_path="$(find "$extract_dir" -type f -name scrcpy -perm +111 | head -1)"
  if [[ -z "$scrcpy_path" ]]; then
    print -u2 "The scrcpy executable was not found in the release archive."
    exit 1
  fi
  mkdir -p "$destination"
  cp -R "${scrcpy_path:h}/." "$destination/"
}

app_dir="$project_dir/dist/DroidMirror.app"
contents_dir="$app_dir/Contents"
if ! $system_scrcpy \
  && [[ -x "$contents_dir/Resources/bin/arm64/scrcpy" ]] \
  && [[ -x "$contents_dir/Resources/bin/x86_64/scrcpy" ]]; then
  mkdir -p "$work_dir/existing-scrcpy"
  cp -R "$contents_dir/Resources/bin/arm64" "$work_dir/existing-scrcpy/arm64"
  cp -R "$contents_dir/Resources/bin/x86_64" "$work_dir/existing-scrcpy/x86_64"
fi
rm -rf "$app_dir"
mkdir -p "$contents_dir/MacOS" "$contents_dir/Resources/bin"
cp "$work_dir/DroidMirror" "$contents_dir/MacOS/DroidMirror"
if ! $system_scrcpy; then
  bundle_scrcpy \
    aarch64 arm64 \
    33611e51977a8289e2e124b220f727895181ef2eb9060e0987a4dc2db9cf0d6b \
    "$contents_dir/Resources/bin/arm64"
  bundle_scrcpy \
    x86_64 x86_64 \
    31a5467a9e907f162b093267cbbab1276b15c6e709c2ea8159566a8d165beb50 \
    "$contents_dir/Resources/bin/x86_64"
fi
cp "$adb_path" "$contents_dir/Resources/bin/adb"
cp "$adb_notice_path" "$contents_dir/Resources/ANDROID_PLATFORM_TOOLS_NOTICE.txt"
cp "$project_dir/THIRD_PARTY_NOTICES.md" "$contents_dir/Resources/THIRD_PARTY_NOTICES.md"

cat > "$contents_dir/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDisplayName</key>
  <string>DroidMirror</string>
  <key>CFBundleExecutable</key>
  <string>DroidMirror</string>
  <key>CFBundleIdentifier</key>
  <string>com.stonebirds.droidmirror</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>DroidMirror</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>2.0.0</string>
  <key>CFBundleVersion</key>
  <string>5</string>
  <key>LSApplicationCategoryType</key>
  <string>public.app-category.utilities</string>
  <key>LSMinimumSystemVersion</key>
  <string>13.0</string>
  <key>NSHighResolutionCapable</key>
  <true/>
</dict>
</plist>
PLIST

codesign --force --deep --sign - "$app_dir"

dmg_path="$project_dir/dist/DroidMirror-${app_version}-${package_arch}.dmg"
rm -f "$dmg_path"
hdiutil create -volname DroidMirror -srcfolder "$app_dir" -ov -format UDZO "$dmg_path"

print "Created: $app_dir"
print "Created: $dmg_path"
rm -rf "$download_cache"
