import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["content", "icon"]
  static values = { storageKey: String }

  connect() {
    const savedState = this.savedState()
    const isExpanded = savedState ?? (this.element.dataset.expanded === "true")
    if (isExpanded) {
      this.expand()
    } else {
      this.collapse()
    }
  }

  savedState() {
    if (!this.hasStorageKeyValue) return null

    try {
      const saved = window.localStorage.getItem(this.storageKeyValue)
      return saved === "true" ? true : saved === "false" ? false : null
    } catch {
      return null
    }
  }

  saveState() {
    if (!this.hasStorageKeyValue) return

    try {
      window.localStorage.setItem(this.storageKeyValue, String(!this.contentTarget.classList.contains("hidden")))
    } catch {
      // Materials remain usable when browser storage is unavailable.
    }
  }

  toggle() {
    if (this.contentTarget.classList.contains("hidden")) {
      this.expand()
    } else {
      this.collapse()
    }
    this.saveState()
  }

  collapse() {
    this.contentTarget.classList.add("hidden")
    if (this.hasIconTarget) {
      this.iconTarget.classList.remove("rotate-90")
    }
    this.dispatch("collapsed")
  }

  expand() {
    this.contentTarget.classList.remove("hidden")
    if (this.hasIconTarget) {
      this.iconTarget.classList.add("rotate-90")
    }
    this.dispatch("expanded")
  }
}
