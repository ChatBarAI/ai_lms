import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["panel", "content", "toggle"]

  toggle() {
    const collapsed = this.panelTarget.classList.toggle("is-collapsed")
    this.contentTarget.hidden = collapsed
    this.toggleTarget.setAttribute("aria-expanded", (!collapsed).toString())
    this.toggleTarget.setAttribute("aria-label", collapsed ? "Show images" : "Hide images")
    this.toggleTarget.setAttribute("title", collapsed ? "Show images" : "Hide images")
  }
}
