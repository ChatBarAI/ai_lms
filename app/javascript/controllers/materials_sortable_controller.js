import { Controller } from "@hotwired/stimulus"

// Drag-to-reorder for readings using the native HTML5 drag-and-drop API.
// Each draggable child must have [data-material-id]. A descendant with
// [data-sortable-handle] enables drag only when the user grabs that handle.
export default class extends Controller {
  static values = { url: String }

  connect() {
    this.handlers = new WeakMap()
    this.dragged = null
    this.attach()
    this.renumber()
  }

  disconnect() {
    this.items().forEach((item) => this.detachItem(item))
  }

  // --- setup ----------------------------------------------------------

  attach() {
    this.items().forEach((item) => this.attachItem(item))
  }

  items() {
    return Array.from(this.element.children).filter((el) => el.dataset.materialId)
  }

  attachItem(item) {
    const handle = item.querySelector("[data-sortable-handle]") || item

    const onHandleDown = () => { item.draggable = true }
    const onHandleUp   = () => { item.draggable = false }

    const onDragStart = (e) => {
      this.dragged = item
      item.classList.add("opacity-50")
      e.dataTransfer.effectAllowed = "move"
      try { e.dataTransfer.setData("text/plain", item.dataset.materialId) } catch (_) { /* Safari */ }
    }
    const onDragEnd = () => {
      item.classList.remove("opacity-50")
      item.draggable = false
      this.dragged = null
      this.renumber()
      this.persist()
    }
    const onDragOver = (e) => {
      if (!this.dragged || this.dragged === item) return
      e.preventDefault()
      e.dataTransfer.dropEffect = "move"
      const rect = item.getBoundingClientRect()
      const before = (e.clientY - rect.top) < (rect.height / 2)
      this.element.insertBefore(this.dragged, before ? item : item.nextSibling)
    }

    handle.addEventListener("mousedown", onHandleDown)
    handle.addEventListener("touchstart", onHandleDown, { passive: true })
    document.addEventListener("mouseup", onHandleUp)
    document.addEventListener("touchend", onHandleUp)
    item.addEventListener("dragstart", onDragStart)
    item.addEventListener("dragend", onDragEnd)
    item.addEventListener("dragover", onDragOver)

    this.handlers.set(item, { handle, onHandleDown, onHandleUp, onDragStart, onDragEnd, onDragOver })
  }

  detachItem(item) {
    const h = this.handlers.get(item)
    if (!h) return
    h.handle.removeEventListener("mousedown", h.onHandleDown)
    h.handle.removeEventListener("touchstart", h.onHandleDown)
    document.removeEventListener("mouseup", h.onHandleUp)
    document.removeEventListener("touchend", h.onHandleUp)
    item.removeEventListener("dragstart", h.onDragStart)
    item.removeEventListener("dragend", h.onDragEnd)
    item.removeEventListener("dragover", h.onDragOver)
    this.handlers.delete(item)
  }

  // --- behaviour ------------------------------------------------------

  renumber() {
    this.element.querySelectorAll("[data-material-number]").forEach((el, idx) => {
      el.textContent = `${idx + 1}.`
    })
  }

  async persist() {
    const ids = this.items().map((el) => el.dataset.materialId)
    const token = document.querySelector("meta[name=csrf-token]")?.content
    await fetch(this.urlValue, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "Accept": "application/json",
        "X-CSRF-Token": token || ""
      },
      body: JSON.stringify({ ids })
    })
  }
}
