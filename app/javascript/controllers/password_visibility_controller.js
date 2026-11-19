import { Controller } from "@hotwired/stimulus"

// Toggles a password field between hidden and visible text.
export default class extends Controller {
  static targets = ["input", "button", "showIcon", "hideIcon"]
  static values = { showLabel: String, hideLabel: String }

  connect() {
    this.render(false)
  }

  toggle() {
    this.render(this.inputTarget.type === "password")
    this.inputTarget.focus()
  }

  render(visible) {
    this.inputTarget.type = visible ? "text" : "password"
    this.buttonTarget.setAttribute("aria-pressed", String(visible))
    this.buttonTarget.setAttribute("aria-label", visible ? this.hideLabelValue : this.showLabelValue)
    this.buttonTarget.title = visible ? this.hideLabelValue : this.showLabelValue
    this.showIconTarget.classList.toggle("hidden", visible)
    this.hideIconTarget.classList.toggle("hidden", !visible)
  }
}
