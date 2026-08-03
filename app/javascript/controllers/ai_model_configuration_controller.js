import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["provider", "model", "models", "baseUrl"]
  static values = { providers: Object }

  connect() {
    this.previousProvider = this.providerTarget.value
    this.refreshModels()
  }

  providerChanged() {
    const previous = this.providersValue[this.previousProvider]
    const selected = this.selectedProvider

    if (!selected) return

    if (!this.modelTarget.value || previous?.models.includes(this.modelTarget.value)) {
      this.modelTarget.value = selected.default_model
    }
    if (!this.baseUrlTarget.value || this.baseUrlTarget.value === previous?.base_url) {
      this.baseUrlTarget.value = selected.base_url
    }

    this.previousProvider = this.providerTarget.value
    this.refreshModels()
  }

  refreshModels() {
    const models = this.selectedProvider?.models || []
    this.modelsTarget.replaceChildren(...models.map((model) => {
      const option = document.createElement("option")
      option.value = model
      return option
    }))
  }

  get selectedProvider() {
    return this.providersValue[this.providerTarget.value]
  }
}
