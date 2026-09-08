function stripJsonc(raw) {
  return String(raw || "")
    .replace(/^\s*\/\/[^\n]*(\n|$)/gm, "")
    .replace(/,(\s*[}\]])/g, "$1")
}

function shellQuote(value) {
  return "'" + String(value || "").replace(/'/g, "'\\''") + "'"
}

function schemeOf(value) {
  var match = String(value || "").trim().match(/^([a-zA-Z][a-zA-Z0-9+.-]*):/)
  return match ? match[1].toLowerCase() : ""
}

function isHttpUrl(value) {
  var scheme = schemeOf(value)
  return scheme === "http" || scheme === "https"
}

function toUrl(query) {
  var q = String(query || "").trim()
  if (!q) return ""
  var scheme = schemeOf(q)
  if (scheme) return (scheme === "http" || scheme === "https") ? q : ""
  if (q.slice(0, 2) === "//") return "https:" + q
  return "https://" + q
}

function looksLikeUrl(query) {
  var q = String(query || "").trim()
  if (!q || /\s/.test(q)) return false
  var scheme = schemeOf(q)
  if (scheme) return scheme === "http" || scheme === "https"
  if (q.slice(0, 2) === "//") return true
  if (/^(localhost|127\.0\.0\.1|\[::1\])(:\d+)?([/?#].*)?$/i.test(q)) return true
  if (/^(\d{1,3}\.){3}\d{1,3}(:\d+)?([/?#].*)?$/.test(q)) return true
  return /^[a-zA-Z0-9][a-zA-Z0-9.-]*\.[a-zA-Z]{2,}(:\d+)?([/?#].*)?$/.test(q)
}

function searchProviders() {
  return {
    google: { id: "google", name: "Google", url: "https://www.google.com/search?q={{query_encoded}}" },
    ddg: { id: "ddg", name: "DuckDuckGo", url: "https://duckduckgo.com/?q={{query_encoded}}" },
    brave: { id: "brave", name: "Brave", url: "https://search.brave.com/search?q={{query_encoded}}" },
    bing: { id: "bing", name: "Bing", url: "https://www.bing.com/search?q={{query_encoded}}" },
    ecosia: { id: "ecosia", name: "Ecosia", url: "https://www.ecosia.org/search?q={{query_encoded}}" },
    kagi: { id: "kagi", name: "Kagi", url: "https://kagi.com/search?q={{query_encoded}}" },
    startpage: { id: "startpage", name: "Startpage", url: "https://www.startpage.com/sp/search?query={{query_encoded}}" }
  }
}

function searchProviderOrder() {
  return ["google", "ddg", "brave", "bing", "ecosia", "kagi", "startpage"]
}

function resolveSearchProvider(value) {
  var raw = String(value || "google").trim()
  if (!raw) raw = "google"
  var key = raw.toLowerCase()
  if (key === "duckduckgo" || key === "duck" || key === "ddg") key = "ddg"
  var providers = searchProviders()
  if (providers[key]) return providers[key]
  if (isHttpProviderTemplate(raw)) {
    return {
      id: "custom",
      name: "Custom",
      url: raw.replace(/%s/g, "{{query_encoded}}")
    }
  }
  return providers.google
}

function mapsProviders() {
  return {
    google: { id: "google", name: "Google Maps", url: "https://www.google.com/maps/search/?api=1&query={{query_encoded}}" },
    osm: { id: "osm", name: "OpenStreetMap", url: "https://www.openstreetmap.org/search?query={{query_encoded}}" },
    bing: { id: "bing", name: "Bing Maps", url: "https://www.bing.com/maps?q={{query_encoded}}" },
    apple: { id: "apple", name: "Apple Maps", url: "https://maps.apple.com/?q={{query_encoded}}" },
    ddg: { id: "ddg", name: "DuckDuckGo Maps", url: "https://duckduckgo.com/?q={{query_encoded}}&iaxm=maps" },
    kagi: { id: "kagi", name: "Kagi Maps", url: "https://kagi.com/maps?q={{query_encoded}}" }
  }
}

function mapsProviderOrder() {
  return ["google", "osm", "bing", "apple", "ddg", "kagi"]
}

function resolveMapsProvider(value) {
  var raw = String(value || "google").trim()
  if (!raw) raw = "google"
  var key = raw.toLowerCase()
  if (key === "openstreetmap" || key === "openstreet" || key === "osm") key = "osm"
  if (key === "duckduckgo" || key === "duck" || key === "ddg") key = "ddg"
  if (key === "googlemaps" || key === "gmaps" || key === "maps") key = "google"
  var providers = mapsProviders()
  if (providers[key]) return providers[key]
  if (isHttpProviderTemplate(raw)) {
    return {
      id: "custom",
      name: "Custom",
      url: raw.replace(/%s/g, "{{query_encoded}}")
    }
  }
  return providers.google
}

function isProviderTemplate(value) {
  var raw = String(value || "")
  return raw.indexOf("%s") >= 0 || raw.indexOf("{{query") >= 0
}

function isHttpProviderTemplate(value) {
  if (!isProviderTemplate(value)) return false
  var raw = String(value || "").trim()
  var probe = raw.replace(/%s/g, "x").replace(/\{\{query[^}]*\}\}/g, "x")
  if (isHttpUrl(probe) || isHttpUrl(raw)) return true
  if (raw.slice(0, 2) === "//") return true
  return false
}

function expandProviderUrl(provider, query) {
  var encoded = encodeURIComponent(String(query || ""))
  var url = String((provider && provider.url) || "")
  if (url.indexOf("%s") >= 0) return url.replace(/%s/g, encoded)
  return url.replace(/\{\{query_encoded\}\}/g, encoded)
}

function providerChoices(providers, order, currentValue, resolveFn) {
  var resolved = resolveFn(currentValue)
  var rows = []
  var i
  for (i = 0; i < order.length; i++) {
    var item = providers[order[i]]
    if (!item) continue
    rows.push({
      id: item.id,
      name: item.name,
      url: item.url,
      current: resolved.id === item.id
    })
  }
  rows.push({
    id: "custom",
    name: "Custom",
    url: resolved.id === "custom" ? resolved.url : "",
    current: resolved.id === "custom"
  })
  return rows
}

function defaultMapsAction() {
  return "omarchy-launch-browser \"https://www.google.com/maps/search/?api=1&query={{query_encoded}}\""
}

function webDestination(query, providerValue, quoteFn) {
  var q = String(query || "").trim()
  var quote = quoteFn || shellQuote
  var provider = resolveSearchProvider(providerValue)
  if (looksLikeUrl(q)) {
    var url = toUrl(q)
    if (url) {
      return {
        kind: "url",
        label: "Open URL",
        detail: url,
        action: "omarchy-launch-browser " + quote(url)
      }
    }
  }
  return {
    kind: "search",
    label: "Search " + provider.name,
    detail: q,
    action: "omarchy-launch-browser " + quote(expandProviderUrl(provider, q))
  }
}

function mapsDestination(query, providerValue, quoteFn) {
  var q = String(query || "").trim()
  var quote = quoteFn || shellQuote
  var provider = resolveMapsProvider(providerValue)
  if (!q) {
    return {
      kind: "maps",
      label: provider.name,
      detail: "",
      action: ""
    }
  }
  return {
    kind: "maps",
    label: provider.name,
    detail: q,
    action: "omarchy-launch-browser " + quote(expandProviderUrl(provider, q))
  }
}

function canonicalUrl(url) {
  return String(url || "").trim().replace(/\/+$/, "").toLowerCase()
}

function hostFromUrl(url) {
  var match = String(url || "").match(/^[a-zA-Z][a-zA-Z0-9+.-]*:\/\/([^/?#]+)/)
  if (!match) return ""
  return match[1].replace(/^www\./i, "").toLowerCase()
}

function defaultWebAliases() {
  return {
    amazon: { key: "amazon", name: "amazon", url: "https://amazon.com/" },
    discord: { key: "discord", name: "discord", url: "https://discord.com/" },
    gh: { key: "gh", name: "gh", url: "https://github.com/" },
    op: { key: "op", name: "op", url: "https://plugins.omarchy.org/" }
  }
}

function normalizeAliasMap(raw) {
  if (!raw || typeof raw !== "object" || Array.isArray(raw)) return {}
  var out = {}
  for (var key in raw) {
    if (!Object.prototype.hasOwnProperty.call(raw, key)) continue
    var k = String(key || "").trim().toLowerCase()
    if (!k) continue
    var value = raw[key]
    if (value === false || value === null) {
      out[k] = { key: k, disabled: true }
      continue
    }
    var url = ""
    var name = k
    if (typeof value === "string") {
      url = value
    } else if (value && typeof value === "object") {
      url = String(value.url || value.action || "")
      if (value.name) name = String(value.name)
    }
    url = toUrl(url)
    if (!url) continue
    out[k] = { key: k, name: name, url: url }
  }
  return out
}

function parseAliases(raw) {
  var text = stripJsonc(raw).trim()
  if (!text) return {}

  var data
  try {
    data = JSON.parse(text)
  } catch (e) {
    return {}
  }
  if (!data || typeof data !== "object" || Array.isArray(data)) return {}

  var out = {}
  var bangsRoot = data
  if (data.bangs && typeof data.bangs === "object" && !Array.isArray(data.bangs))
    bangsRoot = data.bangs

  var maps = [data.aliases, bangsRoot.aliases]
  var w = bangsRoot.w || bangsRoot.W
  if (w && typeof w === "object") maps.push(w.aliases)
  for (var i = 0; i < maps.length; i++) {
    var extra = normalizeAliasMap(maps[i])
    for (var key in extra) {
      if (Object.prototype.hasOwnProperty.call(extra, key)) out[key] = extra[key]
    }
  }
  return out
}

function mergeAliases(base, overlay) {
  var out = {}
  var key
  for (key in base) {
    if (Object.prototype.hasOwnProperty.call(base, key) && !base[key].disabled)
      out[key] = base[key]
  }
  for (key in overlay) {
    if (!Object.prototype.hasOwnProperty.call(overlay, key)) continue
    if (overlay[key] && overlay[key].disabled) delete out[key]
    else out[key] = overlay[key]
  }
  return out
}

function aliasScore(alias, query) {
  if (!alias || alias.disabled) return -1
  var q = String(query || "").trim().toLowerCase()
  if (!q) return 10
  var key = String(alias.key || "").toLowerCase()
  var name = String(alias.name || "").toLowerCase()
  var host = hostFromUrl(alias.url)
  var url = String(alias.url || "").toLowerCase()
  if (key === q || name === q) return 0
  if (key.indexOf(q) === 0 || name.indexOf(q) === 0) return 1
  if (host && host.indexOf(q) === 0) return 2
  if (key.indexOf(q) >= 0 || name.indexOf(q) >= 0) return 3
  if ((host && host.indexOf(q) >= 0) || url.indexOf(q) >= 0) return 4
  return -1
}

function matchAliases(aliases, query) {
  var list = []
  if (!aliases) return list
  for (var key in aliases) {
    if (!Object.prototype.hasOwnProperty.call(aliases, key)) continue
    var alias = aliases[key]
    var score = aliasScore(alias, query)
    if (score < 0) continue
    list.push({
      key: alias.key || key,
      name: alias.name || key,
      url: alias.url,
      score: score
    })
  }
  list.sort(function(a, b) {
    if (a.score !== b.score) return a.score - b.score
    return String(a.key).localeCompare(String(b.key))
  })
  return list
}

function webChoices(query, aliases, providerValue, quoteFn) {
  var q = String(query || "").trim()
  var quote = quoteFn || shellQuote
  var out = []
  var seen = {}
  var matches = matchAliases(aliases, q)
  var i
  for (i = 0; i < matches.length; i++) {
    var alias = matches[i]
    var aliasKey = canonicalUrl(alias.url)
    if (aliasKey) seen[aliasKey] = true
    out.push({
      kind: "alias",
      label: alias.name || alias.key,
      detail: alias.url,
      action: "omarchy-launch-browser " + quote(alias.url)
    })
  }
  if (!q) return out
  if (looksLikeUrl(q)) {
    var url = toUrl(q)
    var urlKey = canonicalUrl(url)
    if (!urlKey || !seen[urlKey]) {
      out.push({
        kind: "url",
        label: "Open URL",
        detail: url,
        action: "omarchy-launch-browser " + quote(url)
      })
    }
  } else {
    var dest = webDestination(q, providerValue, quote)
    out.push({
      kind: "search",
      label: dest.label,
      detail: dest.detail,
      action: dest.action
    })
  }
  return out
}

function normalizeBang(key, raw) {
  var k = String(key || "").toLowerCase()
  if (k.length !== 1) return null
  if (raw === false || raw === null) return { key: k, disabled: true }

  var value = raw
  if (typeof value === "string") value = { action: value }
  if (!value || typeof value !== "object") return null

  var kind = String(value.kind || (value.action ? "command" : "")).toLowerCase()
  if (!value.kind && String(value.action || "") === defaultMapsAction())
    kind = "maps"
  if (kind !== "files" && kind !== "command" && kind !== "web" && kind !== "packages" && kind !== "remove-packages" && kind !== "help" && kind !== "maps" && kind !== "settings") return null
  if (kind === "command" && !value.action) return null

  var requiresQuery = value.requiresQuery
  if (requiresQuery === undefined)
    requiresQuery = kind === "files" || kind === "web" || kind === "packages" || kind === "remove-packages" || kind === "maps" || k === "i" || k === "r"

  return {
    key: k,
    name: String(value.name || k),
    icon: String(value.icon || "󰌧"),
    iconFont: String(value.iconFont || ""),
    placeholder: String(value.placeholder || ""),
    label: String(value.label || ""),
    help: String(value.help || ""),
    kind: kind,
    action: String(value.action || ""),
    requiresQuery: !!requiresQuery
  }
}

function parseBangs(raw) {
  var text = stripJsonc(raw).trim()
  if (!text) return {}

  var data
  try {
    data = JSON.parse(text)
  } catch (e) {
    return {}
  }
  if (!data || typeof data !== "object" || Array.isArray(data)) return {}
  if (data.bangs && typeof data.bangs === "object" && !Array.isArray(data.bangs))
    data = data.bangs

  var out = {}
  for (var key in data) {
    if (!Object.prototype.hasOwnProperty.call(data, key)) continue
    var bang = normalizeBang(key, data[key])
    if (bang) out[bang.key] = bang
  }
  return out
}

function defaults() {
  return {
    m: {
      key: "m",
      name: "maps",
      icon: "󰗵",
      iconFont: "",
      placeholder: "address",
      label: "Maps",
      help: "open an address on the map",
      kind: "maps",
      requiresQuery: true,
      action: ""
    },
    w: {
      key: "w",
      name: "web",
      icon: "󰖟",
      iconFont: "",
      placeholder: "url, search, or alias",
      label: "Open URL or search",
      help: "URL, alias, or web search",
      kind: "web",
      requiresQuery: true,
      action: ""
    },
    f: {
      key: "f",
      name: "files",
      icon: "",
      iconFont: "",
      placeholder: "file or folder",
      label: "Files",
      help: "find a file or folder · Enter opens · ' shows in Files",
      kind: "files",
      requiresQuery: true,
      action: ""
    },
    i: {
      key: "i",
      name: "install pkg",
      icon: "󰏔",
      iconFont: "",
      placeholder: "package",
      label: "Install package",
      help: "search and install a package",
      kind: "packages",
      requiresQuery: true,
      action: ""
    },
    r: {
      key: "r",
      name: "remove pkg",
      icon: "󰆴",
      iconFont: "",
      placeholder: "package",
      label: "Remove package",
      help: "search and uninstall a package",
      kind: "remove-packages",
      requiresQuery: true,
      action: ""
    },
    "?": {
      key: "?",
      name: "help",
      icon: "󰋖",
      iconFont: "",
      placeholder: "",
      label: "Commands",
      help: "this list",
      kind: "help",
      requiresQuery: false,
      action: ""
    },
    ",": {
      key: ",",
      name: "settings",
      icon: "󰒓",
      iconFont: "",
      placeholder: "",
      label: "Settings",
      help: "search provider, maps, aliases, and updates",
      kind: "settings",
      requiresQuery: false,
      action: ""
    }
  }
}

function bangHelpText(bang) {
  if (!bang) return ""
  if (bang.help) return bang.help
  if (bang.key === "m" || bang.kind === "maps") return "open an address on the map"
  if (bang.kind === "web") return "URL, alias, or web search"
  if (bang.kind === "files") return "find a file or folder · Enter opens · ' shows in Files"
  if (bang.kind === "packages") return "search and install a package"
  if (bang.kind === "remove-packages") return "search and uninstall a package"
  if (bang.kind === "settings") return "search provider, maps, aliases, and updates"
  if (bang.kind === "help") return "this list"
  if (bang.placeholder) return bang.placeholder
  return bang.label || bang.name || ""
}

function helpKeys(bangs) {
  var preferred = ["w", "f", "m", "i", "r", ","]
  var keys = []
  var seen = {}
  var i
  for (i = 0; i < preferred.length; i++) {
    var pref = preferred[i]
    if (bangs && bangs[pref] && !bangs[pref].disabled) {
      keys.push(pref)
      seen[pref] = true
    }
  }
  var extra = []
  for (var key in bangs) {
    if (!Object.prototype.hasOwnProperty.call(bangs, key)) continue
    if (seen[key] || key === "?" || (bangs[key] && bangs[key].disabled)) continue
    extra.push(key)
  }
  extra.sort()
  keys = keys.concat(extra)
  if (bangs && bangs["?"] && !bangs["?"].disabled) keys.push("?")
  return keys
}

function mergeBangs(base, overlay) {
  var out = {}
  var key
  for (key in base) {
    if (Object.prototype.hasOwnProperty.call(base, key) && !base[key].disabled)
      out[key] = base[key]
  }
  for (key in overlay) {
    if (!Object.prototype.hasOwnProperty.call(overlay, key)) continue
    if (overlay[key] && overlay[key].disabled) delete out[key]
    else out[key] = overlay[key]
  }
  return out
}

function expandAction(template, query, quoteFn) {
  var q = String(query || "")
  var quote = quoteFn || shellQuote
  return String(template || "")
    .replace(/\{\{query_encoded\}\}/g, encodeURIComponent(q))
    .replace(/\{\{url\}\}/g, quote(toUrl(q)))
    .replace(/\{\{query\}\}/g, quote(q))
}

function fileLabel(path) {
  var text = String(path || "")
  var trimmed = text.replace(/\/+$/, "")
  var slash = trimmed.lastIndexOf("/")
  if (slash < 0) return text
  return trimmed.slice(slash + 1) || text
}

function isAliasKey(key) {
  return /^[a-z0-9][a-z0-9._-]*$/.test(String(key || ""))
}

function parseAliasInput(query) {
  var q = String(query || "").trim()
  if (!q) return null
  var match = q.match(/^(\S+)\s+(\S[\s\S]*)$/)
  if (!match) return null
  var key = match[1].toLowerCase()
  var url = toUrl(match[2].trim())
  if (!isAliasKey(key) || !url) return null
  return { key: key, url: url }
}

function parseSettings(raw) {
  var text = stripJsonc(raw).trim()
  if (!text) return {}

  var data
  try {
    data = JSON.parse(text)
  } catch (e) {
    return {}
  }
  if (!data || typeof data !== "object" || Array.isArray(data)) return {}
  return data
}

function postUpdateHookEnabled(data) {
  return !!(data && typeof data === "object" && data.postUpdateHook === true)
}

function settingsAliasesFromData(data) {
  if (!data || typeof data !== "object") return {}
  return normalizeAliasMap(data.aliases)
}

function aliasSummary(aliases) {
  var keys = []
  var key
  for (key in aliases) {
    if (!Object.prototype.hasOwnProperty.call(aliases, key)) continue
    var alias = aliases[key]
    if (!alias || alias.disabled) continue
    keys.push(alias.key || key)
  }
  keys.sort()
  if (keys.length === 0) return "none"
  if (keys.length <= 4) return keys.join(", ")
  return String(keys.length) + " shortcuts"
}

function sortedAliases(aliases) {
  var list = []
  var key
  for (key in aliases) {
    if (!Object.prototype.hasOwnProperty.call(aliases, key)) continue
    var alias = aliases[key]
    if (!alias || alias.disabled) continue
    list.push({
      key: alias.key || key,
      name: alias.name || key,
      url: alias.url
    })
  }
  list.sort(function(a, b) {
    return String(a.key).localeCompare(String(b.key))
  })
  return list
}

function settingsMatch(label, detail, path, query) {
  var q = String(query || "").trim().toLowerCase()
  if (!q) return true
  var hay = (String(label || "") + " " + String(detail || "") + " " + String(path || "")).toLowerCase()
  return hay.indexOf(q) >= 0
}
