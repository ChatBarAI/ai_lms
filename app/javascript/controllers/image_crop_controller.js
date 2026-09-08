import { Controller } from "@hotwired/stimulus"
import Cropper from "cropperjs"

// Optional zoom/crop step for image file inputs (Cropper.js).
// Compose with file-preview on the same wrapper:
//   data-controller="file-preview image-crop"
//   data-image-crop-width-value / height-value — guide pixel size (omit for free crop)

export default class extends Controller {
  static targets = ["input", "adjustButton", "dialog", "image", "status"]
  static values = { width: Number, height: Number }

  connect() {
    this.syncAdjustButton()
  }

  disconnect() {
    this.teardown()
  }

  fileChanged() {
    this.syncAdjustButton()
  }

  open(event) {
    event?.preventDefault()
    const file = this.selectedFile()
    if (!file) return

    this.teardown()
    this.objectUrl = URL.createObjectURL(file)
    this.imageTarget.src = this.objectUrl
    this.clearStatus()

    if (!this.dialogTarget.open) this.dialogTarget.showModal()

    this.imageTarget.onload = () => {
      this.cropper = new Cropper(this.imageTarget, this.cropperOptions())
    }
  }

  use(event) {
    event?.preventDefault()
    if (!this.cropper) return

    const file = this.selectedFile()
    if (!file) return

    const mime = this.outputMime(file.type)
    const canvas = this.cropper.getCroppedCanvas(this.canvasOptions())
    if (!canvas) {
      this.setStatus("Could not create cropped image.", true)
      return
    }

    canvas.toBlob((blob) => {
      if (!blob) {
        this.setStatus("Could not create cropped image.", true)
        return
      }
      this.attachBlob(blob, mime, file.name)
      this.close()
    }, mime, 0.92)
  }

  cancel(event) {
    event?.preventDefault()
    this.close()
  }

  close() {
    this.teardown()
    if (this.hasDialogTarget && this.dialogTarget.open) this.dialogTarget.close()
  }

  // ── Private ─────────────────────────────────────────────────────────────

  selectedFile() {
    const file = this.inputTarget.files?.[0]
    return file && this.croppable(file) ? file : null
  }

  croppable(file) {
    return file.type.startsWith("image/") && file.type !== "image/svg+xml"
  }

  syncAdjustButton() {
    if (!this.hasAdjustButtonTarget) return
    this.adjustButtonTarget.classList.toggle("hidden", !this.selectedFile())
  }

  cropperOptions() {
    const options = { viewMode: 1, autoCropArea: 1, responsive: true }
    if (this.sized()) options.aspectRatio = this.widthValue / this.heightValue
    return options
  }

  canvasOptions() {
    if (!this.sized()) return {}
    return { width: this.widthValue, height: this.heightValue }
  }

  sized() {
    return this.hasWidthValue && this.hasHeightValue && this.widthValue > 0 && this.heightValue > 0
  }

  outputMime(type) {
    return [ "image/jpeg", "image/png", "image/webp" ].includes(type) ? type : "image/png"
  }

  attachBlob(blob, mimeType, originalName) {
    const extension = { "image/webp": "webp", "image/jpeg": "jpg", "image/png": "png" }[mimeType] || "png"
    const stem = String(originalName || "image").replace(/\.[^.]+$/, "")
    const cropped = new File([ blob ], `${stem}_cropped.${extension}`, { type: mimeType })

    try {
      const transfer = new DataTransfer()
      transfer.items.add(cropped)
      this.inputTarget.files = transfer.files
      this.inputTarget.dispatchEvent(new Event("change", { bubbles: true }))
    } catch (_) {
      this.setStatus("This browser cannot replace the upload with the crop.", true)
    }
  }

  teardown() {
    this.cropper?.destroy()
    this.cropper = null
    if (this.objectUrl) {
      URL.revokeObjectURL(this.objectUrl)
      this.objectUrl = null
    }
    if (this.hasImageTarget) {
      this.imageTarget.onload = null
      this.imageTarget.removeAttribute("src")
    }
  }

  setStatus(message, error = false) {
    if (!this.hasStatusTarget) return
    this.statusTarget.textContent = message
    this.statusTarget.classList.toggle("text-red-700", error)
    this.statusTarget.classList.toggle("text-gray-500", !error)
  }

  clearStatus() {
    this.setStatus("")
  }
}
