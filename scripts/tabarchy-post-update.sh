#!/bin/bash
# Rebase Tabarchy onto the current Omarchy menu after `omarchy update`.
# Installed into ~/.config/omarchy/hooks/post-update.d/ while Tabarchy is enabled.

set -u

plugin="${TABARCHY_PLUGIN_DIR:-$HOME/.config/omarchy/plugins/io.github.jexmarc.tabarchy}"
refresh="$plugin/scripts/refresh-from-omarchy.sh"

notify() {
  if command -v omarchy-notification-send >/dev/null 2>&1; then
    omarchy-notification-send -g 󰍜 "$1"
  fi
}

[[ -x $refresh ]] || exit 0

if "$refresh"; then
  notify "Tabarchy rebased onto the new Omarchy menu"
  if command -v omarchy >/dev/null 2>&1; then
    omarchy restart shell >/dev/null 2>&1 || true
  fi
  exit 0
fi

notify "Tabarchy could not patch this Omarchy menu. Super+Space still uses the last working Tabarchy. Update the plugin, or run: omarchy plugin disable io.github.jexmarc.tabarchy"
exit 0
