function stripJsonc(raw) {
  return String(raw || "")
    .replace(/^\s*\/\/[^\n]*(\n|$)/gm, "")
    .replace(/,(\s*[}\]])/g, "$1")
}

function shellQuote(value) {
  return "'" + String(value || "").replace(/'/g, "'\\''") + "'"
}

function toUrl(query) {
  var q = String(query || "").trim()
  if (!q) return ""
  if (/^[a-zA-Z][a-zA-Z0-9+.-]*:/.test(q)) return q
  if (q.slice(0, 2) === "//") return "https:" + q
  return "https://" + q
}

function looksLikeUrl(query) {
  var q = String(query || "").trim()
  if (!q || /\s/.test(q)) return false
  if (/^[a-zA-Z][a-zA-Z0-9+.-]*:/.test(q)) return true
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

function resolveSearchProvider(value) {
  var raw = String(value || "google").trim()
  if (!raw) raw = "google"
  var key = raw.toLowerCase()
  if (key === "duckduckgo" || key === "duck" || key === "ddg") key = "ddg"
  var providers = searchProviders()
  if (providers[key]) return providers[key]
  if (raw.indexOf("%s") >= 0 || raw.indexOf("{{query") >= 0) {
    return {
      id: "custom",
      name: "Search",
      url: raw.replace(/%s/g, "{{query_encoded}}")
    }
  }
  return providers.google
}

function webDestination(query, providerValue, quoteFn) {
  var q = String(query || "").trim()
  var quote = quoteFn || shellQuote
  var provider = resolveSearchProvider(providerValue)
  if (looksLikeUrl(q)) {
    var url = toUrl(q)
    return {
      kind: "url",
      label: "Open URL",
      detail: url,
      action: "omarchy-launch-browser " + quote(url)
    }
  }
  var searchUrl = String(provider.url || "").replace(/\{\{query_encoded\}\}/g, encodeURIComponent(q))
  return {
    kind: "search",
    label: "Search " + provider.name,
    detail: q,
    action: "omarchy-launch-browser " + quote(searchUrl)
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
    discord: { key: "discord", name: "discord", url: "https://discord.com/" }
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
    url = String(url || "").trim()
    if (!url) continue
    out[k] = { key: k, name: name, url: toUrl(url) }
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
  if (kind !== "files" && kind !== "command" && kind !== "web" && kind !== "packages" && kind !== "remove-packages") return null
  if (kind === "command" && !value.action) return null

  var requiresQuery = value.requiresQuery
  if (requiresQuery === undefined)
    requiresQuery = kind === "files" || kind === "web" || kind === "packages" || kind === "remove-packages" || k === "i" || k === "r"

  return {
    key: k,
    name: String(value.name || k),
    icon: String(value.icon || "󰌧"),
    iconFont: String(value.iconFont || ""),
    placeholder: String(value.placeholder || ""),
    label: String(value.label || ""),
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
      label: "Google Maps",
      kind: "command",
      requiresQuery: false,
      action: "omarchy-launch-browser \"https://www.google.com/maps/search/?api=1&query={{query_encoded}}\""
    },
    w: {
      key: "w",
      name: "web",
      icon: "󰖟",
      iconFont: "",
      placeholder: "url, search, or alias",
      label: "Open URL or search",
      kind: "web",
      requiresQuery: true,
      action: ""
    },
    f: {
      key: "f",
      name: "files",
      icon: "",
      iconFont: "",
      placeholder: "filename",
      label: "Files",
      kind: "files",
      requiresQuery: true,
      action: ""
    },
    i: {
      key: "i",
      name: "install",
      icon: "󰏔",
      iconFont: "",
      placeholder: "package",
      label: "Install package",
      kind: "packages",
      requiresQuery: true,
      action: ""
    },
    r: {
      key: "r",
      name: "remove",
      icon: "󰆴",
      iconFont: "",
      placeholder: "package",
      label: "Remove package",
      kind: "remove-packages",
      requiresQuery: true,
      action: ""
    }
  }
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
