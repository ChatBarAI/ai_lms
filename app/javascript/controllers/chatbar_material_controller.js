import { Controller } from "@hotwired/stimulus"

const SCRIPT_SRC = "https://scripts.chatbar-ai.com/cb-ai-search.min.js"
const SESSION_EVENT = "cbai:session-activate"
let scriptPromise = null

function ensureCbaiScript() {
  if (window._bl_ai_search) return Promise.resolve()
  if (scriptPromise) return scriptPromise

  const existing = document.querySelector('script[data-cbai-loader="1"]')
  if (existing) {
    scriptPromise = new Promise((resolve, reject) => {
      existing.addEventListener("load", resolve, { once: true })
      existing.addEventListener("error", () => reject(new Error("CBAI script load failed")), { once: true })
    })
    return scriptPromise
  }

  scriptPromise = new Promise((resolve, reject) => {
    const script = document.createElement("script")
    script.src = SCRIPT_SRC
    script.async = true
    script.dataset.cbaiLoader = "1"
    script.addEventListener("load", resolve, { once: true })
    script.addEventListener("error", () => reject(new Error("CBAI script load failed")), { once: true })
    document.head.appendChild(script)
  })

  return scriptPromise
}

export default class extends Controller {
  static targets = ["intro", "startButton", "status", "mount"]
  static values = {
    token: String,
    prompt: String,
    context: String
  }

  connect() {
    this.activationId = 0
    this.onSessionActivate = (event) => {
      if (event.detail?.owner !== this.element && this.active) this.reset()
    }
    window.addEventListener(SESSION_EVENT, this.onSessionActivate)
    this.onMaterialLeave = () => {
      if (this.active) this.reset()
    }
    this.materialSection = this.element.closest("[data-controller~='collapsible']")
    this.materialSlide = this.element.closest("[data-material-scroller-target~='slide']")
    this.materialSection?.addEventListener("collapsible:collapsed", this.onMaterialLeave)
    this.materialSlide?.addEventListener("material-scroller:leave", this.onMaterialLeave)
  }

  disconnect() {
    window.removeEventListener(SESSION_EVENT, this.onSessionActivate)
    this.materialSection?.removeEventListener("collapsible:collapsed", this.onMaterialLeave)
    this.materialSlide?.removeEventListener("material-scroller:leave", this.onMaterialLeave)
    this.stopViewportTracking()
    this.activationId += 1
    this.cleanupMedia()
  }

  async start() {
    if (this.started || this.startButtonTarget.disabled) return

    const activationId = ++this.activationId
    this.startButtonTarget.disabled = true
    this.setStatus("Loading ChatBar…")
    window.dispatchEvent(new CustomEvent(SESSION_EVENT, { detail: { owner: this.element } }))

    try {
      await ensureCbaiScript()
      if (activationId !== this.activationId) return
      if (!window._bl_ai_search || typeof window._bl_ai_search.init !== "function") {
        throw new Error("ChatBar is unavailable")
      }

      this.introTarget.classList.add("hidden")
      this.mountTarget.classList.remove("hidden")
      this.mountTarget.dataset.initialised = "1"
      this.startViewportTracking()

      await window._bl_ai_search.init(this.tokenValue, this.mountTarget, {
        additional_context: this.contextValue,
        eail: this.promptValue
      })
      if (activationId !== this.activationId) {
        if (this.activationId === activationId + 1) this.reset()
        return
      }
      this.setStatus("")
    } catch (_error) {
      if (activationId === this.activationId) {
        this.reset()
        this.setStatus("ChatBar could not be loaded. Please try again.")
      }
    }
  }

  reset() {
    this.activationId += 1
    this.stopViewportTracking()
    this.cleanupMedia()
    this.mountTarget.replaceChildren()
    delete this.mountTarget.dataset.initialised
    this.mountTarget.classList.add("hidden")
    this.introTarget.classList.remove("hidden")
    this.startButtonTarget.disabled = false
    this.setStatus("")
  }

  startViewportTracking() {
    this.stopViewportTracking()
    this.viewportTracking = true
    this.onViewportInteraction = () => this.stopViewportTracking()
    this.onViewportKeydown = (event) => {
      if (["ArrowUp", "ArrowDown", "PageUp", "PageDown", "Home", "End", " ", "Tab"].includes(event.key)) {
        this.stopViewportTracking()
      }
    }
    for (const event of ["wheel", "touchstart", "pointerdown"]) {
      window.addEventListener(event, this.onViewportInteraction, { passive: true, capture: true })
    }
    window.addEventListener("keydown", this.onViewportKeydown, true)

    // Run after the carousel's ResizeObserver has updated its track height.
    // Each frame is requested by a size change; there is no polling loop.
    const scheduleAdjustment = () => {
      window.cancelAnimationFrame(this.viewportFrame)
      this.viewportFrame = window.requestAnimationFrame(() => this.keepMountInView())
    }
    this.viewportObserver = new ResizeObserver(scheduleAdjustment)
    this.viewportObserver.observe(this.mountTarget)
    scheduleAdjustment()
  }

  keepMountInView() {
    if (!this.viewportTracking || !this.started) return

    const rect = this.mountTarget.getBoundingClientRect()
    if (rect.height === 0 || rect.right <= 0 || rect.left >= window.innerWidth) return

    const margin = 16
    const availableHeight = window.innerHeight - margin * 2
    let delta = 0
    if (rect.height > availableHeight || rect.top < margin) {
      delta = rect.top - margin
    } else if (rect.bottom > window.innerHeight - margin) {
      delta = rect.bottom - (window.innerHeight - margin)
    }
    if (Math.abs(delta) > 1) {
      // Only scroll the page, leaving the horizontal material carousel alone.
      window.scrollBy({ top: delta, behavior: "instant" })
    }
  }

  stopViewportTracking() {
    this.viewportTracking = false
    this.viewportObserver?.disconnect()
    window.cancelAnimationFrame(this.viewportFrame)
    if (this.onViewportInteraction) {
      for (const event of ["wheel", "touchstart", "pointerdown"]) {
        window.removeEventListener(event, this.onViewportInteraction, true)
      }
    }
    if (this.onViewportKeydown) window.removeEventListener("keydown", this.onViewportKeydown, true)
  }

  cleanupMedia() {
    if (!this.hasMountTarget) return

    this.mountTarget.querySelectorAll("audio, video").forEach((element) => {
      try { element.pause() } catch (_error) {}
      const stream = element.srcObject
      if (stream && typeof stream.getTracks === "function") {
        stream.getTracks().forEach((track) => track.stop())
      }
      try { element.srcObject = null } catch (_error) {}
    })
  }

  setStatus(message) {
    this.statusTarget.textContent = message
    this.statusTarget.classList.toggle("hidden", !message)
  }

  get started() {
    return this.mountTarget.dataset.initialised === "1"
  }

  get active() {
    return this.started || (this.hasStartButtonTarget && this.startButtonTarget.disabled)
  }
}
