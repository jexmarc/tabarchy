#!/bin/bash

# Maintainer snapshot tool. Rebuilds Tabarchy's reviewed menu files from the
# Omarchy install on this machine and records omarchy-baseline. Not invoked
# by the post-update hook. Ship the result as a new plugin version so
# Marketplace can validate it.

set -euo pipefail

root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
omarchy_path=${OMARCHY_PATH:-/usr/share/omarchy}
stock=$omarchy_path/shell/plugins/menu
patch=$root/patches/menu.patch

fail() {
  echo "refresh-from-omarchy: $*" >&2
  exit 1
}

if [[ ${1:-} != --write-snapshot ]]; then
  echo "refresh-from-omarchy: maintainer snapshot tool; refuses to run without --write-snapshot." >&2
  echo "This rewrites reviewed Menu.qml, MenuModel.js, and BarWidget.qml from $stock." >&2
  echo "Usage: $0 --write-snapshot" >&2
  echo "Then release a new plugin version for Marketplace validation." >&2
  exit 1
fi

[[ -f $stock/Menu.qml && -f $stock/MenuModel.js && -f $stock/BarWidget.qml ]] ||
  fail "stock omarchy.menu not found under $stock"
[[ -f $patch ]] || fail "missing patch $patch"

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
cp "$stock/Menu.qml" "$work/Menu.qml"

if ! patch -p0 --directory "$work" --forward --batch <"$patch"; then
  if command -v omarchy-notification-send >/dev/null 2>&1; then
    omarchy-notification-send -g 󰍜 "Tabarchy could not patch this Omarchy menu. Super+Space still uses the last working copy."
  fi
  fail "patches/menu.patch does not apply to $(omarchy version 2>/dev/null || echo 'this Omarchy menu'). Menu.qml was not changed."
fi

cp "$stock/MenuModel.js" "$root/MenuModel.js"
cp "$stock/BarWidget.qml" "$root/BarWidget.qml"
cp "$work/Menu.qml" "$root/Menu.qml"

{
  echo "# Stock omarchy.menu files this Tabarchy snapshot was built from."
  echo "# Runtime code must not copy these from /usr/share/omarchy."
  echo "omarchy_version=$(omarchy version 2>/dev/null || echo unknown)"
  echo "Menu.qml=$(sha256sum -- "$stock/Menu.qml" | awk '{print $1}')"
  echo "MenuModel.js=$(sha256sum -- "$stock/MenuModel.js" | awk '{print $1}')"
  echo "BarWidget.qml=$(sha256sum -- "$stock/BarWidget.qml" | awk '{print $1}')"
} >"$root/omarchy-baseline"

echo "Wrote Menu.qml, MenuModel.js, BarWidget.qml, and omarchy-baseline from $stock"
