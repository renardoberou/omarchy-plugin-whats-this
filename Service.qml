import QtQuick
import Quickshell
import Quickshell.Io
import "Model.js" as Model

// Headless. Owns the toggle (persisted), the help daemon (only while on),
// the keybinding/widget catalog, and the bar widgets' rectangles that the
// bar pill reports. Overlay.qml draws whatever `card` holds.
//
// IPC:
//   omarchy-shell renardoberou.whats-this toggle      # or: on / off
//   omarchy-shell renardoberou.whats-this status | jq
//   omarchy-shell renardoberou.whats-this inspectBar 1690 10   # the card for a bar point
//   omarchy-shell renardoberou.whats-this coachToggle        # or: coachOn / coachOff
//   omarchy-shell renardoberou.whats-this coachReset         # forget what Coach has learned
Item {
  id: root
  property var shell: null

  readonly property string helperDir: Qt.resolvedUrl("bin").toString().replace(/^file:\/\//, "")
  readonly property string daemonPath: helperDir + "/omarchy-whats-this"

  property bool active: false
  property bool stateLoaded: false
  property var catalog: ({ binds: {}, widgets: {} })
  // barKey -> [{m, x, y, w, h, vis}] -- one list per bar (one bar per monitor)
  property var barRects: ({})
  property var card: null
  property int cardSeq: 0

  // Coach: tips when you do something the long way (clicking a workspace
  // on the bar, opening an app from the menu). Its own switch, persisted
  // together with what it has learned.
  property bool coachOn: false
  property bool coachLoaded: false
  property var coachState: Model.coachState(null)
  property var tip: null
  property int tipSeq: 0
  readonly property string coachPath: Quickshell.env("HOME") + "/.local/state/omarchy-whats-this/coach.json"
  readonly property bool daemonWanted: root.stateLoaded && root.coachLoaded && (root.active || root.coachOn)
  property string lastError: ""

  function setActive(on) {
    if (root.active === on) return
    root.active = on
    if (!on) root.card = null
    stateWriter.command = [root.daemonPath, "--state", on ? "on" : "off"]
    stateWriter.running = true
    syncDaemon()
  }

  function setCoach(on) {
    if (root.coachOn === on) return
    root.coachOn = on
    if (!on) root.tip = null
    saveCoach()
    syncDaemon()
  }

  function resetCoach() {
    root.coachState = Model.coachState(null)
    saveCoach()
  }

  function saveCoach() {
    var o = { on: root.coachOn }
    for (var k in root.coachState) o[k] = root.coachState[k]
    coachFile.setText(JSON.stringify(o, null, 2) + "\n")
  }

  // Start, stop or restart the helper so it runs with the modes that are on.
  function syncDaemon() {
    var cmd = [root.daemonPath, "--hover", root.active ? "1" : "0", "--coach", root.coachOn ? "1" : "0"]
    if (daemon.running) {
      if (!root.daemonWanted || String(daemon.command) !== String(cmd)) {
        root.pendingCommand = root.daemonWanted ? cmd : null
        daemon.running = false          // onExited starts it again with the new flags
      }
    } else if (root.daemonWanted) {
      daemon.command = cmd
      daemon.running = true
    }
  }
  property var pendingCommand: null
  onDaemonWantedChanged: syncDaemon()
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
      if (root.active) show(d)
    } else if (d.kind === "coach") {
      if (!root.coachOn) return
      var r = Model.coachDecide(root.coachState, d, root.allBarRects(), root.catalog, Date.now())
      root.coachState = r.state
      saveCoach()
      if (r.tip) {
        root.tip = r.tip
        root.tipSeq++
        tipTimer.restart()
      }
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
    stdout: SplitParser {
      onRead: function(line) { root.handleLine(line) }
    }
    onExited: function(exitCode, exitStatus) {
      root.card = null
      if (root.pendingCommand) {          // stopped by syncDaemon to change modes
        daemon.command = root.pendingCommand
        root.pendingCommand = null
        Qt.callLater(function() { daemon.running = true })
      } else if (root.daemonWanted) {     // died on its own: retry after a pause
        restartTimer.restart()
      }
    }
  }

  Timer {
    id: restartTimer
    interval: 1500
    onTriggered: root.syncDaemon()
  }

  Timer {
    id: tipTimer
    interval: 8000
    onTriggered: root.tip = null
  }

  FileView {
    id: coachFile
    path: root.coachPath
    atomicWrites: true
    printErrors: false
    onLoaded: {
      var o = {}
      try { o = JSON.parse(text()) || {} } catch (e) { o = {} }
      root.coachOn = o.on === true
      root.coachState = Model.coachState(o)
      root.coachLoaded = true
    }
    onLoadFailed: function(error) { root.coachLoaded = true }
  }

  IpcHandler {
    target: "renardoberou.whats-this"
    function toggle(): string { root.toggle(); return root.active ? "on" : "off" }
    function on(): string { root.setActive(true); return "on" }
    function off(): string { root.setActive(false); return "off" }
    // What a card at global (x, y) on the bar would say, without showing it
    // (scripts, tests). Needs it switched on so the bars report their widgets.
    function inspectBar(x: int, y: int): string {
      var hit = Model.barHit(root.allBarRects(), x, y)
      return JSON.stringify(hit ? { widget: hit.m, rect: hit, card: Model.barCard(hit.m, root.catalog) } : null)
    }
    function coachToggle(): string { root.setCoach(!root.coachOn); return root.coachOn ? "coach on" : "coach off" }
    function coachOn(): string { root.setCoach(true); return "coach on" }
    function coachOff(): string { root.setCoach(false); return "coach off" }
    function coachReset(): string { root.resetCoach(); return "coach reset" }
    // Feed Coach an event as if the helper had reported it (testing and
    // scripting): '{"kind":"coach","event":"workspace","name":"2","x":1540,"y":780,"overBar":true}'
    function coachSimulate(eventJson: string): string {
      if (!root.coachOn) return "coach is off"
      root.handleLine(eventJson)
      return root.tip ? root.tip.title : "no tip"
    }
    function coachStatus(): string {
      return JSON.stringify({ on: root.coachOn, state: root.coachState, tip: root.tip, tipSeq: root.tipSeq })
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
