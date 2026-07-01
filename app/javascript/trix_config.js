// Trix runs inside Rails forms. The link dialog URL field is an <input>, so pressing
// Enter submits the outer form instead of applying the link.
document.addEventListener(
  "keydown",
  (event) => {
    if (event.key !== "Enter") return
    if (!event.target.closest(".trix-dialog")) return

    event.preventDefault()
  },
  true
)
