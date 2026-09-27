import assert from "node:assert/strict"
import { readFileSync } from "node:fs"
import test from "node:test"
import vm from "node:vm"

const source = readFileSync(new URL("../../app/javascript/controllers/material_copy_selector_controller.js", import.meta.url), "utf8")
const context = vm.createContext({
  Controller: class {},
  Option: class { constructor(text, value) { this.text = text; this.value = value } }
})
const Selector = vm.runInContext(source.replace(/^import .*\n/gm, "")
  .replace("export default class", "globalThis.Selector = class"), context)

function setup(prompts) {
  const select = () => ({
    value: "", options: [], disabled: true,
    replaceChildren(option) { this.options = [option]; this.value = "" },
    add(option) { this.options.push(option) }
  })
  const group = () => ({ classList: { toggle() {}, add() {} } })
  return Object.assign(new Selector(), {
    promptsValue: prompts,
    catalogValue: [{ id: 1, lessons: [{ id: 2, title: "Introduction", materials: [{ id: 3, title: "Reading", kind: "HTML" }] }] }],
    courseTarget: select(), lessonTarget: select(), materialTarget: select(),
    lessonGroupTarget: group(), materialGroupTarget: group(), submitTarget: { disabled: true }
  })
}

for (const [locale, prompts] of Object.entries({
  en: { courseFirst: "Choose module first…", lesson: "Choose activity…", lessonFirst: "Choose activity first…", material: "Choose a material…" },
  de: { courseFirst: "Zuerst Baustein auswählen…", lesson: "Einheit auswählen…", lessonFirst: "Zuerst Einheit auswählen…", material: "Material auswählen…" }
})) {
  test(`${locale}: selecting and clearing sources retains the supplied terminology`, () => {
    const controller = setup(prompts)
    controller.courseChanged()
    assert.equal(controller.lessonTarget.options[0].text, prompts.courseFirst)
    assert.equal(controller.lessonTarget.disabled, true)

    controller.courseTarget.value = "1"
    controller.courseChanged()
    assert.equal(controller.lessonTarget.options[0].text, prompts.lesson)
    assert.equal(controller.lessonTarget.options[1].text, "Introduction")
    assert.equal(controller.lessonTarget.disabled, false)
    assert.equal(controller.materialTarget.options[0].text, prompts.lessonFirst)

    controller.lessonTarget.value = "2"
    controller.lessonChanged()
    assert.equal(controller.materialTarget.options[0].text, prompts.material)
    assert.equal(controller.materialTarget.options[1].text, "Reading (HTML)")
    assert.equal(controller.materialTarget.disabled, false)
    controller.materialTarget.value = "3"
    controller.materialChanged()
    assert.equal(controller.submitTarget.disabled, false)

    controller.lessonTarget.value = ""
    controller.lessonChanged()
    assert.equal(controller.materialTarget.options[0].text, prompts.lessonFirst)
    assert.equal(controller.materialTarget.disabled, true)
    assert.equal(controller.submitTarget.disabled, true)

    controller.courseTarget.value = ""
    controller.courseChanged()
    assert.equal(controller.lessonTarget.options[0].text, prompts.courseFirst)
    assert.equal(controller.lessonTarget.disabled, true)
  })
}
