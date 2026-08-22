import QtQuick
import qs.Commons
import qs.Ui

ButtonGroup {
  id: root

  property color dim: Color.muted

  spacing: Style.space(4)
  fontSize: Style.font.caption
  options: [
    { value: "all", label: "All" },
    { value: "established", label: "Talking" },
    { value: "listening", label: "Waiting" },
    { value: "internet", label: "Internet" },
    { value: "local", label: "This computer" }
  ]
}
