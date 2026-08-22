import QtQuick
import QtQuick.Shapes
import qs.Commons

Item {
  id: root

  property real iconSize: Style.bar.iconCanvas
  property color color: Color.foreground
  property color accent: Color.accent
  property bool pulse: false

  width: iconSize
  height: iconSize
  implicitWidth: iconSize
  implicitHeight: iconSize

  readonly property real stroke: Math.max(1.2, iconSize * 0.08)
  readonly property real contact: Math.max(2.0, iconSize * 0.13)
  readonly property color contactColor: root.pulse ? root.accent : root.color

  Behavior on contactColor {
    ColorAnimation { duration: 180 }
  }

  Shape {
    anchors.fill: parent
    antialiasing: true

    ShapePath {
      strokeColor: root.color
      strokeWidth: root.stroke
      capStyle: ShapePath.RoundCap
      fillColor: "transparent"
      startX: root.iconSize * 0.12
      startY: root.iconSize * 0.50
      PathLine { x: root.iconSize * 0.88; y: root.iconSize * 0.50 }
    }

    ShapePath {
      strokeColor: Qt.rgba(root.color.r, root.color.g, root.color.b, 0.35)
      strokeWidth: root.stroke
      capStyle: ShapePath.RoundCap
      fillColor: "transparent"
      startX: root.iconSize * 0.12
      startY: root.iconSize * 0.62
      PathLine { x: root.iconSize * 0.88; y: root.iconSize * 0.62 }
    }

    ShapePath {
      strokeColor: root.contactColor
      strokeWidth: root.stroke
      capStyle: ShapePath.RoundCap
      fillColor: "transparent"
      startX: root.iconSize * 0.50
      startY: root.iconSize * 0.16
      PathLine { x: root.iconSize * 0.50; y: root.iconSize * 0.50 }
    }
  }

  Rectangle {
    width: root.contact
    height: root.contact
    radius: width / 2
    color: root.contactColor
    x: (root.iconSize - width) / 2
    y: root.iconSize * 0.50 - height / 2
  }
}
