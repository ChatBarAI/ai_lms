import { Controller } from "@hotwired/stimulus"

// Renders a simple responsive SVG chart. Supports type: "bar" (horizontal),
// "column" (vertical bars), and "line" (line + dots). Designed for small
// datasets typical of an LMS dashboard.
export default class extends Controller {
  static values = {
    type:   { type: String, default: "column" },
    data:   { type: Array,  default: [] },
    color:  { type: String, default: "#4f46e5" },
    max:    { type: Number, default: 0 },
    suffix: { type: String, default: "" }
  }

  connect() {
    this.render()
    this.resizeObserver = new ResizeObserver(() => this.render())
    this.resizeObserver.observe(this.element)
  }

  disconnect() {
    if (this.resizeObserver) this.resizeObserver.disconnect()
  }

  render() {
    const w = this.element.clientWidth
    const h = this.element.clientHeight
    if (!w || !h) return

    const svg = this.svg("svg", {
      width: w, height: h, viewBox: `0 0 ${w} ${h}`,
      xmlns: "http://www.w3.org/2000/svg",
      role: "img", "aria-label": `${this.typeValue} chart`
    })

    switch (this.typeValue) {
      case "bar":    this.renderBar(svg, w, h); break
      case "line":   this.renderLine(svg, w, h); break
      case "column":
      default:       this.renderColumn(svg, w, h); break
    }

    this.element.replaceChildren(svg)
  }

  // --- Renderers --------------------------------------------------------

  renderColumn(svg, w, h) {
    const padL = 36, padR = 8, padT = 8, padB = 28
    const data = this.dataValue
    const maxV = this.computeMax(data)
    const plotW = w - padL - padR
    const plotH = h - padT - padB
    const n = data.length
    const slot = plotW / n
    const barW = Math.max(2, slot * 0.7)

    this.drawAxes(svg, padL, padT, plotW, plotH, maxV)

    data.forEach(([label, value], i) => {
      const v = Math.max(0, value)
      const barH = maxV > 0 ? (v / maxV) * plotH : 0
      const x = padL + i * slot + (slot - barW) / 2
      const y = padT + plotH - barH

      const rect = this.svg("rect", {
        x, y, width: barW, height: barH,
        fill: this.colorValue, rx: 2
      })
      this.appendTitle(rect, `${label}: ${this.fmt(value)}`)
      svg.appendChild(rect)

      const step = n > 10 ? 3 : n > 6 ? 2 : 1
      if (n <= 12 && i % step === 0) {
        const text = this.svg("text", {
          x: x + barW / 2, y: h - padB + 14,
          "text-anchor": "middle", "font-size": 11, fill: "currentColor", opacity: 0.6
        })
        text.textContent = this.formatXLabel(label)
        svg.appendChild(text)
      }
    })
  }

  renderBar(svg, w, h) {
    const padL = 8, padR = 8, padT = 8, padB = 8
    const data = this.dataValue
    const maxV = this.computeMax(data)
    const labelW = Math.min(160, Math.max(60, w * 0.32))
    const valueW = 48
    const plotW = w - padL - padR - labelW - valueW
    const plotH = h - padT - padB
    const n = data.length
    const slot = plotH / n
    const barH = Math.max(4, slot * 0.65)

    data.forEach(([label, value], i) => {
      const v = Math.max(0, value)
      const barW = maxV > 0 ? (v / maxV) * plotW : 0
      const y = padT + i * slot + (slot - barH) / 2

      const lbl = this.svg("text", {
        x: padL + labelW - 6, y: y + barH / 2 + 4,
        "text-anchor": "end", "font-size": 11, fill: "currentColor"
      })
      lbl.textContent = this.shorten(label, 24)
      svg.appendChild(lbl)

      const track = this.svg("rect", {
        x: padL + labelW, y, width: plotW, height: barH,
        fill: "currentColor", opacity: 0.1, rx: 2
      })
      svg.appendChild(track)

      const rect = this.svg("rect", {
        x: padL + labelW, y, width: barW, height: barH,
        fill: this.colorValue, rx: 2
      })
      this.appendTitle(rect, `${label}: ${this.fmt(value)}`)
      svg.appendChild(rect)

      const val = this.svg("text", {
        x: padL + labelW + plotW + 4, y: y + barH / 2 + 4,
        "font-size": 11, fill: "currentColor"
      })
      val.textContent = this.fmt(value)
      svg.appendChild(val)
    })
  }

  renderLine(svg, w, h) {
    const padL = 36, padR = 8, padT = 8, padB = 28
    const data = this.dataValue
    const maxV = this.computeMax(data)
    const plotW = w - padL - padR
    const plotH = h - padT - padB
    const n = data.length

    this.drawAxes(svg, padL, padT, plotW, plotH, maxV)

    if (n === 0) return

    const stepX = n > 1 ? plotW / (n - 1) : 0
    const points = data.map(([_label, value], i) => {
      const v = Math.max(0, value)
      const x = padL + i * stepX
      const y = padT + plotH - (maxV > 0 ? (v / maxV) * plotH : 0)
      return [x, y]
    })

    if (points.length > 1) {
      const d = points.map(([x, y], i) => `${i === 0 ? "M" : "L"} ${x} ${y}`).join(" ")
      svg.appendChild(this.svg("path", {
        d, fill: "none", stroke: this.colorValue, "stroke-width": 2
      }))
    }

    points.forEach(([x, y], i) => {
      const [label, value] = data[i]
      const c = this.svg("circle", {
        cx: x, cy: y, r: 3, fill: this.colorValue
      })
      this.appendTitle(c, `${label}: ${this.fmt(value)}`)
      svg.appendChild(c)
    })

    if (n <= 14) {
      const step = n > 10 ? 3 : n > 6 ? 2 : 1
      data.forEach(([label], i) => {
        if (i % step !== 0) return
        const x = padL + i * stepX
        const text = this.svg("text", {
          x, y: h - padB + 14,
          "text-anchor": "middle", "font-size": 11, fill: "currentColor", opacity: 0.6
        })
        text.textContent = this.formatXLabel(label)
        svg.appendChild(text)
      })
    }
  }

  // --- Helpers ----------------------------------------------------------

  drawAxes(svg, padL, padT, plotW, plotH, maxV) {
    // baseline
    svg.appendChild(this.svg("line", {
      x1: padL, y1: padT + plotH, x2: padL + plotW, y2: padT + plotH,
      stroke: "#e5e7eb"
    }))
    // y-axis
    svg.appendChild(this.svg("line", {
      x1: padL, y1: padT, x2: padL, y2: padT + plotH,
      stroke: "#e5e7eb"
    }))
    // y ticks (0, mid, max)
    const ticks = [ 0, maxV / 2, maxV ]
    ticks.forEach(t => {
      const y = padT + plotH - (maxV > 0 ? (t / maxV) * plotH : 0)
      const txt = this.svg("text", {
        x: padL - 4, y: y + 3,
        "text-anchor": "end", "font-size": 10, fill: "currentColor", opacity: 0.6
      })
      txt.textContent = this.fmt(t)
      svg.appendChild(txt)
    })
  }

  computeMax(data) {
    if (this.maxValue && this.maxValue > 0) return this.maxValue
    const m = data.reduce((acc, [, v]) => Math.max(acc, v || 0), 0)
    return m > 0 ? this.niceCeil(m) : 1
  }

  niceCeil(v) {
    if (v <= 1) return 1
    const pow = Math.pow(10, Math.floor(Math.log10(v)))
    const n = v / pow
    let step
    if (n <= 1) step = 1
    else if (n <= 2) step = 2
    else if (n <= 5) step = 5
    else step = 10
    return step * pow
  }

  fmt(v) {
    const n = Number(v)
    const rounded = Number.isInteger(n) ? n : Math.round(n * 10) / 10
    return `${rounded}${this.suffixValue}`
  }

  formatXLabel(label) {
    const m = String(label).match(/^(\d{4})-(\d{2})-(\d{2})$/)
    if (m) {
      const d = new Date(Number(m[1]), Number(m[2]) - 1, Number(m[3]))
      return d.toLocaleDateString(undefined, { month: "short", day: "numeric" })
    }
    return this.shorten(label, 8)
  }

  shorten(s, n) {
    s = String(s)
    return s.length > n ? s.slice(0, n - 1) + "…" : s
  }

  svg(tag, attrs) {
    const el = document.createElementNS("http://www.w3.org/2000/svg", tag)
    for (const k in attrs) {
      if (attrs[k] !== null && attrs[k] !== undefined) {
        el.setAttribute(k, attrs[k])
      }
    }
    return el
  }

  appendTitle(el, text) {
    const t = this.svg("title", {})
    t.textContent = text
    el.appendChild(t)
  }
}
