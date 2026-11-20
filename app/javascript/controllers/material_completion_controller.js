import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["form", "button", "status"]
  static values = { completed: String, error: String }

  async submit(event) {
    event.preventDefault()
    try {
      await this.complete()
    } catch (error) {
      this.statusTarget.textContent = this.errorValue
    }
  }

  complete() {
    if (this.completionRequest) return this.completionRequest
    if (!this.hasFormTarget) return Promise.resolve(false)

    this.completionRequest = this.saveCompletion().finally(() => {
      this.completionRequest = null
    })
    return this.completionRequest
  }

  async saveCompletion() {
    const form = this.formTarget
    const button = this.buttonTarget
    button.disabled = true
    this.statusTarget.textContent = ""

    try {
      const response = await fetch(form.action, {
        method: "POST",
        headers: {
          Accept: "application/json",
          "X-CSRF-Token": document.querySelector("meta[name='csrf-token']")?.content
        },
        credentials: "same-origin"
      })
      if (!response.ok) throw new Error(`Material acknowledgement failed (${response.status})`)
      const result = await response.json()
      if (result.acknowledged !== true) throw new Error("Material acknowledgement was not confirmed")

      const completed = document.createElement("span")
      completed.className = "inline-flex items-center gap-1 text-sm text-green-700"
      completed.style.minHeight = `${form.getBoundingClientRect().height}px`
      completed.textContent = this.completedValue
      completed.setAttribute("role", "status")
      form.replaceWith(completed)
      this.dispatch("completed")
      return true
    } finally {
      button.disabled = false
    }
  }
}
