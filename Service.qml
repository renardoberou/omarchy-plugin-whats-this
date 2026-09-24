import QtQuick
import Quickshell.Io
import "Model.js" as Model

// Headless. Owns the toggle (persisted), the help daemon (only while on),
// the keybinding/widget catalog, and the bar widgets' rectangles that the
// bar pill reports. Overlay.qml draws whatever `card` holds.
//
// IPC:
//   omarchy-shell renardoberou.help toggle      # or: on / off
//   omarchy-shell renardoberou.help status | jq
//   omarchy-shell renardoberou.help inspectBar 1690 10   # the card for a bar point
Item {
  id: root
  property var shell: null

  readonly property string helperDir: Qt.resolvedUrl("bin").toString().replace(/^file:\/\//, "")
  readonly property string daemonPath: helperDir + "/omarchy-help-daemon"

  property bool active: false
  property bool stateLoaded: false
  property var catalog: ({ binds: {}, widgets: {} })
  // barKey -> [{m, x, y, w, h, vis}] -- one list per bar (one bar per monitor)
  property var barRects: ({})
  property var card: null
  property int cardSeq: 0
  property string lastError: ""

  function setActive(on) {
    if (root.active === on) return
    root.active = on
    if (!on) root.card = null
    stateWriter.command = [root.daemonPath, "--state", on ? "on" : "off"]
    stateWriter.running = true
  }
  function toggle() { setActive(!root.active) }

  // Called by each bar's pill with the widgets it can see in that bar.
  function setBarRects(key, rects) {
    var next = {}
    for (var k in root.barRects) next[k] = root.barRects[k]
    next[key] = rects
    root.barRects = next
  }

  function allBarRects() {
    var all = []
    for (var k in root.barRects) all = all.concat(root.barRects[k] || [])
    return all
  }

  function show(c) {
    root.card = c
    root.cardSeq++
  }

  function handleLine(line) {
    var d = Model.parseLine(line)
    if (!d) return
    if (d.kind === "catalog") {
      root.catalog = { binds: d.binds || {}, widgets: d.widgets || {} }
    } else if (d.kind === "hide") {
      root.card = null
    } else if (d.kind === "error") {
      root.lastError = d.message || "error"
    } else if (d.kind === "bar") {
      var hit = Model.barHit(root.allBarRects(), d.x, d.y)
      if (!hit) { root.card = null; return }
      var c = Model.barCard(hit.m, root.catalog)
      c.x = d.x; c.y = d.y
      show(c)
    } else if (d.kind === "window" || d.kind === "desktop") {
      show(d)
    }
  }

  Component.onCompleted: {
    stateReader.command = [root.daemonPath, "--state"]
    stateReader.running = true
  }

  Process {
    id: stateReader
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        root.active = text.trim() === "on"
        root.stateLoaded = true
      }
    }
  }

  Process { id: stateWriter }

  Process {
    id: daemon
    command: [root.daemonPath]
    running: root.active && root.stateLoaded
    stdout: SplitParser {
      onRead: function(line) { root.handleLine(line) }
    }
    onExited: function(exitCode, exitStatus) {
      // Runs until stopped; if it dies while Help is on, restart it after a
      // short pause (the `running` binding alone won't re-fire).
      root.card = null
      if (root.active) {
        daemon.running = false
        restartTimer.restart()
      }
    }
  }

  Timer {
    id: restartTimer
    interval: 1500
    onTriggered: if (root.active) daemon.running = true
  }

  IpcHandler {
    target: "renardoberou.help"
    function toggle(): string { root.toggle(); return root.active ? "on" : "off" }
    function on(): string { root.setActive(true); return "on" }
    function off(): string { root.setActive(false); return "off" }
    // What a card at global (x, y) on the bar would say, without showing it
    // (scripts, tests). Needs Help on so the bars report their widgets.
    function inspectBar(x: int, y: int): string {
      var hit = Model.barHit(root.allBarRects(), x, y)
      return JSON.stringify(hit ? { widget: hit.m, rect: hit, card: Model.barCard(hit.m, root.catalog) } : null)
    }
    function status(): string {
      return JSON.stringify({
        active: root.active,
        lastError: root.lastError,
        binds: Object.keys(root.catalog.binds).length,
        widgets: Object.keys(root.catalog.widgets).length,
        barRects: root.allBarRects().length,
        cardSeq: root.cardSeq,
        card: root.card
      })
    }
  }
}
