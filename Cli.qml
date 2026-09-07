import QtQuick
import Quickshell
import qs.Commons

// Puts Tabarchy CLIs on PATH while the plugin is enabled, and removes those
// symlinks when the plugin is disabled or uninstalled.
Item {
  id: root

  property var manifest: null
  property var shell: null
  property string omarchyPath: ""

  readonly property string pluginDir: {
    var dir = root.manifest && root.manifest.__sourceDir ? String(root.manifest.__sourceDir) : ""
    return dir.replace(/\/$/, "")
  }
  readonly property var cliNames: ["omarchy-tabarchy-search", "omarchy-tabarchy-maps"]
  readonly property string binDir: (Quickshell.env("HOME") || "") + "/.local/bin"
  readonly property string cliSourceDir: root.pluginDir ? root.pluginDir + "/bin" : ""

  function installCli() {
    if (!root.cliSourceDir || !root.binDir) return
    var names = root.cliNames
    var i
    for (i = 0; i < names.length; i++) {
      var name = names[i]
      Util.execArgv(["bash", "-c", "mkdir -p \"$1\" && ln -sfn \"$2\" \"$3\"", "tabarchy-cli", root.binDir, root.cliSourceDir + "/" + name, root.binDir + "/" + name])
    }
  }

  function uninstallCli() {
    if (!root.cliSourceDir || !root.binDir) return
    var names = root.cliNames
    var i
    for (i = 0; i < names.length; i++) {
      var name = names[i]
      Util.execArgv(["bash", "-c", "target=$(readlink -f \"$1\" 2>/dev/null || true); source=$(readlink -f \"$2\" 2>/dev/null || true); [[ -L $1 && -n $target && $target == \"$source\" ]] && rm -f \"$1\"", "tabarchy-cli", root.binDir + "/" + name, root.cliSourceDir + "/" + name])
    }
  }

  Component.onCompleted: root.installCli()
  onCliSourceDirChanged: root.installCli()
  Component.onDestruction: root.uninstallCli()
}
