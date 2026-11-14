import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  connect() {
    this.bindVideoPosterClickToPlay()
    this.bindQuizStartButtons()
  }

  smoothScrollSectionIntoView(el, margin = 16) {
    if (!el) return

    const pad = typeof margin === "number" ? margin : 16
    const headerHeight = document.querySelector(".site-nav")?.getBoundingClientRect().height || 0
    const topPad = headerHeight + pad
    const viewportHeight = window.innerHeight || document.documentElement.clientHeight
    const rect = el.getBoundingClientRect()
    const currentY = window.scrollY || window.pageYOffset
    const sectionTop = currentY + rect.top

    const fullyVisible = rect.top >= topPad && rect.bottom <= viewportHeight - pad
    if (fullyVisible) return

    const maxVisibleHeight = viewportHeight - topPad - pad
    let targetY

    if (rect.height <= maxVisibleHeight) {
      const lowerBound = sectionTop + rect.height - viewportHeight + pad
      const upperBound = sectionTop - topPad
      targetY = Math.min(Math.max(currentY, lowerBound), upperBound)
    } else {
      targetY = sectionTop - topPad
    }

    window.scrollTo({
      top: Math.max(0, targetY),
      behavior: "smooth"
    })
  }

  activatePoster(el) {
    if (el.dataset.activated === "1") return
    const src = el.dataset.iframeSrc
    if (!src) return

    el.dataset.activated = "1"

    const iframe = document.createElement("iframe")
    iframe.src = src
    iframe.className = "absolute inset-0 w-full h-full rounded-lg border border-gray-200"
    iframe.allow = "accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture"
    iframe.setAttribute("allowfullscreen", "true")
    iframe.referrerPolicy = "strict-origin-when-cross-origin"

    el.innerHTML = ""
    el.appendChild(iframe)
    el.classList.remove("cursor-pointer", "group")
  }

  bindVideoPosterClickToPlay() {
    document.querySelectorAll("[data-lesson-video-poster]").forEach((el) => {
      if (el.dataset.bound === "1") return
      el.dataset.bound = "1"
      el.addEventListener("click", () => this.activatePoster(el))
    })
  }

  recalcFreeTextHeights(contentPanel) {
    if (!contentPanel) return
    contentPanel.querySelectorAll("textarea[data-free-text-answer]").forEach((field) => {
      field.style.height = "auto"
      field.style.height = `${field.scrollHeight}px`
    })
  }

  postStartQuiz(startUrl) {
    const csrf = document.querySelector('meta[name="csrf-token"]')
    if (!startUrl || !csrf) return

    fetch(startUrl, {
      method: "POST",
      headers: {
        "X-CSRF-Token": csrf.getAttribute("content"),
        Accept: "application/json"
      },
      credentials: "same-origin"
    })
  }

  bindQuizStartButtons() {
    document.querySelectorAll("[data-quiz-start-button]").forEach((btn) => {
      if (btn.dataset.bound === "1") return
      btn.dataset.bound = "1"

      btn.addEventListener("click", () => {
        const root = document.getElementById("lesson-quiz")
        if (!root) return

        const gatePanel = root.querySelector("[data-quiz-gate-panel]")
        const contentPanel = root.querySelector("[data-quiz-content-panel]")

        if (gatePanel) gatePanel.classList.add("hidden")
        if (contentPanel) contentPanel.classList.remove("hidden")

        this.recalcFreeTextHeights(contentPanel)
        requestAnimationFrame(() => this.smoothScrollSectionIntoView(root, 20))

        this.postStartQuiz(btn.dataset.startUrl)
      })
    })
  }
}
