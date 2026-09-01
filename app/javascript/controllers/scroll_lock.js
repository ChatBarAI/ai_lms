const owners = new Set()

function syncBodyScrollLock() {
  if (!document.body) return

  document.body.classList.toggle("overflow-hidden", owners.size > 0)
}

export function lockBodyScroll(owner) {
  owners.add(owner)
  syncBodyScrollLock()
}

export function unlockBodyScroll(owner) {
  owners.delete(owner)
  syncBodyScrollLock()
}
