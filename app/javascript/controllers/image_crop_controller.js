import { Controller } from "@hotwired/stimulus"
import Cropper from "cropperjs"

// Optional zoom/crop step for image file inputs (Cropper.js).
// Compose with file-preview on the same wrapper:
//   data-controller="file-preview image-crop"
//   data-image-crop-width-value / height-value — guide pixel size (omit for free crop)
//   data-image-crop-source-url-value — existing attachment URL (edit forms)

export default class extends Controller {
  static targets = ["input", "adjustButton", "dialog", "image", "status", "preview"]
  static values = { width: Number, height: Number, sourceUrl: String }

  connect() {
    this.syncAdjustButton()
  }

  disconnect() {
    this.teardown()
  }

  fileChanged() {
    this.syncAdjustButton()
  }

  async open(event) {
    event?.preventDefault()
    event?.stopPropagation?.()
    this.teardown()
    this.setStatus("Loading image…")
    if (!this.dialogTarget.open) this.dialogTarget.showModal()

    const request = new AbortController()
    this.sourceRequest = request

    try {
      const file = await this.loadSourceFile(request.signal)
      if (request.signal.aborted) return

      this.cropFile = file
      this.objectUrl = URL.createObjectURL(file)
      const image = this.imageTarget
      image.src = this.objectUrl
      await image.decode()
      if (request.signal.aborted) return

      this.cropper = new Cropper(image, this.cropperOptions())
      this.clearStatus()
    } catch (_error) {
      // A previous operation must not clear a newer dialog's state or status.
      if (request.signal.aborted || this.sourceRequest !== request) return
      this.teardown()
      this.setStatus("Could not load this image. Please select the file again.", true)
    }
  }

  use(event) {
    event?.preventDefault()
    if (!this.cropper) return

    const file = this.cropFile || this.selectedFile()
    if (!file) {
      this.setStatus("Could not create cropped image.", true)
      return
    }

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
    if (this.sourceRequest) {
      this.sourceRequest.abort()
      this.sourceRequest = null
    }
    this.teardown()
    if (this.hasDialogTarget && this.dialogTarget.open) this.dialogTarget.close()
  }

  // ── Private ─────────────────────────────────────────────────────────────

  async loadSourceFile(signal) {
    const selected = this.selectedFile()
    if (selected) return selected

    const url = this.resolveSourceUrl()
    if (!url) throw new Error("no image source")

    const response = await fetch(url, { signal, credentials: "same-origin" })
    if (!response.ok) throw new Error(`fetch ${response.status}`)

    const blob = await response.blob()
    if (signal?.aborted) throw new Error("aborted")
    if (!blob.type.startsWith("image/") || blob.type === "image/svg+xml") {
      throw new Error("not a croppable image")
    }

    const name = this.filenameFromUrl(url) || "image.png"
    return new File([ blob ], name, { type: blob.type || "image/png" })
  }

  resolveSourceUrl() {
    if (this.hasSourceUrlValue && this.sourceUrlValue) return this.sourceUrlValue
    if (this.hasPreviewTarget) {
      const src = this.previewTarget.currentSrc || this.previewTarget.src
      if (src) return src
    }
    return null
  }

  filenameFromUrl(url) {
    try {
      const path = new URL(url, window.location.origin).pathname
      const base = path.split("/").pop()
      return base && /\./.test(base) ? decodeURIComponent(base) : null
    } catch (_) {
      return null
    }
  }

  selectedFile() {
    const file = this.inputTarget.files?.[0]
    return file && this.croppable(file) ? file : null
  }

  croppable(file) {
    return file.type.startsWith("image/") && file.type !== "image/svg+xml"
  }

  syncAdjustButton() {
    if (!this.hasAdjustButtonTarget) return
    const canCrop = !!(this.selectedFile() || this.resolveSourceUrl())
    this.adjustButtonTarget.classList.toggle("hidden", !canCrop)
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
      this.syncAdjustButton()
    } catch (_) {
      this.setStatus("This browser cannot replace the upload with the crop.", true)
    }
  }

  teardown() {
    this.cropper?.destroy()
    this.cropper = null
    this.cropFile = null
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
