import assert from "node:assert/strict"
import { readFileSync } from "node:fs"
import test from "node:test"
import vm from "node:vm"

function setup() {
  const calls = []
  const window = Object.assign(new EventTarget(), {
    _bl_ai_search: { init: (_token, _mount, opts) => calls.push(opts) }
  })
  const context = vm.createContext({
    Controller: class {}, window, document: new EventTarget(),
    CustomEvent: class extends Event {
      constructor(name, options) { super(name); this.detail = options.detail }
    }
  })
  const source = readFileSync(new URL("../../app/javascript/controllers/cbai_embed_controller.js", import.meta.url), "utf8")
  const Tutor = vm.runInContext(source.replace(/^import .*\n/gm, "")
    .replace("export default class", "globalThis.Tutor = class"), context)
  const tutor = new Tutor()
  const freshMount = () => ({ dataset: { cbaiToken: "lesson-token", cbaiContext: "Lesson context" } })
  Object.assign(tutor, {
    element: {}, hasMountTarget: true, hasOverlayTarget: true,
    hasOpenButtonTarget: true, openButtonTarget: { disabled: false },
    overlayTarget: { classList: { contains: () => true, remove() {}, add() {} } },
    mountTarget: freshMount(), applyStyle() {}, applyPresentation() {},
    setMicStatus() {}, unlockBody() {},
    destroyTutor() { this.mountTarget = freshMount() },
    ensureMicAccess: async () => ({ ok: true })
  })
  tutor.connect()
  return { tutor, calls }
}

test("each quiz launch gets its own question and regular launch omits EverLink", async () => {
  const { tutor, calls } = setup()
  await tutor.element._cbaiOpenWithEail("Question one")
  await tutor.element._cbaiOpenWithEail("Question two")
  await tutor.openWithMicGate(new Event("click"))
  assert.deepEqual(calls.map(opts => opts.eail), ["Question one", "Question two", undefined])
  assert.equal(Object.hasOwn(calls[2], "eail"), false)
  assert.ok(calls.every(opts => opts.additional_context === "Lesson context"))
})

test("denied microphone access does not queue a quiz query for a regular launch", async () => {
  const { tutor, calls } = setup()
  tutor.ensureMicAccess = async () => ({ ok: false, reason: "blocked" })
  await tutor.element._cbaiOpenWithEail("Question one")
  tutor.ensureMicAccess = async () => ({ ok: true })
  await tutor.openWithMicGate()
  assert.equal(calls.length, 1)
  assert.equal(Object.hasOwn(calls[0], "eail"), false)
})

test("another quiz click during microphone permission cannot overwrite the accepted query", async () => {
  const { tutor, calls } = setup()
  let allow
  tutor.ensureMicAccess = () => new Promise(resolve => { allow = resolve })
  const pending = tutor.element._cbaiOpenWithEail("Question one")
  await tutor.element._cbaiOpenWithEail("Question two")
  allow({ ok: true })
  await pending
  assert.deepEqual(calls.map(opts => opts.eail), ["Question one"])
})

test("closing during a pending mount prevents initialization", async () => {
  const { tutor, calls } = setup()
  const pending = tutor.mountTutor("Question one")
  tutor.close()
  await pending
  assert.equal(calls.length, 0)
})
