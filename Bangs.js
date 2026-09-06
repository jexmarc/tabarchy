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

function normalizeBang(key, raw) {
  var k = String(key || "").toLowerCase()
  if (k.length !== 1) return null
  if (raw === false || raw === null) return { key: k, disabled: true }

  var value = raw
  if (typeof value === "string") value = { action: value }
  if (!value || typeof value !== "object") return null

  var kind = String(value.kind || (value.action ? "command" : "")).toLowerCase()
  if (kind !== "files" && kind !== "command" && kind !== "web") return null
  if (kind === "command" && !value.action) return null

  var requiresQuery = value.requiresQuery
  if (requiresQuery === undefined) requiresQuery = kind === "files" || kind === "web" || k === "i"

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
      placeholder: "url or search",
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
      kind: "command",
      requiresQuery: true,
      action: "omarchy-launch-floating-terminal-with-presentation omarchy-pkg-add {{query}}"
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
