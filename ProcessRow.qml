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
  property color urgent: Color.urgent

  signal activated()
  signal hovered()

  readonly property string tone: Model.processTone(root.process)
  readonly property color toneColor: {
    if (root.tone === "talking") return root.accent
    if (root.tone === "open" || root.tone === "connecting") return root.urgent
    if (root.tone === "waiting") return root.accent
    return root.foreground
  }

  implicitHeight: Math.max(iconBox.implicitHeight, labels.implicitHeight) + Style.space(12)
  fill: Util.alpha(root.toneColor, root.appeared ? 0.14 : 0.07)
  currentFill: Util.alpha(root.toneColor, 0.12)
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
    color: root.toneColor
    opacity: root.hasCursor || root.tone === "talking" || root.tone === "open" ? 1 : 0
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
    color: Util.alpha(root.toneColor, 0.12)
    borderSpec: Border.flat(Util.alpha(root.toneColor, 0.28), Math.max(1, Style.normalBorderWidth))

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
    anchors.right: parent.right
    anchors.verticalCenter: parent.verticalCenter
    anchors.leftMargin: Style.space(10)
    anchors.rightMargin: Style.space(10)
    spacing: Style.space(2)

    Text {
      width: parent.width
      text: Model.processTitle(root.process)
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.body
      font.bold: true
      elide: Text.ElideRight
    }

    Text {
      width: parent.width
      text: {
        var countText = Model.processCountLabel(root.count)
        var traffic = Model.trafficLabel(root.process)
        return traffic !== "" ? countText + " · " + traffic : countText
      }
      color: root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      elide: Text.ElideRight
    }
  }
}
