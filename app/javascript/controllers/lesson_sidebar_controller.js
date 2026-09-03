import { Controller } from "@hotwired/stimulus"
import { lockBodyScroll, unlockBodyScroll } from "controllers/scroll_lock"

export default class extends Controller {
  static targets = ["overlay", "backdrop", "panel", "openButton", "closeButton"]

  connect() {
    this.onKeydown = this.handleKeydown.bind(this)
    this.onBeforeCache = this.closeImmediately.bind(this)
    this.onResize = this.applyPresentation.bind(this)
    document.addEventListener("turbo:before-cache", this.onBeforeCache)
    window.addEventListener("resize", this.onResize)
  }

  toggle() {
    if (this.overlayTarget.getAttribute("aria-hidden") === "true") {
      this.open()
    } else {
      this.close()
    }
  }

  open() {
    if (!this.hasOverlayTarget || !this.hasPanelTarget) return

    this.clearCloseTimer()
    this.previousActiveElement = document.activeElement
    this.overlayTarget.classList.remove("invisible", "pointer-events-none")
    this.overlayTarget.setAttribute("aria-hidden", "false")
    this.openButtonTarget.setAttribute("aria-expanded", "true")
    this.applyPresentation()
    document.addEventListener("keydown", this.onKeydown)

    this.openFrame = requestAnimationFrame(() => {
      this.openFrame = null
      this.backdropTarget.classList.remove("opacity-0")
      this.backdropTarget.classList.add("opacity-100")
      this.panelTarget.classList.remove("-translate-x-full")
      this.panelTarget.classList.add("translate-x-0")
      this.closeButtonTarget.focus()
    })
  }

  close() {
    if (!this.hasOverlayTarget || this.overlayTarget.getAttribute("aria-hidden") === "true") return

    this.clearOpenFrame()
    this.backdropTarget.classList.remove("opacity-100")
    this.backdropTarget.classList.add("opacity-0")
    this.panelTarget.classList.remove("translate-x-0")
    this.panelTarget.classList.add("-translate-x-full")
    this.overlayTarget.setAttribute("aria-hidden", "true")
    this.openButtonTarget.setAttribute("aria-expanded", "false")
    this.unlockPage()
    document.removeEventListener("keydown", this.onKeydown)

    this.closeTimer = window.setTimeout(() => {
      this.overlayTarget.classList.add("invisible", "pointer-events-none")
      this.closeTimer = null
    }, 300)

    if (this.previousActiveElement && typeof this.previousActiveElement.focus === "function") {
      this.previousActiveElement.focus()
    }
  }

  disconnect() {
    this.clearCloseTimer()
    this.clearOpenFrame()
    document.removeEventListener("keydown", this.onKeydown)
    document.removeEventListener("turbo:before-cache", this.onBeforeCache)
    window.removeEventListener("resize", this.onResize)
    this.closeImmediately()
  }

  handleKeydown(event) {
    if (event.key === "Escape") {
      event.preventDefault()
      this.close()
      return
    }

    if (event.key === "Tab" && !this.inlineAvailable) this.maintainFocus(event)
  }

  maintainFocus(event) {
    const focusableSelector = [
      "a[href]",
      "button:not([disabled])",
      "[tabindex]:not([tabindex='-1'])"
    ].join(",")
    const focusableElements = Array.from(this.panelTarget.querySelectorAll(focusableSelector))
    if (focusableElements.length === 0) return

    const first = focusableElements[0]
    const last = focusableElements[focusableElements.length - 1]
    if (event.shiftKey && document.activeElement === first) {
      event.preventDefault()
      last.focus()
    } else if (!event.shiftKey && document.activeElement === last) {
      event.preventDefault()
      first.focus()
    }
  }

  clearCloseTimer() {
    if (!this.closeTimer) return

    window.clearTimeout(this.closeTimer)
    this.closeTimer = null
  }

  clearOpenFrame() {
    if (!this.openFrame) return

    cancelAnimationFrame(this.openFrame)
    this.openFrame = null
  }

  closeImmediately() {
    if (!this.hasOverlayTarget || !this.hasPanelTarget) return

    const wasOpen = this.overlayTarget.getAttribute("aria-hidden") === "false"
    this.clearCloseTimer()
    this.clearOpenFrame()
    this.backdropTarget.classList.remove("opacity-100")
    this.backdropTarget.classList.add("opacity-0")
    this.panelTarget.classList.remove("translate-x-0")
    this.panelTarget.classList.add("-translate-x-full")
    this.overlayTarget.classList.add("invisible", "pointer-events-none")
    this.overlayTarget.setAttribute("aria-hidden", "true")
    this.openButtonTarget.setAttribute("aria-expanded", "false")
    document.removeEventListener("keydown", this.onKeydown)
    if (wasOpen) this.unlockPage()
  }

  applyPresentation() {
    if (!this.hasOverlayTarget || this.overlayTarget.getAttribute("aria-hidden") === "true") return

    const inline = this.inlineAvailable
    this.overlayTarget.setAttribute("aria-modal", inline ? "false" : "true")
    document.body.classList.toggle("lesson-sidebar-inline-active", inline)
    if (inline) {
      unlockBodyScroll(this)
    } else {
      lockBodyScroll(this)
    }
  }

  unlockPage() {
    document.body.classList.remove("lesson-sidebar-inline-active")
    unlockBodyScroll(this)
  }

  get inlineAvailable() {
    return window.matchMedia("(min-width: 1024px)").matches
  }
}
