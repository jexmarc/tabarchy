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

function normalizeBang(key, raw) {
  var k = String(key || "").toLowerCase()
  if (k.length !== 1) return null
  if (raw === false || raw === null) return { key: k, disabled: true }

  var value = raw
  if (typeof value === "string") value = { action: value }
  if (!value || typeof value !== "object") return null

  var kind = String(value.kind || (value.action ? "command" : "")).toLowerCase()
  if (kind !== "files" && kind !== "command") return null
  if (kind === "command" && !value.action) return null

  var requiresQuery = value.requiresQuery
  if (requiresQuery === undefined) requiresQuery = kind === "files" || k === "w" || k === "i"

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
      name: "url",
      icon: "󰖟",
      iconFont: "",
      placeholder: "amazon.com",
      label: "Open URL",
      kind: "command",
      requiresQuery: true,
      action: "omarchy-launch-browser {{url}}"
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
