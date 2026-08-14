import { Controller } from "@hotwired/stimulus"
import { createConsumer } from "actioncable"

export default class extends Controller {
  static targets = ["announcement"]
  static values = { lessonMaterialId: Number }

  connect() {
    if (!this.lessonMaterialIdValue) return

    this.consumer = createConsumer()
    this.subscription = this.consumer.subscriptions.create(
      {
        channel: "MaterialDesignRevisionsChannel",
        lesson_material_id: this.lessonMaterialIdValue
      },
      { received: (data) => this.receive(data) }
    )
  }

  disconnect() {
    if (this.consumer) this.consumer.disconnect()
    this.subscription = null
    this.consumer = null
  }

  receive(data) {
    if (data.event === "snapshot") {
      data.revisions.forEach((revision) => this.updateRevision(revision, false))
      return
    }

    if (data.event === "status_changed") this.updateRevision(data, true)
  }

  updateRevision(revision, announce) {
    const row = this.element.querySelector(`[data-revision-id="${revision.revision_id}"]`)
    if (!row) return

    const badge = row.querySelector("[data-revision-status]")
    if (!badge) return

    badge.textContent = this.statusLabel(revision.status)
    badge.className = `text-center text-xs rounded-full px-2 py-1 ${this.statusClasses(revision.status)}`

    if (announce && this.hasAnnouncementTarget) {
      this.announcementTarget.textContent = this.announcementFor(revision.status)
      this.announcementTarget.className =
        `mb-3 rounded border px-3 py-2 text-sm ${this.announcementClasses(revision.status)}`
    }
  }

  statusLabel(status) {
    return status.charAt(0).toUpperCase() + status.slice(1)
  }

  statusClasses(status) {
    switch (status) {
      case "ready":
        return "bg-green-100 text-green-800"
      case "failed":
        return "bg-red-100 text-red-800"
      case "generating":
        return "bg-amber-100 text-amber-800"
      case "accepted":
        return "bg-indigo-100 text-indigo-800"
      default:
        return "bg-gray-100 text-gray-700"
    }
  }

  announcementFor(status) {
    switch (status) {
      case "ready":
        return "AI design generation completed. The revision is ready to review."
      case "failed":
        return "AI design generation failed. Open the revision for details."
      case "generating":
        return "AI design generation has started."
      default:
        return `AI design status changed to ${status}.`
    }
  }

  announcementClasses(status) {
    if (status === "ready") return "border-green-200 bg-green-50 text-green-800"
    if (status === "failed") return "border-red-200 bg-red-50 text-red-800"

    return "border-amber-200 bg-amber-50 text-amber-800"
  }
}
