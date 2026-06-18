import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["providerSelect", "chatbarFields", "anamFields", "customFields", "customEmbedTypeSelect", "customUrlField", "customScriptField", "displayField"]

  connect() {
    this.update()
  }

  update() {
    const provider = this.selectedProvider
    const isCustom = provider === "custom"
    const embedType = this.selectedCustomEmbedType

    this.chatbarFieldsTargets.forEach((el) => this.toggle(el, provider === "chatbar"))
    this.anamFieldsTargets.forEach((el) => this.toggle(el, provider === "anam"))
    this.customFieldsTargets.forEach((el) => this.toggle(el, isCustom))
    this.customUrlFieldTargets.forEach((el) => this.toggle(el, isCustom && embedType === "iframe"))
    this.customScriptFieldTargets.forEach((el) => this.toggle(el, isCustom && embedType === "script"))

    if (this.hasDisplayFieldTarget) {
      this.toggle(this.displayFieldTarget, provider !== "none")
    }
  }

  get selectedProvider() {
    if (!this.hasProviderSelectTarget) return "chatbar"

    const value = (this.providerSelectTarget.value || "").trim()
    return value.length > 0 ? value : "chatbar"
  }

  get selectedCustomEmbedType() {
    if (!this.hasCustomEmbedTypeSelectTarget) return "iframe"

    const value = (this.customEmbedTypeSelectTarget.value || "").trim()
    return value.length > 0 ? value : "iframe"
  }

  toggle(element, visible) {
    element.classList.toggle("hidden", !visible)
  }
}
