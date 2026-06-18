import { Controller } from "@hotwired/stimulus"

let anamSdkPromise = null

function loadAnamSdk() {
  if (anamSdkPromise) return anamSdkPromise
  anamSdkPromise = import("https://esm.sh/@anam-ai/js-sdk@latest")
  return anamSdkPromise
}

export default class extends Controller {
  static targets = ["overlay", "panel", "openButton", "micStatus", "video", "status"]
  static values = {
    displayMode: String,
    sessionToken: String
  }

  connect() {
    this.anamClient = null
    this.streaming = false
    this.sdk = null

    this.applyStyle()

    this.onEscape = (event) => {
      if (event.key === "Escape" && !this.overlayTarget.classList.contains("hidden")) {
        this.close()
      }
    }

    this.onBeforeVisit = () => this.close()
    this.onPageHide = () => this.stopStreaming()

    document.addEventListener("keydown", this.onEscape)
    document.addEventListener("turbo:before-visit", this.onBeforeVisit)
    window.addEventListener("pagehide", this.onPageHide)

    this.element._anamDestroy = () => this.close()
  }

  disconnect() {
    document.removeEventListener("keydown", this.onEscape)
    document.removeEventListener("turbo:before-visit", this.onBeforeVisit)
    window.removeEventListener("pagehide", this.onPageHide)
    delete this.element._anamDestroy

    this.stopStreaming()
    this.unlockBody()
  }

  async openWithMicGate() {
    if (!this.hasOpenButtonTarget || this.openButtonTarget.disabled) return

    this.openButtonTarget.disabled = true
    this.setMicStatus("")

    try {
      const ok = await this.ensureMicAccess()
      if (!ok) {
        const state = await this.micPermissionState()
        if (state === "denied") {
          this.setMicStatus("Microphone permission is blocked. Allow microphone access in your browser site settings, then try again.")
        } else {
          this.setMicStatus("Could not access the microphone. Please try again.")
        }
        return
      }

      await this.open()
    } finally {
      this.openButtonTarget.disabled = false
    }
  }

  async open() {
    if (!this.hasOverlayTarget) return

    this.overlayTarget.classList.remove("hidden")
    document.body.classList.add("overflow-hidden")
    await this.startStreaming()
  }

  async close() {
    if (this.hasOverlayTarget) {
      this.overlayTarget.classList.add("hidden")
    }

    this.unlockBody()
    await this.stopStreaming()
  }

  applyStyle() {
    if (!this.hasPanelTarget) return

    const popup = ["top-1/2", "left-1/2", "-translate-x-1/2", "-translate-y-1/2", "w-[min(92vw,760px)]", "h-[min(88vh,860px)]", "rounded-lg"]
    const drawer = ["top-0", "right-0", "h-full", "w-[min(92vw,540px)]", "rounded-none"]
    const style = this.displayModeValue === "drawer" ? drawer : popup

    popup.concat(drawer).forEach((klass) => this.panelTarget.classList.remove(klass))
    style.forEach((klass) => this.panelTarget.classList.add(klass))
  }

  async startStreaming() {
    if (this.streaming) return

    const token = (this.sessionTokenValue || "").trim()
    if (!token) {
      this.setStatus("Avatar configuration is missing.")
      return
    }

    try {
      this.setStatus("Connecting avatar...")
      this.sdk = this.sdk || await loadAnamSdk()

      const { createClient, AnamEvent } = this.sdk
      this.anamClient = createClient(token)
      this.anamClient.addListener(AnamEvent.CONNECTION_ESTABLISHED, () => this.setStatus("Connected. Start speaking."))
      this.anamClient.addListener(AnamEvent.CONNECTION_CLOSED, () => this.setStatus("Connection closed."))

      const videoEl = this.hasVideoTarget ? this.videoTarget : null
      if (!videoEl || !videoEl.id) {
        this.setStatus("Avatar video is not available.")
        return
      }

      await this.anamClient.streamToVideoElement(videoEl.id)
      this.streaming = true
    } catch (error) {
      this.streaming = false
      this.setStatus("Could not start avatar. Please try again.")
      if (window.console) console.warn("[ai-lms] Anam stream failed", error)
    }
  }

  async stopStreaming() {
    if (!this.anamClient) {
      this.streaming = false
      return
    }

    try {
      await this.anamClient.stopStreaming()
    } catch (_error) {
      // Ignore shutdown errors while navigating away.
    } finally {
      this.anamClient = null
      this.streaming = false
      this.setStatus("")
    }
  }

  unlockBody() {
    document.body.classList.remove("overflow-hidden")
  }

  setStatus(text) {
    if (!this.hasStatusTarget) return
    this.statusTarget.textContent = text || ""
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
    if (!navigator.mediaDevices || typeof navigator.mediaDevices.getUserMedia !== "function") return true

    try {
      const stream = await navigator.mediaDevices.getUserMedia({ audio: true })
      if (stream && typeof stream.getTracks === "function") {
        stream.getTracks().forEach((track) => track.stop())
      }
      return true
    } catch (_error) {
      return false
    }
  }

  async ensureMicAccess() {
    const state = await this.micPermissionState()
    if (state === "granted") return true

    const grantedByRequest = await this.requestMicAccess()
    if (!grantedByRequest) return false

    const nextState = await this.micPermissionState()
    if (nextState === null) return true
    return nextState === "granted"
  }
}