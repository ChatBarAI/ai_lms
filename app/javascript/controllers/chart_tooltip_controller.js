import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["tooltip", "bounds"]

  show(event) {
    const text = event.currentTarget.dataset.tooltip
    if (!text) return

    this.tooltipTarget.textContent = text
    this.tooltipTarget.classList.remove("hidden")
    this.position(event)
  }

  move(event) {
    if (this.tooltipTarget.classList.contains("hidden")) return
    this.position(event)
  }

  hide() {
    this.tooltipTarget.classList.add("hidden")
  }

  position(event) {
    const offset = 12
    const anchor = this.anchorPoint(event)
    const rect = this.tooltipTarget.getBoundingClientRect()

    if (this.hasBoundsTarget) {
      const bounds = this.boundsTarget.getBoundingClientRect()
      let left = (anchor.x - bounds.left) + offset
      let top = (anchor.y - bounds.top) - rect.height - offset

      const minLeft = 8
      const maxLeft = bounds.width - rect.width - 8
      const minTop = 8
      const maxTop = bounds.height - rect.height - 8

      left = Math.max(minLeft, Math.min(left, Math.max(minLeft, maxLeft)))
      top = Math.max(minTop, Math.min(top, Math.max(minTop, maxTop)))

      this.tooltipTarget.style.left = `${left}px`
      this.tooltipTarget.style.top = `${top}px`
    } else {
      let left = anchor.x + offset
      let top = anchor.y - rect.height - offset
      const maxLeft = window.innerWidth - rect.width - 8
      left = Math.min(left, maxLeft)
      top = Math.max(8, top)

      this.tooltipTarget.style.left = `${left}px`
      this.tooltipTarget.style.top = `${top}px`
    }
  }

  anchorPoint(event) {
    if (typeof event.clientX === "number" && typeof event.clientY === "number") {
      return { x: event.clientX, y: event.clientY }
    }

    const targetRect = event.currentTarget?.getBoundingClientRect()
    if (targetRect) {
      return {
        x: targetRect.left + (targetRect.width / 2),
        y: targetRect.top
      }
    }

    return { x: 8, y: 8 }
  }
}