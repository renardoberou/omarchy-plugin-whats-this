// node --test tests/*.test.js
const test = require("node:test")
const assert = require("node:assert/strict")
const M = require("../Model.js")

test("key chips read like keys", () => {
  assert.deepEqual(M.keyChips("SUPER SHIFT + RETURN"), ["Super", "Shift", "Return"])
  assert.deepEqual(M.keyChips("SUPER + W"), ["Super", "W"])
  assert.deepEqual(M.keyChips("SUPER SHIFT + 1…0"), ["Super", "Shift", "1–0"])
  assert.deepEqual(M.keyChips("SUPER CTRL + comma"), ["Super", "Ctrl", ","])
  assert.deepEqual(M.keyChips("SUPER + mouse:272"), ["Super", "Left drag"])
  assert.deepEqual(M.keyChips("XF86AudioPlay"), ["Audio Play"])
  assert.deepEqual(M.keyChips(""), [])
})

// Real rectangles reported by the bar on this machine (HDMI bar, y=0).
const rects = [
  { m: "omarchy.indicators", x: 2168, y: 0, w: 105, h: 26, vis: true },
  { m: "Dictation", x: 2168, y: 0, w: 21, h: 26, vis: true },
  { m: "NightLight", x: 2231, y: 0, w: 21, h: 26, vis: true },
  { m: "omarchy.clock", x: 2189, y: 0, w: 53, h: 26, vis: false },
  { m: "omarchy.workspaces", x: 1571, y: 0, w: 106, h: 26, vis: true },
  { m: "omarchy.media", x: 2242, y: 0, w: 0, h: 0, vis: true }
]

test("a tie goes to the more specific widget (strip showing one icon)", () => {
  // real: omarchy.indicators and StayAwake both 21x26 at 2168,0
  const tie = [{ m: "omarchy.indicators", x: 2168, y: 0, w: 21, h: 26, vis: true },
               { m: "StayAwake", x: 2168, y: 0, w: 21, h: 26, vis: true }]
  assert.equal(M.barHit(tie, 2175, 10).m, "StayAwake")
})

test("bar hit-test picks the smallest visible widget under the point", () => {
  assert.equal(M.barHit(rects, 2170, 10).m, "Dictation")     // indicator beats the strip around it
  assert.equal(M.barHit(rects, 2240, 10).m, "NightLight")
  assert.equal(M.barHit(rects, 1600, 10).m, "omarchy.workspaces")
  assert.equal(M.barHit(rects, 2200, 5).m, "omarchy.indicators")  // hidden clock underneath never wins
  assert.equal(M.barHit([{ m: "omarchy.media", x: 2242, y: 0, w: 0, h: 0, vis: true }], 2242, 5), null)  // zero-size never hits
  assert.equal(M.barHit(rects, 3000, 10), null)
})

const catalog = {
  binds: { "Audio": "SUPER CTRL + A", "Switch audio output": "SHIFT + XF86AudioMute",
           "Toggle nightlight": "SUPER CTRL + N", "Next workspace": "SUPER + TAB",
           "Switch to workspace 1": "SUPER + 1", "Switch to workspace 2": "SUPER + 2",
           "Switch to workspace 10": "SUPER + 0", "Define selection": "SUPER ALT + D" },
  widgets: { "omarchy.audio": { name: "Audio", description: "Volume slider, output picker, per-app mixer" },
             "omarchy.workspaces": { name: "Workspaces", description: "Workspace number indicators" },
             "renardoberou.gloss": { name: "Gloss", description: "Look up highlighted words offline." },
             "someone.thing": { name: "Thing", description: "Does a thing" } }
}

test("bar card: catalog description plus the widget's shortcuts", () => {
  const c = M.barCard("omarchy.audio", catalog)
  assert.equal(c.title, "Audio")
  assert.equal(c.subtitle, "Volume slider, output picker, per-app mixer.")
  assert.deepEqual(c.sections[0].rows.map(r => r.label), ["Audio", "Switch audio output"])
})

test("indicator icons have their own names and shortcuts", () => {
  const c = M.barCard("NightLight", catalog)
  assert.equal(c.title, "Night light")
  assert.deepEqual(c.sections[0].rows, [{ keys: "SUPER CTRL + N", label: "Toggle nightlight" }])
})

test("workspaces card collapses the numbered bindings into one row", () => {
  const c = M.barCard("omarchy.workspaces", catalog)
  assert.deepEqual(c.sections[0].rows[0], { keys: "SUPER + 1…0", label: "Switch workspace" })
})

test("third-party widgets use their manifest; no shortcuts is fine", () => {
  const c = M.barCard("someone.thing", catalog)
  assert.equal(c.title, "Thing")
  assert.equal(c.subtitle, "Does a thing.")
  assert.deepEqual(c.sections, [])
  assert.equal(M.barCard("renardoberou.gloss", catalog).sections[0].rows[0].keys, "SUPER ALT + D")
})

test("placement stays on screen and away from the pointer", () => {
  assert.deepEqual(M.placeCard(100, 100, 300, 200, 1536, 864, 20, 12), { x: 120, y: 120 })
  const p = M.placeCard(1500, 840, 300, 200, 1536, 864, 20, 12)
  assert.ok(p.x + 300 <= 1500 && p.y + 200 <= 840)
  const screens = [{ x: 1536, y: 0, width: 1360, height: 768 }, { x: 1474, y: 768, width: 1536, height: 864 }]
  assert.deepEqual([M.screenAt(screens, 1900, 1000).x, M.screenAt(screens, 1900, 1000).y], [426, 232])
})

test("daemon lines parse; junk doesn't", () => {
  assert.equal(M.parseLine('{"kind":"hide"}').kind, "hide")
  assert.equal(M.parseLine("nope"), null)
  assert.equal(M.parseLine('{"x":1}'), null)
})

// ---- Coach ----

const wsRects = [{ m: "omarchy.workspaces", x: 1571, y: 0, w: 106, h: 26, vis: true },
                 { m: "omarchy.clock", x: 2189, y: 0, w: 53, h: 26, vis: true }]
const T0 = Date.UTC(2026, 8, 24, 10, 0, 0)
const click = { kind: "coach", event: "workspace", name: "2", x: 1600, y: 10, overBar: true }
const keys = { kind: "coach", event: "workspace", name: "2", x: 900, y: 500, overBar: false }
const viaMenu = { kind: "coach", event: "app-opened", app: "Ghostty", viaMenu: true,
                  launch: { keys: "SUPER + RETURN", label: "Terminal" }, x: 500, y: 500 }
const direct = Object.assign({}, viaMenu, { viaMenu: false })

test("clicking a workspace on the bar gets the keyboard tip", () => {
  const r = M.coachDecide(null, click, wsRects, catalog, T0)
  assert.equal(r.tip.title, "Switch workspaces from the keyboard")
  assert.deepEqual(r.tip.sections[0].rows[0], { keys: "SUPER + 2", label: "Workspace 2" })
  assert.equal(r.tip.sections[0].rows[1].keys, "SUPER + 1…0")
  assert.equal(r.state.shown.workspace, 1)
})

test("opening an app from the menu gets its launch shortcut", () => {
  const r = M.coachDecide(null, viaMenu, [], catalog, T0)
  assert.equal(r.tip.title, "Open Ghostty in one keystroke")
  assert.deepEqual(r.tip.sections[0].rows, [{ keys: "SUPER + RETURN", label: "Terminal" }])
})

test("tips are spaced out (cooldown) and capped per day", () => {
  let r = M.coachDecide(null, click, wsRects, catalog, T0)
  let r2 = M.coachDecide(r.state, viaMenu, [], catalog, T0 + 60 * 1000)
  assert.equal(r2.tip, null)                                  // 1 min later: too soon
  r2 = M.coachDecide(r.state, viaMenu, [], catalog, T0 + M.COACH.cooldownMs)
  assert.ok(r2.tip)
  let st = r2.state; st.dayCount = M.COACH.maxPerDay
  assert.equal(M.coachDecide(st, click, wsRects, catalog, T0 + 10 * M.COACH.cooldownMs).tip, null)
})

test("a tip is shown at most three times", () => {
  let st = null, n = 0
  for (let i = 0; i < 6; i++) {
    const r = M.coachDecide(st, click, wsRects, catalog, T0 + i * M.COACH.cooldownMs)
    if (r.tip) n++
    st = r.state
  }
  assert.equal(n, M.COACH.maxShows)
})

test("using the shortcut twice retires the tip", () => {
  let r = M.coachDecide(null, keys, wsRects, catalog, T0)
  assert.equal(r.tip, null)
  r = M.coachDecide(r.state, keys, wsRects, catalog, T0 + 1)
  assert.equal(r.state.learned.workspace, 2)
  assert.equal(M.coachDecide(r.state, click, wsRects, catalog, T0 + M.COACH.cooldownMs).tip, null)
  // opening Ghostty without the menu counts for the Terminal tip only
  r = M.coachDecide(null, direct, [], catalog, T0)
  assert.equal(r.state.learned["launch:Terminal"], 1)
})

test("no tip for apps without a launch shortcut, or clicks on other widgets", () => {
  assert.equal(M.coachDecide(null, Object.assign({}, viaMenu, { launch: null }), [], catalog, T0).tip, null)
  const clockClick = Object.assign({}, click, { x: 2200 })
  const r = M.coachDecide(null, clockClick, wsRects, catalog, T0)
  assert.equal(r.tip, null)
  assert.equal(r.state.learned.workspace, undefined)          // not counted as keyboard use either
})

test("the day counter resets on a new day", () => {
  let st = M.coachState({ day: "2026-9-23", dayCount: 8, lastTipAt: 0 })
  assert.ok(M.coachDecide(st, click, wsRects, catalog, T0).tip)
})
