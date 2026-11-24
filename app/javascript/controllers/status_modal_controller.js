import { Controller } from "@hotwired/stimulus"

// Opens a page-level dialog (shared/_dialog or similar) by id.
// Optional action params fill the dialog before it opens, so one dialog can serve many triggers:
//   data-status-modal-message-param    -> text of [data-dialog-fill="message"]
//   data-status-modal-link-url-param   -> href of [data-dialog-fill="link"]
//   data-status-modal-link-label-param -> text of [data-dialog-fill="link"]
export default class extends Controller {
  static values = { dialogId: String }

  open(event) {
    event.preventDefault()

    if (!this.hasDialogIdValue) return

    const dialogEl = document.getElementById(this.dialogIdValue)
    if (!dialogEl) return

    this.fill(dialogEl, event.params || {})

    const dialogController = this.application.getControllerForElementAndIdentifier(dialogEl, "dialog")
    if (dialogController && typeof dialogController.open === "function") {
      dialogController.open()
      return
    }

    dialogEl.classList.remove("hidden")
    dialogEl.setAttribute("aria-hidden", "false")
  }

  fill(dialogEl, { message, linkUrl, linkLabel }) {
    const messageEl = dialogEl.querySelector('[data-dialog-fill="message"]')
    if (messageEl && message !== undefined) messageEl.textContent = message

    const linkEl = dialogEl.querySelector('[data-dialog-fill="link"]')
    if (linkEl && linkUrl !== undefined) linkEl.href = linkUrl
    if (linkEl && linkLabel !== undefined) linkEl.textContent = linkLabel
  }
}
