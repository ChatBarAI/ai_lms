import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["menu", "button"]

  connect() {
    this._boundClickOutside = this.clickOutside.bind(this)
    this._boundKeydown = this.onKeydown.bind(this)
    document.addEventListener("click", this._boundClickOutside)
    document.addEventListener("keydown", this._boundKeydown)
    this.setExpanded(false)
  }

  disconnect() {
    document.removeEventListener("click", this._boundClickOutside)
    document.removeEventListener("keydown", this._boundKeydown)
  }

  toggle(event) {
    event.stopPropagation()
    if (this.isOpen()) {
      this.close()
      return
    }

    this.open()
  }

  close() {
    if (!this.isOpen()) return

    this.menuTarget.classList.add("hidden")
    this.setExpanded(false)
  }

  clickOutside(event) {
    if (!this.element.contains(event.target)) {
      this.close()
    }
  }

  open() {
    this.menuTarget.classList.remove("hidden")
    this.setExpanded(true)

    const firstFocusable = this.menuTarget.querySelector("a,button,[tabindex]:not([tabindex='-1'])")
    if (firstFocusable) {
      firstFocusable.focus()
    }
  }

  onKeydown(event) {
    if (event.key === "Escape") {
      this.close()
      if (this.hasButtonTarget) this.buttonTarget.focus()
    }
  }

  isOpen() {
    return !this.menuTarget.classList.contains("hidden")
  }

  setExpanded(expanded) {
    if (!this.hasButtonTarget) return
    this.buttonTarget.setAttribute("aria-expanded", expanded ? "true" : "false")
  }
}
