import { Controller } from "@hotwired/stimulus"
import { lockBodyScroll, unlockBodyScroll } from "controllers/scroll_lock"

// Admin navigation. From 1024px the sidebar is a fixed column shown by CSS alone, so this
// controller only runs the modal drawer used on narrower screens. It follows the lesson
// Progress drawer (lesson_sidebar_controller.js) but has no saved state: every admin page
// load starts with the drawer closed.
export default class extends Controller {
  static targets = ["overlay", "backdrop", "panel", "openButton", "closeButton"]

  connect() {
    this.isOpen = false
    this.desktop = window.matchMedia("(min-width: 1024px)")
    this.onKeydown = this.handleKeydown.bind(this)
    this.onBeforeCache = this.closeImmediately.bind(this)
    this.onBreakpoint = this.handleBreakpoint.bind(this)
    document.addEventListener("turbo:before-cache", this.onBeforeCache)
    this.desktop.addEventListener("change", this.onBreakpoint)
  }

  disconnect() {
    this.clearTimers()
    document.removeEventListener("turbo:before-cache", this.onBeforeCache)
    document.removeEventListener("keydown", this.onKeydown)
    this.desktop.removeEventListener("change", this.onBreakpoint)
    unlockBodyScroll(this)
  }

  toggle() {
    if (this.isOpen) {
      this.close()
    } else {
      this.open()
    }
  }

  open() {
    if (this.isOpen || this.desktop.matches) return

    this.clearTimers()
    this.previousActiveElement = document.activeElement
    this.overlayTarget.classList.remove("invisible", "pointer-events-none")
    this.setOpenState(true)

    this.openFrame = requestAnimationFrame(() => {
      this.openFrame = null
      this.showPanel(true)
      this.closeButtonTarget.focus()
    })
  }

  close() {
    if (!this.isOpen) return

    this.clearTimers()
    this.showPanel(false)
    this.setOpenState(false)
    this.closeTimer = window.setTimeout(() => {
      this.closeTimer = null
      this.overlayTarget.classList.add("invisible", "pointer-events-none")
    }, 300)

    const returnTarget = this.previousActiveElement?.isConnected ? this.previousActiveElement : this.openButtonTarget
    returnTarget.focus({ preventScroll: true })
  }

  // No animation: used before Turbo caches the page and when the screen widens to desktop.
  closeImmediately() {
    this.clearTimers()
    this.showPanel(false)
    this.overlayTarget.classList.add("invisible", "pointer-events-none")
    if (this.isOpen) this.setOpenState(false)
  }

  handleBreakpoint() {
    if (this.desktop.matches) this.closeImmediately()
  }

  setOpenState(open) {
    this.isOpen = open
    this.openButtonTarget.setAttribute("aria-expanded", String(open))
    if (open) {
      this.overlayTarget.setAttribute("role", "dialog")
      this.overlayTarget.setAttribute("aria-modal", "true")
      lockBodyScroll(this)
      document.addEventListener("keydown", this.onKeydown)
    } else {
      this.overlayTarget.removeAttribute("role")
      this.overlayTarget.removeAttribute("aria-modal")
      unlockBodyScroll(this)
      document.removeEventListener("keydown", this.onKeydown)
    }
  }

  showPanel(visible) {
    this.backdropTarget.classList.toggle("opacity-0", !visible)
    this.backdropTarget.classList.toggle("opacity-100", visible)
    this.panelTarget.classList.toggle("-translate-x-full", !visible)
    this.panelTarget.classList.toggle("translate-x-0", visible)
  }

  handleKeydown(event) {
    if (event.key === "Escape") {
      event.preventDefault()
      this.close()
      return
    }

    if (event.key === "Tab") this.maintainFocus(event)
  }

  maintainFocus(event) {
    const focusable = Array.from(this.panelTarget.querySelectorAll("a[href], button:not([disabled]), [tabindex]:not([tabindex='-1'])"))
    if (focusable.length === 0) return

    const first = focusable[0]
    const last = focusable[focusable.length - 1]
    if (event.shiftKey && document.activeElement === first) {
      event.preventDefault()
      last.focus()
    } else if (!event.shiftKey && document.activeElement === last) {
      event.preventDefault()
      first.focus()
    }
  }

  clearTimers() {
    if (this.openFrame) {
      cancelAnimationFrame(this.openFrame)
      this.openFrame = null
    }
    if (this.closeTimer) {
      window.clearTimeout(this.closeTimer)
      this.closeTimer = null
    }
  }
}
