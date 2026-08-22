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
    { value: "established", label: "Estab" },
    { value: "listening", label: "Listen" },
    { value: "internet", label: "Net" },
    { value: "local", label: "Local" }
  ]
}
