import { Controller } from "@hotwired/stimulus"
import { lockBodyScroll, unlockBodyScroll } from "controllers/scroll_lock"

const storageKey = "lesson-progress-sidebar-open"

export default class extends Controller {
  static targets = ["overlay", "backdrop", "panel", "openButton", "closeButton", "scrollArea"]

  connect() {
    this.onKeydown = this.handleKeydown.bind(this)
    this.onBeforeCache = this.finishAnimation.bind(this)
    this.onBeforeRender = this.prepareNavigation.bind(this)
    this.onResize = this.applyPresentation.bind(this)
    document.addEventListener("turbo:before-cache", this.onBeforeCache)
    document.addEventListener("turbo:before-render", this.onBeforeRender)
    window.addEventListener("resize", this.onResize)
    let open = this.overlayTarget.getAttribute("aria-hidden") === "false"
    try {
      const saved = sessionStorage.getItem(storageKey)
      if (saved !== null) open = saved === "true"
    } catch {
      // The live drawer still retains its state when storage is unavailable.
    }
    if (open) this.open({ restore: true })
    else this.closeImmediately()

    if (this.overlayTarget.dataset.scrollTop !== undefined) {
      this.scrollAreaTarget.scrollTop = Number(this.overlayTarget.dataset.scrollTop)
      delete this.overlayTarget.dataset.scrollTop
    }
  }

  toggle() {
    if (this.overlayTarget.getAttribute("aria-hidden") === "true") {
      this.open()
    } else {
      this.close()
    }
  }

  open({ restore = false } = {}) {
    if (!this.hasOverlayTarget || !this.hasPanelTarget) return

    this.clearCloseTimer()
    this.previousActiveElement = document.activeElement
    this.overlayTarget.classList.remove("invisible", "pointer-events-none")
    this.overlayTarget.setAttribute("aria-hidden", "false")
    this.openButtonTarget.setAttribute("aria-expanded", "true")
    this.rememberState(true)
    this.applyPresentation()
    document.addEventListener("keydown", this.onKeydown)

    if (restore) {
      this.finishAnimation()
      if (!this.inlineAvailable && !this.panelTarget.contains(document.activeElement)) {
        this.closeButtonTarget.focus({ preventScroll: true })
      }
      return
    }

    this.openFrame = requestAnimationFrame(() => {
      this.openFrame = null
      this.backdropTarget.classList.remove("opacity-0")
      this.backdropTarget.classList.add("opacity-100")
      this.panelTarget.classList.remove("-translate-x-full")
      this.panelTarget.classList.add("translate-x-0")
      if (!restore || !this.inlineAvailable) this.closeButtonTarget.focus()
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
    this.rememberState(false)
    this.unlockPage()
    document.removeEventListener("keydown", this.onKeydown)

    this.closeTimer = window.setTimeout(() => {
      this.overlayTarget.classList.add("invisible", "pointer-events-none")
      this.closeTimer = null
    }, 300)

    const returnTarget = this.previousActiveElement?.isConnected ? this.previousActiveElement : this.openButtonTarget
    returnTarget.focus({ preventScroll: true })
  }

  disconnect() {
    this.clearCloseTimer()
    this.clearOpenFrame()
    document.removeEventListener("keydown", this.onKeydown)
    document.removeEventListener("turbo:before-cache", this.onBeforeCache)
    document.removeEventListener("turbo:before-render", this.onBeforeRender)
    window.removeEventListener("resize", this.onResize)
    this.unlockPage()
  }

  prepareNavigation(event) {
    const incoming = event.detail.newBody.querySelector(`#${this.overlayTarget.id}[data-turbo-permanent]`)
    if (!incoming) return

    // Turbo transfers the existing shell. Refresh server-rendered details inside it.
    this.finishAnimation()
    const scrollTop = this.scrollAreaTarget.scrollTop
    const incomingPanel = incoming.querySelector('[data-lesson-sidebar-target="panel"]')
    this.panelTarget.replaceChildren(...incomingPanel.childNodes)
    this.overlayTarget.dataset.scrollTop = String(scrollTop)
    this.scrollAreaTarget.scrollTop = scrollTop

    const open = this.overlayTarget.getAttribute("aria-hidden") === "false"
    event.detail.newBody.classList.toggle("lesson-sidebar-inline-active", open && this.inlineAvailable)
    event.detail.newBody.classList.toggle("overflow-hidden", open && !this.inlineAvailable)
    event.detail.newBody.querySelector('[data-lesson-sidebar-target="openButton"]')
      ?.setAttribute("aria-expanded", String(open))
  }

  finishAnimation() {
    this.clearCloseTimer()
    this.clearOpenFrame()
    const open = this.overlayTarget.getAttribute("aria-hidden") === "false"
    this.overlayTarget.classList.toggle("invisible", !open)
    this.overlayTarget.classList.toggle("pointer-events-none", !open)
    this.backdropTarget.classList.toggle("opacity-0", !open)
    this.backdropTarget.classList.toggle("opacity-100", open)
    this.panelTarget.classList.toggle("-translate-x-full", !open)
    this.panelTarget.classList.toggle("translate-x-0", open)
  }

  rememberState(open) {
    try {
      sessionStorage.setItem(storageKey, String(open))
    } catch {
      // Storage may be disabled; opening and closing must still work.
    }
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
    // Reset a closed drawer restored from a Turbo cache snapshot.
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
    this.element.classList.toggle("lesson-sidebar-inline-active", inline)
    if (inline) {
      unlockBodyScroll(this)
    } else {
      lockBodyScroll(this)
    }
  }

  unlockPage() {
    // This controller belongs to a body. Turbo may have installed the next body
    // before disconnect runs, so cleanup must only alter our own layout.
    this.element.classList.remove("lesson-sidebar-inline-active")
    unlockBodyScroll(this)
  }

  get inlineAvailable() {
    return window.matchMedia("(min-width: 1024px)").matches
  }
}
