import { Controller } from "@hotwired/stimulus"

// Expands same-origin material documents so the iframe itself does not scroll.
export default class extends Controller {
  static values = { minHeight: { type: Number, default: 480 } }

  connect() {
    this.resize = this.scheduleResize.bind(this)
    this.element.addEventListener("load", this.resize)
    this.element.closest("[data-controller~='collapsible']")
      ?.addEventListener("collapsible:expanded", this.resize)
    window.addEventListener("resize", this.resize)

    if (this.element.contentDocument?.readyState === "complete") this.resize()
  }

  disconnect() {
    this.element.removeEventListener("load", this.resize)
    this.element.closest("[data-controller~='collapsible']")
      ?.removeEventListener("collapsible:expanded", this.resize)
    window.removeEventListener("resize", this.resize)
    window.cancelAnimationFrame(this.resizeFrame)
    this.documentObserver?.disconnect()
  }

  scheduleResize() {
    window.cancelAnimationFrame(this.resizeFrame)
    this.resizeFrame = window.requestAnimationFrame(() => this.measureAndResize())
  }

  measureAndResize() {
    try {
      const document = this.element.contentDocument
      if (!document?.documentElement || this.element.offsetWidth === 0) return

      // Measure against a stable viewport. Otherwise material CSS such as
      // `min-height: 100vh` grows as the iframe grows and creates a feedback loop.
      this.element.style.height = `${this.minHeightValue}px`

      const body = document.body
      const height = Math.max(
        this.minHeightValue,
        document.documentElement.scrollHeight,
        document.documentElement.offsetHeight,
        body?.scrollHeight || 0,
        body?.offsetHeight || 0
      )

      this.element.style.height = `${height}px`

      this.observeDocument(document)
    } catch (error) {
      // Keep the CSS fallback height if a future material endpoint is cross-origin.
      if (error.name !== "SecurityError") throw error
    }
  }

  observeDocument(document) {
    if (this.observedDocument === document) return

    this.documentObserver?.disconnect()
    this.observedDocument = document
    this.documentObserver = new ResizeObserver(this.resize)
    this.documentObserver.observe(document.documentElement)
    if (document.body) this.documentObserver.observe(document.body)
  }
}
