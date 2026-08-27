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
  }

  disconnect() {
    window.removeEventListener(SESSION_EVENT, this.onSessionActivate)
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
    this.cleanupMedia()
    this.mountTarget.replaceChildren()
    delete this.mountTarget.dataset.initialised
    this.mountTarget.classList.add("hidden")
    this.introTarget.classList.remove("hidden")
    this.startButtonTarget.disabled = false
    this.setStatus("")
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
