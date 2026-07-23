import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["freeToggle", "priceInput"]

  connect() {
    this.sync()
  }

  sync() {
    if (!this.hasFreeToggleTarget || !this.hasPriceInputTarget) return

    const free = this.freeToggleTarget.checked
    this.priceInputTarget.disabled = free

    if (free) {
      this.priceInputTarget.value = ""
    }

    this.priceInputTarget.classList.toggle("bg-gray-100", free)
    this.priceInputTarget.classList.toggle("text-gray-500", free)
    this.priceInputTarget.setAttribute("aria-disabled", free ? "true" : "false")
  }
}
