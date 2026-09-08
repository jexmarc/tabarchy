#!/bin/bash
# tabarchy-owned: io.github.jexmarc.tabarchy
#
# Opt-in notice after `omarchy update`. Does not rewrite reviewed Menu.qml,
# MenuModel.js, or BarWidget.qml. Those change only in a new plugin version.

set -u

PLUGIN_ID="io.github.jexmarc.tabarchy"
plugin="${TABARCHY_PLUGIN_DIR:-$HOME/.config/omarchy/plugins/${PLUGIN_ID}}"
baseline="$plugin/omarchy-baseline"
stock="${OMARCHY_PATH:-/usr/share/omarchy}/shell/plugins/menu"

notify() {
  if command -v omarchy-notification-send >/dev/null 2>&1; then
    omarchy-notification-send -g 󰍜 "$1"
  fi
}

file_hash() {
  local path=$1
  [[ -f $path ]] || return 1
  sha256sum -- "$path" | awk '{print $1}'
}

baseline_hash() {
  local name=$1
  [[ -f $baseline ]] || return 1
  awk -F= -v n="$name" '$1 == n { print $2; exit }' "$baseline"
}

stock_changed() {
  local name expected actual
  [[ -f $baseline ]] || return 0
  for name in Menu.qml MenuModel.js BarWidget.qml; do
    expected=$(baseline_hash "$name" || true)
    actual=$(file_hash "$stock/$name" || true)
    if [[ -z $expected || -z $actual || $expected != "$actual" ]]; then
      return 0
    fi
  done
  return 1
}

[[ -d $plugin ]] || exit 0
stock_changed || exit 0

notify "Omarchy's menu changed. Tabarchy kept its last reviewed snapshot. Update Tabarchy for a newly validated menu: omarchy plugin update ${PLUGIN_ID}"
exit 0
