import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Commons
import qs.Ui
import "Model.js" as Model

// Click-through tooltip card: what's under the pointer and its shortcuts.
// It appears after the pointer rests (the daemon decides when) on the
// monitor under the pointer, beside it, and disappears as soon as the
// pointer moves. An empty input mask means it can never take a click.
Item {
  id: root

  property var shell: null
  property var manifest: null
  // Overlays receive their plugin's service directly -- never a `bar`.
  property var service: null

  readonly property var svc: service || (shell ? shell.serviceFor("renardoberou.whats-this") : null)
  // A Coach tip wins over a hover card, and shows whether or not hover help
  // is on; it goes away on its own timer (Service), not when the pointer moves.
  readonly property var card: svc ? (svc.tip || (svc.active ? svc.card : null)) : null
  readonly property bool showing: !!card
  readonly property var where: card ? Model.screenAt(Quickshell.screens, card.x, card.y)
                                    : { screen: null, x: 0, y: 0 }

  // Keep the last card's content while it fades out.
  property var shown: null
  onCardChanged: if (card) shown = card

  PanelWindow {
    id: panel
    screen: root.where.screen
    visible: root.showing || box.opacity > 0.001
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "omarchy-whats-this"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore
    mask: Region {}

    readonly property int margin: Style.space(12)
    readonly property int gap: Style.space(20)

    Item {
      id: box
      width: Math.min(Style.space(340), panel.width - 2 * panel.margin)
      height: Math.min(column.implicitHeight + Style.space(18), panel.height - 2 * panel.margin)
      clip: true

      readonly property var spot: Model.placeCard(root.where.x, root.where.y, width, height,
                                                  panel.width, panel.height, panel.gap, panel.margin)
      x: spot.x
      y: spot.y

      opacity: root.showing ? 1.0 : 0.0
      Behavior on opacity { NumberAnimation { duration: 110; easing.type: Easing.OutCubic } }

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
        y: Style.space(9)
        width: parent.width - Style.space(24)
        spacing: Style.space(4)

        Text {
          textFormat: Text.PlainText
          text: root.shown ? root.shown.title : ""
          width: parent.width
          elide: Text.ElideRight
          color: Color.popups.text
          font.family: Style.font.family
          font.pixelSize: Style.font.title
          font.bold: true
        }

        Text {
          visible: !!(root.shown && root.shown.subtitle)
          textFormat: Text.PlainText
          text: root.shown ? root.shown.subtitle : ""
          width: parent.width
          wrapMode: Text.Wrap
          maximumLineCount: 3
          elide: Text.ElideRight
          color: Qt.darker(Color.popups.text, 1.25)
          font.family: Style.font.family
          font.pixelSize: Style.font.bodySmall
        }

        Text {
          visible: !!(root.shown && root.shown.detail)
          textFormat: Text.PlainText
          text: root.shown ? root.shown.detail : ""
          width: parent.width
          elide: Text.ElideMiddle
          color: Qt.darker(Color.popups.text, 1.6)
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
        }

        Repeater {
          model: root.shown ? (root.shown.sections || []) : []

          delegate: Column {
            required property var modelData
            width: column.width
            spacing: Style.space(3)
            topPadding: Style.space(4)

            Text {
              textFormat: Text.PlainText
              text: modelData.heading
              color: Color.accent
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
              font.bold: true
            }

            Repeater {
              model: modelData.rows

              delegate: Row {
                required property var modelData
                width: column.width
                spacing: Style.space(8)

                Row {
                  id: chips
                  spacing: Style.space(3)
                  anchors.verticalCenter: parent.verticalCenter

                  Repeater {
                    model: Model.keyChips(modelData.keys)
                    delegate: Rectangle {
                      required property var modelData
                      width: chipText.implicitWidth + Style.space(8)
                      height: chipText.implicitHeight + Style.space(3)
                      radius: Style.space(3)
                      color: "transparent"
                      border.width: 1
                      border.color: Qt.darker(Color.popups.text, 1.8)

                      Text {
                        id: chipText
                        anchors.centerIn: parent
                        textFormat: Text.PlainText
                        text: modelData
                        color: Color.popups.text
                        font.family: Style.font.family
                        font.pixelSize: Style.font.caption
                      }
                    }
                  }
                }

                Text {
                  anchors.verticalCenter: parent.verticalCenter
                  width: parent.width - chips.width - parent.spacing
                  textFormat: Text.PlainText
                  text: modelData.label
                  elide: Text.ElideRight
                  color: Qt.darker(Color.popups.text, 1.15)
                  font.family: Style.font.family
                  font.pixelSize: Style.font.bodySmall
                }
              }
            }
          }
        }
      }
    }
  }
}
