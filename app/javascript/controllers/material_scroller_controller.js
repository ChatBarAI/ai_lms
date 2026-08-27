import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["track", "slide", "previous", "next", "counter", "status"]

  connect() {
    this.currentIndex = 0
    if (typeof ResizeObserver !== "undefined") {
      this.resizeObserver = new ResizeObserver(() => this.updateTrackHeight())
    }
    this.syncNow()
    this.restoreQuizDestination()
  }

  disconnect() {
    window.clearTimeout(this.syncTimeout)
    this.resizeObserver?.disconnect()
    this.stopQuizAlignment()
  }

  previous() {
    if (this.advancing) return
    this.goTo(this.currentIndex - 1)
  }

  async next() {
    if (this.advancing) return

    this.advancing = true
    this.clearStatus()
    this.nextTarget.disabled = true
    this.nextTarget.textContent = "Completing…"

    try {
      const acknowledged = await this.completeCurrentMaterial()
      const isLast = this.currentIndex === this.slideTargets.length - 1

      if (isLast && (acknowledged || this.completionChanged)) {
        const destination = new URL(window.location.href)
        destination.hash = "lesson-quiz"
        window.sessionStorage.setItem("material-scroller-open-quiz", "true")
        window.history.replaceState({}, "", destination)
        window.location.reload()
      } else if (isLast) {
        this.finish()
      } else {
        this.goTo(this.currentIndex + 1)
      }
    } catch (error) {
      this.showStatus("The material could not be marked complete. Please try again.")
    } finally {
      this.advancing = false
      this.updateControls()
    }
  }

  async completeCurrentMaterial() {
    const slide = this.slideTargets[this.currentIndex]
    const url = slide?.dataset.materialScrollerAcknowledgeUrl
    if (!url) return false

    const csrfToken = document.querySelector("meta[name='csrf-token']")?.content
    const response = await fetch(url, {
      method: "POST",
      headers: {
        Accept: "application/json",
        "X-CSRF-Token": csrfToken
      },
      credentials: "same-origin"
    })

    if (!response.ok) throw new Error(`Material acknowledgement failed (${response.status})`)

    this.completionChanged = true
    slide.removeAttribute("data-material-scroller-acknowledge-url")
    this.showCompletedState(slide)
    return true
  }

  showCompletedState(slide) {
    const form = slide.querySelector("form[action*='/acknowledge']")
    if (!form) return

    const completed = document.createElement("span")
    completed.className = "inline-flex items-center gap-1 text-sm text-green-700"
    completed.textContent = "✓ Marked as complete"
    form.replaceWith(completed)
  }

  clearStatus() {
    if (!this.hasStatusTarget) return
    this.statusTarget.textContent = ""
    this.statusTarget.classList.add("hidden")
  }

  showStatus(message) {
    if (!this.hasStatusTarget) return
    this.statusTarget.textContent = message
    this.statusTarget.classList.remove("hidden")
  }

  finish({ behavior = "smooth" } = {}) {
    const quiz = document.getElementById("lesson-quiz")
    const destination = quiz || document.getElementById("lesson-status")
    if (!destination) return

    const collapsible = quiz?.querySelector("[data-controller~='collapsible']")
    const content = collapsible?.querySelector("[data-collapsible-target='content']")
    if (content?.classList.contains("hidden")) {
      collapsible.querySelector("[data-action*='collapsible#toggle']")?.click()
    }

    window.requestAnimationFrame(() => {
      destination.scrollIntoView({ behavior, block: "start" })
    })
  }

  restoreQuizDestination() {
    if (window.location.hash !== "#lesson-quiz") return
    if (window.sessionStorage.getItem("material-scroller-open-quiz") !== "true") return

    window.sessionStorage.removeItem("material-scroller-open-quiz")
    this.quizAlignmentActive = true
    this.realignQuiz = () => {
      if (this.quizAlignmentActive) this.finish({ behavior: "auto" })
    }

    if (typeof ResizeObserver !== "undefined") {
      this.quizLayoutObserver = new ResizeObserver(this.realignQuiz)
      this.quizLayoutObserver.observe(this.element)
    }

    window.addEventListener("load", this.realignQuiz)
    this.realignQuiz()
    document.fonts?.ready.then(this.realignQuiz)
    this.quizAlignmentTimer = window.setTimeout(() => this.stopQuizAlignment(), 3000)
  }

  stopQuizAlignment() {
    this.quizAlignmentActive = false
    this.quizLayoutObserver?.disconnect()
    if (this.realignQuiz) window.removeEventListener("load", this.realignQuiz)
    window.clearTimeout(this.quizAlignmentTimer)
  }

  goTo(index) {
    const boundedIndex = Math.max(0, Math.min(index, this.slideTargets.length - 1))
    const slide = this.slideTargets[boundedIndex]
    if (!slide) return

    this.currentIndex = boundedIndex
    this.updateControls()
    this.observeCurrentSlide()
    this.updateTrackHeight()
    const trackRect = this.trackTarget.getBoundingClientRect()
    const slideRect = slide.getBoundingClientRect()
    const left = this.trackTarget.scrollLeft + slideRect.left - trackRect.left
    this.trackTarget.scrollTo({ left, behavior: "smooth" })
    window.requestAnimationFrame(() => this.scrollActiveSlideIntoView(slide))
  }

  sync() {
    window.clearTimeout(this.syncTimeout)
    this.syncTimeout = window.setTimeout(() => this.syncNow(), 100)
  }

  syncNow() {
    if (!this.hasTrackTarget || this.slideTargets.length === 0) return

    const trackLeft = this.trackTarget.getBoundingClientRect().left
    let closestIndex = 0
    let closestDistance = Infinity

    this.slideTargets.forEach((slide, index) => {
      const distance = Math.abs(slide.getBoundingClientRect().left - trackLeft)
      if (distance < closestDistance) {
        closestDistance = distance
        closestIndex = index
      }
    })

    this.currentIndex = closestIndex
    this.updateControls()
    this.observeCurrentSlide()
    this.updateTrackHeight()
  }

  observeCurrentSlide() {
    if (!this.resizeObserver) return

    this.resizeObserver.disconnect()
    const slide = this.slideTargets[this.currentIndex]
    if (slide) this.resizeObserver.observe(slide)
  }

  updateTrackHeight() {
    if (!this.hasTrackTarget) return

    const slide = this.slideTargets[this.currentIndex]
    if (slide) this.trackTarget.style.height = `${slide.offsetHeight}px`
  }

  scrollActiveSlideIntoView(slide) {
    const margin = 16
    const top = window.scrollY + slide.getBoundingClientRect().top - margin
    window.scrollTo({ top: Math.max(0, top), behavior: "smooth" })
  }

  updateControls() {
    const count = this.slideTargets.length
    const isLast = this.currentIndex === count - 1
    if (this.hasCounterTarget) this.counterTarget.textContent = `${this.currentIndex + 1} of ${count}`
    if (this.hasPreviousTarget) this.previousTarget.disabled = this.currentIndex === 0 || this.advancing
    if (this.hasNextTarget) {
      this.nextTarget.disabled = Boolean(this.advancing)
      if (this.advancing) return
      this.nextTarget.textContent = isLast ? "Done ✓" : "Next →"
      this.nextTarget.setAttribute("aria-label", isLast ? "Finish materials and go to quiz" : "Next material")
    }
  }
}
