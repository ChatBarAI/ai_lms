import { Controller } from "@hotwired/stimulus"

const IMAGE_TYPES = new Set(["image/png", "image/jpeg", "image/webp", "image/gif"])
const VIDEO_TYPES = new Set(["video/mp4", "video/webm", "video/ogg"])
const IMAGE_EXTENSIONS = new Set(["png", "jpg", "jpeg", "webp", "gif"])
const VIDEO_EXTENSIONS = new Set(["mp4", "webm", "ogg"])

export default class extends Controller {
  static targets = ["overlay", "status"]
  static values = {
    imageMaxBytes: Number,
    videoMaxBytes: Number,
    imageDialogId: { type: String, default: "add-design-asset-dialog" },
    videoDialogId: { type: String, default: "add-video-asset-dialog" }
  }

  connect() {
    this.dragDepth = 0
  }

  dragenter(event) {
    if (!this.hasFiles(event)) return

    event.preventDefault()
    this.dragDepth += 1
    this.overlayTarget.classList.remove("hidden")
  }

  dragover(event) {
    if (!this.hasFiles(event)) return

    event.preventDefault()
    event.dataTransfer.dropEffect = "copy"
  }

  dragleave(event) {
    this.dragDepth = Math.max(0, this.dragDepth - 1)
    if (this.dragDepth === 0) this.overlayTarget.classList.add("hidden")
  }

  drop(event) {
    if (!this.hasFiles(event)) return

    event.preventDefault()
    this.dragDepth = 0
    this.overlayTarget.classList.add("hidden")

    const files = Array.from(event.dataTransfer.files || [])
    if (files.length !== 1) {
      this.showError("Drop one image or video at a time so its details can be completed.")
      return
    }

    const file = files[0]
    const kind = this.assetKind(file)
    if (!kind) {
      this.showError("Choose a PNG, JPEG, WebP, GIF, MP4, WebM, or OGG file.")
      return
    }

    const limit = kind === "image" ? this.imageMaxBytesValue : this.videoMaxBytesValue
    if (file.size >= limit) {
      this.showError(`${kind === "image" ? "Images" : "Videos"} must be less than ${this.formatBytes(limit)}.`)
      return
    }

    if (!this.attachToModal(file, kind)) {
      this.showError("This browser could not prepare the dropped file. Use Add image or Add video instead.")
      return
    }

    this.clearStatus()
  }

  hasFiles(event) {
    const transfer = event.dataTransfer
    return Boolean(transfer && (
      Array.from(transfer.types || []).includes("Files") || transfer.files?.length
    ))
  }

  assetKind(file) {
    if (IMAGE_TYPES.has(file.type)) return "image"
    if (VIDEO_TYPES.has(file.type)) return "video"
    if (file.type) return null

    const extension = file.name.split(".").pop()?.toLowerCase()
    if (IMAGE_EXTENSIONS.has(extension)) return "image"
    if (VIDEO_EXTENSIONS.has(extension)) return "video"
    return null
  }

  attachToModal(file, kind) {
    const dialogId = kind === "image" ? this.imageDialogIdValue : this.videoDialogIdValue
    const dialog = document.getElementById(dialogId)
    const form = dialog?.querySelector("form")
    const input = form?.querySelector('input[type="file"][name$="[file]"]')
    if (!dialog || !form || !input) return false

    if (kind === "image") {
      const capture = this.application.getControllerForElementAndIdentifier(form, "screen-capture")
      capture?.selectBrowse()
    }

    try {
      const transfer = new DataTransfer()
      transfer.items.add(file)
      input.files = transfer.files
    } catch (_) {
      return false
    }

    input.dispatchEvent(new Event("change", { bubbles: true }))
    const nameInput = form.querySelector('input[name$="[name]"]')
    if (nameInput && !nameInput.value.trim()) nameInput.value = file.name.replace(/\.[^.]+$/, "")

    const dialogController = this.application.getControllerForElementAndIdentifier(dialog, "dialog")
    if (dialogController) {
      dialogController.open()
    } else {
      dialog.classList.remove("hidden")
      dialog.setAttribute("aria-hidden", "false")
    }

    requestAnimationFrame(() => nameInput?.focus())
    return true
  }

  showError(message) {
    this.statusTarget.textContent = message
    this.statusTarget.classList.remove("hidden")
  }

  clearStatus() {
    this.statusTarget.textContent = ""
    this.statusTarget.classList.add("hidden")
  }

  formatBytes(bytes) {
    return `${Math.round(bytes / (1024 * 1024))} MB`
  }
}
