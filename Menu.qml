import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import qs.Commons
import qs.Ui
import "MenuModel.js" as MenuModel
import "Bangs.js" as Bangs

// Derived from Omarchy's omarchy.menu Menu.qml. Tabarchy-only behavior is
// the patch in patches/menu.patch. Do not overwrite these files from
// /usr/share/omarchy at runtime; cut a new plugin snapshot instead.

Item {
  id: root

  // Injected by omarchy-shell when this plugin is summoned.
  property string omarchyPath: Quickshell.env("OMARCHY_PATH")
  property var shell: null
  property var manifest: null

  // Plugin lifecycle hooks. The host calls open(payloadJson) after
  // `omarchy-shell shell summon omarchy.menu ...` and close() when hidden.
  property string pendingInitialMenu: "root"

  function open(payloadJson) {
    var payload = ({})
    try { payload = JSON.parse(payloadJson || "{}") } catch (e) { payload = ({}) }

    if (payload.fontFamily) root.fontFamily = payload.fontFamily

    if (payload.mode === "select" || payload.mode === "input") {
      root.openDmenu(payload)
    } else {
      root.openRoute(payload.initialMenu || payload.menu || "root")
    }
  }

  function close() {
    root.cancel()
  }

  function refresh() {
    defaultMenuFile.reload()
    userMenuFile.reload()
    return "ok"
  }

  function ping() { return "ok" }

  property string fontFamily: Style.font.menuFamily
  // JSONC menu definitions. The shell parses both at startup and merges
  // the user file on top of the defaults, so the keybind → IPC → visible
  // path doesn't have to shell out to bash + jq on every open.
  property string defaultMenuPath: omarchyPath + "/default/omarchy/omarchy-menu.jsonc"
  property string userMenuPath: Quickshell.env("HOME") + "/.config/omarchy/extensions/omarchy-menu.jsonc"
  property var defaultMenuItems: []
  property var userMenuItems: []
  property bool opened: false
  property string mode: "menu"
  readonly property bool dmenuActive: mode === "select" || mode === "input"
  property string dmenuPrompt: ""
  property var dmenuOptions: []
  property string selectionFile: ""
  property string doneFile: ""
  property int dmenuWidth: 300
  property int dmenuMaxHeight: 0
  property bool requestActive: false
  property bool rowsLoaded: false
  property string activeMenu: "root"
  property string filterText: ""
  property var bangs: Bangs.defaults()
  property var webAliases: Bangs.defaultWebAliases()
  property var jsoncAliases: ({})
  property var settingsAliases: ({})
  property var settingsData: ({})
  property string searchProvider: "google"
  property string mapsProvider: "google"
  property string settingsPage: "root"
  property string settingsAliasKey: ""
  property var activeBang: null
  property string bangQuery: ""
  property string bangStashKey: ""
  property string bangStashQuery: ""
  property var bangFileRows: []
  property int bangFilesGeneration: 0
  property var bangPkgRows: []
  property string bangPkgActiveQuery: ""
  property bool bangPkgSearching: false
  property bool bangPkgAborting: false
  readonly property string pluginDir: {
    var dir = root.manifest && root.manifest.__sourceDir ? String(root.manifest.__sourceDir) : ""
    if (dir) return dir.replace(/\/$/, "")
    var url = String(Qt.resolvedUrl("."))
    if (url.indexOf("file://") === 0) url = decodeURIComponent(url.substring(7))
    return url.replace(/\/$/, "")
  }
  readonly property string settingsPath: (Quickshell.env("HOME") || "") + "/.config/omarchy/tabarchy-settings.json"
  property int selectedIndex: 0
  property bool cursorActive: false
  property int requestSerial: 0
  property int applySerial: 0
  property var items: ({})
  property var itemOrder: []
  property var navStack: []
  property var providersLoaded: ({})
  property var providerQueue: []
  property int providerRevision: 0

  // Shared application engine (entries, hidden filters, icons, launch,
  // removal), owned by the shell and also used by the standalone launcher.
  readonly property var appLibrary: root.shell ? root.shell.appLibrary : null
  property bool deleteConfirmOpen: false
  property var deleteTarget: null
  property bool mdOpenOpen: false
  property string mdOpenPath: ""
  onOpenedChanged: if (!opened) {
    deleteConfirmOpen = false
    deleteTarget = null
    mdOpenOpen = false
    mdOpenPath = ""
  }
  // Bound to the central [menu] section in shell.toml via Color.qml.
  // Each color already includes its alpha companion (composed in the
  // singleton), so consumers can drop them straight into a Rectangle.
  property color background: Color.menu.background
  property color foreground: Color.menu.text
  property color border: Color.menu.border
  property var borderSpec: Border.surfaceSpec("menu", "border", border, Math.max(1, Style.space(2)))
  property color scrim: Color.menu.scrim
  property color selectedBackground: Color.menu.selectedBackground
  property color selectedText: Color.menu.selectedText
  property color selectedBorder: Color.menu.selectedBorder
  property var selectedBorderSpec: Border.surfaceSpec("menu", "selected-border", selectedBorder, 0)
  readonly property real rowReservedBorderLeft: Border.left(selectedBorderSpec)
  readonly property real rowReservedBorderRight: Border.right(selectedBorderSpec)
  readonly property int cornerRadius: Style.cornerRadius
  property int contentMargin: Style.spacing.panelPadding
  property int headerHeight: {
    var base = Math.max(Style.space(34), Style.font.title + Style.spacing.controlPaddingY * 2)
    if (!root.activeBang) return base
    var badge = Math.max(Style.font.caption + Style.space(4), Style.space(14))
    return Math.max(base, badge + Style.space(2) + Style.font.heading + Style.space(4))
  }
  property int contentSpacing: Style.spacing.md
  property int baseRowHeight: Math.max(Style.space(50), Style.font.body + Style.spacing.rowPaddingX * 2)
  property int detailRowHeight: Math.max(Style.space(58), Style.font.body + Style.font.caption + Style.spacing.rowPaddingX * 2)
  // How much of the first hidden row stays visible at the fold — enough to
  // read as a cut-off row rather than a bottom border.
  property int rowPeek: Math.round(baseRowHeight * 0.55)
  property int rowSpacing: Style.spacing.xs
  property int dividerHeight: Style.space(17)
  property bool searchDivider: false
  property int layoutSerial: 0
  readonly property bool pkgBang: root.activeBang && (root.activeBang.kind === "packages" || root.activeBang.kind === "remove-packages")
  readonly property bool pkgRemove: root.activeBang && root.activeBang.kind === "remove-packages"
  readonly property bool wideBang: root.pkgBang || (root.activeBang && (root.activeBang.kind === "files" || root.activeBang.kind === "web" || root.activeBang.kind === "help" || root.activeBang.kind === "maps" || root.activeBang.kind === "settings"))
  property int cardWidth: Math.min(root.dmenuActive ? Style.space(root.dmenuWidth) : (root.wideBang ? Style.space(600) : ((root.activeMenu === "trigger.capture.screenrecord" || root.activeMenu === "style.font") ? Style.space(520) : Style.space(300))), panel.width - Style.gapsOut * 2)
  property int visibleRowsHeight: root.dmenuActive ? dmenuRowListHeight(layoutSerial, displayModel.count, filterText) : rowListHeight(layoutSerial, displayModel.count, filterText, searchDivider)
  readonly property bool pkgPane: root.pkgBang
  readonly property bool pkgDetailVisible: root.pkgPane && displayModel.count > 0
  property int pkgDetailHeight: Style.space(72)
  readonly property bool helpPane: root.activeBang && root.activeBang.kind === "help"
  readonly property bool settingsPane: root.activeBang && root.activeBang.kind === "settings"
  readonly property bool navPane: root.helpPane || root.settingsPane
  readonly property bool settingsAliasesPage: root.settingsPane && (root.settingsPage === "aliases" || root.settingsPage === "alias-edit")
  property int helpNavHeight: Style.space(52)
  readonly property string selectedPkgDetail: {
    var _watch = root.layoutSerial
    if (!root.pkgDetailVisible || !root.cursorActive) return ""
    if (root.selectedIndex < 0 || root.selectedIndex >= displayModel.count) return ""
    var row = displayModel.get(root.selectedIndex)
    if (!row || row.kind !== "bang-pkg") return ""
    return row.detail || ""
  }
  property int cardHeight: root.dmenuActive
    ? Math.min(contentMargin * 2 + headerHeight + (mode === "input" ? 0 : contentSpacing + visibleRowsHeight), panel.height - Style.gapsOut * 2)
    : Math.min(contentMargin * 2 + headerHeight + contentSpacing + visibleRowsHeight + (root.pkgDetailVisible ? contentSpacing + pkgDetailHeight : 0) + (root.navPane ? contentSpacing + helpNavHeight : 0), panel.height - Style.gapsOut * 2)

  function finishRequest(selection) {
    if (!root.requestActive || !root.doneFile) {
      root.opened = false
      return
    }

    var activeSelectionFile = root.selectionFile
    var activeDoneFile = root.doneFile
    root.requestActive = false
    root.selectionFile = ""
    root.doneFile = ""

    if (selection === null || selection === undefined) {
      resultProc.command = ["bash", "-c", ": > " + Util.shellQuote(activeDoneFile)]
    } else {
      resultProc.command = ["bash", "-c", "printf '%s\\n' " + Util.shellQuote(selection) + " > " + Util.shellQuote(activeSelectionFile) + "; : > " + Util.shellQuote(activeDoneFile)]
    }
    resultProc.running = true
  }

  function runAction(action) {
    var command = String(action || "")
    if (!command) return

    Util.execDetached(command)
  }

  // Menu rows only surface their detail while a search is narrowing them;
  // dmenu rows carry caller-supplied subtext that must always be visible.
  function rowHeightForDetail(detail) {
    return (root.filterText || root.dmenuActive || root.activeBang) && detail ? root.detailRowHeight : root.baseRowHeight
  }

  function clearBang() {
    root.activeBang = null
    root.bangQuery = ""
    root.settingsPage = "root"
    root.settingsAliasKey = ""
    root.bangFileRows = []
    root.bangPkgRows = []
    root.bangPkgSearching = false
    root.bangPkgActiveQuery = ""
    root.bangPkgAborting = bangPkgProc.running
    root.bangFilesGeneration += 1
    bangFilesProc.running = false
    bangFilesTimer.stop()
    bangPkgProc.running = false
    bangPkgTimer.stop()
  }

  function bangLookup(letter) {
    var key = String(letter || "").toLowerCase()
    if (key.length !== 1) return null
    return root.bangs[key] || null
  }

  function enterBang(bang) {
    panel.freezeCardTop()
    root.activeBang = bang
    root.settingsPage = "root"
    root.settingsAliasKey = ""
    root.bangQuery = (bang.kind === "settings") ? "" : ((root.bangStashKey === bang.key) ? root.bangStashQuery : "")
    root.filterText = ""
    root.bangFileRows = []
    root.bangPkgRows = []
    root.selectedIndex = 0
    root.cursorActive = (bang.kind !== "files" && bang.kind !== "packages" && bang.kind !== "remove-packages") || !!root.bangQuery
    root.disarmPointer()
    if (bang.kind === "files") root.scheduleBangFiles()
    if (bang.kind === "packages" || bang.kind === "remove-packages") {
      root.bangPkgSearching = root.bangQuery.trim().length >= 2
      root.scheduleBangPackages()
    }
    root.rebuildDisplay()
  }

  function exitBang(restoreLetter) {
    var key = root.activeBang ? root.activeBang.key : ""
    root.bangStashKey = key
    root.bangStashQuery = root.bangQuery
    root.clearBang()
    if (restoreLetter && key) root.setFilter(key)
    else root.setFilter("")
  }

  function tryEnterBang() {
    if (root.dmenuActive || root.activeBang) return false
    var typed = root.filterText
    if (!typed || typed.length !== 1) return false
    var bang = root.bangLookup(typed)
    if (!bang) return false
    root.enterBang(bang)
    return true
  }

  function toggleBang() {
    if (root.dmenuActive) return
    if (root.activeBang) root.exitBang(true)
    else root.tryEnterBang()
  }

  function isCtrlOnly(event) {
    var mods = event.modifiers
    return !!(mods & Qt.ControlModifier)
      && !(mods & Qt.AltModifier)
      && !(mods & Qt.MetaModifier)
      && !(mods & Qt.ShiftModifier)
  }

  function isPasteKey(event) {
    var mods = event.modifiers
    if (event.key === Qt.Key_Insert)
      return !!(mods & Qt.ShiftModifier) && !(mods & Qt.ControlModifier) && !(mods & Qt.AltModifier) && !(mods & Qt.MetaModifier)
    if (event.key !== Qt.Key_V) return false
    if (mods & Qt.AltModifier) return false
    if ((mods & Qt.ControlModifier) && (mods & Qt.MetaModifier)) return false
    return !!(mods & Qt.ControlModifier) || !!(mods & Qt.MetaModifier)
  }

  function requestPaste() {
    pasteProc.running = false
    pasteProc.command = ["wl-paste", "--no-newline", "--type", "text"]
    pasteProc.running = true
  }

  function applyPaste(raw) {
    var clip = String(raw || "").replace(/\r/g, "").replace(/\n+/g, " ").trim()
    if (!clip) return
    if (clip.length > 500) clip = clip.slice(0, 500)
    if (root.activeBang) root.setBangQuery(root.bangQuery + clip)
    else root.setFilter(root.filterText + clip)
  }

  function setBangQuery(nextQuery) {
    panel.freezeCardTop()
    root.bangQuery = nextQuery
    root.selectedIndex = 0
    root.cursorActive = true
    root.disarmPointer()
    if (root.activeBang && root.activeBang.kind === "files") root.scheduleBangFiles()
    if (root.pkgBang) {
      root.bangPkgSearching = nextQuery.trim().length >= 2
      root.scheduleBangPackages()
    }
    root.rebuildDisplay()
  }

  function bangEmptyText() {
    if (!root.activeBang) return ""
    if (root.pkgBang) {
      if (root.bangQuery.trim().length < 2) return "Type at least two characters"
      if (root.bangPkgSearching)
        return root.pkgRemove ? "Searching installed packages…" : "Searching Arch, Omarchy, and AUR…"
    }
    if (root.settingsPane) {
      if (root.settingsPage === "alias-edit") return "Type the new URL"
      if (root.settingsPage === "search" || root.settingsPage === "maps")
        return root.bangQuery ? "No matches for “" + root.bangQuery + "”" : "Type a URL with %s for a custom provider"
    }
    if (root.bangQuery) return "No matches for “" + root.bangQuery + "”"
    if (root.activeBang.placeholder) return "Type " + root.activeBang.placeholder
    return "Type to continue"
  }

  function headerBangName() {
    if (!root.activeBang) return ""
    var name = root.activeBang.name
    if (root.activeBang.key === "i" && name === "install") name = "install pkg"
    if (root.activeBang.key === "r" && name === "remove") name = "remove pkg"
    if (root.settingsPane) {
      if (root.settingsPage === "search") name = "search"
      else if (root.settingsPage === "maps") name = "maps"
      else if (root.settingsPage === "aliases" || root.settingsPage === "alias-edit") name = "aliases"
    }
    return name
  }

  function headerText() {
    if (root.activeBang)
      return root.headerBangName() + ":" + (root.bangQuery ? " " + root.bangQuery : "")
    if (root.filterText) return root.filterText
    if (root.dmenuActive) return root.dmenuPrompt + "…"
    var current = root.item(root.activeMenu)
    return ((current ? (current.title || current.label) : "Go") + "…")
  }

  function refreshWebAliases() {
    root.webAliases = Bangs.mergeAliases(
      Bangs.mergeAliases(Bangs.defaultWebAliases(), root.jsoncAliases),
      root.settingsAliases
    )
  }

  function settingsGoBack() {
    if (!root.settingsPane) return false
    if (root.settingsPage === "root") return false
    if (root.settingsPage === "alias-edit") {
      root.settingsPage = "aliases"
      root.settingsAliasKey = ""
      root.setBangQuery("")
      return true
    }
    root.settingsPage = "root"
    root.setBangQuery("")
    return true
  }

  function openSettingsPage(page, query) {
    root.settingsPage = page
    root.setBangQuery(query || "")
  }

  function bangSettingsRow(spec, index) {
    return {
      itemId: spec.itemId || ("bang.settings." + index),
      disabled: !!spec.disabled,
      kind: "bang-settings",
      icon: spec.icon || "󰒓",
      iconFont: "",
      appIcon: "",
      appId: "",
      label: spec.label || "",
      target: spec.target || "",
      detail: spec.detail || "",
      path: spec.path || "",
      childCount: spec.childCount || 0,
      action: spec.action || "",
      provider: spec.provider || "",
      score: index,
      section: ""
    }
  }

  function appendSettingsRows(rows) {
    for (var i = 0; i < rows.length; i++)
      displayModel.append(root.bangSettingsRow(rows[i], i))
  }

  function rebuildSettingsDisplay() {
    var query = String(root.bangQuery || "")
    var q = query.trim()
    var rows = []
    var i

    if (root.settingsPage === "search") {
      var searchChoices = Bangs.providerChoices(Bangs.searchProviders(), Bangs.searchProviderOrder(), root.searchProvider, Bangs.resolveSearchProvider)
      for (i = 0; i < searchChoices.length; i++) {
        var search = searchChoices[i]
        var searchLabel = (search.current ? "✓  " : "") + search.name
        var searchDetail = search.id === "custom" ? (search.url || "URL with %s") : ""
        if (!Bangs.settingsMatch(searchLabel, searchDetail, search.id, q) && search.id !== "custom") continue
        if (search.id === "custom" && q && !Bangs.settingsMatch(searchLabel, searchDetail, search.id, q) && !Bangs.isHttpProviderTemplate(q)) continue
        rows.push({
          itemId: "bang.settings.search." + search.id,
          icon: "󰍉",
          label: searchLabel,
          detail: searchDetail,
          target: search.id === "custom" ? "set-search-custom" : "set-search",
          path: search.id === "custom" ? "" : search.id,
          provider: search.current ? "current" : ""
        })
      }
    } else if (root.settingsPage === "maps") {
      var mapsChoices = Bangs.providerChoices(Bangs.mapsProviders(), Bangs.mapsProviderOrder(), root.mapsProvider, Bangs.resolveMapsProvider)
      for (i = 0; i < mapsChoices.length; i++) {
        var maps = mapsChoices[i]
        var mapsLabel = (maps.current ? "✓  " : "") + maps.name
        var mapsDetail = maps.id === "custom" ? (maps.url || "URL with %s") : ""
        if (!Bangs.settingsMatch(mapsLabel, mapsDetail, maps.id, q) && maps.id !== "custom") continue
        if (maps.id === "custom" && q && !Bangs.settingsMatch(mapsLabel, mapsDetail, maps.id, q) && !Bangs.isHttpProviderTemplate(q)) continue
        rows.push({
          itemId: "bang.settings.maps." + maps.id,
          icon: "󰗵",
          label: mapsLabel,
          detail: mapsDetail,
          target: maps.id === "custom" ? "set-maps-custom" : "set-maps",
          path: maps.id === "custom" ? "" : maps.id,
          provider: maps.current ? "current" : ""
        })
      }
    } else if (root.settingsPage === "alias-edit") {
      var editKey = root.settingsAliasKey
      var editUrl = q ? Bangs.toUrl(q) : ""
      rows.push({
        itemId: "bang.settings.alias.save",
        icon: "",
        label: "Save " + editKey,
        detail: editUrl || "type a URL",
        target: "alias-save",
        path: editKey,
        disabled: !editUrl
      })
    } else if (root.settingsPage === "aliases") {
      var parsed = Bangs.parseAliasInput(query)
      if (parsed) {
        var existing = root.webAliases[parsed.key]
        rows.push({
          itemId: "bang.settings.alias.save",
          icon: "",
          label: (existing ? "Update " : "Add ") + parsed.key,
          detail: parsed.url,
          target: "alias-save",
          path: parsed.key
        })
      } else if (!q) {
        rows.push({
          itemId: "bang.settings.alias.add",
          icon: "",
          label: "Add alias",
          detail: "name  url",
          target: "alias-add"
        })
      }
      var aliases = Bangs.sortedAliases(root.webAliases)
      for (i = 0; i < aliases.length; i++) {
        var alias = aliases[i]
        if (!parsed && q && !Bangs.settingsMatch(alias.key, alias.url, "", q)) continue
        if (parsed && alias.key !== parsed.key) continue
        rows.push({
          itemId: "bang.settings.alias." + alias.key,
          icon: "",
          label: alias.name || alias.key,
          detail: alias.url,
          target: "alias-edit",
          path: alias.key,
          childCount: 1
        })
      }
    } else {
      var searchName = Bangs.resolveSearchProvider(root.searchProvider).name
      var mapsName = Bangs.resolveMapsProvider(root.mapsProvider).name
      var aliasDetail = Bangs.aliasSummary(root.webAliases)
      var hookOn = Bangs.postUpdateHookEnabled(root.settingsData)
      var rootRows = [
        { itemId: "bang.settings.search", icon: "󰍉", label: "Search provider", detail: searchName, target: "search", childCount: 1 },
        { itemId: "bang.settings.maps", icon: "󰗵", label: "Maps provider", detail: mapsName, target: "maps", childCount: 1 },
        { itemId: "bang.settings.aliases", icon: "", label: "Aliases", detail: aliasDetail, target: "aliases", childCount: 1 },
        { itemId: "bang.settings.hook", icon: "󰚰", label: "After Omarchy updates", detail: hookOn ? "On — notify, keep the reviewed menu" : "Off — keep the reviewed menu until Tabarchy updates", target: "toggle-hook" },
        { itemId: "bang.settings.edit", icon: "", label: "Edit config file", detail: "~/.config/omarchy/tabarchy.jsonc", target: "edit-config" }
      ]
      for (i = 0; i < rootRows.length; i++) {
        if (!Bangs.settingsMatch(rootRows[i].label, rootRows[i].detail, "", q)) continue
        rows.push(rootRows[i])
      }
    }

    root.appendSettingsRows(rows)
  }

  function setSearchProviderValue(value) {
    var resolved = Bangs.resolveSearchProvider(value)
    var stored = resolved.id === "custom" ? String(value || "").trim() : resolved.id
    root.searchProvider = stored
    Util.execArgv([root.pluginDir + "/bin/omarchy-tabarchy-search", stored])
    root.rebuildDisplay()
  }

  function setMapsProviderValue(value) {
    var resolved = Bangs.resolveMapsProvider(value)
    var stored = resolved.id === "custom" ? String(value || "").trim() : resolved.id
    root.mapsProvider = stored
    Util.execArgv([root.pluginDir + "/bin/omarchy-tabarchy-maps", stored])
    root.rebuildDisplay()
  }

  function writeSettingsText(text) {
    settingsWriteProc.running = false
    settingsWriteProc.command = ["bash", "-c", "mkdir -p \"$(dirname \"$1\")\" && printf '%s' \"$2\" > \"$1.tmp\" && mv \"$1.tmp\" \"$1\"", "tabarchy-settings", root.settingsPath, text]
    settingsWriteProc.running = true
  }

  function cloneSettingsData() {
    var src = root.settingsData || {}
    var data = {}
    var field
    for (field in src) {
      if (Object.prototype.hasOwnProperty.call(src, field))
        data[field] = src[field]
    }
    return data
  }

  function writeSettingsData(data) {
    root.settingsData = data
    root.settingsAliases = Bangs.settingsAliasesFromData(data)
    root.refreshWebAliases()
    root.writeSettingsText(JSON.stringify(data, null, 2) + "\n")
  }

  function setPostUpdateHook(enabled) {
    var data = root.cloneSettingsData()
    data.postUpdateHook = !!enabled
    root.writeSettingsData(data)
    root.rebuildDisplay()
  }

  function setSettingsAlias(key, value) {
    var k = String(key || "").trim().toLowerCase()
    if (!Bangs.isAliasKey(k)) return
    var src = root.settingsData || {}
    var data = {}
    var field
    for (field in src) {
      if (Object.prototype.hasOwnProperty.call(src, field) && field !== "aliases")
        data[field] = src[field]
    }
    var aliases = {}
    var current = (src.aliases && typeof src.aliases === "object" && !Array.isArray(src.aliases)) ? src.aliases : {}
    var aliasKey
    for (aliasKey in current) {
      if (Object.prototype.hasOwnProperty.call(current, aliasKey))
        aliases[aliasKey] = current[aliasKey]
    }
    aliases[k] = value
    data.aliases = aliases
    root.settingsData = data
    root.settingsAliases = Bangs.settingsAliasesFromData(data)
    root.refreshWebAliases()
    root.writeSettingsText(JSON.stringify(data, null, 2) + "\n")
  }

  function saveSettingsAlias(key, url) {
    root.setSettingsAlias(key, url)
    root.settingsPage = "aliases"
    root.settingsAliasKey = ""
    root.setBangQuery("")
  }

  function deleteSettingsAlias(key) {
    root.setSettingsAlias(key, false)
    if (root.settingsAliasKey === key) {
      root.settingsPage = "aliases"
      root.settingsAliasKey = ""
    }
    root.setBangQuery("")
  }

  function openTabarchyConfig() {
    var dest = (Quickshell.env("HOME") || "") + "/.config/omarchy/tabarchy.jsonc"
    var src = root.pluginDir + "/tabarchy.jsonc"
    applySerial = requestSerial
    opened = false
    root.clearBang()
    filterText = ""
    Util.execArgv(["bash", "-c", "mkdir -p \"$HOME/.config/omarchy\"; [[ -f $1 ]] || cp \"$2\" \"$1\"; omarchy-launch-editor \"$1\"", "tabarchy-edit", dest, src])
  }

  function scheduleBangFiles() {
    bangFilesTimer.restart()
  }

  function scheduleBangPackages() {
    bangPkgTimer.restart()
  }

  function startBangFiles() {
    if (!root.activeBang || root.activeBang.kind !== "files") return
    var query = root.bangQuery.trim()
    root.bangFilesGeneration += 1
    bangFilesProc.running = false
    if (!query) {
      root.bangFileRows = []
      root.rebuildDisplay()
      return
    }

    bangFilesProc.generation = root.bangFilesGeneration
    bangFilesProc.collected = ""
    bangFilesProc.command = [
      "bash", "-c",
      "fd --color=never --absolute-path --no-ignore-vcs --type d --max-results 25 --exclude .git --exclude node_modules --exclude .venv --exclude venv --format 'd|{}' -- \"$1\" \"$2\"\n" +
      "fd --color=never --absolute-path --no-ignore-vcs --type f --max-results 25 --exclude .git --exclude node_modules --exclude .venv --exclude venv --format 'f|{}' -- \"$1\" \"$2\"",
      "tabarchy-fd",
      query,
      Quickshell.env("HOME") || ""
    ]
    bangFilesProc.running = true
  }

  function startBangPackages() {
    if (!root.pkgBang) return
    var query = root.bangQuery.trim()
    var script = root.pluginDir + "/bin/tabarchy-pkg-search"
    if (query.length < 2) {
      root.bangPkgAborting = bangPkgProc.running
      bangPkgProc.running = false
      root.bangPkgSearching = false
      root.bangPkgActiveQuery = ""
      root.bangPkgRows = []
      root.rebuildDisplay()
      return
    }

    root.bangPkgSearching = true
    if (bangPkgProc.running) {
      root.rebuildDisplay()
      return
    }

    root.bangPkgActiveQuery = query
    bangPkgProc.command = root.pkgRemove
      ? ["/usr/bin/python3", script, "--installed", "--", query]
      : ["/usr/bin/python3", script, "--", query]
    bangPkgProc.running = true
    root.rebuildDisplay()
  }

  function bangHelpRow(bang, index) {
    var command = bang.kind !== "help" && bang.kind !== "help-key"
    return {
      itemId: "bang.help." + bang.key,
      disabled: false,
      kind: "bang-help",
      icon: bang.icon,
      iconFont: bang.iconFont || "",
      appIcon: "",
      appId: "",
      label: bang.key + "  " + (bang.name || bang.key),
      target: command ? bang.key : "",
      detail: Bangs.bangHelpText(bang),
      path: "",
      childCount: command ? 1 : 0,
      action: "",
      provider: "",
      score: index,
      section: ""
    }
  }

  function bangWebRow(choice, index, bang) {
    var icon = bang.icon
    if (choice.kind === "alias") icon = ""
    else if (choice.kind === "search") icon = "󰍉"
    return {
      itemId: "bang.web." + index,
      disabled: false,
      kind: "bang",
      icon: icon,
      iconFont: bang.iconFont || "",
      appIcon: "",
      appId: "",
      label: choice.label,
      target: "",
      detail: choice.detail,
      path: "",
      childCount: 0,
      action: choice.action,
      provider: choice.kind,
      score: index,
      section: ""
    }
  }

  function bangFileRow(entry, index) {
    var path = entry && typeof entry === "object" ? String(entry.path || "") : String(entry || "")
    var isDir = !!(entry && typeof entry === "object" && entry.isDir)
    if (!isDir && path.slice(-1) === "/") isDir = true
    return {
      itemId: "bang.file." + index,
      disabled: false,
      kind: "bang-file",
      icon: isDir ? "" : "",
      iconFont: "",
      appIcon: "",
      appId: "",
      label: Bangs.fileLabel(path) + (isDir ? "/" : ""),
      target: "",
      detail: path,
      path: path,
      childCount: 0,
      action: path,
      provider: isDir ? "dir" : "",
      score: index,
      section: ""
    }
  }

  function bangPkgRow(line, index) {
    var parts = String(line || "").split("\t")
    var name = parts[0] || ""
    var repo = parts[1] || ""
    var installed = parts[2] === "1"
    var description = parts.slice(3).join("\t")
    var removing = root.pkgRemove
    var command = removing
      ? "omarchy-pkg-drop"
      : (repo === "aur" ? "omarchy-pkg-aur-add" : "omarchy-pkg-add")
    var source = repo === "aur" ? "AUR" : (repo === "omarchy" ? "Omarchy" : (repo === "local" ? "" : repo))
    var detailParts = []
    if (source) detailParts.push(source)
    if (description) detailParts.push(description)
    return {
      itemId: "bang.pkg." + index,
      disabled: removing ? false : installed,
      kind: "bang-pkg",
      icon: repo === "aur" ? "" : "󰏖",
      iconFont: "",
      appIcon: "",
      appId: "",
      label: name,
      target: "",
      detail: detailParts.join(" · "),
      path: repo,
      childCount: 0,
      action: "omarchy-launch-floating-terminal-with-presentation " + command + " " + Util.shellQuote(name),
      provider: (!removing && installed) ? "installed" : "",
      score: index,
      section: ""
    }
  }

  function rebuildBangDisplay() {
    displayModel.clear()
    root.searchDivider = false

    var bang = root.activeBang
    if (!bang) {
      layoutSerial += 1
      return
    }

    if (bang.kind === "files") {
      for (var i = 0; i < root.bangFileRows.length; i++)
        displayModel.append(root.bangFileRow(root.bangFileRows[i], i))
    } else if (bang.kind === "packages" || bang.kind === "remove-packages") {
      for (var p = 0; p < root.bangPkgRows.length; p++)
        displayModel.append(root.bangPkgRow(root.bangPkgRows[p], p))
    } else if (bang.kind === "help") {
      var helpQuery = String(root.bangQuery || "").trim().toLowerCase()
      var keys = Bangs.helpKeys(root.bangs)
      var shown = 0
      for (var h = 0; h < keys.length; h++) {
        var item = root.bangs[keys[h]]
        if (!item || item.disabled) continue
        if (helpQuery) {
          var hay = (item.key + " " + item.name + " " + Bangs.bangHelpText(item)).toLowerCase()
          if (hay.indexOf(helpQuery) < 0) continue
        }
        displayModel.append(root.bangHelpRow(item, shown))
        shown += 1
      }
    } else if (bang.kind === "web") {
      var choices = Bangs.webChoices(root.bangQuery, root.webAliases, root.searchProvider, Util.shellQuote)
      if (choices.length === 0) {
        displayModel.append({
          itemId: "bang." + bang.key,
          disabled: true,
          kind: "bang",
          icon: bang.icon,
          iconFont: bang.iconFont,
          appIcon: "",
          appId: "",
          label: bang.label || bang.name,
          target: "",
          detail: bang.placeholder,
          path: "",
          childCount: 0,
          action: "",
          provider: "",
          score: 0,
          section: ""
        })
      } else {
        for (var w = 0; w < choices.length; w++)
          displayModel.append(root.bangWebRow(choices[w], w, bang))
      }
    } else if (bang.kind === "maps") {
      var dest = Bangs.mapsDestination(root.bangQuery, root.mapsProvider, Util.shellQuote)
      var mapsMissing = bang.requiresQuery && !String(root.bangQuery || "").trim()
      displayModel.append({
        itemId: "bang." + bang.key,
        disabled: mapsMissing,
        kind: "bang",
        icon: bang.icon,
        iconFont: bang.iconFont,
        appIcon: "",
        appId: "",
        label: dest.label || bang.label || bang.name,
        target: "",
        detail: dest.detail || bang.placeholder,
        path: "",
        childCount: 0,
        action: dest.action,
        provider: "",
        score: 0,
        section: ""
      })
    } else if (bang.kind === "settings") {
      root.rebuildSettingsDisplay()
    } else {
      var query = root.bangQuery
      var missing = bang.requiresQuery && !String(query).trim()
      var label = bang.label || bang.name
      var detail = String(query).trim() || bang.placeholder
      var action = missing ? "" : Bangs.expandAction(bang.action, query, Util.shellQuote)
      displayModel.append({
        itemId: "bang." + bang.key,
        disabled: missing,
        kind: "bang",
        icon: bang.icon,
        iconFont: bang.iconFont,
        appIcon: "",
        appId: "",
        label: label,
        target: "",
        detail: detail,
        path: "",
        childCount: 0,
        action: action,
        provider: "",
        score: 0,
        section: ""
      })
    }

    layoutSerial += 1
    root.settleCursor()
    Qt.callLater(function() {
      if (displayModel.count > 0) root.revealCursor()
    })
  }

  // Height the card can devote to rows before running off the screen — or
  // past the frozen top edge once a search has pinned the card in place.
  // Uses panel.cardTop rather than effectiveCardTop: the centered top is
  // derived from the card height, which this value feeds.
  function availableRowsHeight() {
    var top = panel.cardTop >= 0 ? panel.cardTop : Style.gapsOut
    var available = panel.height - top - Style.gapsOut - root.contentMargin * 2 - root.headerHeight - root.contentSpacing
    // The starting menu sets the ceiling along with the offset: drilling into
    // a longer submenu scrolls behind the fold instead of growing the card.
    if (panel.maxRowsHeight >= 0) available = Math.min(available, panel.maxRowsHeight)
    // A card that swallows the whole screen reads as a page, not a menu.
    return Math.min(available, Math.round(panel.height * 0.7))
  }

  // When every row fits, the list gets its full height. When they don't,
  // the card must end mid-row: a clipped row is what tells the eye there is
  // more below the fold, so never come out even on a row boundary.
  function foldedListHeight(totals, available) {
    var count = totals.length
    if (count === 0) return root.baseRowHeight
    if (totals[count - 1] <= available) return totals[count - 1]

    var peek = root.rowPeek
    var full = 0
    while (full < count && totals[full] <= available) full++
    while (full > 1 && totals[full - 1] + root.rowSpacing + peek > available) full--
    if (full < 1) return Math.max(available, root.baseRowHeight)

    return totals[full - 1] + root.rowSpacing + peek
  }

  function rowListHeight(_serial, _count, _filter, _divider) {
    if (displayModel.count === 0) return root.baseRowHeight

    var totals = []
    var total = 0
    var previousSection = ""

    for (var i = 0; i < displayModel.count; i++) {
      var row = displayModel.get(i)
      if (i > 0) total += root.rowSpacing
      if (row.section === "drilldown" && previousSection !== "drilldown") total += root.dividerHeight
      total += root.rowHeightForDetail(row.detail)
      previousSection = row.section
      totals.push(total)
    }

    return foldedListHeight(totals, availableRowsHeight())
  }

  function dmenuRowListHeight(_serial, _count, _filter) {
    if (root.mode === "input") return 0
    if (displayModel.count === 0) return root.baseRowHeight

    var available = availableRowsHeight()
    if (root.dmenuMaxHeight > 0) available = Math.min(available, Style.space(root.dmenuMaxHeight))

    var totals = []
    var total = 0
    for (var i = 0; i < displayModel.count; i++) {
      if (i > 0) total += root.rowSpacing
      total += root.rowHeightForDetail(displayModel.get(i).detail)
      totals.push(total)
    }

    return foldedListHeight(totals, available)
  }

  function item(id) {
    return root.items[id] || null
  }

  // ------------------------------------------------------------------
  // JSONC → normalized item array. Mirrors the bash bin's jq pipeline so
  // the on-disk authoring format stays untouched.
  // ------------------------------------------------------------------

  function stripJsonc(raw) {
    return MenuModel.stripJsonc(raw)
  }

  function normalizeAliases(value) {
    return MenuModel.normalizeAliases(value)
  }

  function normalizeItem(id, raw) {
    return MenuModel.normalizeItem(id, raw)
  }

  function parseMenuJsonc(raw) {
    return MenuModel.parseMenuJsonc(raw)
  }

  // Merge defaults + user extension. Later entries override earlier ones
  // on a per-key basis (so the user can tweak label/icon/action without
  // re-declaring the whole row).
  function rebuildItemsFromSources() {
    var mergedMenu = MenuModel.mergeMenuSources(root.defaultMenuItems, root.userMenuItems)
    root.providerRevision += 1
    root.providersLoaded = ({})
    root.providerQueue = []
    root.items = mergedMenu.items
    root.itemOrder = mergedMenu.itemOrder
    root.rowsLoaded = true
    root.evaluateGuards()
    if (root.opened) {
      root.rebuildDisplay()
      if (!root.dmenuActive) {
        if (root.filterText.trim()) root.loadProvidersForSearch()
        else root.loadProviderForMenu(root.activeMenu)
      }
    }
  }

  // Each known provider is a tiny bash one-liner that enumerates a list and
  // emits one tab-delimited row per item: `label\tvalue\tcurrent`. The shell
  // turns those into menu items children of `menuId`. A `volatile` provider
  // re-runs every time its submenu is entered, so a font installed since the
  // shell started shows up without restarting it.
  readonly property var providers: ({
    "fonts": {
      script: "current=$(omarchy-font-current 2>/dev/null); omarchy-font-list 2>/dev/null | while read -r f; do [[ -z $f ]] && continue; printf '%s\\t%s\\t%s\\n' \"$f\" \"$f\" \"$current\"; done",
      icon: "",
      volatile: true,
      actionFor: function(value) { return "omarchy-font-set " + Util.shellQuote(value) }
    },
    "power-profiles": {
      script: "current=$(powerprofilesctl get 2>/dev/null); omarchy-powerprofiles-list 2>/dev/null | while read -r p; do [[ -z $p ]] && continue; printf '%s\\t%s\\t%s\\n' \"$p\" \"$p\" \"$current\"; done",
      icon: "\udb81\udc0b",
      actionFor: function(value) { return "omarchy-powerprofiles-set autodetect " + Util.shellQuote(value) }
    }
  })

  function slugify(value) {
    return MenuModel.slugify(value)
  }

  // The apps provider is QML-native: rows come from the shared AppLibrary
  // (DesktopEntries) instead of a bash enumeration, so they carry image
  // icons, launch feedback, and uninstall support like the launcher.
  function fallbackSortedEntries() {
    var out = []
    try {
      var values = DesktopEntries.applications.values || []
      for (var i = 0; i < values.length; i++) {
        var entry = values[i]
        if (!entry || entry.noDisplay) continue
        var name = String(entry.name || entry.id || "")
        if (!name) continue
        out.push({ entry: entry, score: 0 })
      }
    } catch (e) {
    }
    return out
  }

  function mergeAppRows() {
    var rows = []
    if (root.appLibrary) {
      try { rows = root.appLibrary.sortedEntries("") || [] } catch (e) { rows = [] }
    }
    if (!rows.length) rows = root.fallbackSortedEntries()
    var appRows = []
    for (var j = 0; j < rows.length; j++) {
      var packed = rows[j]
      var entry = packed && packed.entry ? packed.entry : packed
      if (!entry) continue
      var appId = String(entry.id || "")
      if (!appId) continue
      var subtext = root.appLibrary ? root.appLibrary.entrySubtext(entry) : String(entry.genericName || "")
      var aliases = subtext ? [subtext] : []
      try {
        if (entry.keywords && typeof entry.keywords.join === "function") aliases = aliases.concat(entry.keywords)
      } catch (e) { }
      appRows.push({
        id: "apps." + appId,
        parent: "apps",
        kind: "app",
        icon: "",
        appIcon: String(entry.icon || ""),
        appId: appId,
        label: root.appLibrary ? root.appLibrary.entryName(entry) : String(entry.name || appId),
        title: "",
        target: "",
        description: subtext,
        action: "",
        provider: "",
        aliases: aliases,
        when: "",
        checked: "",
        disabled: "",
        order: 0
      })
    }

    try {
      var merged = MenuModel.mergeAppRows(root.items, root.itemOrder, appRows)
      root.items = merged.items
      root.itemOrder = merged.itemOrder
    } catch (e) {
    }
    if (root.opened) root.rebuildDisplay()
  }

  function startProviderForMenu(id) {
    var entry = root.item(id)
    if (!entry || !entry.provider || root.providersLoaded[id]) return
    if (entry.provider === "apps") {
      root.providersLoaded[id] = true
      root.mergeAppRows()
      return
    }
    var spec = root.providers[entry.provider]
    if (!spec) return

    root.providersLoaded[id] = true
    providerProc.menuId = id
    providerProc.providerKey = entry.provider
    providerProc.revision = root.providerRevision
    providerProc.collected = ""
    providerProc.command = ["bash", "-lc", spec.script]
    providerProc.running = true
  }

  function mergeProviderRows(rows, menuId, providerKey) {
    var spec = root.providers[providerKey]
    if (!spec) return
    var lines = String(rows || "").split("\n")
    var providerRows = []
    var takenIds = ({})
    for (var i = 0; i < lines.length; i++) {
      var line = lines[i].trim()
      if (!line) continue
      var parts = line.split("\t")
      var label = parts[0] || ""
      var value = parts[1] || parts[0] || ""
      var current = parts[2] || ""
      if (!label) continue
      // Distinct values can slugify alike — Fira Code and Fira-Code both give
      // fira-code — and a repeated id is dropped, which would silently lose a
      // row from the list. Nudge it until it is the row's own.
      var rowId = menuId + "." + root.slugify(value)
      while (takenIds[rowId]) rowId += "-"
      takenIds[rowId] = true

      providerRows.push({
        id: rowId,
        parent: menuId,
        kind: "action",
        icon: (value === current) ? "✓" : (spec.icon || ""),
        label: label,
        title: "",
        target: "",
        description: "",
        action: spec.actionFor(value),
        provider: "",
        aliases: [],
        when: "",
        checked: "",
        disabled: "",
        order: 0
      })
    }
    var merged = MenuModel.swapProviderRows(root.items, root.itemOrder, menuId, providerRows)
    root.items = merged.items
    root.itemOrder = merged.itemOrder
    if (root.opened) root.rebuildDisplay()
  }

  function startNextProvider() {
    if (providerProc.running) return

    while (root.providerQueue.length > 0) {
      var id = root.providerQueue.shift()
      var entry = root.item(id)
      if (!entry || !entry.provider || root.providersLoaded[id]) continue

      root.startProviderForMenu(id)
      return
    }
  }

  // Entering a submenu is the one moment a volatile list is worth paying for
  // again: it may have been reshaped by the last pick from it. Search doesn't
  // invalidate, or every keystroke would restart the same enumeration.
  function invalidateVolatileProvider(id) {
    var entry = root.item(id)
    var spec = entry && entry.provider ? root.providers[entry.provider] : null
    if (spec && spec.volatile) root.providersLoaded[id] = false
  }

  function loadProviderForMenu(id) {
    var entry = root.item(id)
    if (!entry || !entry.provider || root.providersLoaded[id]) return

    // Native providers don't touch providerProc, so they never need to queue.
    if (entry.provider === "apps") {
      root.startProviderForMenu(id)
      return
    }

    if (providerProc.running) {
      if (root.providerQueue.indexOf(id) < 0) root.providerQueue = root.providerQueue.concat([id])
      return
    }

    root.startProviderForMenu(id)
  }

  function loadProvidersForSearch() {
    var active = root.item(root.activeMenu) ? root.activeMenu : "root"

    for (var i = 0; i < root.itemOrder.length; i++) {
      var entry = root.item(root.itemOrder[i])
      if (!entry || !entry.provider || root.providersLoaded[entry.id]) continue
      if (active !== "root" && entry.id !== active && !root.isDescendantOf(entry.id, active)) continue

      root.loadProviderForMenu(entry.id)
    }
  }

  function depthFor(id) {
    return MenuModel.depthFor(root.items, id)
  }

  function pathFor(id) {
    return MenuModel.pathFor(root.items, id)
  }

  function parentPathFor(id) {
    return MenuModel.parentPathFor(root.items, id)
  }

  function isDescendantOf(id, ancestorId) {
    return MenuModel.isDescendantOf(root.items, id, ancestorId)
  }

  function childCount(id) {
    return MenuModel.childCount(root.items, root.itemOrder, id)
  }

  // Guarded items are hidden when their `when:` evaluates false. Static
  // submenus are also hidden when none of their descendants are visible;
  // provider-backed menus stay visible because their rows load on demand.
  function isVisible(entry) {
    return MenuModel.isVisible(root.items, root.itemOrder, root.whenResults, entry)
  }

  // Label with the ✓ marker baked in when `checked:` or `disabled:` evaluated
  // truthy.
  function labelFor(entry) {
    return MenuModel.labelFor(entry, root.checkedResults, root.disabledResults)
  }

  function searchableToken(value) {
    return MenuModel.searchableToken(value)
  }

  function leafIdFor(id) {
    return MenuModel.leafIdFor(id)
  }

  function nameSearchText(entry) {
    return MenuModel.nameSearchText(entry)
  }

  function termInSearchWords(term, text) {
    return MenuModel.termInSearchWords(term, text)
  }

  function descriptionTextMatches(query, text) {
    return MenuModel.descriptionTextMatches(query, text)
  }

  // Rows whose `disabled:` evaluated truthy stay listed but dimmed, and the
  // cursor steps over them.
  function isDisabled(entry) {
    return MenuModel.isDisabled(root.disabledResults, entry)
  }

  // A disabled row earns its place in the submenu it belongs to, where the
  // list around it is the point. Search is a list of what you can do, so it
  // leaves them out.
  function matchesQuery(entry, query) {
    return MenuModel.matchesQuery(entry, query, root.isVisible(entry) && !root.isDisabled(entry))
  }

  function searchScore(entry, query) {
    return MenuModel.searchScore(root.items, entry, query)
  }

  function displayRow(entry, detail, score, section) {
    return MenuModel.displayRow(root.items, root.itemOrder, root.checkedResults, root.disabledResults, entry, detail, score, section)
  }

  function recoverStockRow() {
    var id = (root.manifest && root.manifest.id) ? String(root.manifest.id) : "io.github.jexmarc.tabarchy"
    return {
      itemId: "tabarchy.recover",
      disabled: false,
      kind: "bang",
      icon: "󰦛",
      iconFont: "",
      appIcon: "",
      appId: "",
      label: "Restore stock Super+Space menu",
      target: "",
      detail: "Tabarchy did not load the Omarchy menu. Enter disables Tabarchy.",
      path: "",
      childCount: 0,
      action: "omarchy plugin disable " + id,
      provider: "",
      score: 0,
      section: ""
    }
  }

  function rowSelectable(index) {
    if (index < 0 || index >= displayModel.count) return false
    return !displayModel.get(index).disabled
  }

  // First selectable row at or past `from`, continuing in the direction of
  // travel and wrapping. -1 when every row is disabled, which leaves the menu
  // with no cursor at all rather than one parked on a row Enter won't run.
  function nextSelectable(from, direction) {
    var count = displayModel.count
    if (count === 0) return -1

    var step = direction < 0 ? -1 : 1
    var index = ((from % count) + count) % count
    for (var i = 0; i < count; i++) {
      if (root.rowSelectable(index)) return index
      index = (index + step + count) % count
    }

    return -1
  }

  // Park the cursor on a selectable row after the rows underneath it changed.
  // A menu with nothing selectable in it -- every app in it already installed
  // -- shows no cursor at all, and grows one the moment a row can take it.
  function settleCursor() {
    var target = root.nextSelectable(root.selectedIndex, 1)
    root.selectedIndex = target >= 0 ? target : 0
    root.cursorActive = target >= 0
  }

  function rebuildDmenuDisplay() {
    displayModel.clear()
    root.searchDivider = false

    if (root.mode === "input") {
      layoutSerial += 1
      return
    }

    var query = root.filterText.trim().toLowerCase()
    for (var i = 0; i < root.dmenuOptions.length; i++) {
      // An option is "<label>", "<glyph>\t<label>", or
      // "<glyph>\t<label>\t<subtext>". The glyph never comes back with the
      // selection; the subtext renders under the label, filters alongside it,
      // and returns with the selection as a stable key for same-named rows.
      var parts = String(root.dmenuOptions[i] || "").split("\t")
      var icon = parts.length > 1 ? parts.shift() : ""
      var label = parts.shift() || ""
      var detail = parts.join("\t")
      if (query && label.toLowerCase().indexOf(query) < 0
          && detail.toLowerCase().indexOf(query) < 0) continue
      displayModel.append({
        itemId: "dmenu." + i,
        disabled: false,
        kind: "dmenu",
        icon: icon,
        iconFont: "",
        appIcon: "",
        appId: "",
        label: label,
        target: "",
        detail: detail,
        path: "",
        childCount: 0,
        action: "",
        provider: "",
        score: i,
        section: ""
      })
    }

    layoutSerial += 1

    if (displayModel.count === 0) selectedIndex = 0
    else if (selectedIndex >= displayModel.count) selectedIndex = displayModel.count - 1
    else if (selectedIndex < 0) selectedIndex = 0

    Qt.callLater(function() {
      if (displayModel.count > 0) root.revealCursor()
    })
  }

  function rebuildDisplay() {
    if (root.dmenuActive) {
      root.rebuildDmenuDisplay()
      return
    }
    if (root.activeBang) {
      root.rebuildBangDisplay()
      return
    }

    displayModel.clear()

    if (!root.rowsLoaded) return

    var active = root.item(root.activeMenu) ? root.activeMenu : "root"
    root.activeMenu = active
    var rows = []
    var query = root.filterText.trim()
    root.searchDivider = false

    if (query) {
      var currentRows = []
      var drilldownRows = []

      for (var i = 0; i < root.itemOrder.length; i++) {
        var entry = root.item(root.itemOrder[i])
        if (!entry || entry.id === "root") continue
        if (!root.isDescendantOf(entry.id, active)) continue
        if (!root.matchesQuery(entry, query)) continue

        var detail = root.parentPathFor(entry.id)
        var row = root.displayRow(entry, detail, root.searchScore(entry, query))
        if (entry.parent === active) currentRows.push(row)
        else drilldownRows.push(row)
      }

      var searchSort = function(a, b) {
        if (a.score !== b.score) return a.score - b.score
        return a.path.localeCompare(b.path)
      }

      currentRows.sort(searchSort)
      drilldownRows.sort(searchSort)
      root.searchDivider = currentRows.length > 0 && drilldownRows.length > 0
      if (root.searchDivider) {
        for (var d = 0; d < drilldownRows.length; d++) drilldownRows[d].section = "drilldown"
      }
      rows = currentRows.concat(drilldownRows)
    } else {
      for (var j = 0; j < root.itemOrder.length; j++) {
        var child = root.item(root.itemOrder[j])
        if (!child || child.parent !== active) continue
        if (!root.isVisible(child)) continue
        rows.push(root.displayRow(child, child.description, child.order))
      }

      // DesktopEntries can reorder its values when an application starts.
      // Keep the Apps menu alphabetical independently of provider refreshes.
      if (active === "apps") {
        rows.sort(function(a, b) {
          var aLabel = String(a.label || "").toLowerCase()
          var bLabel = String(b.label || "").toLowerCase()
          if (aLabel < bLabel) return -1
          if (aLabel > bLabel) return 1
          var aId = String(a.itemId || "")
          var bId = String(b.itemId || "")
          if (aId < bId) return -1
          if (aId > bId) return 1
          return 0
        })
      }
    }

    for (var k = 0; k < rows.length; k++) displayModel.append(rows[k])
    if (rows.length === 0 && active === "root" && !query)
      displayModel.append(root.recoverStockRow())
    layoutSerial += 1

    root.settleCursor()

    Qt.callLater(function() {
      if (displayModel.count > 0) root.revealCursor()
    })
  }

  // Contain alone parks the cursor row flush with the viewport edge, hiding
  // the neighbor entirely and losing the fold affordance. Keep the next
  // hidden row peeking past the cursor in the direction of travel.
  function revealCursor() {
    if (displayModel.count === 0) return
    resultList.positionViewAtIndex(root.selectedIndex, ListView.Contain)

    var item = resultList.itemAtIndex(root.selectedIndex)
    if (!item) return

    var reach = root.rowPeek + root.rowSpacing
    if (root.selectedIndex < displayModel.count - 1) {
      var maxY = Math.max(resultList.originY, resultList.originY + resultList.contentHeight - resultList.height)
      var overhang = item.y + item.height + reach - (resultList.contentY + resultList.height)
      if (overhang > 0) resultList.contentY = Math.min(resultList.contentY + overhang, maxY)
    }
    if (root.selectedIndex > 0) {
      var underhang = resultList.contentY - (item.y - reach)
      if (underhang > 0) resultList.contentY = Math.max(resultList.contentY - underhang, resultList.originY)
    }
  }

  function select(delta) {
    if (displayModel.count === 0) return

    root.disarmPointer()
    var from = cursorActive ? selectedIndex + delta : (delta < 0 ? displayModel.count - 1 : 0)
    var target = root.nextSelectable(from, delta)
    if (target < 0) return

    cursorActive = true
    selectedIndex = target
    revealCursor()
  }

  function setFilter(nextFilter) {
    panel.freezeCardTop()
    root.filterText = nextFilter
    root.selectedIndex = 0
    root.cursorActive = root.mode !== "input"
    root.disarmPointer()
    if (!root.dmenuActive && root.filterText.trim()) root.loadProvidersForSearch()
    root.rebuildDisplay()
  }

  function setActiveMenu(id, pushHistory, fromPointer) {
    panel.freezeCardTop()
    if (!root.item(id)) id = "root"
    if (pushHistory && id !== root.activeMenu) root.navStack = root.navStack.concat([root.activeMenu])
    root.activeMenu = id
    root.clearBang()
    root.filterText = ""
    root.selectedIndex = 0
    root.cursorActive = true
    if (fromPointer) pointerGate.allowInitialSample()
    else root.disarmPointer()
    root.rebuildDisplay()
    root.invalidateVolatileProvider(id)
    root.loadProviderForMenu(id)
  }

  function goBack() {
    if (root.activeMenu === "root") return false

    if (root.navStack.length > 0) {
      var previous = root.navStack[root.navStack.length - 1]
      root.navStack = root.navStack.slice(0, root.navStack.length - 1)
      root.setActiveMenu(previous, false)
      return true
    }

    var active = root.item(root.activeMenu)
    root.setActiveMenu((active && active.parent) ? active.parent : "root", false)
    return true
  }

  function activateIndex(index, fromPointer) {
    if (root.deleteConfirmOpen || root.mdOpenOpen) return
    if (root.dmenuActive) {
      if (root.mode === "input") {
        root.applyDmenuSelection(root.filterText)
        return
      }
      if (index < 0 || index >= displayModel.count) return
      var picked = displayModel.get(index)
      root.applyDmenuSelection(picked.detail ? picked.label + "\t" + picked.detail : picked.label)
      return
    }

    if (!root.rowSelectable(index)) return

    var row = displayModel.get(index)
    if (row.kind === "bang") {
      root.applySelected(row.itemId, row.action)
    } else if (row.kind === "bang-settings") {
      root.activateSettingsRow(row)
    } else if (row.kind === "bang-help") {
      var next = root.bangLookup(row.target)
      if (next && next.kind !== "help") root.enterBang(next)
    } else if (row.kind === "bang-file") {
      if (row.provider === "dir") {
        root.openFilePath(row.action, "reveal")
        return
      }
      if (root.isMarkdownPath(row.action)) {
        root.mdOpenPath = row.action
        mdChoice.selectedIndex = 1
        root.mdOpenOpen = true
        return
      }
      root.openFilePath(row.action, "")
    } else if (row.kind === "bang-pkg") {
      root.applySelected(row.itemId, row.action)
    } else if (row.kind === "menu" || row.kind === "link") {
      root.setActiveMenu(row.target || row.itemId, true, fromPointer)
    } else if (row.kind === "app") {
      var appId = row.appId
      var label = row.label
      applySerial = requestSerial
      opened = false
      filterText = ""
      if (root.appLibrary) root.appLibrary.launch(appId, label)
      else Util.execDetached("uwsm-app -- gtk-launch " + Util.shellQuote(appId + ".desktop"))
    } else {
      root.applySelected(row.itemId, row.action)
    }
  }

  function isFileRevealKey(event) {
    if (!root.activeBang || root.activeBang.kind !== "files") return false
    if (event.key === Qt.Key_Apostrophe)
      return event.modifiers === Qt.NoModifier
    if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter) && root.isCtrlOnly(event))
      return true
    return false
  }

  function revealSelectedFile() {
    if (!root.activeBang || root.activeBang.kind !== "files") return
    if (!root.cursorActive || root.selectedIndex < 0 || root.selectedIndex >= displayModel.count) return
    var row = displayModel.get(root.selectedIndex)
    if (!row || row.kind !== "bang-file" || !row.action) return
    applySerial = requestSerial
    opened = false
    root.clearBang()
    filterText = ""
    Util.execArgv([root.pluginDir + "/bin/tabarchy-open", "--reveal", row.action])
  }

  function isMarkdownPath(path) {
    var name = String(path || "").toLowerCase()
    return name.endsWith(".md") || name.endsWith(".markdown") || name.endsWith(".mkd") || name.endsWith(".mdown") || name.endsWith(".mdwn")
  }

  function openFilePath(path, mode) {
    if (!path) return
    applySerial = requestSerial
    opened = false
    root.clearBang()
    filterText = ""
    if (mode === "edit" || mode === "view" || mode === "reveal")
      Util.execArgv([root.pluginDir + "/bin/tabarchy-open", "--" + mode, path])
    else
      Util.execArgv([root.pluginDir + "/bin/tabarchy-open", path])
  }

  function cancelMdOpen() {
    root.mdOpenOpen = false
    root.mdOpenPath = ""
    mdChoice.selectedIndex = 1
    root.disarmPointer()
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function confirmMdOpen(index) {
    var path = root.mdOpenPath
    var mode = index === 0 ? "edit" : "view"
    root.mdOpenOpen = false
    root.mdOpenPath = ""
    mdChoice.selectedIndex = 1
    root.openFilePath(path, mode)
  }

  function activateSettingsRow(row) {
    if (!row) return
    var target = row.target
    var query = String(root.bangQuery || "").trim()
    if (target === "search" || target === "maps" || target === "aliases") {
      root.openSettingsPage(target, "")
    } else if (target === "edit-config") {
      root.openTabarchyConfig()
    } else if (target === "toggle-hook") {
      root.setPostUpdateHook(!Bangs.postUpdateHookEnabled(root.settingsData))
    } else if (target === "set-search") {
      root.setSearchProviderValue(row.path)
    } else if (target === "set-maps") {
      root.setMapsProviderValue(row.path)
    } else if (target === "set-search-custom") {
      if (Bangs.isHttpProviderTemplate(query)) root.setSearchProviderValue(query)
      else if (query) return
    } else if (target === "set-maps-custom") {
      if (Bangs.isHttpProviderTemplate(query)) root.setMapsProviderValue(query)
      else if (query) return
    } else if (target === "alias-add") {
      var parsedAdd = Bangs.parseAliasInput(root.bangQuery)
      if (parsedAdd) root.saveSettingsAlias(parsedAdd.key, parsedAdd.url)
    } else if (target === "alias-save") {
      if (root.settingsPage === "alias-edit") {
        if (query) root.saveSettingsAlias(root.settingsAliasKey, Bangs.toUrl(query))
      } else {
        var parsedSave = Bangs.parseAliasInput(root.bangQuery)
        if (parsedSave) root.saveSettingsAlias(parsedSave.key, parsedSave.url)
      }
    } else if (target === "alias-edit" && row.path) {
      var current = root.webAliases[row.path]
      root.settingsAliasKey = row.path
      root.openSettingsPage("alias-edit", current && current.url ? current.url : "")
    }
  }

  function requestDeleteSelected() {
    if (!root.cursorActive || root.selectedIndex < 0 || root.selectedIndex >= displayModel.count) return
    var row = displayModel.get(root.selectedIndex)
    if (root.settingsAliasesPage && row && row.kind === "bang-settings" && row.path && (row.target === "alias-edit" || row.target === "alias-save")) {
      root.deleteTarget = { kind: "alias", key: row.path, label: row.path }
      deleteConfirm.selectedIndex = 1
      root.deleteConfirmOpen = true
      return
    }
    if (!row || row.kind !== "app") return
    root.deleteTarget = { kind: "app", appId: row.appId, label: row.label }
    deleteConfirm.selectedIndex = 1
    root.deleteConfirmOpen = true
  }

  function cancelDelete() {
    root.deleteConfirmOpen = false
    root.deleteTarget = null
    deleteConfirm.selectedIndex = 1
    root.disarmPointer()
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function confirmDelete() {
    var target = root.deleteTarget
    root.deleteConfirmOpen = false
    root.deleteTarget = null
    if (!target) return
    if (target.kind === "alias") {
      root.deleteSettingsAlias(target.key)
      deleteConfirm.selectedIndex = 1
      root.disarmPointer()
      Qt.callLater(function() { keyCatcher.forceActiveFocus() })
      return
    }
    root.cancel()
    if (root.appLibrary) root.appLibrary.remove(target.appId, target.label)
  }

  function applyDmenuSelection(value) {
    applySerial = requestSerial
    opened = false
    filterText = ""
    root.finishRequest(value)
  }

  function applySelected(id, action) {
    if (!id) { cancel(); return }

    applySerial = requestSerial
    opened = false
    root.clearBang()
    filterText = ""
    root.runAction(action)
  }

  function cancel() {
    if (root.dmenuActive) root.finishRequest(null)
    opened = false
    root.clearBang()
    filterText = ""
  }

  function openExistingMenu(initialMenu) {
    requestSerial += 1
    mode = "menu"
    requestActive = false
    selectionFile = ""
    doneFile = ""
    activeMenu = root.item(initialMenu) ? initialMenu : "root"
    navStack = []
    root.clearBang()
    filterText = ""
    selectedIndex = 0
    cursorActive = true
    root.disarmPointer()
    root.evaluateGuards()
    opened = true
    rebuildDisplay()
    invalidateVolatileProvider(activeMenu)
    loadProviderForMenu(activeMenu)
    // The shell may start before first-install packages have finished placing
    // their icons. Refresh here even when the desktop entry list did not change.
    if (root.appLibrary) root.appLibrary.refreshIcons()

    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function openDmenu(payload) {
    requestSerial += 1
    mode = payload.mode === "input" ? "input" : "select"
    dmenuPrompt = String(payload.prompt || (mode === "input" ? "Input" : "Select"))
    dmenuOptions = Array.isArray(payload.options) ? payload.options : []
    selectionFile = String(payload.selectionFile || "")
    doneFile = String(payload.doneFile || "")
    requestActive = !!doneFile
    dmenuWidth = Math.max(1, Number(payload.width || 300))
    dmenuMaxHeight = Math.max(0, Number(payload.maxHeight || 0))
    activeMenu = "root"
    navStack = []
    root.clearBang()
    filterText = ""
    selectedIndex = 0
    cursorActive = mode !== "input"
    root.disarmPointer()
    opened = true
    rebuildDisplay()

    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }
  ListModel { id: displayModel }

  // ----------------------------------------------------------- route surface
  //
  // The menu is opened through the standard plugin lifecycle:
  // `omarchy-shell shell summon omarchy.menu '{"menu":"system"}'`.
  // Callers may pass a real id (`system`, `setup.power`) or an alias declared
  // in JSONC (`power`, `reminder-set`). Unknown strings fall through to the
  // id-as-route behavior so misspellings still attempt to open the literal id.
  function resolveRoute(input) {
    return MenuModel.resolveRoute(root.items, root.itemOrder, input)
  }

  function openRoute(initialMenu) {
    var id = root.resolveRoute(initialMenu)
    var entry = root.items[id]
    // If the resolved id is an action (i.e. the user invoked an alias for
    // a leaf, e.g. `omarchy menu summon screenrecord-stop`), run it directly
    // instead of opening an action with no children.
    if (entry && entry.kind === "action" && entry.action) {
      root.cancel()
      root.runAction(entry.action)
      return "ok"
    }
    // If it's a link (a redirect to another menu), follow the link.
    if (entry && entry.kind === "link" && entry.target) id = entry.target
    root.pendingInitialMenu = id
    root.openExistingMenu(id)
    return "ok"
  }

  function disarmPointer() {
    pointerGate.reset()
  }

  function selectFromPointer(index, item, mouse) {
    if (!pointerGate.moved(item, mouse)) return
    if (!root.rowSelectable(index)) return
    root.cursorActive = true
    root.selectedIndex = index
  }

  Process {
    id: providerProc
    property string menuId: ""
    property string providerKey: ""
    property string collected: ""
    property int revision: 0
    stdout: SplitParser {
      onRead: function(data) { providerProc.collected += data + "\n" }
    }
    onExited: {
      if (providerProc.revision === root.providerRevision) {
        root.mergeProviderRows(providerProc.collected, providerProc.menuId, providerProc.providerKey)
        if (root.filterText.trim()) root.loadProvidersForSearch()
      }
      root.startNextProvider()
    }
  }

  Process {
    id: resultProc
    onExited: {
      if (root.applySerial === root.requestSerial)
        root.opened = false
    }
  }

  PointerMoveGate {
    id: pointerGate
    referenceItem: card
  }

  Connections {
    target: root.appLibrary
    function onAppsChanged() {
      if (root.providersLoaded["apps"]) root.mergeAppRows()
    }
  }

  Connections {
    target: DesktopEntries.applications
    function onValuesChanged() {
      if (root.providersLoaded["apps"]) root.mergeAppRows()
    }
  }

  // The JSONC sources are watched so live edits to the default file (or the
  // user extension at ~/.config/omarchy/extensions/omarchy-menu.jsonc) take
  // effect without restarting the shell.
  FileView {
    id: defaultMenuFile
    path: root.defaultMenuPath
    watchChanges: true
    printErrors: false
    onLoaded: { root.defaultMenuItems = root.parseMenuJsonc(text()); root.rebuildItemsFromSources() }
    onFileChanged: reload()
  }

  FileView {
    id: userMenuFile
    path: root.userMenuPath
    watchChanges: true
    printErrors: false
    onLoaded: { root.userMenuItems = root.parseMenuJsonc(text()); root.rebuildItemsFromSources() }
    onLoadFailed: { root.userMenuItems = []; root.rebuildItemsFromSources() }
    onFileChanged: reload()
  }

  FileView {
    id: bangsFile
    path: Quickshell.env("HOME") + "/.config/omarchy/tabarchy.jsonc"
    watchChanges: true
    printErrors: false
    onLoaded: {
      var raw = text()
      root.bangs = Bangs.mergeBangs(Bangs.defaults(), Bangs.parseBangs(raw))
      root.jsoncAliases = Bangs.parseAliases(raw)
      root.refreshWebAliases()
      if (root.opened && root.activeBang) root.rebuildDisplay()
    }
    onLoadFailed: {
      root.bangs = Bangs.defaults()
      root.jsoncAliases = ({})
      root.refreshWebAliases()
    }
    onFileChanged: reload()
  }

  FileView {
    id: settingsFile
    path: root.settingsPath
    watchChanges: true
    printErrors: false
    onLoaded: {
      root.settingsData = Bangs.parseSettings(text())
      root.settingsAliases = Bangs.settingsAliasesFromData(root.settingsData)
      root.refreshWebAliases()
      if (root.opened && root.activeBang) root.rebuildDisplay()
    }
    onLoadFailed: {
      root.settingsData = ({})
      root.settingsAliases = ({})
      root.refreshWebAliases()
    }
    onFileChanged: reload()
  }

  FileView {
    id: searchProviderFile
    path: Quickshell.env("HOME") + "/.config/omarchy/defaults/search"
    watchChanges: true
    printErrors: false
    onLoaded: {
      var next = String(text() || "").trim() || "google"
      root.searchProvider = next
      if (root.opened && root.activeBang && (root.activeBang.kind === "web" || root.activeBang.kind === "settings"))
        root.rebuildDisplay()
    }
    onLoadFailed: { root.searchProvider = "google" }
    onFileChanged: reload()
  }

  FileView {
    id: mapsProviderFile
    path: Quickshell.env("HOME") + "/.config/omarchy/defaults/maps"
    watchChanges: true
    printErrors: false
    onLoaded: {
      var next = String(text() || "").trim() || "google"
      root.mapsProvider = next
      if (root.opened && root.activeBang && (root.activeBang.kind === "maps" || root.activeBang.kind === "settings"))
        root.rebuildDisplay()
    }
    onLoadFailed: { root.mapsProvider = "google" }
    onFileChanged: reload()
  }

  Process {
    id: settingsWriteProc
    command: ["true"]
    onExited: settingsFile.reload()
  }

  Timer {
    id: bangFilesTimer
    interval: 80
    repeat: false
    onTriggered: root.startBangFiles()
  }

  Timer {
    id: bangPkgTimer
    interval: 220
    repeat: false
    onTriggered: root.startBangPackages()
  }

  Process {
    id: pasteProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.applyPaste(text)
    }
  }

  Process {
    id: bangFilesProc
    property string collected: ""
    property int generation: 0
    stdout: SplitParser {
      onRead: function(data) { bangFilesProc.collected += data + "\n" }
    }
    onExited: {
      if (bangFilesProc.generation !== root.bangFilesGeneration) return
      if (!root.activeBang || root.activeBang.kind !== "files") return
      var rows = []
      var seen = {}
      var lines = bangFilesProc.collected.split("\n")
      for (var i = 0; i < lines.length; i++) {
        var line = lines[i]
        if (!line) continue
        var isDir = false
        var path = line
        if (line.slice(0, 2) === "d|" || line.slice(0, 2) === "f|" || line.slice(0, 2) === "d\t" || line.slice(0, 2) === "f\t") {
          isDir = line.charAt(0) === "d"
          path = line.slice(2)
        } else if (line.slice(-1) === "/") {
          isDir = true
          path = line.replace(/\/+$/, "")
        }
        path = path.replace(/\/+$/, "")
        if (!path || seen[path]) continue
        seen[path] = true
        rows.push({ path: path, isDir: isDir })
      }
      rows.sort(function(a, b) {
        if (a.isDir !== b.isDir) return a.isDir ? -1 : 1
        return 0
      })
      root.bangFileRows = rows
      root.rebuildDisplay()
    }
  }

  Process {
    id: bangPkgProc
    stdout: StdioCollector {
      id: bangPkgOut
      waitForEnd: true
    }
    stderr: StdioCollector {
      id: bangPkgErr
      waitForEnd: true
    }
    onExited: function(exitCode) {
      if (root.bangPkgAborting) {
        root.bangPkgAborting = false
        return
      }
      if (!root.pkgBang) {
        root.bangPkgSearching = false
        return
      }
      var current = root.bangQuery.trim()
      if (current.length < 2) {
        root.bangPkgSearching = false
        root.bangPkgActiveQuery = ""
        root.bangPkgRows = []
        root.rebuildDisplay()
        return
      }
      if (root.bangPkgActiveQuery !== current) {
        root.bangPkgSearching = true
        root.startBangPackages()
        return
      }
      root.bangPkgSearching = false
      var text = bangPkgOut.text || ""
      var rows = []
      var lines = text.split("\n")
      for (var i = 0; i < lines.length; i++) {
        var line = lines[i]
        if (line) rows.push(line)
      }
      root.bangPkgRows = rows
      if (exitCode !== 0 && bangPkgErr.text)
        console.warn("tabarchy-pkg-search:", String(bangPkgErr.text).trim())
      root.rebuildDisplay()
    }
  }

  // ---------------------------------------------------------------- guards
  //
  // `when:` (visibility) and `checked:` (✓ marker) are bash expressions the
  // shell wasn't allowed to evaluate before the perf rewrite. Now the shell
  // batches them into one bash subprocess per (re)load so the open path
  // never has to wait on them.

  property var whenResults: ({})       // id → true|false (allow visibility)
  property var checkedResults: ({})    // id → true|false (show ✓)
  property var disabledResults: ({})   // id → true|false (dim, skip cursor)
  property bool guardsPending: false

  function evaluateGuards() {
    // Process ignores a command change while it is running, and `collected`
    // belongs to the run in flight, so a second evaluation cannot overwrite
    // the first: it would throw away the lines already read and never start.
    // The surviving tail then lands as the whole answer, and every id lost
    // with it goes back to showing, since a `when:` only hides on an explicit
    // false. Wait for the run in flight and evaluate once it lands instead.
    if (guardProc.running) {
      root.guardsPending = true
      return
    }
    root.guardsPending = false

    var script = MenuModel.guardScript(root.items)
    if (!script) {
      root.whenResults = ({})
      root.checkedResults = ({})
      root.disabledResults = ({})
      return
    }
    guardProc.collected = ""
    guardProc.command = ["bash", "-lc", script]
    guardProc.running = true
  }

  Process {
    id: guardProc
    property string collected: ""
    stdout: SplitParser {
      onRead: function(data) { guardProc.collected += data + "\n" }
    }
    onExited: function(exitCode, exitStatus) {
      // A batch that was killed rather than finished has only told us about
      // the rows it reached, and a row whose `when:` went unanswered shows.
      // Keep the last complete set rather than let a half-read one through.
      // A signal leaves the exit code at 0, so the status is what tells us.
      if (exitCode !== 0 || exitStatus !== 0) {
        if (root.guardsPending) Qt.callLater(function() { root.evaluateGuards() })
        return
      }

      var nextWhen = ({})
      var nextChecked = ({})
      var nextDisabled = ({})
      var lines = guardProc.collected.split("\n")
      for (var i = 0; i < lines.length; i++) {
        var line = lines[i].trim()
        if (!line) continue
        var colon = line.lastIndexOf(":")
        if (colon < 0) continue
        var value = line.substring(colon + 1) === "1"
        var rest = line.substring(0, colon)
        var tagAt = rest.lastIndexOf(":")
        if (tagAt < 0) continue
        var id = rest.substring(0, tagAt)
        var tag = rest.substring(tagAt + 1)
        if (tag === "w") nextWhen[id] = value
        else if (tag === "c") nextChecked[id] = value
        else if (tag === "d") nextDisabled[id] = value
      }
      root.whenResults = nextWhen
      root.checkedResults = nextChecked
      root.disabledResults = nextDisabled
      if (root.opened) root.rebuildDisplay()
      // Run the evaluation that had to stand aside. Deferred by a turn so the
      // process is settled before its command is set again.
      if (root.guardsPending) Qt.callLater(function() { root.evaluateGuards() })
    }
  }
  PanelWindow {
    id: panel
    visible: root.opened && root.rowsLoaded
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "omarchy-menu"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    exclusionMode: ExclusionMode.Ignore

    // The card opens centered exactly as always. The first search keystroke
    // or submenu move freezes the top line where it currently sits — from
    // then on the card grows and shrinks downward instead of re-centering
    // on every resize, which made the menu jump around. The rows height is
    // frozen at the same moment, so the starting menu also caps how tall the
    // card may grow from there. Closing unfreezes both.
    property int cardTop: -1
    property int maxRowsHeight: -1
    readonly property int centeredTop: Math.max(Style.gapsOut, Math.round((height - root.cardHeight) / 2))
    readonly property int effectiveCardTop: cardTop >= 0 ? cardTop : centeredTop
    function freezeCardTop() {
      if (visible && cardTop < 0) {
        cardTop = effectiveCardTop
        maxRowsHeight = root.visibleRowsHeight
      }
    }
    onVisibleChanged: if (!visible) { cardTop = -1; maxRowsHeight = -1 }

    Rectangle {
      anchors.fill: parent
      color: root.scrim
    }

    MouseArea {
      anchors.fill: parent
      onClicked: root.cancel()
    }

    BorderSurface {
      id: card
      width: root.cardWidth
      height: Math.min(root.cardHeight, panel.height - Style.gapsOut - panel.effectiveCardTop)
      radius: root.cornerRadius
      anchors.horizontalCenter: parent.horizontalCenter
      y: panel.effectiveCardTop
      color: root.background
      borderSpec: root.borderSpec
      padding: root.contentMargin

      MouseArea { anchors.fill: parent; onClicked: {} }

      Item {
        id: keyCatcher
        anchors.fill: parent
        z: (root.deleteConfirmOpen || root.mdOpenOpen) ? 20 : 0
        focus: true

        Keys.priority: Keys.BeforeItem
        Keys.onPressed: function(event) {
          if (root.deleteConfirmOpen) {
            if (deleteConfirm.handleKey(event)) event.accepted = true
            return
          }
          if (root.mdOpenOpen) {
            if (event.key === Qt.Key_V) {
              root.confirmMdOpen(1)
              event.accepted = true
              return
            }
            if (event.key === Qt.Key_E) {
              root.confirmMdOpen(0)
              event.accepted = true
              return
            }
            if (mdChoice.handleKey(event)) event.accepted = true
            return
          }

          if (root.isFileRevealKey(event)) {
            root.revealSelectedFile()
            event.accepted = true
          } else if (event.key === Qt.Key_Delete) {
            root.requestDeleteSelected()
            event.accepted = true
          } else if (event.key === Qt.Key_Escape) {
            if (root.activeBang) {
              if (root.bangQuery) root.setBangQuery("")
              else if (!root.settingsGoBack()) root.exitBang(false)
            } else if (root.filterText) root.setFilter("")
            else root.cancel()
            event.accepted = true
          } else if (root.activeBang && Util.editsFilter(event, root.bangQuery)) {
            root.setBangQuery(Util.editedFilter(event, root.bangQuery))
            event.accepted = true
          } else if (root.activeBang && (event.key === Qt.Key_Backspace || event.key === Qt.Key_Left) && !root.bangQuery) {
            if (!root.settingsGoBack()) root.exitBang(true)
            event.accepted = true
          } else if (Util.editsFilter(event, root.filterText)) {
            root.setFilter(Util.editedFilter(event, root.filterText))
            event.accepted = true
          } else if (!root.activeBang && (event.key === Qt.Key_Backspace || event.key === Qt.Key_Left) && !root.filterText) {
            root.goBack()
            event.accepted = true
          } else if (event.key === Qt.Key_Tab) {
            root.toggleBang()
            event.accepted = true
          } else if (root.isPasteKey(event)) {
            root.requestPaste()
            event.accepted = true
          } else if (event.key === Qt.Key_Up || (event.key === Qt.Key_K && root.isCtrlOnly(event))) {
            root.select(-1)
            event.accepted = true
          } else if (event.key === Qt.Key_Down || (event.key === Qt.Key_J && root.isCtrlOnly(event))) {
            root.select(1)
            event.accepted = true
          } else if (event.key === Qt.Key_PageUp) {
            root.select(-6)
            event.accepted = true
          } else if (event.key === Qt.Key_PageDown) {
            root.select(6)
            event.accepted = true
          } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Right) {
            if (root.dmenuActive) {
              if (root.mode === "input") root.applyDmenuSelection(root.filterText)
              else if (displayModel.count > 0) root.activateIndex(root.cursorActive ? root.selectedIndex : 0)
            } else if (root.activeBang) {
              if (displayModel.count > 0) root.activateIndex(root.cursorActive ? root.selectedIndex : 0)
            } else if (root.cursorActive) root.activateIndex(root.selectedIndex)
            else root.settleCursor()
            event.accepted = true
          } else if (event.text && event.text.length === 1 && event.text.charCodeAt(0) >= 32 && event.text.charCodeAt(0) !== 127 && (event.modifiers === Qt.NoModifier || event.modifiers === Qt.ShiftModifier)) {
            if (root.activeBang) root.setBangQuery(root.bangQuery + event.text)
            else root.setFilter(root.filterText + event.text)
            event.accepted = true
          }
        }

        ConfirmDialog {
          id: deleteConfirm

          anchors.fill: parent
          opened: root.deleteConfirmOpen
          z: 10
          message: (root.deleteTarget && root.deleteTarget.kind === "alias")
            ? ("Delete alias " + ((root.deleteTarget && root.deleteTarget.label) || "") + "?")
            : ("Do you want to uninstall " + ((root.deleteTarget && root.deleteTarget.label) || "") + "?")
          confirmText: (root.deleteTarget && root.deleteTarget.kind === "alias") ? "Delete" : "Uninstall"
          background: root.background
          foreground: root.foreground
          scrim: root.scrim
          selectedBackground: root.selectedBackground
          selectedText: root.selectedText
          fontFamily: root.fontFamily
          cornerRadius: root.cornerRadius
          onCanceled: root.cancelDelete()
          onConfirmed: root.confirmDelete()
        }

        ChoiceDialog {
          id: mdChoice

          anchors.fill: parent
          opened: root.mdOpenOpen
          z: 10
          message: "View or edit " + Bangs.fileLabel(root.mdOpenPath) + "?"
          leftText: "Edit"
          rightText: "View"
          background: root.background
          foreground: root.foreground
          scrim: root.scrim
          selectedBackground: root.selectedBackground
          selectedText: root.selectedText
          fontFamily: root.fontFamily
          cornerRadius: root.cornerRadius
          onDismissed: root.cancelMdOpen()
          onPicked: function(index) { root.confirmMdOpen(index) }
        }
      }

      Column {
        anchors.fill: parent
        anchors.topMargin: card.contentTopInset
        anchors.rightMargin: card.contentRightInset
        anchors.bottomMargin: card.contentBottomInset
        anchors.leftMargin: card.contentLeftInset
        spacing: root.contentSpacing

        Rectangle {
          width: parent.width
          height: root.headerHeight
          radius: root.cornerRadius
          color: "transparent"

          Column {
            id: bangHeader
            visible: !!root.activeBang
            anchors.left: parent.left
            anchors.right: headerSpinner.left
            anchors.rightMargin: headerSpinner.visible ? Style.space(8) : 0
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(2)

            Rectangle {
              width: tabarchyBadgeLabel.implicitWidth + Style.space(8)
              height: Math.max(tabarchyBadgeLabel.implicitHeight + Style.space(2), Style.space(14))
              radius: Math.round(height / 2)
              color: Color.accent

              Text {
                id: tabarchyBadgeLabel
                anchors.centerIn: parent
                textFormat: Text.PlainText
                text: "Tabarchy"
                color: root.background
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.weight: Font.Medium
              }
            }

            Text {
              id: bangHeaderText
              width: parent.width
              textFormat: Text.PlainText
              text: root.headerText()
              color: root.foreground
              opacity: root.bangQuery ? 1 : 0.58
              font.family: root.fontFamily
              font.pixelSize: Style.font.heading
              elide: Text.ElideRight
            }
          }

          Text {
            visible: !root.activeBang
            textFormat: Text.PlainText
            anchors.left: parent.left
            anchors.right: headerSpinner.left
            anchors.rightMargin: headerSpinner.visible ? Style.space(8) : 0
            anchors.verticalCenter: parent.verticalCenter
            text: root.headerText()
            color: root.foreground
            opacity: root.filterText ? 1 : 0.58
            font.family: root.fontFamily
            font.pixelSize: Style.font.heading
            elide: Text.ElideRight
          }

          Scanner {
            id: headerSpinner
            visible: root.bangPkgSearching
            running: root.bangPkgSearching
            cells: 7
            width: Style.space(52)
            height: Style.space(10)
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
          }

        }

        Item {
          width: parent.width
          height: root.visibleRowsHeight

          ListView {
            id: resultList
            anchors.fill: parent
            model: displayModel
            clip: true
            spacing: root.rowSpacing
            boundsBehavior: Flickable.StopAtBounds
            opacity: root.bangPkgSearching && displayModel.count > 0 ? 0.55 : 1

            section.property: "section"
            section.criteria: ViewSection.FullString
            section.delegate: Item {
              required property string section

              width: ListView.view.width
              height: section === "drilldown" ? root.dividerHeight : 0
              visible: section === "drilldown"

              Rectangle {
                anchors.left: parent.left
                anchors.leftMargin: Style.space(4)
                anchors.right: parent.right
                anchors.rightMargin: Style.space(4)
                anchors.verticalCenter: parent.verticalCenter
                height: Style.spacing.hairline
                color: Util.alpha(root.foreground, 0.2)
              }
            }

            delegate: BorderSurface {
              id: row
              required property int index
              required property string itemId
              required property string kind
              required property string icon
              required property string iconFont
              required property string appIcon
              required property string appId
              required property string label
              required property string target
              required property string detail
              required property string path
              required property string action
              required property int childCount
              required property bool disabled
              required property string provider

              readonly property bool hasCursor: root.cursorActive && row.index === root.selectedIndex
              readonly property bool isApp: row.kind === "app"
              readonly property bool hasIcon: row.icon.length > 0 || row.isApp
              readonly property bool pkgInstalled: row.kind === "bang-pkg" && row.provider === "installed"

              width: ListView.view.width
              height: root.rowHeightForDetail(row.detail)
              // Faded: the row is here to say the software is already
              // installed, not to be picked. Package hits keep full opacity
              // so the Installed badge stays readable; navigation skips them.
              opacity: row.disabled && !row.pkgInstalled ? 0.4 : 1
              radius: root.cornerRadius
              color: row.hasCursor ? root.selectedBackground : "transparent"
              borderSpec: row.hasCursor ? root.selectedBorderSpec : Border.none()

              Rectangle {
                visible: false
                width: Style.space(4)
                height: parent.height - Style.space(18)
                radius: Math.min(root.cornerRadius, Style.space(4))
                color: root.selectedBackground
                anchors.left: parent.left
                anchors.leftMargin: root.rowReservedBorderLeft + Style.space(8)
                anchors.verticalCenter: parent.verticalCenter
              }

              Text {
                id: iconText
                textFormat: Text.PlainText
                visible: row.hasIcon && !row.isApp
                text: row.icon
                color: row.hasCursor ? root.selectedText : root.foreground
                font.family: row.iconFont.length > 0 ? row.iconFont : root.fontFamily
                font.pixelSize: Style.font.iconLarge
                width: Style.space(36)
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                anchors.left: parent.left
                anchors.leftMargin: root.rowReservedBorderLeft + Style.space(8)
                y: contentColumn.y + labelRow.y + (labelRow.height - height) / 2
              }

              Image {
                id: appIconImage
                visible: row.isApp
                width: Style.font.iconLarge
                height: Style.font.iconLarge
                fillMode: Image.PreserveAspectFit
                // Decode at physical pixels — a logical-size decode leaves
                // PNG icons upscaled and blurry on HiDPI displays.
                sourceSize.width: width * Screen.devicePixelRatio
                sourceSize.height: height * Screen.devicePixelRatio
                source: row.isApp && root.appLibrary ? root.appLibrary.iconSource(row.appIcon) : ""
                asynchronous: true
                anchors.left: parent.left
                anchors.leftMargin: root.rowReservedBorderLeft + Style.space(8) + (Style.space(36) - width) / 2
                y: contentColumn.y + labelRow.y + (labelRow.height - height) / 2
              }

              Column {
                id: contentColumn
                anchors.left: row.hasIcon ? iconText.right : parent.left
                anchors.leftMargin: row.hasIcon ? Style.space(6) : root.rowReservedBorderLeft + Style.space(18)
                anchors.right: trail.left
                anchors.rightMargin: Style.space(6)
                anchors.verticalCenter: parent.verticalCenter
                spacing: Style.space(3)

                Row {
                  id: labelRow
                  width: parent.width
                  spacing: Style.space(8)

                  Text {
                    id: labelText
                    textFormat: Text.PlainText
                    width: parent.width - (installedBadge.visible ? installedBadge.width + parent.spacing : 0)
                    text: row.label
                    color: row.hasCursor ? root.selectedText : root.foreground
                    opacity: row.pkgInstalled ? 0.72 : 1
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.heading
                    font.weight: Font.Medium
                    elide: Text.ElideRight
                  }

                  Rectangle {
                    id: installedBadge
                    visible: row.pkgInstalled
                    width: badgeLabel.implicitWidth + Style.space(10)
                    height: Math.max(badgeLabel.implicitHeight + Style.space(4), Style.space(16))
                    radius: Math.round(height / 2)
                    color: Color.accent
                    anchors.verticalCenter: parent.verticalCenter

                    Text {
                      id: badgeLabel
                      anchors.centerIn: parent
                      textFormat: Text.PlainText
                      text: "installed"
                      color: root.background
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                      font.weight: Font.Medium
                    }
                  }
                }

                Text {
                  textFormat: Text.PlainText
                  width: parent.width
                  text: row.detail
                  visible: (root.filterText || row.kind === "dmenu" || root.activeBang) && row.detail.length > 0
                  color: root.foreground
                  opacity: 0.52
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.bodySmall
                  wrapMode: Text.NoWrap
                  maximumLineCount: 1
                  elide: Text.ElideRight
                }
              }

              Row {
                id: trail
                width: Style.space(14)
                anchors.right: parent.right
                anchors.rightMargin: root.rowReservedBorderRight + Style.space(8)
                y: contentColumn.y + labelRow.y + (labelRow.height - height) / 2
                spacing: 0

                Text {
                  textFormat: Text.PlainText
                  visible: false
                  text: row.childCount
                  color: root.foreground
                  opacity: 0.45
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                  anchors.verticalCenter: parent.verticalCenter
                }

                Text {
                  textFormat: Text.PlainText
                  text: row.kind === "menu" || row.kind === "link" || (row.kind === "bang-help" && row.target.length > 0) || (row.kind === "bang-settings" && row.childCount > 0) ? "›" : ""
                  color: row.hasCursor ? root.selectedText : root.foreground
                  opacity: row.kind === "menu" || row.kind === "link" || (row.kind === "bang-help" && row.target.length > 0) || (row.kind === "bang-settings" && row.childCount > 0) ? 0.36 : 0
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.heading
                  font.weight: Font.Normal
                  anchors.verticalCenter: parent.verticalCenter
                }
              }

              MouseArea {
                id: mouseArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: row.disabled ? Qt.ArrowCursor : Qt.PointingHandCursor
                onEntered: root.selectFromPointer(row.index, row, {
                  x: mouseArea.mouseX,
                  y: mouseArea.mouseY
                })
                onPositionChanged: function(mouse) {
                  root.selectFromPointer(row.index, row, mouse)
                }
                onClicked: {
                  if (row.disabled) return
                  root.cursorActive = true
                  root.selectedIndex = row.index
                  root.activateIndex(row.index, true)
                }
              }
            }
          }

          // Scroll scrims. The clipped row already marks the fold at rest;
          // these keep both edges honest once the list has been scrolled,
          // when content hides above the card top as well as below. Strength
          // tracks the distance still hidden past each edge rather than
          // animating on a clock, so a programmatic jump — wrapping from the
          // last row back to the first — lands with the fade already applied.
          Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            height: Math.min(Style.space(28), parent.height / 2)
            visible: opacity > 0
            opacity: resultList.contentHeight > resultList.height
              ? Math.max(0, Math.min(1, (resultList.contentY - resultList.originY) / height))
              : 0
            gradient: Gradient {
              GradientStop { position: 0; color: root.background }
              GradientStop { position: 1; color: Util.alpha(root.background, 0) }
            }
          }

          Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: Math.min(Style.space(28), parent.height / 2)
            visible: opacity > 0
            opacity: resultList.contentHeight > resultList.height
              ? Math.max(0, Math.min(1, (resultList.originY + resultList.contentHeight - resultList.height - resultList.contentY) / height))
              : 0
            gradient: Gradient {
              GradientStop { position: 0; color: Util.alpha(root.background, 0) }
              GradientStop { position: 1; color: root.background }
            }
          }

          Column {
            anchors.centerIn: parent
            spacing: Style.space(8)
            visible: displayModel.count === 0 && root.mode !== "input"

            Scanner {
              visible: root.bangPkgSearching
              running: root.bangPkgSearching
              cells: 11
              width: Style.space(180)
              height: Style.space(14)
              anchors.horizontalCenter: parent.horizontalCenter
            }

            Text {
              visible: !root.bangPkgSearching
              text: "󰈉"
              color: root.selectedText
              opacity: 0.8
              font.family: root.fontFamily
              font.pixelSize: Style.font.displayLarge
              horizontalAlignment: Text.AlignHCenter
              width: Style.space(320)
            }

            Text {
              textFormat: Text.PlainText
              text: root.activeBang ? root.bangEmptyText() : (root.filterText ? "No matches for “" + root.filterText + "”" : (root.activeMenu === "apps" ? "No applications found" : "Nothing here yet"))
              color: root.foreground
              opacity: 0.7
              font.family: root.fontFamily
              font.pixelSize: Style.font.title
              horizontalAlignment: Text.AlignHCenter
              width: Style.space(320)
            }
          }
        }

        Item {
          visible: root.pkgDetailVisible
          width: parent.width
          height: visible ? root.pkgDetailHeight : 0
          clip: true

          Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            height: Style.spacing.hairline
            color: Util.alpha(root.foreground, 0.2)
          }

          Text {
            textFormat: Text.PlainText
            anchors.fill: parent
            anchors.topMargin: Style.space(8)
            text: root.selectedPkgDetail || (root.bangPkgSearching ? "" : (root.pkgRemove ? "Select a package to remove" : "Select a package to read its description"))
            color: root.foreground
            opacity: root.selectedPkgDetail ? 0.78 : 0.45
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.WordWrap
            maximumLineCount: 4
            elide: Text.ElideRight
          }
        }

        Item {
          visible: root.navPane
          width: parent.width
          height: visible ? root.helpNavHeight : 0
          clip: true

          Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            height: Style.spacing.hairline
            color: Util.alpha(root.foreground, 0.2)
          }

          Column {
            anchors.fill: parent
            anchors.topMargin: Style.space(8)
            spacing: Style.space(3)

            Text {
              textFormat: Text.PlainText
              width: parent.width
              text: "Navigation"
              color: root.foreground
              opacity: 0.5
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              font.weight: Font.Medium
            }

            Text {
              textFormat: Text.PlainText
              width: parent.width
              text: root.settingsAliasesPage
                ? "Ctrl+J / Ctrl+K  down / up     Delete  remove alias"
                : "Ctrl+J / Ctrl+K  down / up     Super+V / Ctrl+V  paste"
              color: root.foreground
              opacity: 0.62
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              wrapMode: Text.WordWrap
              maximumLineCount: 2
              elide: Text.ElideRight
            }
          }
        }

        Item {
          width: parent.width
          height: 0
        }
      }
    }
  }
}
