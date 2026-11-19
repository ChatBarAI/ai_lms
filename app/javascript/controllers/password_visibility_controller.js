import { Controller } from "@hotwired/stimulus"

// Toggles a password field between hidden and visible text.
export default class extends Controller {
  static targets = ["input", "button", "showIcon", "hideIcon"]
  static values = { showLabel: String, hideLabel: String }

  connect() {
    this.render(false)
    // Re-mask before submit and before Turbo snapshots the page: Turbo only
    // blanks input[type=password] in its cache, so a revealed (type=text)
    // field would otherwise keep the plaintext password in the snapshot.
    this.conceal = () => this.render(false)
    this.form = this.inputTarget.form
    this.form?.addEventListener("submit", this.conceal)
    document.addEventListener("turbo:before-cache", this.conceal)
  }

  disconnect() {
    this.form?.removeEventListener("submit", this.conceal)
    document.removeEventListener("turbo:before-cache", this.conceal)
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
