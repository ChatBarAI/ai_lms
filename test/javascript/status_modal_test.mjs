import assert from "node:assert/strict"
import { readFileSync } from "node:fs"
import test from "node:test"
import vm from "node:vm"

const source = readFileSync(new URL("../../app/javascript/controllers/status_modal_controller.js", import.meta.url), "utf8")

for (const useDialogController of [true, false]) {
  test(`locked purchase submission opens and fills the dialog ${useDialogController ? "through its controller" : "with the fallback"}`, () => {
    const fields = Object.fromEntries(["title", "message", "link", "secondary-link"].map(name => [name, {
      classList: { toggle() {} }
    }]))
    const classes = new Set(["hidden"])
    const attributes = { "aria-hidden": "true" }
    const dialog = {
      querySelector: selector => fields[selector.match(/data-dialog-fill="([^"]+)"/)[1]],
      classList: { remove: name => classes.delete(name) },
      setAttribute: (name, value) => { attributes[name] = value }
    }
    const StatusModal = vm.runInNewContext(source
      .replace(/^import .*\n/gm, "")
      .replace("export default class", "globalThis.StatusModal = class"), {
      Controller: class {},
      document: {
        getElementById(id) {
          assert.equal(id, "locked-dialog")
          return dialog
        }
      }
    })
    let opened = 0
    const instance = Object.assign(new StatusModal(), {
      hasDialogIdValue: true,
      dialogIdValue: "locked-dialog",
      application: {
        getControllerForElementAndIdentifier(element, identifier) {
          assert.equal(element, dialog)
          assert.equal(identifier, "dialog")
          return useDialogController ? { open: () => { opened += 1 } } : null
        }
      }
    })
    let prevented = false

    instance.open({
      type: "submit",
      preventDefault: () => { prevented = true },
      params: {
        title: "Module locked",
        message: "Complete Algebra first",
        linkUrl: "/courses/algebra",
        linkLabel: "Go to Algebra"
      }
    })

    assert.equal(prevented, true, "checkout submission must be prevented")
    assert.equal(fields.title.textContent, "Module locked")
    assert.equal(fields.message.textContent, "Complete Algebra first")
    assert.equal(fields.link.href, "/courses/algebra")
    assert.equal(fields.link.textContent, "Go to Algebra")
    if (useDialogController) {
      assert.equal(opened, 1)
    } else {
      assert.equal(classes.has("hidden"), false)
      assert.equal(attributes["aria-hidden"], "false")
    }
  })
}
