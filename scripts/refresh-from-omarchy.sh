#!/bin/bash

# Rebuild Tabarchy's menu files from the Omarchy install on this machine.
# MenuModel.js and BarWidget.qml are copied unchanged. Menu.qml is that
# stock file plus patches/menu.patch.

set -euo pipefail

root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
omarchy_path=${OMARCHY_PATH:-/usr/share/omarchy}
stock=$omarchy_path/shell/plugins/menu
patch=$root/patches/menu.patch

fail() {
  echo "refresh-from-omarchy: $*" >&2
  exit 1
}

[[ -f $stock/Menu.qml && -f $stock/MenuModel.js && -f $stock/BarWidget.qml ]] ||
  fail "stock omarchy.menu not found under $stock"
[[ -f $patch ]] || fail "missing patch $patch"

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
cp "$stock/Menu.qml" "$work/Menu.qml"

if ! patch -p0 --directory "$work" --forward --batch <"$patch"; then
  fail "patches/menu.patch does not apply to $(omarchy version 2>/dev/null || echo 'this Omarchy menu'). Menu.qml was not changed. See README."
fi

cp "$stock/MenuModel.js" "$root/MenuModel.js"
cp "$stock/BarWidget.qml" "$root/BarWidget.qml"
cp "$work/Menu.qml" "$root/Menu.qml"

echo "Refreshed Menu.qml, MenuModel.js, and BarWidget.qml from $stock"
