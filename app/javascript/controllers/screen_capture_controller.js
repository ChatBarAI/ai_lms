import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [
    "video", "captureButton", "stopButton", "status", "format", "quality", "qualityValue",
    "browsePanel", "capturePanel", "modeButton", "submitButton", "cropDialog", "cropCanvas",
    "useCropButton"
  ]

  connect() {
    this.stream = null
    this.updateQuality()
    this.dialog = this.element.closest('[role="dialog"]')
    if (this.dialog) {
      this.dialogObserver = new MutationObserver(() => {
        if (this.dialog.classList.contains("hidden")) this.stop()
      })
      this.dialogObserver.observe(this.dialog, { attributes: true, attributeFilter: ["class"] })
    }
  }

  disconnect() {
    this.dialogObserver?.disconnect()
    this.stop()
  }

  selectBrowse() {
    this.stop()
    this.hideCropper()
    this.selectMode("browse")
  }

  selectCapture() {
    this.selectMode("capture")
  }

  fileChanged() {
    const input = this.element.querySelector('input[type="file"][name$="[file]"]')
    this.submitButtonTarget.disabled = !input?.files.length
  }

  async start() {
    if (!navigator.mediaDevices?.getDisplayMedia) {
      this.setStatus("Screen capture is not supported by this browser.", true)
      return
    }

    try {
      this.stop()
      this.clearSelectedFile()
      this.hideCropper()
      const displayOptions = { video: true, audio: false }
      const captureController = this.focusRetainingCaptureController()
      if (captureController) displayOptions.controller = captureController

      this.stream = await navigator.mediaDevices.getDisplayMedia(displayOptions)
      this.videoTarget.srcObject = this.stream
      await this.videoTarget.play()

      this.videoTarget.classList.remove("hidden")
      this.captureButtonTarget.disabled = false
      this.stopButtonTarget.classList.remove("hidden")
      this.setStatus("Sharing is active. Arrange the selected screen or window, then capture the snapshot.")

      this.stream.getVideoTracks()[0]?.addEventListener("ended", () => this.captureEnded(), { once: true })
    } catch (error) {
      if (error.name === "NotAllowedError") {
        this.setStatus("Screen sharing was cancelled or not permitted.", true)
      } else {
        this.setStatus(`Could not start screen sharing: ${error.message}`, true)
      }
    }
  }

  capture() {
    const width = this.videoTarget.videoWidth
    const height = this.videoTarget.videoHeight
    if (!width || !height) {
      this.setStatus("The shared screen is not ready yet. Please try again.", true)
      return
    }

    this.sourceCanvas = document.createElement("canvas")
    this.sourceCanvas.width = width
    this.sourceCanvas.height = height
    this.sourceCanvas.getContext("2d").drawImage(this.videoTarget, 0, 0, width, height)
    this.selection = { x: 0, y: 0, width, height }

    this.cropCanvasTarget.width = width
    this.cropCanvasTarget.height = height
    this.useCropButtonTarget.disabled = false
    this.stop()
    if (!this.cropDialogTarget.open) this.cropDialogTarget.showModal()
    this.renderCropper()
    this.setStatus("Drag over the snapshot to select an area, then use the selected area.")
  }

  beginCrop(event) {
    if (!this.sourceCanvas) return

    event.preventDefault()
    this.cropCanvasTarget.setPointerCapture(event.pointerId)
    this.cropStart = this.canvasPoint(event)
    this.selection = { x: this.cropStart.x, y: this.cropStart.y, width: 0, height: 0 }
    this.renderCropper()
  }

  resizeCrop(event) {
    if (!this.cropStart || !this.cropCanvasTarget.hasPointerCapture(event.pointerId)) return

    const point = this.canvasPoint(event)
    this.selection = {
      x: Math.min(this.cropStart.x, point.x),
      y: Math.min(this.cropStart.y, point.y),
      width: Math.abs(point.x - this.cropStart.x),
      height: Math.abs(point.y - this.cropStart.y)
    }
    this.renderCropper()
  }

  endCrop(event) {
    if (!this.cropStart) return

    this.resizeCrop(event)
    this.cropStart = null
    if (this.selection.width < 5 || this.selection.height < 5) this.selectFullImage()
  }

  selectFullImage() {
    if (!this.sourceCanvas) return

    this.selection = {
      x: 0, y: 0,
      width: this.sourceCanvas.width,
      height: this.sourceCanvas.height
    }
    this.renderCropper()
  }

  useCrop() {
    if (!this.sourceCanvas || !this.selection?.width || !this.selection?.height) return

    const selection = this.roundedSelection()
    const output = document.createElement("canvas")
    output.width = selection.width
    output.height = selection.height
    output.getContext("2d").drawImage(
      this.sourceCanvas,
      selection.x, selection.y, selection.width, selection.height,
      0, 0, selection.width, selection.height
    )

    const mimeType = this.formatTarget.value
    const quality = Number(this.qualityTarget.value) / 100
    output.toBlob((blob) => {
      this.attachBlob(blob, mimeType)
      if (blob) this.hideCropper()
    }, mimeType, quality)
  }

  cancelCrop(event) {
    event?.preventDefault()
    this.hideCropper()
    this.setStatus("Crop cancelled. Choose a screen or window to capture again.")
  }

  stop() {
    this.stream?.getTracks().forEach((track) => track.stop())
    this.stream = null

    if (this.hasVideoTarget) {
      this.videoTarget.srcObject = null
      this.videoTarget.classList.add("hidden")
    }
    if (this.hasCaptureButtonTarget) this.captureButtonTarget.disabled = true
    if (this.hasStopButtonTarget) this.stopButtonTarget.classList.add("hidden")
  }

  updateQuality() {
    if (this.hasQualityValueTarget) this.qualityValueTarget.textContent = `${this.qualityTarget.value}%`
  }

  captureEnded() {
    this.stop()
    this.setStatus("Screen sharing ended. The last captured snapshot, if any, remains selected.")
  }

  attachBlob(blob, requestedMimeType) {
    if (!blob) {
      this.setStatus("The browser could not create the snapshot.", true)
      return
    }

    const mimeType = blob.type || requestedMimeType
    const extension = { "image/webp": "webp", "image/jpeg": "jpg", "image/png": "png" }[mimeType] || "jpg"
    const timestamp = new Date().toISOString().replace(/[:.]/g, "-")
    const file = new File([blob], `lesson-snapshot-${timestamp}.${extension}`, { type: mimeType })
    const input = this.element.querySelector('input[type="file"][name$="[file]"]')

    try {
      const transfer = new DataTransfer()
      transfer.items.add(file)
      input.files = transfer.files
      input.dispatchEvent(new Event("change", { bubbles: true }))
      this.fillDefaultName()
      this.setStatus(`Snapshot selected (${this.formatBytes(file.size)}). Upload the asset to add it to the designer.`)
    } catch (_) {
      this.setStatus("This browser cannot add the snapshot to the upload field. Download or upload it manually.", true)
    }
  }

  setStatus(message, error = false) {
    this.statusTarget.textContent = message
    this.statusTarget.classList.toggle("text-red-700", error)
    this.statusTarget.classList.toggle("text-gray-500", !error)
  }

  formatBytes(bytes) {
    if (bytes < 1024) return `${bytes} B`
    if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB`
    return `${(bytes / (1024 * 1024)).toFixed(1)} MB`
  }

  focusRetainingCaptureController() {
    if (typeof window.CaptureController !== "function") return null

    const controller = new window.CaptureController()
    const behaviors = ["focus-capturing-application", "no-focus-change"]
    const supported = behaviors.some((behavior) => {
      try {
        controller.setFocusBehavior(behavior)
        return true
      } catch (_) {
        return false
      }
    })

    return supported ? controller : null
  }

  fillDefaultName() {
    const nameInput = this.element.querySelector('input[name$="[name]"]')
    if (nameInput && !nameInput.value.trim()) nameInput.value = "Desktop snapshot"
  }

  selectMode(mode) {
    if (this.currentMode && this.currentMode !== mode) this.clearSelectedFile()
    this.currentMode = mode
    this.browsePanelTarget.classList.toggle("hidden", mode !== "browse")
    this.capturePanelTarget.classList.toggle("hidden", mode !== "capture")

    this.modeButtonTargets.forEach((button) => {
      const selected = button.dataset.screenCaptureMode === mode
      button.setAttribute("aria-pressed", selected.toString())
      button.classList.toggle("border-indigo-600", selected)
      button.classList.toggle("bg-indigo-50", selected)
      button.classList.toggle("text-indigo-700", selected)
      button.classList.toggle("border-gray-300", !selected)
      button.classList.toggle("bg-white", !selected)
      button.classList.toggle("text-gray-700", !selected)
    })
  }

  clearSelectedFile() {
    const input = this.element.querySelector('input[type="file"][name$="[file]"]')
    if (!input?.files.length) return

    input.value = ""
    input.dispatchEvent(new Event("change", { bubbles: true }))
  }

  hideCropper() {
    if (this.hasCropDialogTarget && this.cropDialogTarget.open) this.cropDialogTarget.close()
    this.sourceCanvas = null
    this.selection = null
    this.cropStart = null
    if (this.hasUseCropButtonTarget) this.useCropButtonTarget.disabled = true
  }

  canvasPoint(event) {
    const rect = this.cropCanvasTarget.getBoundingClientRect()
    const x = (event.clientX - rect.left) * (this.cropCanvasTarget.width / rect.width)
    const y = (event.clientY - rect.top) * (this.cropCanvasTarget.height / rect.height)
    return {
      x: Math.max(0, Math.min(this.cropCanvasTarget.width, x)),
      y: Math.max(0, Math.min(this.cropCanvasTarget.height, y))
    }
  }

  roundedSelection() {
    const x = Math.max(0, Math.min(this.sourceCanvas.width - 1, Math.floor(this.selection.x)))
    const y = Math.max(0, Math.min(this.sourceCanvas.height - 1, Math.floor(this.selection.y)))
    return {
      x,
      y,
      width: Math.min(this.sourceCanvas.width - x, Math.max(1, Math.round(this.selection.width))),
      height: Math.min(this.sourceCanvas.height - y, Math.max(1, Math.round(this.selection.height)))
    }
  }

  renderCropper() {
    if (!this.sourceCanvas || !this.selection) return

    const context = this.cropCanvasTarget.getContext("2d")
    const { width, height } = this.cropCanvasTarget
    const selection = this.roundedSelection()

    context.clearRect(0, 0, width, height)
    context.drawImage(this.sourceCanvas, 0, 0)
    context.fillStyle = "rgba(15, 23, 42, 0.55)"
    context.fillRect(0, 0, width, height)
    context.drawImage(
      this.sourceCanvas,
      selection.x, selection.y, selection.width, selection.height,
      selection.x, selection.y, selection.width, selection.height
    )
    context.strokeStyle = "#4f46e5"
    context.lineWidth = Math.max(2, width / 1000)
    context.strokeRect(selection.x, selection.y, selection.width, selection.height)
  }
}
