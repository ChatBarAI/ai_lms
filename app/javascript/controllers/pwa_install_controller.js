import { Controller } from "@hotwired/stimulus"

const DISMISS_COOKIE_NAME = "pwa_install_dismissed"
const DISMISS_COOKIE_MAX_AGE_SECONDS = 60 * 60 * 24 * 30

export default class extends Controller {
  static targets = ["container", "title", "primaryButton", "details"]

  connect() {
    this.deferredPrompt = null
    this.iosGuidanceVisible = false
    this.handleBeforeInstallPrompt = this.handleBeforeInstallPrompt.bind(this)
    this.handleAppInstalled = this.handleAppInstalled.bind(this)

    window.addEventListener("beforeinstallprompt", this.handleBeforeInstallPrompt)
    window.addEventListener("appinstalled", this.handleAppInstalled)

    if (this.isStandalone()) {
      this.hide()
      return
    }

    if (this.isDismissed()) {
      this.hide()
      return
    }

    if (this.isIosFamily()) {
      this.configureForIosGuidance()
      this.show()
    }
  }

  disconnect() {
    window.removeEventListener("beforeinstallprompt", this.handleBeforeInstallPrompt)
    window.removeEventListener("appinstalled", this.handleAppInstalled)
  }

  async install() {
    if (this.deferredPrompt) {
      this.deferredPrompt.prompt()
      await this.deferredPrompt.userChoice
      this.deferredPrompt = null
      this.hide()
      return
    }

    if (this.isIosFamily()) {
      this.toggleIosGuidance()
    }
  }

  dismiss() {
    this.setDismissedCookie()
    this.hide()
  }

  handleBeforeInstallPrompt(event) {
    event.preventDefault()
    this.deferredPrompt = event

    if (this.isDismissed()) {
      return
    }

    this.configureForInstallPrompt()
    this.show()
  }

  handleAppInstalled() {
    this.deferredPrompt = null
    this.hide()
  }

  isStandalone() {
    return window.matchMedia("(display-mode: standalone)").matches || window.navigator.standalone
  }

  isIosFamily() {
    const ua = window.navigator.userAgent || ""
    const isIosDevice = /iPhone|iPad|iPod/i.test(ua)
    const isIpadOsDesktopMode = window.navigator.platform === "MacIntel" && window.navigator.maxTouchPoints > 1
    return isIosDevice || isIpadOsDesktopMode
  }

  isSafariBrowser() {
    const ua = window.navigator.userAgent || ""
    const hasSafariToken = /Safari/i.test(ua)
    const excluded = /CriOS|FxiOS|EdgiOS|OPiOS|YaBrowser|DuckDuckGo|GSA|Instagram|FBAN|FBAV/i.test(ua)
    return hasSafariToken && !excluded
  }

  isChromeOnIos() {
    const ua = window.navigator.userAgent || ""
    return /CriOS/i.test(ua)
  }

  configureForInstallPrompt() {
    if (this.hasTitleTarget) {
      this.titleTarget.textContent = "Install this app for faster access"
    }
    if (this.hasPrimaryButtonTarget) {
      this.primaryButtonTarget.textContent = "Install"
    }
    if (this.hasDetailsTarget) {
      this.detailsTarget.classList.add("hidden")
    }
    this.iosGuidanceVisible = false
  }

  configureForIosGuidance() {
    if (this.hasTitleTarget) {
      this.titleTarget.textContent = "Install on iPad or iPhone"
    }
    if (this.hasPrimaryButtonTarget) {
      this.primaryButtonTarget.textContent = "Show steps"
    }
    if (this.hasDetailsTarget) {
      const detailsText = this.isSafariBrowser()
        ? "Tap Share (square with up arrow), then tap Add to Home Screen."
        : this.isChromeOnIos()
          ? "Tap Share, then tap Add to Home Screen."
          : "Tap your browser menu and choose Add to Home Screen. If unavailable, open in Safari and use Share > Add to Home Screen."
      this.detailsTarget.textContent = detailsText
      this.detailsTarget.classList.add("hidden")
    }
    this.iosGuidanceVisible = false
  }

  toggleIosGuidance() {
    if (!this.hasDetailsTarget) {
      return
    }

    this.iosGuidanceVisible = !this.iosGuidanceVisible
    this.detailsTarget.classList.toggle("hidden", !this.iosGuidanceVisible)
    if (this.hasPrimaryButtonTarget) {
      this.primaryButtonTarget.textContent = this.iosGuidanceVisible ? "Hide steps" : "Show steps"
    }
  }

  show() {
    if (!this.hasContainerTarget || this.isStandalone() || this.isDismissed()) {
      return
    }

    this.containerTarget.classList.remove("hidden")
  }

  hide() {
    if (!this.hasContainerTarget) {
      return
    }

    this.containerTarget.classList.add("hidden")
    if (this.hasDetailsTarget) {
      this.detailsTarget.classList.add("hidden")
    }
    this.iosGuidanceVisible = false
  }

  isDismissed() {
    const cookie = document.cookie || ""
    return cookie
      .split(";")
      .map((entry) => entry.trim())
      .some((entry) => entry === `${DISMISS_COOKIE_NAME}=1`)
  }

  setDismissedCookie() {
    const secureAttribute = window.location.protocol === "https:" ? "; Secure" : ""
    document.cookie = `${DISMISS_COOKIE_NAME}=1; max-age=${DISMISS_COOKIE_MAX_AGE_SECONDS}; path=/; SameSite=Lax${secureAttribute}`
  }
}
