import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons

// Puts Tabarchy CLIs on PATH while enabled. The post-update hook is installed
// only when settings postUpdateHook is true. Owned-link guards refuse foreign
// collisions and skip removal of files this plugin does not own.
Item {
  id: root

  property var manifest: null
  property var shell: null
  property string omarchyPath: ""
  property bool hookConsent: false

  readonly property string pluginDir: {
    var dir = root.manifest && root.manifest.__sourceDir ? String(root.manifest.__sourceDir) : ""
    if (dir) return dir.replace(/\/$/, "")
    var url = String(Qt.resolvedUrl("."))
    if (url.indexOf("file://") === 0) url = decodeURIComponent(url.substring(7))
    return url.replace(/\/$/, "")
  }
  readonly property string settingsPath: (Quickshell.env("HOME") || "") + "/.config/omarchy/tabarchy-settings.json"
  readonly property string userFiles: root.pluginDir ? root.pluginDir + "/scripts/user-files.sh" : ""

  function runUserFiles(action) {
    if (!root.userFiles || !root.pluginDir) return
    Util.execArgv(["bash", root.userFiles, action, root.pluginDir])
  }

  function installCli() {
    root.runUserFiles("install-cli")
  }

  function uninstallCli() {
    root.runUserFiles("uninstall-cli")
  }

  function syncHook() {
    root.runUserFiles(root.hookConsent ? "install-hook" : "uninstall-hook")
  }

  function hookConsentFromText(raw) {
    var text = String(raw || "").trim()
    if (!text) return false
    try {
      var data = JSON.parse(text)
      return !!(data && data.postUpdateHook === true)
    } catch (e) {
      return null
    }
  }

  Component.onCompleted: root.installCli()
  onPluginDirChanged: {
    root.installCli()
    root.syncHook()
  }
  Component.onDestruction: {
    root.uninstallCli()
    root.runUserFiles("uninstall-hook")
  }

  FileView {
    id: settingsFile
    path: root.settingsPath
    watchChanges: true
    printErrors: false
    onLoaded: {
      var consent = root.hookConsentFromText(text())
      if (consent === null) return
      root.hookConsent = consent
      root.syncHook()
    }
    onLoadFailed: {
      root.hookConsent = false
      root.syncHook()
    }
    onFileChanged: reload()
  }
}
