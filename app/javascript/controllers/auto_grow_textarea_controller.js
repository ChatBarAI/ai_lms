import { Controller } from "@hotwired/stimulus"

// Keeps free-text quiz fields at content height while typing.
export default class extends Controller {
  static targets = ["field"]

  connect() {
    this.resize()
  }

  resize() {
    if (!this.hasFieldTarget) return

    const style = window.getComputedStyle(this.fieldTarget)
    const lineHeight = parseFloat(style.lineHeight) || 24
    const paddingTop = parseFloat(style.paddingTop) || 0
    const paddingBottom = parseFloat(style.paddingBottom) || 0
    const borderTop = parseFloat(style.borderTopWidth) || 0
    const borderBottom = parseFloat(style.borderBottomWidth) || 0
    const intrinsicMinHeight = lineHeight + paddingTop + paddingBottom + borderTop + borderBottom
    const cssMinHeight = parseFloat(style.minHeight) || 0
    const minHeight = Math.max(intrinsicMinHeight, cssMinHeight)

    this.fieldTarget.style.height = "auto"
    const contentHeight = Math.max(this.fieldTarget.scrollHeight, minHeight)
    const multilineBuffer = contentHeight > minHeight ? 2 : 0
    this.fieldTarget.style.height = `${contentHeight + multilineBuffer}px`
  }
}
