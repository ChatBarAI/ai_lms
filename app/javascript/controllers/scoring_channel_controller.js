import { Controller } from "@hotwired/stimulus"
import { createConsumer } from "actioncable"

// Subscribes to ScoringChannel for a given progress record and reloads the
// page exactly once when the server broadcasts "done". Replaces the old
// setTimeout-based auto_reload approach.
export default class extends Controller {
  static values = { progressId: Number }

  connect() {
    const progressId = this.progressIdValue
    if (!progressId) return

    this.subscription = createConsumer().subscriptions.create(
      { channel: "ScoringChannel", progress_id: progressId },
      {
        received: (data) => {
          if (data.event === "scoring_complete") {
            this.subscription.consumer.disconnect()
            location.reload()
          }
        }
      }
    )
  }

  disconnect() {
    if (this.subscription) {
      this.subscription.consumer.disconnect()
      this.subscription = null
    }
  }
}
