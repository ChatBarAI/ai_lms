import { Controller } from "@hotwired/stimulus"

// Drives the auto-scrolling one-at-a-time quiz experience on the lesson show page.
// Dims unanswered questions, auto-advances on radio selection, and enables the
// submit button only after every question has been answered.
export default class extends Controller {
  static targets = ["question", "submit", "submitContainer", "progressText"]
  static values = { hideProgressWhileCollapsed: Boolean }

  connect() {
    this.answered = new Set()
    this._disableSubmit()
    this._updateProgress()
    if (this.questionTargets.length > 0) {
      this._focusQuestion(0, { scroll: false })
    }

    // If this quiz is initially collapsed (completed lesson), keep header progress hidden
    // until the user expands the section to retry.
    if (this.hideProgressWhileCollapsedValue) this.onCollapsed()
  }

  onExpanded() {
    if (!this.hideProgressWhileCollapsedValue || !this.hasProgressTextTarget) return
    this.progressTextTarget.classList.remove("hidden")
  }

  onCollapsed() {
    if (!this.hideProgressWhileCollapsedValue || !this.hasProgressTextTarget) return
    this.progressTextTarget.classList.add("hidden")
  }

  // Fired when a radio button (MC or true/false) changes.
  radioChanged(event) {
    const questionEl = event.target.closest("[data-quiz-target='question']")
    if (!questionEl) return
    const qid = questionEl.dataset.questionId
    this.answered.add(qid)
    this._markDone(questionEl)
    this._updateProgress()

    const idx = this.questionTargets.indexOf(questionEl)
    const next = this._nextUnanswered(idx + 1)
    if (next !== -1) {
      setTimeout(() => this._focusQuestion(next), 500)
    } else {
      setTimeout(() => this.submitTarget.scrollIntoView({ behavior: "smooth", block: "center" }), 500)
    }
  }

  tabAdvance(event) {
    if (event.key !== "Tab" || event.shiftKey) return
    event.preventDefault()
    event.currentTarget.click()
  }

  // Fired when the "Next →" button on a free-text question is clicked.
  textNext(event) {
    event.preventDefault()
    const questionEl = event.currentTarget.closest("[data-quiz-target='question']")
    if (!questionEl) return
    const input = this._freeTextInput(questionEl)
    if (!input || !input.value.trim()) {
      input && input.focus()
      return
    }

    const qid = questionEl.dataset.questionId
    this.answered.add(qid)
    this._markDone(questionEl)
    this._updateProgress()

    const idx = this.questionTargets.indexOf(questionEl)
    const next = this._nextUnanswered(idx + 1)
    if (next !== -1) {
      setTimeout(() => this._focusQuestion(next), 200)
    } else {
      setTimeout(() => this.submitTarget.scrollIntoView({ behavior: "smooth", block: "center" }), 200)
    }
  }

  // Returns the index of the next unanswered question, searching forward from
  // `from` then wrapping around. Returns -1 if all are answered.
  _nextUnanswered(from) {
    for (let i = from; i < this.questionTargets.length; i++) {
      if (!this.answered.has(this.questionTargets[i].dataset.questionId)) return i
    }
    for (let i = 0; i < from; i++) {
      if (!this.answered.has(this.questionTargets[i].dataset.questionId)) return i
    }
    return -1
  }

  // Highlights the question at `idx`, dims all others. Scrolls into view unless { scroll: false }.
  _focusQuestion(idx, options = {}) {
    const target = this.questionTargets[idx]
    if (!target) return
    this.questionTargets.forEach((q, i) => {
      const done = this.answered.has(q.dataset.questionId)
      const active = i === idx
      q.classList.toggle("opacity-40", !active && !done)
      q.classList.toggle("ring-2", active)
      q.classList.toggle("ring-indigo-400", active)
      q.classList.toggle("shadow-sm", active)
    })
    if (options.scroll === false) return
    target.scrollIntoView({ behavior: "smooth", block: "center" })
    const textInput = this._freeTextInput(target)
    if (textInput) setTimeout(() => textInput.focus(), 400)
  }

  _freeTextInput(container) {
    return container.querySelector("textarea[data-free-text-answer='true'], textarea[name^='answers['], input[type='text']")
  }

  // Visually marks a question card as answered (green border, ✓ revealed).
  _markDone(questionEl) {
    const checkmark = questionEl.querySelector("[data-checkmark]")
    if (checkmark) checkmark.classList.remove("hidden")
    questionEl.classList.remove("ring-2", "ring-indigo-400", "shadow-sm")
    questionEl.classList.add("border-green-300")
    questionEl.classList.remove("opacity-40")
  }

  _updateProgress() {
    const count = this.answered.size
    const total = this.questionTargets.length
    if (this.hasProgressTextTarget) {
      this.progressTextTarget.textContent = `${count} / ${total} answered`
    }
    // Update each free-text Next button: only the last *remaining* unanswered question shows "Done ✓"
    const unansweredIndices = this.questionTargets
      .map((q, i) => this.answered.has(q.dataset.questionId) ? -1 : i)
      .filter(i => i !== -1)
    const lastUnansweredIdx = unansweredIndices.length > 0 ? unansweredIndices[unansweredIndices.length - 1] : -1
    this.questionTargets.forEach((q, i) => {
      const btn = q.querySelector("button[data-action*='textNext']")
      if (!btn) return
      btn.textContent = (i === lastUnansweredIdx) ? "Done ✓" : "Next →"
    })
    if (count >= total) {
      this._enableSubmit()
    }
  }

  _disableSubmit() {
    if (this.hasSubmitContainerTarget) this.submitContainerTarget.classList.add("hidden")
    if (!this.hasSubmitTarget) return
    this.submitTarget.disabled = true
  }

  _enableSubmit() {
    if (this.hasSubmitContainerTarget) {
      this.submitContainerTarget.classList.remove("hidden")
      this.submitContainerTarget.scrollIntoView({ behavior: "smooth", block: "center" })
    }
    if (!this.hasSubmitTarget) return
    this.submitTarget.disabled = false
  }
}
