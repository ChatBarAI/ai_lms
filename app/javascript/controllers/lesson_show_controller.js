import { Controller } from "@hotwired/stimulus"

let ytApiReady = false
let ytQueue = []
let ytApiRequested = false

function loadYouTubeAPI() {
  if (ytApiRequested) return
  if (document.querySelector('script[src*="youtube.com/iframe_api"]')) {
    ytApiRequested = true
    return
  }

  ytApiRequested = true
  const script = document.createElement("script")
  script.src = "https://www.youtube.com/iframe_api"
  document.head.appendChild(script)
}

function attachYTPlayer(iframe, onEnded) {
  if (!window.YT || typeof window.YT.Player !== "function") return
  new window.YT.Player(iframe, {
    events: {
      onStateChange: (event) => {
        if (event.data === 0) onEnded()
      }
    }
  })
}

const previousOnYTReady = window.onYouTubeIframeAPIReady
window.onYouTubeIframeAPIReady = function onYouTubeIframeAPIReady() {
  if (typeof previousOnYTReady === "function") previousOnYTReady()
  ytApiReady = true
  ytQueue.forEach(({ iframe, onEnded }) => attachYTPlayer(iframe, onEnded))
  ytQueue = []
}

export default class extends Controller {
  connect() {
    this.bindVideoPosterClickToPlay()
    this.bindNativeVideos()
    this.bindYouTubeIframes()
    this.bindQuizStartButtons()
  }

  smoothScrollSectionIntoView(el, margin = 16) {
    if (!el) return

    const pad = typeof margin === "number" ? margin : 16
    const viewportHeight = window.innerHeight || document.documentElement.clientHeight
    const rect = el.getBoundingClientRect()
    const currentY = window.scrollY || window.pageYOffset
    const sectionTop = currentY + rect.top

    const fullyVisible = rect.top >= pad && rect.bottom <= viewportHeight - pad
    if (fullyVisible) return

    const maxVisibleHeight = viewportHeight - (pad * 2)
    let targetY

    if (rect.height <= maxVisibleHeight) {
      const lowerBound = sectionTop + rect.height - viewportHeight + pad
      const upperBound = sectionTop - pad
      targetY = Math.min(Math.max(currentY, lowerBound), upperBound)
    } else {
      targetY = sectionTop - pad
    }

    window.scrollTo({
      top: Math.max(0, targetY),
      behavior: "smooth"
    })
  }

  scrollToQuiz = () => {
    const quiz = document.getElementById("lesson-quiz")
    this.smoothScrollSectionIntoView(quiz, 16)
  }

  bindNativeVideos() {
    document.querySelectorAll("video").forEach((video) => {
      if (video.dataset.quizScrollBound === "1") return
      video.dataset.quizScrollBound = "1"
      video.addEventListener("ended", this.scrollToQuiz)
    })
  }

  bindYouTubeIframes() {
    let needsApi = false

    document.querySelectorAll('iframe[src*="youtube.com/embed"]').forEach((iframe) => {
      if (iframe.dataset.ytBound === "1") return
      iframe.dataset.ytBound = "1"

      if (ytApiReady) {
        attachYTPlayer(iframe, this.scrollToQuiz)
      } else {
        ytQueue.push({ iframe, onEnded: this.scrollToQuiz })
        needsApi = true
      }
    })

    if (needsApi) loadYouTubeAPI()
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

    el.innerHTML = ""
    el.appendChild(iframe)
    el.classList.remove("cursor-pointer", "group")

    if (src.includes("youtube.com/embed")) {
      iframe.dataset.ytBound = "1"
      if (ytApiReady) {
        attachYTPlayer(iframe, this.scrollToQuiz)
      } else {
        ytQueue.push({ iframe, onEnded: this.scrollToQuiz })
        loadYouTubeAPI()
      }
    }
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
