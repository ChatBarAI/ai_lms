import { Controller } from "@hotwired/stimulus"

// Hidden inputs move with their rows, so the normal lesson form saves the order.
export default class extends Controller {
  static targets = ["list", "item", "status"]
  static values = { defaultOrder: Array, movedMessage: String, resetMessage: String }

  connect() {
    this.refresh()
  }

  disconnect() {
    this.endDrag()
  }

  move(event) {
    const button = event.currentTarget
    const item = button.closest("[data-section-key]")
    const items = this.itemTargets
    const index = items.indexOf(item)
    const direction = button.dataset.direction
    const neighbor = items[index + (direction === "up" ? -1 : 1)]
    if (!neighbor) return

    if (direction === "up") this.listTarget.insertBefore(item, neighbor)
    else this.listTarget.insertBefore(neighbor, item)

    this.refresh()
    const focusButton = button.disabled
      ? item.querySelector(`button[data-direction='${direction === "up" ? "down" : "up"}']`)
      : button
    focusButton.focus()
    this.announce(item)
  }

  reset() {
    this.endDrag()
    const items = this.itemTargets
    this.defaultOrderValue.forEach(key => {
      const item = items.find(row => row.dataset.sectionKey === key)
      if (item) this.listTarget.appendChild(item)
    })
    this.refresh()
    this.statusTarget.textContent = this.resetMessageValue
  }

  armDrag(event) {
    this.disarmDrag()
    this.armedItem = event.currentTarget.closest("[data-section-key]")
    this.armedItem.draggable = true
  }

  disarmDrag() {
    if (this.armedItem && !this.dragged) {
      this.armedItem.draggable = false
      this.armedItem = null
    }
  }

  startDrag(event) {
    const item = event.target.closest("[data-section-key]")
    if (!item || item !== this.armedItem) {
      event.preventDefault()
      return
    }

    this.dragged = item
    this.originalOrder = this.itemTargets
    this.dropped = false
    item.classList.add("opacity-50")
    event.dataTransfer.effectAllowed = "move"
    event.dataTransfer.setData("text/plain", item.dataset.sectionKey)
  }

  dragOver(event) {
    if (!this.dragged) return
    event.preventDefault()
    event.dataTransfer.dropEffect = "move"
    const item = event.target.closest("[data-section-key]")
    if (!item || item === this.dragged || !this.itemTargets.includes(item)) return

    const rect = item.getBoundingClientRect()
    const before = event.clientY < rect.top + rect.height / 2
    this.listTarget.insertBefore(this.dragged, before ? item : item.nextSibling)
    this.refresh()
  }

  drop(event) {
    if (!this.dragged) return
    event.preventDefault()
    this.dropped = true
    this.announce(this.dragged)
  }

  endDrag() {
    if (this.dragged) {
      if (!this.dropped) this.originalOrder.forEach(item => this.listTarget.appendChild(item))
      this.dragged.classList.remove("opacity-50")
      this.dragged = null
      this.originalOrder = null
    }
    this.disarmDrag()
    this.refresh()
  }

  refresh() {
    const items = this.itemTargets
    items.forEach((item, index) => {
      item.querySelector("[data-section-number]").textContent = `${index + 1}.`
      item.querySelector("button[data-direction='up']").disabled = index === 0
      item.querySelector("button[data-direction='down']").disabled = index === items.length - 1
    })
  }

  announce(item) {
    this.statusTarget.textContent = this.movedMessageValue
      .replace("%{section}", item.dataset.sectionLabel)
      .replace("%{position}", this.itemTargets.indexOf(item) + 1)
      .replace("%{count}", this.itemTargets.length)
  }
}
