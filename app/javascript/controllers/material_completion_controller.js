import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["form", "button", "status"]
  static values = { completed: String, error: String, reloadOnQuizUnlock: Boolean }

  async submit(event) {
    event.preventDefault()
    try {
      await this.complete()
    } catch (error) {
      this.statusTarget.textContent = this.errorValue
    }
  }

  complete() {
    if (this.completionRequest) return this.completionRequest
    if (!this.hasFormTarget) return Promise.resolve(false)

    this.completionRequest = this.saveCompletion().finally(() => {
      this.completionRequest = null
    })
    return this.completionRequest
  }

  async saveCompletion() {
    const form = this.formTarget
    const button = this.buttonTarget
    button.disabled = true
    this.statusTarget.textContent = ""

    try {
      const response = await fetch(form.action, {
        method: "POST",
        headers: {
          Accept: "application/json",
          "X-CSRF-Token": document.querySelector("meta[name='csrf-token']")?.content
        },
        credentials: "same-origin"
      })
      if (!response.ok) throw new Error(`Material acknowledgement failed (${response.status})`)
      const result = await response.json()
      if (result.acknowledged !== true) throw new Error("Material acknowledgement was not confirmed")

      const completed = document.createElement("span")
      completed.className = "inline-flex items-center gap-1 text-sm text-green-700"
      completed.style.minHeight = `${form.getBoundingClientRect().height}px`
      completed.textContent = this.completedValue
      completed.setAttribute("role", "status")
      form.replaceWith(completed)
      this.dispatch("completed", { detail: { quizUnlocked: result.quiz_unlocked === true } })
      if (this.reloadOnQuizUnlockValue && result.quiz_unlocked === true) {
        this.showUnlockedQuiz()
      } else if (result.progress_changed === true) {
        this.refreshLessonStatus()
      }
      return true
    } finally {
      button.disabled = false
    }
  }

  // The quiz was locked until now, so no answers can be lost by fetching the whole lesson again.
  // "replace" makes Turbo fetch the page instead of only scrolling to the anchor on the same URL.
  showUnlockedQuiz() {
    const url = new URL(window.location.href)
    url.hash = document.getElementById("lesson-quiz") ? "lesson-quiz" : "lesson-status"
    window.Turbo.visit(url.toString(), { action: "replace" })
  }

  // Reload only the progress card so a quiz in progress keeps its answers.
  refreshLessonStatus() {
    const frame = document.getElementById("lesson-status-frame")
    if (!frame) return

    const url = new URL(window.location.href)
    url.hash = ""
    if (frame.getAttribute("src") === url.toString()) {
      frame.reload()
    } else {
      frame.setAttribute("src", url.toString())
    }
  }
}
