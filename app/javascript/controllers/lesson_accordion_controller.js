import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["button", "panel"]

  toggle(event) {
    const selectedButton = event.currentTarget
    const selectedPanel = this.panelFor(selectedButton)
    if (!selectedPanel) return

    const willExpand = selectedButton.getAttribute("aria-expanded") !== "true"

    this.buttonTargets.forEach((button) => {
      const panel = this.panelFor(button)
      if (panel) this.setExpanded(button, panel, false)
    })

    if (willExpand) this.setExpanded(selectedButton, selectedPanel, true)
  }

  panelFor(button) {
    const panelId = button.getAttribute("aria-controls")
    return this.panelTargets.find((panel) => panel.id === panelId)
  }

  setExpanded(button, panel, expanded) {
    button.setAttribute("aria-expanded", expanded ? "true" : "false")
    panel.classList.toggle("hidden", !expanded)

    const chevron = button.querySelector("[data-lesson-accordion-chevron]")
    if (chevron) chevron.classList.toggle("rotate-180", expanded)
  }
}
