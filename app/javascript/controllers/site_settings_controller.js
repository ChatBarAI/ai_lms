import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["authOrgCta", "googleSignInToggle", "microsoftSignInToggle", "googleJitGroup", "microsoftJitGroup"]

  static values = {
    defaults: Object,
    activeSection: String
  }

  connect() {
    const initialSection = this.activeSectionValue || this.tabButtons[0]?.dataset.siteSettingsTabKey
    if (initialSection) this.setActiveSection(initialSection)
    this.refreshAuthOrgCta()
  }

  refreshAuthOrgCta() {
    if (!this.hasAuthOrgCtaTarget) return

    const googleEnabled = this.hasGoogleSignInToggleTarget && this.googleSignInToggleTarget.checked
    const microsoftEnabled = this.hasMicrosoftSignInToggleTarget && this.microsoftSignInToggleTarget.checked
    const shouldShow = googleEnabled || microsoftEnabled

    this.authOrgCtaTarget.classList.toggle("hidden", !shouldShow)

    if (this.hasGoogleJitGroupTarget) {
      this.googleJitGroupTarget.classList.toggle("hidden", !googleEnabled)
    }

    if (this.hasMicrosoftJitGroupTarget) {
      this.microsoftJitGroupTarget.classList.toggle("hidden", !microsoftEnabled)
    }
  }

  activateTab(event) {
    event.preventDefault()
    const sectionKey = event.currentTarget.dataset.siteSettingsTabKey
    if (!sectionKey) return

    this.setActiveSection(sectionKey)
  }

  sync(event) {
    const source = event.target
    const key = source.dataset.siteSettingsColorKey
    if (!key) return

    const value = source.value
    if (!/^#[0-9a-fA-F]{6}$/.test(value)) return

    this.element.querySelectorAll(`[data-site-settings-color-key="${key}"]`).forEach((input) => {
      if (input !== source) input.value = value
    })
  }

  reset(event) {
    const setName = event.currentTarget.dataset.siteSettingsResetSet
    const set = this.defaultsValue?.[setName]
    if (!set) return

    Object.entries(set).forEach(([field, value]) => {
      if (field === "theme_mode") {
        const radio = this.element.querySelector(
          `input[type="radio"][name="site_setting[theme_mode]"][value="${value}"]`
        )
        if (radio) radio.checked = true
        return
      }

      this.element
        .querySelectorAll(`[data-site-settings-color-key="${field}"]`)
        .forEach((input) => {
          input.value = value
        })
    })
  }

  get tabButtons() {
    return this.element.querySelectorAll("[data-site-settings-tab-key]")
  }

  get sections() {
    return this.element.querySelectorAll("[data-site-settings-section]")
  }

  setActiveSection(sectionKey) {
    this.sections.forEach((section) => {
      section.classList.toggle("hidden", section.dataset.siteSettingsSection !== sectionKey)
    })

    this.tabButtons.forEach((button) => {
      const active = button.dataset.siteSettingsTabKey === sectionKey
      button.classList.toggle("border-indigo-600", active)
      button.classList.toggle("bg-white", active)
      button.classList.toggle("text-indigo-700", active)
      button.classList.toggle("border-transparent", !active)
      button.classList.toggle("text-gray-600", !active)
    })
  }
}
