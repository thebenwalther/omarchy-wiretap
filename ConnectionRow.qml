pragma ComponentBehavior: Bound

import QtQuick
import qs.Commons
import qs.Ui
import "Model.js" as Model

CursorSurface {
  id: root

  property var connection: ({})
  property bool appeared: false
  property string fontFamily: Style.font.family
  property color dim: Qt.darker(foreground, 1.5)
  property color urgent: Color.urgent

  signal activated()
  signal hovered()

  readonly property string tone: Model.connectionTone(root.connection)
  readonly property color toneColor: {
    if (root.tone === "talking") return root.accent
    if (root.tone === "open" || root.tone === "connecting") return root.urgent
    if (root.tone === "waiting") return root.accent
    if (root.tone === "finishing" || root.tone === "idle") return root.dim
    return root.foreground
  }
  readonly property bool vivid: root.tone === "talking" || root.tone === "open" || root.tone === "connecting"

  implicitHeight: headlines.implicitHeight + Style.space(12)
  fill: Util.alpha(root.toneColor, root.appeared ? 0.14 : 0.06)
  currentFill: Util.alpha(root.toneColor, 0.12)
  bordered: false

  Behavior on color { ColorAnimation { duration: 180 } }

  MouseArea {
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onEntered: root.hovered()
    onClicked: root.activated()
  }

  Rectangle {
    anchors.left: parent.left
    anchors.top: parent.top
    anchors.bottom: parent.bottom
    width: Math.max(2, Style.space(3))
    radius: width / 2
    color: root.toneColor
    opacity: root.hasCursor ? 1 : 0
    Behavior on opacity { NumberAnimation { duration: 100 } }
  }

  Rectangle {
    id: stateDot
    anchors.left: parent.left
    anchors.leftMargin: Style.space(28)
    anchors.verticalCenter: parent.verticalCenter
    width: Style.space(6)
    height: Style.space(6)
    radius: width / 2
    color: root.toneColor
  }

  Column {
    id: headlines
    anchors.left: stateDot.right
    anchors.right: parent.right
    anchors.leftMargin: Style.space(10)
    anchors.rightMargin: Style.space(10)
    anchors.verticalCenter: parent.verticalCenter
    spacing: Style.space(2)

    Text {
      width: parent.width
      text: Model.connectionHeadline(root.connection)
      color: root.vivid ? root.toneColor : root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.body
      elide: Text.ElideRight
    }

    Text {
      visible: Model.connectionDetail(root.connection) !== ""
      width: parent.width
      text: Model.connectionDetail(root.connection)
      color: root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      elide: Text.ElideRight
    }
  }
}
