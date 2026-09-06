import QtQuick
import Quickshell
import qs.Commons

// Puts omarchy-tabarchy-search on PATH while Tabarchy is enabled, and
// removes that symlink when the plugin is disabled or uninstalled.
Item {
  id: root

  property var manifest: null
  property var shell: null
  property string omarchyPath: ""

  readonly property string pluginDir: {
    var dir = root.manifest && root.manifest.__sourceDir ? String(root.manifest.__sourceDir) : ""
    return dir.replace(/\/$/, "")
  }
  readonly property string cliSource: root.pluginDir ? root.pluginDir + "/bin/omarchy-tabarchy-search" : ""
  readonly property string cliDest: (Quickshell.env("HOME") || "") + "/.local/bin/omarchy-tabarchy-search"

  function installCli() {
    if (!root.cliSource || !root.cliDest) return
    var binDir = root.cliDest.replace(/\/[^/]+$/, "")
    Util.execArgv(["bash", "-c", "mkdir -p \"$1\" && ln -sfn \"$2\" \"$3\"", "tabarchy-cli", binDir, root.cliSource, root.cliDest])
  }

  function uninstallCli() {
    if (!root.cliSource || !root.cliDest) return
    Util.execArgv(["bash", "-c", "target=$(readlink -f \"$1\" 2>/dev/null || true); source=$(readlink -f \"$2\" 2>/dev/null || true); [[ -L $1 && -n $target && $target == \"$source\" ]] && rm -f \"$1\"", "tabarchy-cli", root.cliDest, root.cliSource])
  }

  Component.onCompleted: root.installCli()
  onCliSourceChanged: root.installCli()
  Component.onDestruction: root.uninstallCli()
}
