import QtQuick
import Quickshell
import qs.Commons

// Puts Tabarchy CLIs on PATH and a post-update rebase hook while enabled.
// Removes those when the plugin is disabled or uninstalled.
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
  readonly property string hookSrc: root.pluginDir ? root.pluginDir + "/scripts/tabarchy-post-update.sh" : ""
  readonly property string hookDest: (Quickshell.env("HOME") || "") + "/.config/omarchy/hooks/post-update.d/tabarchy-post-update.sh"

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

  function installHook() {
    if (!root.hookSrc || !root.hookDest) return
    var hookDir = root.hookDest.replace(/\/[^/]+$/, "")
    Util.execArgv(["bash", "-c", "mkdir -p \"$1\" && cp \"$2\" \"$3\" && chmod 755 \"$3\"", "tabarchy-hook", hookDir, root.hookSrc, root.hookDest])
  }

  function uninstallHook() {
    if (!root.hookDest) return
    Util.execArgv(["rm", "-f", root.hookDest])
  }

  Component.onCompleted: {
    root.installCli()
    root.installHook()
  }
  onCliSourceDirChanged: root.installCli()
  onHookSrcChanged: root.installHook()
  Component.onDestruction: {
    root.uninstallCli()
    root.uninstallHook()
  }
}
