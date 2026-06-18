import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["content", "icon"]

  connect() {
    // Initialize collapsed state - default to collapsed unless explicitly set to expanded
    const isExpanded = this.element.dataset.expanded === "true"
    if (isExpanded) {
      this.expand()
    } else {
      this.collapse()
    }
  }

  toggle() {
    if (this.contentTarget.classList.contains("hidden")) {
      this.expand()
    } else {
      this.collapse()
    }
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
