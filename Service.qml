import QtQuick
import Quickshell.Io
import "Model.js" as Model

// Headless. Owns the toggle state and the bin/omarchy-help-daemon process
// (only runs while active). BarWidget.qml and Overlay.qml both read this
// service's state via bar.shell.serviceFor("renardoberou.help") and never
// talk to hyprctl/AT-SPI directly themselves.
Item {
  id: root
  property var shell: null

  readonly property string helperDir: Qt.resolvedUrl("bin").toString().replace(/^file:\/\//, "")
  readonly property string daemonPath: helperDir + "/omarchy-help-daemon"

  property bool active: false
  property var hover: ({ tier: "none", name: "", role: "", detail: "", x: 0, y: 0 })

  function toggle() { root.active = !root.active }

  function handleLine(line) {
    root.hover = Model.parseHoverLine(line)
  }

  onActiveChanged: {
    if (!root.active) {
      root.hover = { tier: "none", name: "", role: "", detail: "", x: 0, y: 0 }
    }
  }

  Process {
    id: daemon
    command: [root.daemonPath]
    running: root.active
    stdout: SplitParser {
      onRead: function(line) { root.handleLine(line) }
    }
    onExited: function(exitCode, exitStatus) {
      // The daemon runs an infinite poll loop and shouldn't exit on its
      // own while active -- if it does (crash, killed AT-SPI bridge),
      // force the running:false->true transition QML needs to relaunch it,
      // since the `running: root.active` binding alone won't re-fire when
      // root.active hasn't itself changed.
      if (root.active) {
        daemon.running = false
        Qt.callLater(function() { daemon.running = true })
      }
    }
  }
}
