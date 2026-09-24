// Pure logic for What's This: daemon lines, bar-widget hit testing and cards,
// key-chip formatting and card placement. No I/O -- loads in Quickshell and
// in plain node (`node --test tests/*.test.js`).

function parseLine(line) {
  try {
    var d = JSON.parse(String(line || ""))
    return d && typeof d.kind === "string" ? d : null
  } catch (e) {
    return null
  }
}

// ---- keys ------------------------------------------------------------------

var KEY_NAMES = {
  "SUPER": "Super", "SHIFT": "Shift", "CTRL": "Ctrl", "CONTROL": "Ctrl", "ALT": "Alt",
  "RETURN": "Return", "ENTER": "Enter", "SPACE": "Space", "ESCAPE": "Esc", "TAB": "Tab",
  "BACKSPACE": "Backspace", "DELETE": "Del", "Delete": "Del", "PRINT": "Print",
  "HOME": "Home", "END": "End", "LEFT": "←", "RIGHT": "→", "UP": "↑", "DOWN": "↓",
  "comma": ",", "COMMA": ",", "PERIOD": ".", "period": ".", "SLASH": "/", "MINUS": "-",
  "EQUAL": "=", "mouse:272": "Left drag", "mouse:273": "Right drag",
  "mouse_down": "Scroll ↓", "mouse_up": "Scroll ↑"
}

// "SUPER SHIFT + RETURN" -> ["Super", "Shift", "Return"];
// "SUPER + 1…0" -> ["Super", "1–0"]; "XF86AudioPlay" -> ["Audio Play"].
function keyChips(keys) {
  var s = String(keys || "").trim()
  if (!s) return []
  var i = s.lastIndexOf(" + ")
  var mods = i >= 0 ? s.slice(0, i).split(/\s+/) : []
  var key = i >= 0 ? s.slice(i + 3) : s
  function pretty(k) {
    if (KEY_NAMES[k]) return KEY_NAMES[k]
    if (/^XF86/.test(k)) return k.replace(/^XF86/, "").replace(/([a-z])([A-Z])/g, "$1 $2")
    if (k.indexOf("…") >= 0) return k.split("…").map(pretty).join("–")
    return k.length === 1 ? k.toUpperCase() : k.charAt(0) + k.slice(1).toLowerCase()
  }
  return mods.filter(function(m) { return m }).map(pretty).concat([pretty(key)])
}

// ---- bar widgets ------------------------------------------------------------

// The small indicator icons inside omarchy.indicators aren't plugins, so
// they have no catalog entry.
var INDICATORS = {
  "Dictation": { name: "Dictation", description: "Shows while voice dictation is listening.", binds: ["Toggle dictation"] },
  "ScreenRecording": { name: "Screen recording", description: "Shows while the screen is being recorded.", binds: ["Screenrecording"] },
  "Reminder": { name: "Reminder", description: "Shows when a reminder is set.", binds: ["Set reminder", "Show reminders"] },
  "NightLight": { name: "Night light", description: "Shows while the night light is on.", binds: ["Toggle nightlight"] },
  "Dnd": { name: "Do not disturb", description: "Shows while notifications are silenced.", binds: ["Toggle silencing notifications"] },
  "StayAwake": { name: "Stay awake", description: "Shows while locking on idle is off.", binds: ["Toggle locking on idle"] }
}

// Keybindings that go with a bar widget, by binding description.
var WIDGET_BINDS = {
  "omarchy.menu": ["Omarchy menu", "Apps menu"],
  "omarchy.workspaces": ["Next workspace", "Former workspace"],
  "omarchy.audio": ["Audio", "Switch audio output"],
  "omarchy.bluetooth": ["Bluetooth"],
  "omarchy.network": ["Network"],
  "omarchy.power": ["Power", "Toggle power profile"],
  "omarchy.monitor": ["Display", "Toggle nightlight"],
  "omarchy.clock": ["Calendar", "Show time"],
  "omarchy.weather": ["Toggle weather"],
  "omarchy.agents": ["Agent"],
  "omarchy.microphone": ["Mute microphone"],
  "omarchy.media": ["Play", "Next track", "Previous track"],
  "renardoberou.gloss": ["Define selection"]
}

// The widget under (x, y): the smallest visible rectangle containing it, so
// an indicator icon wins over the indicators strip around it. Rectangles
// arrive parents-first, so on a tie (the strip showing exactly one icon is
// the same size as that icon) the later, more specific one wins.
function barHit(rects, x, y) {
  var best = null
  ;(rects || []).forEach(function(r) {
    if (!r || !r.vis || r.w < 2 || r.h < 2) return
    if (x < r.x || x >= r.x + r.w || y < r.y || y >= r.y + r.h) return
    if (!best || r.w * r.h <= best.w * best.h) best = r
  })
  return best
}

function workspaceRow(binds) {
  var nums = []
  for (var d in binds) {
    var m = d.match(/^Switch to workspace (\d+)$/)
    if (m) nums.push([Number(m[1]), binds[d]])
  }
  if (nums.length < 2) return null
  nums.sort(function(a, b) { return a[0] - b[0] })
  var first = nums[0][1], last = nums[nums.length - 1][1]
  var head = first.slice(0, first.lastIndexOf(" + "))
  return { keys: head + " + " + first.slice(first.lastIndexOf(" + ") + 3) + "…" + last.slice(last.lastIndexOf(" + ") + 3),
           label: "Switch workspace" }
}

function barCard(module, catalog) {
  var binds = (catalog && catalog.binds) || {}
  var widgets = (catalog && catalog.widgets) || {}
  var ind = INDICATORS[module]
  var w = widgets[module]
  var name = ind ? ind.name : (w && w.name) || String(module || "Bar")
  var description = ind ? ind.description : (w && w.description) || ""
  if (description && !/[.!?]$/.test(description)) description += "."
  var wanted = ind ? ind.binds : (WIDGET_BINDS[module] || [name])
  var rows = []
  wanted.forEach(function(d) { if (binds[d]) rows.push({ keys: binds[d], label: d }) })
  if (module === "omarchy.workspaces") {
    var ws = workspaceRow(binds)
    if (ws) rows.unshift(ws)
  }
  return {
    kind: "bar", title: name, subtitle: description, detail: "",
    sections: rows.length ? [{ heading: "Shortcuts", rows: rows }] : []
  }
}

// ---- Coach ------------------------------------------------------------------
//
// The daemon reports moments where a shortcut would have done the job --
// clicking a workspace number on the bar, opening an app from the menu --
// and also the same things done without the mouse. This decides: show a
// tip, count the shortcut as used, or stay quiet. A tip retires once its
// shortcut has been used twice, is shown at most three times, and tips are
// spaced out so Coach never nags.

var COACH = { cooldownMs: 3 * 60 * 1000, maxPerDay: 8, maxShows: 3, learnedAfter: 2 }

function coachState(raw) {
  var s = raw && typeof raw === "object" ? raw : {}
  return { learned: s.learned || {}, shown: s.shown || {}, lastTipAt: Number(s.lastTipAt) || 0,
           day: String(s.day || ""), dayCount: Number(s.dayCount) || 0 }
}

function dayOf(ms) {
  var d = new Date(ms)
  return d.getFullYear() + "-" + (d.getMonth() + 1) + "-" + d.getDate()
}

function copyState(st) {
  var o = coachState(JSON.parse(JSON.stringify(st)))
  return o
}

// -> { state, tip } ; tip is null when there's nothing to say
function coachDecide(state, ev, rects, catalog, nowMs) {
  var st = copyState(coachState(state))
  var binds = (catalog && catalog.binds) || {}
  if (st.day !== dayOf(nowMs)) { st.day = dayOf(nowMs); st.dayCount = 0 }
  if (!ev || ev.kind !== "coach") return { state: st, tip: null }

  var key = "", slow = false, tip = null
  if (ev.event === "workspace") {
    key = "workspace"
    var hit = ev.overBar ? barHit(rects, ev.x, ev.y) : null
    if (hit && hit.m === "omarchy.workspaces") {
      slow = true
      var rows = []
      var direct = binds["Switch to workspace " + ev.name]
      if (direct) rows.push({ keys: direct, label: "Workspace " + ev.name })
      var all = workspaceRow(binds)
      if (all) rows.push(all)
      if (binds["Next workspace"]) rows.push({ keys: binds["Next workspace"], label: "Next workspace" })
      tip = { title: "Switch workspaces from the keyboard",
              subtitle: "You clicked workspace " + ev.name + " on the bar. Next time:", rows: rows }
    } else if (ev.overBar) {
      return { state: st, tip: null }       // over some other bar widget: no signal
    }
  } else if (ev.event === "app-opened") {
    if (!ev.launch || !ev.launch.keys) return { state: st, tip: null }
    key = "launch:" + ev.launch.label
    if (ev.viaMenu) {
      slow = true
      tip = { title: "Open " + (ev.app || ev.launch.label) + " in one keystroke",
              subtitle: "You opened it from the menu. Next time:",
              rows: [{ keys: ev.launch.keys, label: ev.launch.label }] }
    }
  } else {
    return { state: st, tip: null }
  }

  if (!slow) {                                // did it the fast way: learning
    st.learned[key] = (st.learned[key] || 0) + 1
    return { state: st, tip: null }
  }
  var eligible = (st.learned[key] || 0) < COACH.learnedAfter &&
                 (st.shown[key] || 0) < COACH.maxShows &&
                 nowMs - st.lastTipAt >= COACH.cooldownMs &&
                 st.dayCount < COACH.maxPerDay &&
                 tip.rows.length > 0
  if (!eligible) return { state: st, tip: null }
  st.shown[key] = (st.shown[key] || 0) + 1
  st.lastTipAt = nowMs
  st.dayCount += 1
  return {
    state: st,
    tip: { kind: "tip", key: key, title: tip.title, subtitle: tip.subtitle,
           detail: "Coach · this tip stops once you've used the shortcut",
           sections: [{ heading: "Shortcut", rows: tip.rows }], x: ev.x, y: ev.y }
  }
}

// ---- placement --------------------------------------------------------------

function screenAt(screens, gx, gy) {
  var list = screens || []
  for (var i = 0; i < list.length; i++) {
    var s = list[i]
    if (gx >= s.x && gx < s.x + s.width && gy >= s.y && gy < s.y + s.height)
      return { screen: s, x: gx - s.x, y: gy - s.y }
  }
  return list.length ? { screen: list[0], x: 0, y: 0 } : { screen: null, x: 0, y: 0 }
}

// Below-right of the pointer like a tooltip; flipped away from edges so it
// never runs off screen or sits under the pointer.
function placeCard(px, py, w, h, aw, ah, gap, margin) {
  var x = px + gap, y = py + gap
  if (x + w > aw - margin) x = px - gap - w
  if (y + h > ah - margin) y = py - gap - h
  x = Math.max(margin, Math.min(x, aw - w - margin))
  y = Math.max(margin, Math.min(y, ah - h - margin))
  return { x: x, y: y }
}

if (typeof module !== "undefined") {
  module.exports = {
    parseLine: parseLine,
    keyChips: keyChips,
    barHit: barHit,
    barCard: barCard,
    workspaceRow: workspaceRow,
    screenAt: screenAt,
    coachDecide: coachDecide,
    coachState: coachState,
    COACH: COACH,
    placeCard: placeCard,
    INDICATORS: INDICATORS
  }
}
