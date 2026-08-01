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
  video_url: "videourl"
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

    this.element.querySelectorAll("[data-material-kind-target]").forEach((panel) => {
      const hidden = panel.dataset.materialKindTarget !== activeTarget
      panel.classList.toggle("hidden", hidden)

      panel.querySelectorAll("input, textarea, select").forEach((field) => {
        field.disabled = hidden
      })
    })
  }
}
