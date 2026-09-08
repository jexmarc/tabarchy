#!/bin/bash

# Install or remove Tabarchy PATH links and the opt-in post-update hook.
# Replaces or deletes a destination only when it already belongs to this plugin.
# Foreign files are left untouched.

set -euo pipefail

PLUGIN_ID="io.github.jexmarc.tabarchy"
OWNED_MARKER="# tabarchy-owned: ${PLUGIN_ID}"
CLI_NAMES=(omarchy-tabarchy-search omarchy-tabarchy-maps)

usage() {
  echo "Usage: user-files.sh install-cli|uninstall-cli|install-hook|uninstall-hook <plugin-dir>" >&2
  exit 2
}

(($# == 2)) || usage

action=$1
plugin_dir=${2%/}

[[ $plugin_dir == /* ]] || {
  echo "tabarchy: plugin dir must be absolute" >&2
  exit 1
}

home=${HOME:-}
[[ -n $home ]] || {
  echo "tabarchy: HOME is unset" >&2
  exit 1
}

bin_dir=$home/.local/bin
hook_src=$plugin_dir/scripts/tabarchy-post-update.sh
hook_dest=$home/.config/omarchy/hooks/post-update.d/tabarchy-post-update.sh

notify() {
  if command -v omarchy-notification-send >/dev/null 2>&1; then
    omarchy-notification-send -g 󰍜 "$1"
  fi
}

same_link_target() {
  local dest=$1 src=$2
  [[ -L $dest ]] || return 1
  local dest_log src_abs dest_abs
  dest_log=$(readlink -- "$dest" 2>/dev/null || true)
  [[ $dest_log == "$src" ]] && return 0
  dest_abs=$(readlink -f -- "$dest" 2>/dev/null || true)
  src_abs=$(readlink -f -- "$src" 2>/dev/null || true)
  if [[ -n $dest_abs && -n $src_abs && $dest_abs == "$src_abs" ]]; then
    return 0
  fi
  return 1
}

legacy_hook() {
  local dest=$1
  [[ -f $dest && ! -L $dest ]] || return 1
  [[ $(basename -- "$dest") == tabarchy-post-update.sh ]] || return 1
  grep -q 'TABARCHY_PLUGIN_DIR' "$dest" || return 1
  grep -q 'refresh-from-omarchy.sh' "$dest" || return 1
  return 0
}

hook_owned() {
  local dest=$1 src=$2
  if [[ -L $dest ]]; then
    if same_link_target "$dest" "$src"; then
      return 0
    fi
    return 1
  fi
  [[ -f $dest ]] || return 1
  if [[ -f $src ]] && cmp -s -- "$dest" "$src"; then
    return 0
  fi
  if grep -qxF -- "$OWNED_MARKER" "$dest"; then
    return 0
  fi
  if legacy_hook "$dest"; then
    return 0
  fi
  return 1
}

install_cli() {
  local name src dest
  mkdir -p -- "$bin_dir"
  for name in "${CLI_NAMES[@]}"; do
    src=$plugin_dir/bin/$name
    dest=$bin_dir/$name
    if [[ ! -e $src ]]; then
      echo "tabarchy: missing $src" >&2
      continue
    fi
    if same_link_target "$dest" "$src"; then
      continue
    fi
    if [[ -e $dest || -L $dest ]]; then
      echo "tabarchy: refusing to replace $dest (not our symlink)" >&2
      notify "Tabarchy did not replace $dest (already exists)"
      continue
    fi
    ln -s -- "$src" "$dest"
  done
}

uninstall_cli() {
  local name src dest
  for name in "${CLI_NAMES[@]}"; do
    src=$plugin_dir/bin/$name
    dest=$bin_dir/$name
    if same_link_target "$dest" "$src"; then
      rm -f -- "$dest"
    fi
  done
}

install_hook() {
  if [[ ! -f $hook_src ]]; then
    echo "tabarchy: missing $hook_src" >&2
    return 1
  fi
  mkdir -p -- "$(dirname -- "$hook_dest")"
  if same_link_target "$hook_dest" "$hook_src"; then
    return 0
  fi
  if [[ -e $hook_dest || -L $hook_dest ]]; then
    if hook_owned "$hook_dest" "$hook_src"; then
      rm -f -- "$hook_dest"
    else
      echo "tabarchy: refusing to replace $hook_dest (not our hook)" >&2
      notify "Tabarchy did not replace $hook_dest (already exists)"
      return 0
    fi
  fi
  ln -s -- "$hook_src" "$hook_dest"
}

uninstall_hook() {
  if [[ -e $hook_dest || -L $hook_dest ]]; then
    if hook_owned "$hook_dest" "$hook_src"; then
      rm -f -- "$hook_dest"
    fi
  fi
}

case $action in
install-cli) install_cli ;;
uninstall-cli) uninstall_cli ;;
install-hook) install_hook ;;
uninstall-hook) uninstall_hook ;;
*) usage ;;
esac
