import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["course", "lesson", "material", "lessonGroup", "materialGroup", "submit"]
  static values = { catalog: Array }

  courseChanged() {
    const course = this.catalogValue.find((entry) => String(entry.id) === this.courseTarget.value)
    this.replaceOptions(
      this.lessonTarget,
      course?.lessons || [],
      course ? "Choose a lesson…" : "Choose a course first…"
    )
    this.replaceOptions(this.materialTarget, [], "Choose a lesson first…")
    this.lessonGroupTarget.classList.toggle("hidden", !course)
    this.materialGroupTarget.classList.add("hidden")
    this.submitTarget.disabled = true
  }

  lessonChanged() {
    const course = this.catalogValue.find((entry) => String(entry.id) === this.courseTarget.value)
    const lesson = course?.lessons.find((entry) => String(entry.id) === this.lessonTarget.value)
    this.replaceOptions(
      this.materialTarget,
      lesson?.materials || [],
      lesson ? "Choose a material…" : "Choose a lesson first…",
      true
    )
    this.materialGroupTarget.classList.toggle("hidden", !lesson)
    this.submitTarget.disabled = true
  }

  materialChanged() {
    this.submitTarget.disabled = !this.materialTarget.value
  }

  replaceOptions(select, entries, prompt, includeKind = false) {
    select.replaceChildren(new Option(prompt, ""))
    entries.forEach((entry) => {
      const label = includeKind ? `${entry.title} (${entry.kind})` : entry.title
      select.add(new Option(label, entry.id))
    })
    select.disabled = entries.length === 0
  }
}
