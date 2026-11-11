#!/bin/bash
# Copyright (C) 2026 ZeroDream
# https://github.com/zero-dream

set -euo pipefail

# --------------------------------------------------

# env:
#   GH_TOKEN: ${{secrets.WORKFLOW_TOKEN}}

# --------------------------------------------------

cd "$WRT_MainPath/"
PACKAGE_PATH="$WRT_MainPath/package"

echo "$(printf -- '-%.0s' {1..50})"
echo "Handle: $(basename "${BASH_SOURCE[0]}")"
echo ''

# --------------------------------------------------

ZeroWrtRepo="$ZD_Owner/zerowrt-repository"
ZeroWrtIndexName='00-IndexList'

function findDeletePackage() {
	local name=$1
	echo "Find dir: $name"
	find "$WRT_MainPath/feeds/luci/" "$WRT_MainPath/feeds/packages/" \
		-mindepth 1 -type d -iname "*$name*" -prune -print -exec rm -rf -- {} +
}

# Mirror Release 使用另一套附件命名。索引与软件包必须来自同一个 Package Release。
if ! packageTag=$(gh release list --repo "$ZeroWrtRepo" \
	--exclude-drafts --exclude-pre-releases --json tagName \
	--jq '[.[] | select(.tagName | endswith("-Package"))][0].tagName // empty') || [[ -z "$packageTag" ]]; then
	echo "No Package release found in $ZeroWrtRepo." >&2
	exit 1
fi
echo "Package release: $ZeroWrtRepo@$packageTag"

if ! packageIndex=$(gh release download "$packageTag" --repo "$ZeroWrtRepo" \
	--pattern "$ZeroWrtIndexName" --output -); then
	echo "Could not download $ZeroWrtIndexName from $packageTag." >&2
	exit 1
fi

packages=()
while IFS= read -r package; do
	package=${package%$'\r'}
	[[ "$package" =~ ^[[:space:]]*$ ]] && continue
	if [[ ! "$package" =~ ^[a-zA-Z0-9][a-zA-Z0-9._+-]*$ ]]; then
		printf 'Invalid package name in %s: %q\n' "$ZeroWrtIndexName" "$package" >&2
		exit 1
	fi
	packages+=("$package")
done <<<"$packageIndex"

if (( ${#packages[@]} == 0 )); then
	echo "Empty $ZeroWrtIndexName in $packageTag." >&2
	exit 1
fi

# 下载并解包全部软件包后再清理 feeds，避免下载失败时移除已有软件包。
packageStage=$(mktemp -d "$CI_TempPath/ZeroWrtRepo.XXXXXX")
trap 'rm -rf -- "$packageStage"' EXIT
for package in "${packages[@]}"; do
	if ! gh release download "$packageTag" --repo "$ZeroWrtRepo" \
		--pattern "$package.tar.gz" --output - | tar -xz -C "$packageStage"; then
		echo "Could not extract $package.tar.gz from $packageTag." >&2
		exit 1
	fi
	echo "Downloaded: $package"
done

for package in "${packages[@]}"; do
	findDeletePackage "$package"
done
mkdir -p "$PACKAGE_PATH"
cp -a "$packageStage/." "$PACKAGE_PATH/"
