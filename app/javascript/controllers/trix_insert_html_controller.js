import { Controller } from "@hotwired/stimulus"

// Adds an "Insert HTML" panel below the Trix editor.
// Clicking "Insert" calls editor.insertHTML(), which converts the HTML
// into Trix's internal document model (unsupported formatting is dropped).
export default class extends Controller {
  static targets = ["panel", "input"]

  toggle() {
    this.panelTarget.classList.toggle("hidden")
    if (!this.panelTarget.classList.contains("hidden")) {
      this.inputTarget.focus()
    }
  }

  insert() {
    const html = this.inputTarget.value.trim()
    if (!html) return

    const trixEditor = this.element.querySelector("trix-editor")
    if (!trixEditor) return

    trixEditor.editor.insertHTML(html)
    this.inputTarget.value = ""
    this.panelTarget.classList.add("hidden")
    trixEditor.focus()
  }

  cancel() {
    this.inputTarget.value = ""
    this.panelTarget.classList.add("hidden")
  }
}
