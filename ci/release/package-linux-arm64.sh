#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 2 ]]; then
  echo "Usage: $0 <version> <release-tag> [commit] [objdir] [output-dir]" >&2
  exit 2
fi

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
version="$1"
release_tag="$2"
commit="${3:-$(git -C "$repo_root" rev-parse HEAD)}"
objdir="${4:-$repo_root/obj-linux-arm64-release}"
output_dir="${5:-$objdir/release}"
target="linux-arm64"
built_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
install_dir="$objdir/dist/firefox"

case "$(uname -m)" in
  aarch64|arm64) ;;
  *) echo "This release packager must run on Linux ARM64." >&2; exit 1 ;;
esac

for command_name in curl file jq timeout unzip zip; do
  command -v "$command_name" >/dev/null || {
    echo "Missing required command: $command_name" >&2
    exit 1
  }
done

if [[ ! -x "$install_dir/firefox" ]]; then
  echo "Packaged Firefox directory not found: $install_dir" >&2
  exit 1
fi

if [[ -z "$output_dir" || "$output_dir" == "/" || "$output_dir" == "$repo_root" ]]; then
  echo "Refusing unsafe output directory: $output_dir" >&2
  exit 1
fi

stage_dir="$objdir/release-stage"
rm -rf -- "$stage_dir" "$output_dir"
mkdir -p "$stage_dir" "$output_dir"

portable_dir_name="AceFox-${version}-linux-arm64"
portable_root="$stage_dir/$portable_dir_name"
appdir="$stage_dir/AceFox.AppDir"
appimage_name="AceFox-${version}-linux-arm64.AppImage"
portable_zip_name="AceFox-${version}-linux-arm64-portable.zip"
appimage="$output_dir/$appimage_name"
portable_zip="$output_dir/$portable_zip_name"

write_package_manifest() {
  local destination="$1"
  local package_format="$2"
  jq -n     --arg version "$version"     --arg tag "$release_tag"     --arg commit "$commit"     --arg target "$target"     --arg built_at "$built_at"     --arg package_format "$package_format"     '{
      schema_version: 1,
      product: "AceFox",
      distribution_brand: "AI2Apps",
      version: $version,
      tag: $tag,
      commit: $commit,
      target: $target,
      built_at_utc: $built_at,
      package_format: $package_format,
      signing: {required: false, status: "unsigned"}
    }' > "$destination"
}

# Portable ZIP: preserve the native install tree, Unix modes, and symlinks.
cp -a "$install_dir" "$portable_root"
write_package_manifest "$portable_root/runtime-manifest.json" "portable-zip"
(
  cd "$stage_dir"
  zip -qry -y "$portable_zip" "$portable_dir_name"
)
unzip -tq "$portable_zip"
file "$portable_root/firefox" | grep -Eq 'ARM aarch64|ARM64'
timeout 45s "$portable_root/firefox" --headless --version

# AppImage: AppRun starts the native Firefox install tree without modifying it.
mkdir -p "$appdir/usr/lib"   "$appdir/usr/share/applications"   "$appdir/usr/share/icons/hicolor/256x256/apps"
cp -a "$install_dir" "$appdir/usr/lib/acefox"

cat > "$appdir/AppRun" <<'APP_RUN_EOF'
#!/bin/sh
HERE="$(dirname "$(readlink -f "$0")")"
exec "$HERE/usr/lib/acefox/firefox" "$@"
APP_RUN_EOF
chmod 0755 "$appdir/AppRun"

cat > "$appdir/acefox.desktop" <<DESKTOP_EOF
[Desktop Entry]
Type=Application
Name=AI2Apps
Comment=AceFox AI2Apps Browser Runtime
Exec=acefox %u
Icon=acefox
Categories=Network;WebBrowser;
Terminal=false
StartupNotify=true
StartupWMClass=firefox-default
MimeType=text/html;text/xml;application/xhtml+xml;x-scheme-handler/http;x-scheme-handler/https;
X-AppImage-Version=$version
DESKTOP_EOF

cp "$appdir/acefox.desktop" "$appdir/usr/share/applications/acefox.desktop"
cp "$repo_root/browser/branding/ai2apps/default256.png" "$appdir/acefox.png"
cp "$repo_root/browser/branding/ai2apps/default256.png"   "$appdir/usr/share/icons/hicolor/256x256/apps/acefox.png"
ln -s usr/lib/acefox/firefox "$appdir/acefox"
write_package_manifest "$appdir/runtime-manifest.json" "AppImage"

appimagetool_url="${APPIMAGETOOL_URL:-https://github.com/AppImage/appimagetool/releases/download/continuous/appimagetool-aarch64.AppImage}"
tool_cache_dir="${RUNNER_TEMP:-$stage_dir/tools}"
mkdir -p "$tool_cache_dir"
appimagetool="$tool_cache_dir/appimagetool-aarch64.AppImage"
curl --fail --location --retry 3 --silent --show-error   "$appimagetool_url" -o "$appimagetool"
chmod 0755 "$appimagetool"
appimagetool_sha256="$(sha256sum "$appimagetool" | awk '{print $1}')"
ARCH=aarch64 APPIMAGE_EXTRACT_AND_RUN=1 "$appimagetool" "$appdir" "$appimage"
chmod 0755 "$appimage"
timeout 60s env APPIMAGE_EXTRACT_AND_RUN=1 "$appimage" --headless --version

appimage_sha256="$(sha256sum "$appimage" | awk '{print $1}')"
portable_zip_sha256="$(sha256sum "$portable_zip" | awk '{print $1}')"
appimage_size="$(stat -c %s "$appimage")"
portable_zip_size="$(stat -c %s "$portable_zip")"

jq -n   --arg version "$version"   --arg tag "$release_tag"   --arg commit "$commit"   --arg target "$target"   --arg built_at "$built_at"   --arg appimage_name "$appimage_name"   --arg appimage_sha256 "$appimage_sha256"   --argjson appimage_size "$appimage_size"   --arg portable_zip_name "$portable_zip_name"   --arg portable_zip_sha256 "$portable_zip_sha256"   --argjson portable_zip_size "$portable_zip_size"   --arg appimagetool_url "$appimagetool_url"   --arg appimagetool_sha256 "$appimagetool_sha256"   '{
    schema_version: 1,
    product: "AceFox",
    distribution_brand: "AI2Apps",
    version: $version,
    tag: $tag,
    commit: $commit,
    target: $target,
    built_at_utc: $built_at,
    signing: {required: false, status: "unsigned"},
    build: {
      mozconfig: "ci/mozconfig/linux-arm64-release",
      wasm_sandboxed_libraries: false,
      appimagetool: {url: $appimagetool_url, sha256: $appimagetool_sha256}
    },
    artifacts: [
      {file: $appimage_name, format: "AppImage", bytes: $appimage_size, sha256: $appimage_sha256},
      {file: $portable_zip_name, format: "portable-zip", bytes: $portable_zip_size, sha256: $portable_zip_sha256}
    ]
  }' > "$output_dir/runtime-manifest.json"

(
  cd "$output_dir"
  sha256sum "$appimage_name" "$portable_zip_name" runtime-manifest.json > SHA256SUMS
  sha256sum --check SHA256SUMS
)

printf 'Release assets created in %s
' "$output_dir"
ls -lh "$output_dir"
