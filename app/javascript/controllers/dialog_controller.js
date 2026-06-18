import { Controller } from "@hotwired/stimulus"

// Controls a fixed-overlay modal using the same div-based pattern as the AI tutor.
// The outer element is the overlay (fixed inset-0); open/close toggle the `hidden` class.
//
// Auto-opens on connect when data-dialog-open-value="true".
// Backdrop click is wired via data-action="click->dialog#close" on the backdrop div.

export default class extends Controller {
  static targets = ["panel", "closeButton"]
  static values = { open: Boolean }

  connect() {
    if (this.openValue) this.open()
  }

  open() {
    this.previousActiveElement = document.activeElement
    this.element.classList.remove("hidden")
    this.element.setAttribute("aria-hidden", "false")
    document.body.classList.add("overflow-hidden")
    this._boundKeydown = this.onKeydown.bind(this)
    document.addEventListener("keydown", this._boundKeydown)

    if (this.hasCloseButtonTarget) {
      this.closeButtonTarget.focus()
    } else if (this.hasPanelTarget) {
      this.panelTarget.focus()
    }
  }

  close() {
    this.element.classList.add("hidden")
    this.element.setAttribute("aria-hidden", "true")
    document.body.classList.remove("overflow-hidden")
    if (this._boundKeydown) {
      document.removeEventListener("keydown", this._boundKeydown)
      this._boundKeydown = null
    }

    if (this.previousActiveElement && typeof this.previousActiveElement.focus === "function") {
      this.previousActiveElement.focus()
    }
  }

  disconnect() {
    if (this._boundKeydown) {
      document.removeEventListener("keydown", this._boundKeydown)
      this._boundKeydown = null
    }
  }

  onKeydown(event) {
    if (this.element.classList.contains("hidden")) return

    if (event.key === "Escape") {
      event.preventDefault()
      this.close()
      return
    }

    if (event.key === "Tab") {
      this.maintainFocus(event)
    }
  }

  maintainFocus(event) {
    if (!this.hasPanelTarget) return

    const focusableSelector = [
      "a[href]",
      "button:not([disabled])",
      "textarea:not([disabled])",
      "input:not([disabled])",
      "select:not([disabled])",
      "[tabindex]:not([tabindex='-1'])"
    ].join(",")

    const focusableElements = Array.from(this.panelTarget.querySelectorAll(focusableSelector))
    if (focusableElements.length === 0) return

    const first = focusableElements[0]
    const last = focusableElements[focusableElements.length - 1]

    if (event.shiftKey && document.activeElement === first) {
      event.preventDefault()
      last.focus()
    } else if (!event.shiftKey && document.activeElement === last) {
      event.preventDefault()
      first.focus()
    }
  }
}
