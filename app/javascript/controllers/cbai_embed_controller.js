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
      existing.addEventListener("load", () => resolve(), { once: true })
      existing.addEventListener("error", () => reject(new Error("CBAI script load failed")), { once: true })
    })
    return scriptPromise
  }

  scriptPromise = new Promise((resolve, reject) => {
    const script = document.createElement("script")
    script.src = SCRIPT_SRC
    script.async = true
    script.dataset.cbaiLoader = "1"
    script.addEventListener("load", () => resolve(), { once: true })
    script.addEventListener("error", () => reject(new Error("CBAI script load failed")), { once: true })
    document.head.appendChild(script)
  })

  return scriptPromise
}

export default class extends Controller {
  static targets = ["overlay", "panel", "openButton", "micStatus", "mount"]
  static values = {
    displayMode: String
  }

  connect() {
    this.applyStyle()

    this.onEscape = (event) => {
      if (event.key === "Escape" && !this.overlayTarget.classList.contains("hidden")) {
        this.close()
      }
    }

    this.onPageHide = () => this.destroyTutor()
    this.onBeforeVisit = () => this.destroyTutor()
    this.onResize = () => {
      if (!this.overlayTarget.classList.contains("hidden")) this.applyPresentation()
    }
    this.onSessionActivate = (event) => {
      const open = this.hasOverlayTarget && !this.overlayTarget.classList.contains("hidden")
      if (event.detail?.owner !== this.element && (open || this.isMounted())) this.close()
    }

    document.addEventListener("keydown", this.onEscape)
    document.addEventListener("turbo:before-visit", this.onBeforeVisit)
    window.addEventListener("pagehide", this.onPageHide)
    window.addEventListener("resize", this.onResize)
    window.addEventListener(SESSION_EVENT, this.onSessionActivate)

    this.element._cbaiOpenWithEail = (eailText) => {
      if (this.isMounted()) this.destroyTutor()
      if (this.hasMountTarget) this.mountTarget.dataset.cbaiEail = eailText || ""
      this.openWithMicGate()
    }
  }

  disconnect() {
    document.removeEventListener("keydown", this.onEscape)
    document.removeEventListener("turbo:before-visit", this.onBeforeVisit)
    window.removeEventListener("pagehide", this.onPageHide)
    window.removeEventListener("resize", this.onResize)
    window.removeEventListener(SESSION_EVENT, this.onSessionActivate)
    this.unlockBody()
    this.destroyTutor()
    delete this.element._cbaiOpenWithEail
  }

  async openWithMicGate() {
    if (!this.hasOpenButtonTarget || this.openButtonTarget.disabled) return

    this.openButtonTarget.disabled = true
    this.setMicStatus("")

    try {
      const result = await this.ensureMicAccess()
      if (!result.ok) {
        if (result.reason === "blocked") {
          this.setMicStatus("Microphone permission is blocked. Allow microphone access in your browser site settings, then try again.")
        } else if (result.reason === "not_found") {
          this.setMicStatus("No microphone was found on this device.")
        } else {
          this.setMicStatus("Could not access the microphone. Please try again.")
        }
        return
      }

      this.open()
    } finally {
      this.openButtonTarget.disabled = false
    }
  }

  open() {
    if (!this.hasOverlayTarget) return

    window.dispatchEvent(new CustomEvent(SESSION_EVENT, { detail: { owner: this.element } }))
    this.overlayTarget.classList.remove("hidden")
    this.applyPresentation()
    this.mountTutor()
  }

  close() {
    if (!this.hasOverlayTarget) return

    this.overlayTarget.classList.add("hidden")
    this.unlockBody()
    this.destroyTutor()
  }

  async mountTutor() {
    if (!this.hasMountTarget || this.isMounted()) return

    const token = this.mountTarget.dataset.cbaiToken
    if (!token) return

    try {
      await ensureCbaiScript()
    } catch (_error) {
      if (window.console) console.warn("[ai-lms] failed to load CBAI script from " + SCRIPT_SRC)
      return
    }

    if (!window._bl_ai_search || typeof window._bl_ai_search.init !== "function") return

    this.mountTarget.dataset.initialised = "1"
    const opts = {
      additional_context: this.mountTarget.dataset.cbaiContext || "",
      callback: (response) => {
        if (window.console) console.debug("[ai-lms] AI response complete", response)
      }
    }

    const eail = this.mountTarget.dataset.cbaiEail
    if (eail) {
      opts.eail = eail
      delete this.mountTarget.dataset.cbaiEail
    }

    window._bl_ai_search.init(token, this.mountTarget, opts)
  }

  destroyTutor() {
    if (!this.hasMountTarget) return

    const media = this.mountTarget.querySelectorAll("audio, video")
    media.forEach((el) => {
      try { el.pause() } catch (_error) {}

      const stream = el.srcObject
      if (stream && typeof stream.getTracks === "function") {
        stream.getTracks().forEach((track) => {
          try { track.stop() } catch (_error) {}
        })
      }

      try { el.srcObject = null } catch (_error) {}
      try {
        el.removeAttribute("src")
        el.load()
      } catch (_error) {}
    })

    const fresh = this.mountTarget.cloneNode(false)
    delete fresh.dataset.initialised
    this.mountTarget.parentNode.replaceChild(fresh, this.mountTarget)
  }

  applyStyle() {
    if (!this.hasPanelTarget) return

    const popup = ["top-1/2", "left-1/2", "-translate-x-1/2", "-translate-y-1/2", "w-[min(92vw,640px)]", "h-[min(85vh,720px)]", "rounded-lg"]
    const drawer = ["top-0", "right-0", "h-full", "w-[min(92vw,480px)]", "rounded-none"]
    const inline = ["ai-tutor-inline-panel", "rounded-none"]
    let style = popup
    if (this.displayModeValue === "drawer" || (this.displayModeValue === "inline" && !this.inlineAvailable)) style = drawer
    if (this.displayModeValue === "inline" && this.inlineAvailable) style = inline

    popup.concat(drawer, inline).forEach((klass) => this.panelTarget.classList.remove(klass))
    style.forEach((klass) => this.panelTarget.classList.add(klass))
  }

  applyPresentation() {
    this.applyStyle()
    const inline = this.displayModeValue === "inline" && this.inlineAvailable
    this.overlayTarget.classList.toggle("ai-tutor-inline-overlay", inline)
    this.overlayTarget.setAttribute("aria-modal", inline ? "false" : "true")
    document.body.classList.toggle("ai-tutor-inline-active", inline)
    document.body.classList.toggle("overflow-hidden", !inline)
  }

  get inlineAvailable() {
    return window.matchMedia("(min-width: 960px)").matches
  }

  unlockBody() {
    document.body.classList.remove("overflow-hidden")
    document.body.classList.remove("ai-tutor-inline-active")
    if (this.hasOverlayTarget) this.overlayTarget.classList.remove("ai-tutor-inline-overlay")
  }

  isMounted() {
    return this.hasMountTarget && this.mountTarget.dataset.initialised === "1"
  }

  setMicStatus(text) {
    if (!this.hasMicStatusTarget) return

    this.micStatusTarget.textContent = text || ""
    this.micStatusTarget.classList.toggle("hidden", !text)
  }

  async micPermissionState() {
    if (!navigator.permissions || typeof navigator.permissions.query !== "function") return null

    try {
      const permission = await navigator.permissions.query({ name: "microphone" })
      return permission ? permission.state : null
    } catch (_error) {
      return null
    }
  }

  async requestMicAccess() {
    if (!navigator.mediaDevices || typeof navigator.mediaDevices.getUserMedia !== "function") {
      return { ok: true, reason: "unsupported" }
    }

    try {
      const stream = await navigator.mediaDevices.getUserMedia({ audio: true })
      if (stream && typeof stream.getTracks === "function") {
        stream.getTracks().forEach((track) => track.stop())
      }
      return { ok: true, reason: null }
    } catch (error) {
      let reason = "unknown"
      if (error && (error.name === "NotAllowedError" || error.name === "SecurityError")) reason = "blocked"
      if (error && error.name === "NotFoundError") reason = "not_found"
      return { ok: false, reason }
    }
  }

  async ensureMicAccess() {
    const state = await this.micPermissionState()
    if (state === "granted") return { ok: true, reason: null }

    const result = await this.requestMicAccess()
    if (!result.ok) return result

    const nextState = await this.micPermissionState()
    if (nextState === null) return result

    return { ok: nextState === "granted", reason: nextState === "granted" ? null : "blocked" }
  }
}
