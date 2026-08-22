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

  signal activated()
  signal hovered()

  readonly property string stateName: String(root.connection && root.connection.state || "")
  readonly property color stateColor: {
    if (root.stateName === "estab") return root.foreground
    if (root.stateName === "listen") return root.accent
    return root.dim
  }

  implicitHeight: Math.max(protoChip.implicitHeight, endpoint.implicitHeight) + Style.space(10)
  fill: Util.alpha(accent, root.appeared ? 0.11 : 0.08)
  currentFill: Util.alpha(accent, 0.11)
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
    color: root.accent
    opacity: root.hasCursor ? 1 : 0
    Behavior on opacity { NumberAnimation { duration: 100 } }
  }

  BorderSurface {
    id: protoChip
    anchors.left: parent.left
    anchors.leftMargin: Style.space(28)
    anchors.verticalCenter: parent.verticalCenter
    implicitWidth: protoLabel.implicitWidth + Style.space(8)
    implicitHeight: protoLabel.implicitHeight + Style.space(4)
    radius: Style.cornerRadius
    color: Util.alpha(root.foreground, 0.06)
    borderSpec: Border.none()

    Text {
      id: protoLabel
      anchors.centerIn: parent
      text: Model.protocolLabel(root.connection && root.connection.protocol)
      color: root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      font.bold: true
    }
  }

  Rectangle {
    id: stateDot
    anchors.left: protoChip.right
    anchors.leftMargin: Style.space(8)
    anchors.verticalCenter: parent.verticalCenter
    width: Style.space(6)
    height: Style.space(6)
    radius: width / 2
    color: root.stateColor
  }

  Text {
    id: stateText
    anchors.left: stateDot.right
    anchors.leftMargin: Style.space(6)
    anchors.verticalCenter: parent.verticalCenter
    text: Model.stateLabel(root.stateName)
    color: root.stateColor
    font.family: root.fontFamily
    font.pixelSize: Style.font.caption
    font.bold: true
  }

  Text {
    id: endpoint
    anchors.left: stateText.right
    anchors.leftMargin: Style.space(10)
    anchors.right: classMark.left
    anchors.rightMargin: Style.space(8)
    anchors.verticalCenter: parent.verticalCenter
    text: {
      var conn = root.connection || {}
      var line = Model.formatEndpoint(conn.localAddress, conn.localPort)
        + "  →  "
        + Model.formatEndpoint(conn.remoteAddress, conn.remotePort)
      if (conn.service) line += "  " + conn.service
      if (conn.interface) line += "  " + conn.interface
      return line
    }
    color: root.foreground
    font.family: root.fontFamily
    font.pixelSize: Style.font.caption
    elide: Text.ElideMiddle
  }

  Text {
    id: classMark
    anchors.right: parent.right
    anchors.rightMargin: Style.space(10)
    anchors.verticalCenter: parent.verticalCenter
    text: Model.classLabel(root.connection && root.connection.class)
    color: root.dim
    font.family: root.fontFamily
    font.pixelSize: Style.font.caption
    font.bold: true
  }
}
