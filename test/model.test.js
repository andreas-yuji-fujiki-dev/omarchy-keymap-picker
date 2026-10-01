// Run with: node test/model.test.js
const assert = require("assert")
const fs = require("fs")
const path = require("path")
const Model = require("../Model.js")

const xml = fs.readFileSync(Model.XKB_RULES, "utf8")
const layouts = Model.parseLayouts(xml)

assert(layouts.length > 50, "expected dozens of layouts, got " + layouts.length)

const br = layouts[Model.findLayout(layouts, "br")]
assert.strictEqual(br.description, "Portuguese (Brazil)")
assert(br.variants.some(v => v.name === "nodeadkeys"), "br should have nodeadkeys")

const us = layouts[Model.findLayout(layouts, "us")]
assert.strictEqual(us.description, "English (US)")
assert(us.variants.some(v => v.name === "intl"))

// Every name that reaches the apply script must pass the same validation.
for (const l of layouts) {
  assert(Model.isValidName(l.name), "layout name rejected: " + l.name)
  for (const v of l.variants) assert(Model.isValidName(v.name), "variant name rejected: " + l.name + "/" + v.name)
}

// Sorted, no duplicates, no empty descriptions.
const names = layouts.map(l => l.name)
assert.strictEqual(new Set(names).size, names.length)
for (let i = 1; i < layouts.length; i++)
  assert(layouts[i - 1].description.toLowerCase() <= layouts[i].description.toLowerCase())

// Search by country, by xkb name and through variants.
assert(Model.filterLayouts(layouts, "brazil").some(l => l.name === "br"))
assert(Model.filterLayouts(layouts, "dvorak").length > 3)
assert.strictEqual(Model.filterLayouts(layouts, "").length, layouts.length)
assert.strictEqual(Model.filterLayouts(layouts, "zzzz-nope").length, 0)

const rows = Model.variantRows(br)
assert.deepStrictEqual(rows[0], { value: "", label: "Default", description: "Portuguese (Brazil)" })
assert.strictEqual(rows.length, br.variants.length + 1)

assert.strictEqual(Model.firstOf("us,dk,eu"), "us")
assert.strictEqual(Model.firstOf(""), "")
assert.strictEqual(Model.badgeText("br"), "BR")
assert.strictEqual(Model.describe(layouts, "br", ""), "Portuguese (Brazil)")
assert.strictEqual(Model.describe(layouts, "br", "nodeadkeys"), br.variants.find(v => v.name === "nodeadkeys").description)
assert(!Model.isValidName("us\"); os.execute(\"x"))

console.log("model ok:", layouts.length, "layouts,", layouts.reduce((n, l) => n + l.variants.length, 0), "variants")
