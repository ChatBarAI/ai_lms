import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { dialogId: String }

  open(event) {
    event.preventDefault()

    if (!this.hasDialogIdValue) return

    const dialogEl = document.getElementById(this.dialogIdValue)
    if (!dialogEl) return

    const dialogController = this.application.getControllerForElementAndIdentifier(dialogEl, "dialog")
    if (dialogController && typeof dialogController.open === "function") {
      dialogController.open()
      return
    }

    dialogEl.classList.remove("hidden")
    dialogEl.setAttribute("aria-hidden", "false")
  }
}
