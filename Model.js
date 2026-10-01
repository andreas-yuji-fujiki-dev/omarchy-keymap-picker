// Pure data helpers for the Keymap picker: XKB layout parsing, search and the
// small bits of string handling around Hyprland's kb_layout / kb_variant.
// Nothing here touches Qt, so it can be tested under node (test/model.test.js).

var XKB_RULES = "/usr/share/X11/xkb/rules/evdev.xml"

function decodeEntities(text) {
  return String(text)
    .replace(/&lt;/g, "<")
    .replace(/&gt;/g, ">")
    .replace(/&quot;/g, "\"")
    .replace(/&apos;/g, "'")
    .replace(/&amp;/g, "&")
}

function tag(block, name) {
  var match = new RegExp("<" + name + ">([\\s\\S]*?)</" + name + ">").exec(block)
  return match ? decodeEntities(match[1].trim()) : ""
}

// Reads the layoutList of an xkeyboard-config rules file (evdev.xml) into
// [{ name, description, variants: [{ name, description }] }], sorted by the
// human description ("Portuguese (Brazil)"), the same names GNOME lists.
function parseLayouts(xml) {
  var layouts = []
  var layoutRe = /<layout>([\s\S]*?)<\/layout>/g
  var layoutMatch
  while ((layoutMatch = layoutRe.exec(String(xml))) !== null) {
    var block = layoutMatch[1]
    var variantListAt = block.indexOf("<variantList>")
    var head = variantListAt >= 0 ? block.slice(0, variantListAt) : block
    var name = tag(head, "name")
    if (name === "") continue

    var variants = []
    if (variantListAt >= 0) {
      var variantRe = /<variant(?:\s[^>]*)?>([\s\S]*?)<\/variant>/g
      var variantMatch
      while ((variantMatch = variantRe.exec(block.slice(variantListAt))) !== null) {
        var variantName = tag(variantMatch[1], "name")
        if (variantName === "") continue
        variants.push({
          name: variantName,
          description: tag(variantMatch[1], "description") || variantName
        })
      }
      variants.sort(function(a, b) { return compare(a.description, b.description) })
    }

    layouts.push({
      name: name,
      description: tag(head, "description") || name,
      variants: variants
    })
  }
  layouts.sort(function(a, b) { return compare(a.description, b.description) })
  return layouts
}

function compare(a, b) {
  var x = String(a).toLowerCase()
  var y = String(b).toLowerCase()
  return x < y ? -1 : (x > y ? 1 : 0)
}

// A layout matches when the query appears in its description, its xkb name,
// or any of its variants, so "dvorak" finds every country that ships one.
function filterLayouts(layouts, query) {
  var q = String(query || "").trim().toLowerCase()
  if (q === "") return layouts
  var out = []
  for (var i = 0; i < layouts.length; i++) {
    var layout = layouts[i]
    var hit = layout.description.toLowerCase().indexOf(q) !== -1 ||
      layout.name.toLowerCase() === q
    for (var v = 0; !hit && v < layout.variants.length; v++)
      hit = layout.variants[v].description.toLowerCase().indexOf(q) !== -1
    if (hit) out.push(layout)
  }
  return out
}

function findLayout(layouts, name) {
  for (var i = 0; i < layouts.length; i++)
    if (layouts[i].name === name) return i
  return -1
}

// The rows of the variant column: the layout's own default first, then its
// variants. `value` is what gets handed to kb_variant ("" for the default).
function variantRows(layout) {
  if (!layout) return []
  var rows = [{ value: "", label: "Default", description: layout.description }]
  for (var i = 0; i < layout.variants.length; i++)
    rows.push({
      value: layout.variants[i].name,
      label: layout.variants[i].description,
      description: layout.variants[i].name
    })
  return rows
}

// Hyprland accepts comma separated lists ("us,dk"); the picker manages one
// layout, so the first entry is the one shown as current.
function firstOf(list) {
  return String(list || "").split(",")[0].trim()
}

function isValidName(value) {
  return /^[A-Za-z0-9_+.\-]*$/.test(String(value))
}

function badgeText(layoutName) {
  return String(layoutName || "").toUpperCase() || "??"
}

function describe(layouts, layoutName, variantName) {
  var at = findLayout(layouts, layoutName)
  if (at < 0) return layoutName + (variantName ? " (" + variantName + ")" : "")
  var layout = layouts[at]
  for (var i = 0; i < layout.variants.length; i++)
    if (layout.variants[i].name === variantName) return layout.variants[i].description
  return layout.description
}

if (typeof module !== "undefined") {
  module.exports = {
    XKB_RULES: XKB_RULES,
    parseLayouts: parseLayouts,
    filterLayouts: filterLayouts,
    findLayout: findLayout,
    variantRows: variantRows,
    firstOf: firstOf,
    isValidName: isValidName,
    badgeText: badgeText,
    describe: describe
  }
}
