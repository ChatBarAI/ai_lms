import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["course", "lesson", "material", "lessonGroup", "materialGroup", "submit"]
  static values = { catalog: Array, prompts: Object }

  courseChanged() {
    const course = this.catalogValue.find((entry) => String(entry.id) === this.courseTarget.value)
    this.replaceOptions(
      this.lessonTarget,
      course?.lessons || [],
      course ? this.promptsValue.lesson : this.promptsValue.courseFirst
    )
    this.replaceOptions(this.materialTarget, [], this.promptsValue.lessonFirst)
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
      lesson ? this.promptsValue.material : this.promptsValue.lessonFirst,
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
