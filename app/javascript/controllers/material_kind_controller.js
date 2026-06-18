import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["pdf", "html", "rawhtml", "audioupload", "audiourl", "imageupload"]

  connect() {
    const select = this.element.querySelector('select[name$="[kind]"]')
    this.apply(select ? select.value : "")
  }

  toggle(event) {
    this.apply(event.target.value)
  }

  apply(value) {
    if (this.hasPdfTarget)        this.pdfTarget.classList.toggle("hidden", value !== "pdf")
    if (this.hasHtmlTarget)       this.htmlTarget.classList.toggle("hidden", value !== "html")
    if (this.hasRawhtmlTarget)    this.rawhtmlTarget.classList.toggle("hidden", value !== "raw_html")
    if (this.hasAudiouploadTarget) this.audiouploadTarget.classList.toggle("hidden", value !== "audio_upload")
    if (this.hasAudiourlTarget)   this.audiourlTarget.classList.toggle("hidden", value !== "audio_url")
    if (this.hasImageuploadTarget) this.imageuploadTarget.classList.toggle("hidden", value !== "image_upload")
  }
}
