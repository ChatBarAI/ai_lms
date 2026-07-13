import "trix"

// Trix runs inside Rails forms. Several browser + Turbo interactions need guards.

// Don't fall back to filename/filesize when caption is cleared — show nothing instead.
;(function disableDefaultAttachmentCaptions() {
  const attachments = window.Trix?.config?.attachments
  if (!attachments) return

  if (attachments.preview?.caption) {
    attachments.preview.caption.name = false
    attachments.preview.caption.size = false
  }

  if (attachments.file?.caption) {
    attachments.file.caption.name = false
    attachments.file.caption.size = false
  }
})()

function findTrixEditor(element) {
  return element?.closest?.("trix-editor")
}

function findAttachmentFigure(element) {
  return element?.closest?.("figure.attachment[data-trix-attachment]")
}

// Link dialog URL field is an <input>; Enter would submit the outer Rails form.
document.addEventListener(
  "keydown",
  (event) => {
    if (event.key !== "Enter") return

    if (event.target.closest(".trix-dialog")) {
      event.preventDefault()
      return
    }

    // Caption editor is a <textarea> inside the form; stop Enter bubbling to form handlers.
    if (event.target.matches("textarea.attachment__caption-editor")) {
      event.stopPropagation()
    }
  },
  true
)

// Turbo caches the live DOM. Attachment toolbars/caption editors left open get restored
// as duplicates when navigating back to the edit page.
document.addEventListener("turbo:before-cache", () => {
  document.querySelectorAll("trix-editor").forEach((element) => {
    const { editor } = element
    if (!editor) return

    editor.composition?.stopEditingAttachment?.()

    const inputId = element.getAttribute("input")
    const input = inputId ? document.getElementById(inputId) : null
    if (input) input.value = element.innerHTML
  })
})

// Uploaded images are wrapped in <a href="..."> for display. Without this, clicking the
// image while an attachment is already open can re-trigger insert/select and duplicate it.
// Only block media re-clicks — never the remove toolbar or caption editor.
document.addEventListener(
  "mousedown",
  (event) => {
    const figure = findAttachmentFigure(event.target)
    const trixEditor = findTrixEditor(event.target)
    if (!figure || !trixEditor?.editor) return

    // Remove button, caption field, and other chrome must keep working.
    if (event.target.closest(".attachment__toolbar")) return
    if (event.target.closest("[data-trix-action]")) return
    if (event.target.closest("textarea.attachment__caption-editor")) return
    if (event.target.closest("figcaption")) return

    // Only suppress clicks on the preview image / its display link.
    const media = event.target.closest("img, a")
    if (!media || !figure.contains(media)) return

    const editingAttachment = trixEditor.editor.composition?.editingAttachment
    if (!editingAttachment) return

    const activeEditor = trixEditor.editor.compositionController?.attachmentEditor
    const activeElement = activeEditor?.element
    if (!activeElement) return

    if (activeElement === figure || activeElement.contains(event.target)) {
      event.preventDefault()
      event.stopPropagation()
    }
  },
  true
)

// Double-clicking a preview image can insert a second copy in some browsers.
document.addEventListener(
  "dblclick",
  (event) => {
    if (findAttachmentFigure(event.target)) {
      event.preventDefault()
      event.stopPropagation()
    }
  },
  true
)
