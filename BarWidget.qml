import QtQuick
import Quickshell
import qs.Ui
import qs.Commons

BarWidget {
  id: root
  moduleName: "renardoberou.whats-this"

  readonly property var svc: bar && bar.shell ? bar.shell.serviceFor("renardoberou.whats-this") : null
  readonly property bool active: svc ? svc.active : false
  readonly property string tip: active
    ? "What's This — on. Rest the pointer on anything to see what it is and its shortcuts. Click to turn off."
    : "What's This — off. Click, then rest the pointer on a window, the desktop or a bar icon."

  implicitWidth: pillRow.implicitWidth + Style.space(14)
  implicitHeight: barSize

  Row {
    id: pillRow
    anchors.centerIn: parent
    spacing: Style.space(4)

    Text {
      textFormat: Text.PlainText
      text: "󰋗"
      color: root.active ? (root.bar ? root.bar.urgent : Color.urgent)
                         : (root.bar ? root.bar.barForeground : Color.foreground)
      font.family: root.bar ? root.bar.fontFamily : Style.font.family
      font.pixelSize: Style.font.body
      anchors.verticalCenter: parent.verticalCenter
    }
  }

  MouseArea {
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onClicked: if (root.svc) root.svc.toggle()
    onEntered: if (root.bar) root.bar.showTooltip(root, root.tip)
    onExited: if (root.bar) root.bar.hideTooltip(root)
  }

  // Bar-icon help: this pill lives inside the bar, so it can see every
  // widget next to it -- each carries a `moduleName` and knows where it is on
  // screen. While it is on, report this bar's widget rectangles to the
  // service, which hit-tests them when the pointer rests on the bar. (The
  // shell gives plugins no API for this; it relies on bar widgets keeping
  // their `moduleName`, which every Omarchy bar widget has.)
  function barWidgetRects() {
    var top = root, hops = 0
    while (top.parent && hops < 40) { top = top.parent; hops++ }
    var out = [], seen = {}
    // Carry what the parents do to their children: an item that is
    // `visible` can still be invisible on screen -- faded to opacity 0, or
    // outside a parent that clips (the indicators strip keeps every
    // indicator laid out and only shows the active ones).
    function walk(it, depth, alpha, clip) {
      if (!it || depth > 40 || !it.visible) return
      alpha = alpha * (it.opacity === undefined ? 1 : it.opacity)
      if (alpha < 0.05) return
      var g = it.mapToGlobal(0, 0)
      var r = { x: g.x, y: g.y, w: it.width, h: it.height }
      if (clip) {
        var x1 = Math.max(r.x, clip.x), y1 = Math.max(r.y, clip.y)
        var x2 = Math.min(r.x + r.w, clip.x + clip.w), y2 = Math.min(r.y + r.h, clip.y + clip.h)
        r = { x: x1, y: y1, w: Math.max(0, x2 - x1), h: Math.max(0, y2 - y1) }
      }
      if (it.moduleName && r.w > 1 && r.h > 1) {
        var o = { m: String(it.moduleName), x: Math.round(r.x), y: Math.round(r.y),
                  w: Math.round(r.w), h: Math.round(r.h), vis: true }
        var key = o.m + "@" + o.x + "," + o.y + "," + o.w + "," + o.h
        if (!seen[key]) { seen[key] = true; out.push(o) }
      }
      var childClip = it.clip ? r : clip
      if (childClip && (childClip.w <= 0 || childClip.h <= 0)) return
      var kids = it.children || []
      for (var i = 0; i < kids.length; i++) walk(kids[i], depth + 1, alpha, childClip)
    }
    walk(top, 0, 1, null)
    return { key: String(top), rects: out }
  }

  Timer {
    interval: 1500
    repeat: true
    running: root.active
    triggeredOnStart: true
    onTriggered: {
      if (!root.svc) return
      var r = root.barWidgetRects()
      root.svc.setBarRects(r.key, r.rects)
    }
  }
}
