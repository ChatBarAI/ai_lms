import { Controller } from "@hotwired/stimulus"
import { Turbo } from "@hotwired/turbo-rails"

export default class extends Controller {
  static values = { url: String, saved: String, effective: String, manual: Boolean, refresh: Boolean }

  connect() {
    this.disconnected = false
    this.dirty = false
    this.markDirty = () => { this.dirty = true }
    this.check = () => this.sync()
    document.addEventListener("input", this.markDirty)
    document.addEventListener("change", this.markDirty)
    document.addEventListener("turbo:before-visit", this.markDirty)
    document.addEventListener("turbo:submit-start", this.markDirty)
    window.addEventListener("focus", this.check)
    this.sync()
  }

  disconnect() {
    this.disconnected = true
    document.removeEventListener("input", this.markDirty)
    document.removeEventListener("change", this.markDirty)
    document.removeEventListener("turbo:before-visit", this.markDirty)
    document.removeEventListener("turbo:submit-start", this.markDirty)
    window.removeEventListener("focus", this.check)
  }

  async sync() {
    if (this.saving || this.dirty) return
    try {
      const zone = Intl.DateTimeFormat().resolvedOptions().timeZone
      if (!zone || zone === this.savedValue) return
      const csrf = document.querySelector('meta[name="csrf-token"]')?.content
      if (!csrf) return
      this.saving = true
      const response = await fetch(this.urlValue, {
        method: "PATCH",
        credentials: "same-origin",
        headers: { "Content-Type": "application/json", "X-CSRF-Token": csrf, "Accept": "application/json" },
        body: JSON.stringify({ time_zone: zone })
      })
      if (!response.ok || response.redirected || this.disconnected) return
      this.savedValue = zone
      // Refresh a clean page once so the first detected zone is visible now.
      // Never discard an edited form or replace a failed form submission.
      if (this.refreshValue && !this.manualValue && zone !== this.effectiveValue && !this.dirty && !document.querySelector("form[aria-invalid='true'], .field_with_errors")) {
        Turbo.visit(window.location.href, { action: "replace" })
      }
    } catch {
      // Device detection/network failures leave the saved zone (or UTC) in use.
    } finally {
      this.saving = false
    }
  }
}
