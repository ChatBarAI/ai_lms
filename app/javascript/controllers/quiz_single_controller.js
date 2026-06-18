import { Controller } from "@hotwired/stimulus"

// Drives the one-at-a-time quiz layout.
// Shows one question slide at a time; prev/next arrows navigate between them.
// Auto-advances to the next unanswered slide on radio selection.
// Enables submit once every question has been answered.
export default class extends Controller {
  static targets = ["slide", "track", "viewport", "submit", "submitContainer", "prevBtn", "nextBtn", "currentIndex", "counter", "hint"]
  static values = { hideProgressWhileCollapsed: Boolean }

  connect() {
    this.current = 0
    this.answered = new Set()
    this._resizeHandler = this._syncViewportHeight.bind(this)
    window.addEventListener("resize", this._resizeHandler)
    this._observePanelVisibility()
    this._disableSubmit()
    this._update()
    requestAnimationFrame(() => this._syncViewportHeight())

    if (this.hideProgressWhileCollapsedValue) this.onCollapsed()
  }

  disconnect() {
    if (this._resizeHandler) window.removeEventListener("resize", this._resizeHandler)
    if (this._panelObserver) this._panelObserver.disconnect()
  }

  onExpanded() {
    if (!this.hideProgressWhileCollapsedValue || !this.hasCounterTarget) return
    this.counterTarget.classList.remove("hidden")
  }

  onCollapsed() {
    if (!this.hideProgressWhileCollapsedValue || !this.hasCounterTarget) return
    this.counterTarget.classList.add("hidden")
  }

  prev() {
    if (this.current > 0) {
      this.current--
      this._update()
      this._focusCurrentTextInput()
    }
  }

  next() {
    if (this.current < this.slideTargets.length - 1) {
      this.current++
      this._update()
      this._focusCurrentTextInput()
    }
  }

  radioChanged(event) {
    const slide = event.target.closest("[data-quiz-single-target='slide']")
    if (!slide) return
    this.answered.add(slide.dataset.questionId)
    this._markDone(slide)

    const next = this._nextUnanswered(this.current + 1)
    if (next !== -1) {
      this.current = next
      this._update()
      this._focusCurrentTextInput()
    } else if (this.answered.size >= this.slideTargets.length) {
      this._enableSubmit()
    }
  }

  tabAdvance(event) {
    if (event.key !== "Tab" || event.shiftKey) return
    event.preventDefault()
    event.currentTarget.click()
  }

  textNext(event) {
    event.preventDefault()
    const slide = event.currentTarget.closest("[data-quiz-single-target='slide']")
    if (!slide) return
    const input = this._freeTextInput(slide)
    if (!input || !input.value.trim()) { input && input.focus(); return }
    this.answered.add(slide.dataset.questionId)
    this._markDone(slide)
    const next = this._nextUnanswered(this.current + 1)
    if (next !== -1) {
      this.current = next
      this._update()
      const nextInput = this._freeTextInput(this.slideTargets[next])
      if (nextInput) nextInput.focus({ preventScroll: true })
    } else if (this.answered.size >= this.slideTargets.length) {
      this._enableSubmit()
    }
  }

  _nextUnanswered(from) {
    for (let i = from; i < this.slideTargets.length; i++) {
      if (!this.answered.has(this.slideTargets[i].dataset.questionId)) return i
    }
    for (let i = 0; i < from; i++) {
      if (!this.answered.has(this.slideTargets[i].dataset.questionId)) return i
    }
    return -1
  }

  _update() {
    const total = this.slideTargets.length
    if (this.hasTrackTarget) {
      this.trackTarget.style.transform = `translateX(-${this.current * 100}%)`
    }
    this._syncViewportHeight()

    if (this.hasCurrentIndexTarget) {
      this.currentIndexTarget.textContent = this.current + 1
    }
    if (this.hasPrevBtnTarget) this.prevBtnTarget.disabled = this.current === 0
    if (this.hasNextBtnTarget) {
      const isLast = this.current === total - 1
      this.nextBtnTarget.disabled = isLast
      this.nextBtnTarget.textContent = isLast ? "Done ✓" : "→"
    }
  }

  _syncViewportHeight(retry = true) {
    if (!this.hasViewportTarget) return
    const activeSlide = this.slideTargets[this.current]
    if (!activeSlide) return
    const height = activeSlide.offsetHeight
    if (height === 0) {
      if (retry) requestAnimationFrame(() => this._syncViewportHeight(false))
      return
    }
    this.viewportTarget.style.height = `${height}px`
  }

  _observePanelVisibility() {
    const panel = this.element.closest("[data-quiz-content-panel]")
    if (!panel || typeof MutationObserver === "undefined") return

    this._panelObserver = new MutationObserver(() => {
      this._syncViewportHeight()
    })
    this._panelObserver.observe(panel, {
      attributes: true,
      attributeFilter: ["class", "style", "hidden"]
    })
  }

  _focusCurrentTextInput() {
    const input = this._freeTextInput(this.slideTargets[this.current])
    if (input) input.focus({ preventScroll: true })
  }

  _freeTextInput(container) {
    return container?.querySelector("textarea[data-free-text-answer='true'], textarea[name^='answers['], input[type='text']")
  }

  _markDone(slide) {
    const checkmark = slide.querySelector("[data-checkmark]")
    if (checkmark) checkmark.classList.remove("hidden")
    slide.querySelector(".border.border-gray-200.rounded-lg")
      ?.classList.add("border-green-300")
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
