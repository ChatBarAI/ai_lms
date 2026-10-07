import { Controller } from "@hotwired/stimulus"

// Matches dashboard layout#toggleHelpPanel: slide-in iframe panel from the right.
// Uses inline transform — Tailwind's translate-x-full is not in our built CSS.
export default class extends Controller {
  static targets = ["panel", "overlay", "openButton"]

  get isOpen() {
    return this.hasPanelTarget && this.panelTarget.dataset.open === "true"
  }

  toggle(event) {
    event?.preventDefault?.()
    if (this.isOpen) this.close()
    else this.open()
  }

  open() {
    if (!this.hasPanelTarget) return
    this.panelTarget.dataset.open = "true"
    this.panelTarget.style.transform = "translateX(0)"
    this.panelTarget.style.pointerEvents = "auto"
    if (this.hasOverlayTarget) this.overlayTarget.classList.remove("hidden")
  }

  close() {
    if (!this.hasPanelTarget) return
    this.panelTarget.dataset.open = "false"
    this.panelTarget.style.transform = "translateX(100%)"
    this.panelTarget.style.pointerEvents = "none"
    if (this.hasOverlayTarget) this.overlayTarget.classList.add("hidden")
  }

  keydown(event) {
    if (event.key === "Escape") this.close()
  }

  connect() {
    this.close()
    this._onKey = (e) => this.keydown(e)
    document.addEventListener("keydown", this._onKey)
  }

  disconnect() {
    document.removeEventListener("keydown", this._onKey)
  }
}
