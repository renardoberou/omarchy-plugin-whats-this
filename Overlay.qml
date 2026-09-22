import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import qs.Commons
import qs.Ui
import "Model.js" as Model

// Click-through, always-on-top card that tracks the cursor while Help is
// active. Same layer-shell technique as omarchy-keycaps/Panel.qml: an
// empty `mask` makes the whole full-screen window pass every input event
// through, so this can never intercept a hover/click meant for the app
// underneath -- it only reads cursor position via the daemon's own
// hyprctl polling, never Quickshell's own mouse events.
Item {
  id: root

  property var shell: null
  property var manifest: null
  property var bar: null

  readonly property var svc: bar && bar.shell ? bar.shell.serviceFor("renardoberou.help") : null
  readonly property var hover: svc ? svc.hover : ({ tier: "none", name: "", role: "", detail: "", x: 0, y: 0 })
  readonly property bool showing: !!(svc && svc.active && Model.hasContent(hover))

  readonly property var targetScreen: {
    var monitor = Hyprland.focusedMonitor
    var name = monitor ? String(monitor.name || "") : ""
    var screens = Quickshell.screens || []
    for (var i = 0; i < screens.length; i++) {
      if (String(screens[i].name || "") === name) return screens[i]
    }
    return screens.length > 0 ? screens[0] : null
  }

  PanelWindow {
    id: panel
    screen: root.targetScreen
    visible: root.showing || card.opacity > 0.001
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "omarchy-help"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore
    mask: Region {}

    readonly property int cardWidth: Style.space(280)
    readonly property int margin: Style.space(16)

    Item {
      id: card
      width: panel.cardWidth
      height: column.implicitHeight + Style.space(16)

      x: Math.max(panel.margin, Math.min(root.hover.x + Style.space(18), panel.width - width - panel.margin))
      y: Math.max(panel.margin, Math.min(root.hover.y + Style.space(18), panel.height - height - panel.margin))

      opacity: root.showing ? 1.0 : 0.0
      Behavior on opacity { NumberAnimation { duration: 100; easing.type: Easing.OutCubic } }

      Rectangle {
        anchors.fill: parent
        radius: Style.cornerRadius
        color: Color.popups.background
        border.width: Style.normalBorderWidth
        border.color: Color.popups.border
      }

      Column {
        id: column
        x: Style.space(12)
        y: Style.space(8)
        width: parent.width - Style.space(24)
        spacing: Style.space(3)

        Row {
          width: parent.width
          spacing: Style.space(6)

          Text {
            textFormat: Text.PlainText
            text: Model.tierBadge(root.hover.tier)
            color: Color.accent
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
            font.bold: true
          }

          Text {
            textFormat: Text.PlainText
            text: root.hover.role
            visible: !!root.hover.role
            color: Qt.darker(Color.popups.text, 1.3)
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
          }
        }

        Text {
          textFormat: Text.PlainText
          text: root.hover.name
          width: parent.width
          elide: Text.ElideRight
          color: Color.popups.text
          font.family: Style.font.family
          font.pixelSize: Style.font.title
          font.bold: true
        }

        Text {
          textFormat: Text.PlainText
          text: root.hover.detail
          visible: !!root.hover.detail
          width: parent.width
          wrapMode: Text.Wrap
          maximumLineCount: 4
          elide: Text.ElideRight
          color: Color.popups.text
          font.family: Style.font.family
          font.pixelSize: Style.font.bodySmall
        }
      }
    }
  }
}
