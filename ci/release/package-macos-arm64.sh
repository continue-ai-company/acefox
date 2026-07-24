#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 5 ]]; then
  echo "Usage: $0 <version> <release-tag> <commit> <source-run-id> <input-dir> [output-dir]" >&2
  exit 2
fi

version="$1"
release_tag="$2"
commit="$3"
source_run_id="$4"
input_dir="$5"
output_dir="${6:-${RUNNER_TEMP:-/tmp}/acefox-macos-arm64-release-assets}"
target="macos-arm64"
built_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

[[ "$(uname -s)" == "Darwin" && "$(uname -m)" == "arm64" ]] || {
  echo "This release packager must run on macOS ARM64." >&2
  exit 1
}

for command_name in ditto file hdiutil jq plutil shasum unzip; do
  command -v "$command_name" >/dev/null || {
    echo "Missing required command: $command_name" >&2
    exit 1
  }
done

[[ -d "$input_dir" ]] || {
  echo "Downloaded build artifact directory not found: $input_dir" >&2
  exit 1
}

if [[ -z "$output_dir" || "$output_dir" == "/" || -e "$output_dir" ]]; then
  echo "Output directory must be a new, explicit path: $output_dir" >&2
  exit 1
fi

dmg_candidates=()
while IFS= read -r -d '' candidate; do
  dmg_candidates+=("$candidate")
done < <(find "$input_dir" -type f -name '*.dmg' -print0)
if [[ "${#dmg_candidates[@]}" -ne 1 ]]; then
  echo "Expected exactly one DMG in the build artifact, found ${#dmg_candidates[@]}." >&2
  printf '%s\n' "${dmg_candidates[@]:-}" >&2
  exit 1
fi

stage_dir="$(mktemp -d "${RUNNER_TEMP:-/tmp}/acefox-macos-release.XXXXXX")"
mount_dir="$stage_dir/mount"
portable_app="$stage_dir/AceFox.app"
mounted=false

cleanup() {
  if [[ "$mounted" == true ]]; then
    hdiutil detach "$mount_dir" -quiet || true
  fi
}
trap cleanup EXIT

mkdir -p "$mount_dir" "$output_dir"
hdiutil attach "${dmg_candidates[0]}" -readonly -nobrowse -mountpoint "$mount_dir" -quiet
mounted=true

app_candidates=()
while IFS= read -r -d '' candidate; do
  app_candidates+=("$candidate")
done < <(find "$mount_dir" -type d -name '*.app' -prune -print0)
if [[ "${#app_candidates[@]}" -ne 1 ]]; then
  echo "Expected exactly one app bundle in the DMG, found ${#app_candidates[@]}." >&2
  printf '%s\n' "${app_candidates[@]:-}" >&2
  exit 1
fi

ditto "${app_candidates[0]}" "$portable_app"
hdiutil detach "$mount_dir" -quiet
mounted=false

app_executable="$portable_app/Contents/MacOS/firefox"
[[ -x "$app_executable" ]] || {
  echo "Packaged browser executable not found: $app_executable" >&2
  exit 1
}
file "$app_executable" | grep -q 'arm64'
"$app_executable" --headless --version

dmg_name="AceFox-${version}-macos-arm64.dmg"
portable_zip_name="AceFox-${version}-macos-arm64.app.zip"
manifest_name="runtime-manifest-macos-arm64.json"
checksums_name="SHA256SUMS-macos-arm64.txt"
dmg="$output_dir/$dmg_name"
portable_zip="$output_dir/$portable_zip_name"
manifest="$output_dir/$manifest_name"

cp "${dmg_candidates[0]}" "$dmg"
ditto -c -k --keepParent --sequesterRsrc "$portable_app" "$portable_zip"
unzip -tq "$portable_zip"

dmg_sha256="$(shasum -a 256 "$dmg" | awk '{print $1}')"
portable_zip_sha256="$(shasum -a 256 "$portable_zip" | awk '{print $1}')"
dmg_size="$(stat -f %z "$dmg")"
portable_zip_size="$(stat -f %z "$portable_zip")"
bundle_identifier="$(plutil -extract CFBundleIdentifier raw "$portable_app/Contents/Info.plist")"

jq -n \
  --arg version "$version" \
  --arg tag "$release_tag" \
  --arg commit "$commit" \
  --arg target "$target" \
  --arg built_at "$built_at" \
  --arg source_run_id "$source_run_id" \
  --arg bundle_identifier "$bundle_identifier" \
  --arg dmg_name "$dmg_name" \
  --arg dmg_sha256 "$dmg_sha256" \
  --argjson dmg_size "$dmg_size" \
  --arg portable_zip_name "$portable_zip_name" \
  --arg portable_zip_sha256 "$portable_zip_sha256" \
  --argjson portable_zip_size "$portable_zip_size" \
  '{
    schema_version: 1,
    product: "AceFox",
    distribution_brand: "AI2Apps",
    version: $version,
    tag: $tag,
    commit: $commit,
    target: $target,
    built_at_utc: $built_at,
    source_workflow_run_id: $source_run_id,
    bundle_identifier: $bundle_identifier,
    signing: {required: false, status: "unsigned"},
    artifacts: [
      {file: $dmg_name, format: "dmg", bytes: $dmg_size, sha256: $dmg_sha256},
      {file: $portable_zip_name, format: "app-zip", bytes: $portable_zip_size, sha256: $portable_zip_sha256}
    ]
  }' > "$manifest"

(
  cd "$output_dir"
  shasum -a 256 "$dmg_name" "$portable_zip_name" "$manifest_name" > "$checksums_name"
  shasum -a 256 -c "$checksums_name"
)

printf 'macOS ARM64 release assets created in %s\n' "$output_dir"
ls -lh "$output_dir"
