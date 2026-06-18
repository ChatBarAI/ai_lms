import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["overlay", "panel", "openButton", "frame", "mount", "scriptSource"]
  static values = {
    displayMode: String,
    embedUrl: String,
    embedType: String
  }

  connect() {
    this.scriptNodes = []

    this.applyStyle()

    this.onEscape = (event) => {
      if (event.key === "Escape" && this.hasOverlayTarget && !this.overlayTarget.classList.contains("hidden")) {
        this.close()
      }
    }

    this.onBeforeVisit = () => this.close()
    this.onPageHide = () => this.close()

    document.addEventListener("keydown", this.onEscape)
    document.addEventListener("turbo:before-visit", this.onBeforeVisit)
    window.addEventListener("pagehide", this.onPageHide)
  }

  disconnect() {
    document.removeEventListener("keydown", this.onEscape)
    document.removeEventListener("turbo:before-visit", this.onBeforeVisit)
    window.removeEventListener("pagehide", this.onPageHide)
    this.unlockBody()
    if (this.embedTypeValue === "script") {
      this.unmountScriptEmbed()
    } else {
      this.unloadFrame()
    }
  }

  open() {
    if (!this.hasOverlayTarget) return

    this.overlayTarget.classList.remove("hidden")
    document.body.classList.add("overflow-hidden")

    if (this.embedTypeValue === "script") {
      this.mountScriptEmbed()
    } else {
      this.loadFrame()
    }
  }

  close() {
    if (!this.hasOverlayTarget) return

    this.overlayTarget.classList.add("hidden")
    this.unlockBody()

    if (this.embedTypeValue === "script") {
      this.unmountScriptEmbed()
    } else {
      this.unloadFrame()
    }
  }

  loadFrame() {
    if (!this.hasFrameTarget || this.frameTarget.src) return

    const url = this.embedUrlValue
    if (url) this.frameTarget.src = url
  }

  unloadFrame() {
    if (this.hasFrameTarget) this.frameTarget.src = ""
  }

  async mountScriptEmbed() {
    if (!this.hasMountTarget) return
    if (this.mountTarget.dataset.initialised === "1") return

    const content = this.inlineScriptContent
    if (!content) return

    const template = document.createElement("template")
    template.innerHTML = content

    const scripts = Array.from(template.content.querySelectorAll("script"))
    scripts.forEach((scriptNode) => scriptNode.remove())

    this.mountTarget.innerHTML = ""
    this.ensureDefaultMountTargets()
    this.mountTarget.appendChild(template.content.cloneNode(true))
    this.normalizeEmbeddedFrames()

    if (scripts.length === 0 && !content.includes("<")) {
      const script = document.createElement("script")
      script.text = content
      this.mountTarget.appendChild(script)
      this.scriptNodes.push(script)
      this.mountTarget.dataset.initialised = "1"
      return
    }

    for (let index = 0; index < scripts.length; index += 1) {
      await this.executeScriptNode(scripts[index], index)
    }

    this.mountTarget.dataset.initialised = "1"
  }

  unmountScriptEmbed() {
    this.scriptNodes.forEach((node) => {
      try {
        node.remove()
      } catch (_error) {
      }
    })
    this.scriptNodes = []

    if (this.hasMountTarget) {
      this.mountTarget.innerHTML = ""
      delete this.mountTarget.dataset.initialised
    }
  }

  async executeScriptNode(node, index) {
    const script = document.createElement("script")
    Array.from(node.attributes).forEach((attr) => {
      script.setAttribute(attr.name, attr.value)
    })
    script.dataset.customTutorKey = `${this.embedKey}-${index}`

    if (script.src) {
      await this.appendExternalScript(script)
      this.scriptNodes.push(script)
      return
    }

    if (node.textContent) {
      script.text = node.textContent
    }

    this.appendInlineScriptWithDomReadyCompat(script)
    this.scriptNodes.push(script)
  }

  appendExternalScript(scriptNode) {
    return new Promise((resolve) => {
      scriptNode.async = false
      scriptNode.addEventListener("load", () => resolve(), { once: true })
      scriptNode.addEventListener("error", () => resolve(), { once: true })
      this.mountTarget.appendChild(scriptNode)
    })
  }

  appendInlineScriptWithDomReadyCompat(scriptNode) {
    const queuedDomReadyHandlers = []
    const originalAddEventListener = document.addEventListener.bind(document)
    document.addEventListener = (type, listener, options) => {
      if (type === "DOMContentLoaded" && typeof listener === "function") {
        queuedDomReadyHandlers.push(listener)
        return
      }

      return originalAddEventListener(type, listener, options)
    }

    try {
      this.mountTarget.appendChild(scriptNode)
    } finally {
      document.addEventListener = originalAddEventListener
    }

    queuedDomReadyHandlers.forEach((listener) => {
      try {
        listener.call(document, new Event("DOMContentLoaded"))
      } catch (_error) {
      }
    })
  }

  ensureDefaultMountTargets() {
    const aliases = ["auto_ai_search_bot", "ai_search_bot", "custom_ai_tutor_mount"]

    aliases.forEach((id) => {
      const node = document.createElement("div")
      node.id = id
      node.className = "w-full"
      this.mountTarget.appendChild(node)
    })
  }

  get inlineScriptContent() {
    if (!this.hasScriptSourceTarget) return ""
    return (this.scriptSourceTarget.value || "").trim()
  }

  normalizeEmbeddedFrames() {
    if (!this.hasMountTarget) return

    const frames = this.mountTarget.querySelectorAll("iframe")
    frames.forEach((frame) => {
      if (!frame.getAttribute("width")) frame.setAttribute("width", "100%")
      if (!frame.getAttribute("height")) frame.setAttribute("height", "420")
      frame.classList.add("w-full")
      if (!frame.style.border) frame.style.border = "0"
    })
  }

  get embedKey() {
    return this.element.id || "custom-tutor"
  }

  applyStyle() {
    if (!this.hasPanelTarget) return

    const popup = ["top-1/2", "left-1/2", "-translate-x-1/2", "-translate-y-1/2", "w-[min(92vw,640px)]", "h-[min(85vh,720px)]", "rounded-lg"]
    const drawer = ["top-0", "right-0", "h-full", "w-[min(92vw,480px)]", "rounded-none"]
    const style = this.displayModeValue === "drawer" ? drawer : popup

    popup.concat(drawer).forEach((klass) => this.panelTarget.classList.remove(klass))
    style.forEach((klass) => this.panelTarget.classList.add(klass))
  }

  unlockBody() {
    document.body.classList.remove("overflow-hidden")
  }
}
