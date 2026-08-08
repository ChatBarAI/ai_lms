import { Controller } from "@hotwired/stimulus"

const TARGET_BY_KIND = Object.freeze({
  pdf: "pdf",
  html: "html",
  raw_html: "rawhtml",
  raw_html_iframe: "rawhtml",
  google_doc: "googledoc",
  web_page: "webpage",
  audio_upload: "audioupload",
  audio_url: "audiourl",
  image_upload: "imageupload",
  video_upload: "videoupload",
  video_url: "videourl",
  copy: "copy"
})

export default class extends Controller {
  connect() {
    const select = this.element.querySelector('select[name$="[kind]"]')
    this.apply(select ? select.value : "")
  }

  toggle(event) {
    this.apply(event.target.value)
  }

  apply(value) {
    const activeTarget = TARGET_BY_KIND[value]
    const submit = this.element.querySelector("[data-material-kind-submit]")

    if (submit) {
      if (value === "ai_designed") {
        submit.value = "Continue to AI designer"
      } else if (value === "copy") {
        submit.value = "Create copy"
      } else {
        submit.value = submit.dataset.defaultLabel
      }
    }

    this.element.querySelectorAll("[data-material-kind-target]").forEach((panel) => {
      const hidden = panel.dataset.materialKindTarget !== activeTarget
      panel.classList.toggle("hidden", hidden)

      panel.querySelectorAll("input, textarea, select").forEach((field) => {
        field.disabled = hidden
      })
    })

    if (value === "copy") {
      queueMicrotask(() => this.openCopyDialog())
    }
  }

  openCopyDialog() {
    const dialog = this.element.querySelector('[data-material-kind-target="copy"]')
    if (!dialog) return

    const controller = this.application.getControllerForElementAndIdentifier(dialog, "dialog")
    if (controller) {
      controller.open()
      const firstIncomplete = Array.from(dialog.querySelectorAll("select")).find((select) => !select.disabled && !select.value)
      firstIncomplete?.focus()
    }
  }
}
