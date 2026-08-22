pragma ComponentBehavior: Bound

import QtQuick
import qs.Commons
import qs.Ui
import "Model.js" as Model

CursorSurface {
  id: root

  property var process: ({})
  property int count: 0
  property bool expanded: false
  property bool appeared: false
  property string iconSource: ""
  property string fontFamily: Style.font.family
  property color dim: Qt.darker(foreground, 1.5)

  signal activated()
  signal hovered()

  implicitHeight: Math.max(iconBox.implicitHeight, labels.implicitHeight, trail.implicitHeight) + Style.space(12)
  fill: Util.alpha(accent, root.appeared ? 0.11 : 0.08)
  currentFill: Util.alpha(accent, 0.11)
  bordered: true

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
    id: iconBox
    anchors.left: parent.left
    anchors.leftMargin: Style.space(11)
    anchors.verticalCenter: parent.verticalCenter
    implicitWidth: Style.space(28)
    implicitHeight: Style.space(28)
    radius: Style.cornerRadius
    color: Util.alpha(root.foreground, 0.06)
    borderSpec: Border.flat(Util.alpha(root.foreground, 0.18), Math.max(1, Style.normalBorderWidth))

    Image {
      anchors.centerIn: parent
      width: Style.space(18)
      height: Style.space(18)
      source: root.iconSource
      fillMode: Image.PreserveAspectFit
      smooth: true
      visible: root.iconSource !== ""
    }
  }

  Column {
    id: labels
    anchors.left: iconBox.right
    anchors.right: trail.left
    anchors.verticalCenter: parent.verticalCenter
    anchors.leftMargin: Style.space(10)
    anchors.rightMargin: Style.space(8)
    spacing: Style.space(2)

    Text {
      width: parent.width
      text: String(root.process && root.process.displayName || "unknown")
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.body
      font.bold: true
      elide: Text.ElideRight
    }

    Text {
      width: parent.width
      text: {
        var proc = root.process || {}
        var bits = []
        var pid = Number(proc.pid) || 0
        if (pid > 0) bits.push("pid " + pid)
        if (proc.user) bits.push(String(proc.user))
        if (proc.system) bits.push("system")
        return bits.join(" · ")
      }
      color: root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      elide: Text.ElideRight
    }
  }

  Column {
    id: trail
    anchors.right: parent.right
    anchors.rightMargin: Style.space(10)
    anchors.verticalCenter: parent.verticalCenter
    spacing: Style.space(2)

    BorderSurface {
      anchors.right: parent.right
      implicitWidth: countLabel.implicitWidth + Style.space(10)
      implicitHeight: countLabel.implicitHeight + Style.space(4)
      radius: Style.cornerRadius
      color: "transparent"
      borderSpec: Border.controlSpec("normal", root.foreground, root.accent)

      Text {
        id: countLabel
        anchors.centerIn: parent
        text: String(root.count)
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        font.bold: true
      }
    }

    Text {
      visible: Model.bytePair(root.process) !== ""
      anchors.right: parent.right
      text: Model.bytePair(root.process)
      color: root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
    }
  }
}
