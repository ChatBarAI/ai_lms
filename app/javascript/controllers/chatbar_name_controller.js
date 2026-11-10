import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["key", "name"]
  static values = { url: String }

  connect() {
    this.initialName = this.nameTarget.textContent.trim()
    this.initialKey = this.keyTarget.value.trim()
    this.generation = 0
  }

  disconnect() {
    this.cancel()
  }

  cancel() {
    this.generation += 1
    this.request?.abort()
  }

  changed() {
    this.cancel()
    this.nameTarget.textContent = this.keyTarget.value.trim() === this.initialKey
      ? this.initialName
      : "Leave the API key field to look up its ChatBar name."
  }

  async lookup() {
    this.cancel()
    const key = this.keyTarget.value.trim()
    if (!key) {
      this.nameTarget.textContent = this.initialKey ? "No ChatBar connected" : this.initialName
      return
    }

    const generation = this.generation
    this.request = new AbortController()
    this.nameTarget.textContent = "Looking up ChatBar name…"
    try {
      const response = await fetch(this.urlValue, {
        method: "POST",
        credentials: "same-origin",
        headers: {
          "Content-Type": "application/json",
          "Accept": "application/json",
          "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]')?.content || ""
        },
        body: JSON.stringify({ api_key: key }),
        signal: this.request.signal
      })
      if (!response.ok) throw new Error("Lookup failed")
      const data = await response.json()
      if (generation === this.generation) this.nameTarget.textContent = data.name || "Name unavailable"
    } catch (error) {
      if (generation === this.generation && error.name !== "AbortError") {
        this.nameTarget.textContent = "Could not look up ChatBar name. Check the API key and try again."
      }
    }
  }
}
