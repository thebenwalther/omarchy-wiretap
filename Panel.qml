pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

Panel {
  id: root
  moduleName: "io.github.thebenwalther.wiretap"
  ipcTarget: root.moduleName
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  property var snapshot: Model.emptySnapshot()
  property var appearedIds: []
  property var newProcessKeys: []
  property var expandedKeys: []
  property bool usingLastGood: false
  property bool backendError: false
  property string backendErrorText: ""
  property string commandPath: ""
  property string scope: "all"
  property bool hideSystem: true
  property string query: ""
  property int cursor: 0
  property int phraseIndex: 0
  property double nowMs: Date.now()
  property string copyNotice: ""

  readonly property var phrases: [
    "Watching sockets",
    "Counting listeners",
    "Tracing owners",
    "Sorting wires",
    "Holding the line"
  ]
  readonly property color foreground: Color.popups.text
  readonly property color dim: Qt.darker(foreground, 1.5)
  readonly property color accent: Color.accent
  readonly property color urgent: Color.urgent
  readonly property string fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
  readonly property var rows: Model.visibleRows(root.snapshot, root.query, root.scope, root.expandedKeys, root.appearedIds, root.newProcessKeys)
  readonly property int rowCount: root.rows.length
  readonly property string detailText: {
    if (root.backendError && Model.socketCount(root.snapshot) === 0) return "ERROR"
    if (root.usingLastGood) return "STALE"
    return Model.relativeAge(root.snapshot.generatedAt, root.nowMs) || "…"
  }
  readonly property string statusCaption: {
    if (root.backendError && Model.socketCount(root.snapshot) === 0)
      return root.backendErrorText || "iproute2 ss is not on PATH"
    if (root.usingLastGood) return "Showing last snapshot"
    if (root.copyNotice !== "") return root.copyNotice
    var ms = Model.formatElapsedMs(root.snapshot.elapsedMs)
    return ms !== "" ? "ss · " + ms : "ss"
  }

  function processIcon(proc) {
    var shell = root.bar && root.bar.shell
    var lib = shell && shell.appLibrary
    if (lib && typeof lib.iconSource === "function")
      return lib.iconSource((proc && (proc.desktopHint || proc.displayName)) || "")
    return ""
  }

  function open() {
    if (root.hostWidget && typeof root.hostWidget.refresh === "function") root.hostWidget.refresh()
    root.controller.show()
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function close() {
    root.query = ""
    root.copyNotice = ""
    if (filterField.activeFocus) filterField.focus = false
    root.controller.hide()
  }

  function toggle() {
    root.opened ? root.close() : root.open()
  }

  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root.hostWidget || root, direction)
    return false
  }

  function clampCursor() {
    if (root.rowCount <= 0) {
      root.cursor = 0
      return
    }
    if (root.cursor < 0) root.cursor = 0
    if (root.cursor >= root.rowCount) root.cursor = root.rowCount - 1
  }

  function moveCursor(dx, dy) {
    if (dx !== 0) {
      var row = root.rows[root.cursor]
      if (!row || !row.process) return
      if (dx > 0) root.expandedKeys = Model.withExpanded(root.expandedKeys, row.process.key, true)
      else root.expandedKeys = Model.withExpanded(root.expandedKeys, row.process.key, false)
      return
    }
    if (root.rowCount <= 0) {
      root.cursor = 0
      return
    }
    var next = root.cursor + dy
    if (next < 0) next = root.rowCount - 1
    if (next >= root.rowCount) next = 0
    root.cursor = next
  }

  function activateCursor() {
    var row = root.rows[root.cursor]
    if (!row) return
    if (row.kind === "process") {
      root.expandedKeys = Model.toggleExpanded(root.expandedKeys, row.process.key)
      return
    }
    root.copyValue(Model.connectionCopyText(row.connection))
  }

  function copyCursor() {
    var row = root.rows[root.cursor]
    if (!row) return
    if (row.kind === "connection") root.copyValue(Model.connectionCopyText(row.connection))
    else root.copyValue(Model.processCopyText(row.process))
  }

  function copyValue(text) {
    var value = String(text || "")
    if (value === "") return
    Quickshell.execDetached(["bash", "-c", "printf %s " + Util.shellQuote(value) + " | wl-copy"])
    root.copyNotice = "Copied"
    noticeTimer.restart()
  }

  function copyJson() {
    root.copyValue(Model.snapshotJson(root.snapshot))
  }

  function exportFile() {
    var home = Quickshell.env("HOME")
    if (!home || root.commandPath === "") return
    var path = home + "/Downloads/wiretap-" + Math.floor(Date.now() / 1000) + ".json"
    exportProc.command = root.exportArgs(path)
    exportProc.running = true
    root.copyNotice = "Wrote " + path
    noticeTimer.restart()
  }

  function exportArgs(path) {
    var args = [root.commandPath, "snapshot", "--pretty", "--output", path]
    if (!root.hideSystem) args.push("--include-system")
    if (root.hostWidget && root.hostWidget.hideUnix === false) args.push("--include-unix")
    if (root.hostWidget && root.hostWidget.hideUnconnectedUdp === false) args.push("--include-unconnected-udp")
    return args
  }

  function setScope(value) {
    if (root.hostWidget && typeof root.hostWidget.setScope === "function")
      root.hostWidget.setScope(value)
    else root.scope = value
  }

  function expandAll() {
    root.expandedKeys = Model.allProcessKeys(root.snapshot)
  }

  function collapseAll() {
    root.expandedKeys = []
  }

  function focusFilter() {
    filterField.forceActiveFocus()
  }

  function handleTextKey(text) {
    var raw = String(text || "")
    if (raw === "/") {
      root.focusFilter()
      return
    }
    if (raw === "c" || raw === "C") {
      root.copyCursor()
      return
    }
    if (raw === "e") {
      root.copyJson()
      return
    }
    if (raw === "E") {
      root.exportFile()
      return
    }
    if (raw === "a") {
      root.expandAll()
      return
    }
    if (raw === "A") {
      root.collapseAll()
      return
    }
    if (raw === "r" || raw === "R") {
      if (root.hostWidget) root.hostWidget.refresh()
      return
    }
    if (raw === "s") {
      if (root.hostWidget) root.hostWidget.toggleHideSystem()
      return
    }
    var asNum = parseInt(raw, 10)
    if (asNum >= 1 && asNum <= 5) {
      var next = Model.scopeAt(asNum)
      if (next) root.setScope(next)
    }
  }

  onRowsChanged: root.clampCursor()

  Timer {
    interval: 1000
    repeat: true
    running: root.opened
    triggeredOnStart: true
    onTriggered: root.nowMs = Date.now()
  }

  Timer {
    interval: 8000
    repeat: true
    running: root.opened
    onTriggered: root.phraseIndex = (root.phraseIndex + 1) % root.phrases.length
  }

  Timer {
    id: noticeTimer
    interval: 1600
    onTriggered: root.copyNotice = ""
  }

  Process {
    id: exportProc
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.hostWidget || root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(520))
    contentHeight: panel.fittedContentHeight(contentColumn.implicitHeight, Style.space(560))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: filterField.activeFocus
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onMoveRequested: function(dx, dy) { root.moveCursor(dx, dy) }
      onActivateRequested: root.activateCursor()
      onTextKey: function(text) { root.handleTextKey(text) }

      Flickable {
        id: scroller
        anchors.fill: parent
        contentWidth: width
        contentHeight: contentColumn.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        Column {
          id: contentColumn
          width: parent.width
          spacing: Style.spacing.panelGap

          BorderSurface {
            width: parent.width
            implicitHeight: hero.implicitHeight + Style.space(24)
            radius: Style.cornerRadius
            color: Util.alpha(root.accent, 0.08)
            borderSpec: Border.flat(Util.alpha(root.accent, 0.42), Math.max(1, Style.normalBorderWidth))

            PanelHero {
              id: hero
              anchors.fill: parent
              anchors.margins: Style.space(12)
              foreground: root.foreground
              fontFamily: root.fontFamily
              title: "Wiretap"
              meta: Model.heroMeta(root.snapshot) + " · " + root.phrases[root.phraseIndex % root.phrases.length]
              detail: root.detailText
              iconComponent: Component {
                WiretapIcon {
                  iconSize: Style.space(28)
                  color: root.accent
                  accent: root.accent
                }
              }
            }
          }

          TextField {
            id: filterField
            width: parent.width
            foreground: root.foreground
            accent: root.accent
            placeholderText: "Filter name, pid, port, listen…"
            text: root.query
            onTextChanged: root.query = text
            Keys.onPressed: function(event) {
              if (event.key === Qt.Key_Escape) {
                if (filterField.text !== "") filterField.text = ""
                else keyCatcher.forceActiveFocus()
                event.accepted = true
              } else if (event.key === Qt.Key_Down) {
                keyCatcher.forceActiveFocus()
                root.moveCursor(0, 1)
                event.accepted = true
              }
            }
          }

          ScopeChips {
            id: chips
            width: parent.width
            value: root.scope
            foreground: root.foreground
            background: Color.popups.background
            accent: root.accent
            fontFamily: root.fontFamily
            focusable: false
            onChanged: function(value) { root.setScope(value) }
          }

          Text {
            visible: root.backendError && Model.socketCount(root.snapshot) === 0
            width: parent.width
            text: root.backendErrorText || "iproute2 ss is not on PATH"
            color: root.urgent
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            wrapMode: Text.WordWrap
          }

          Text {
            visible: !root.backendError && root.rowCount === 0 && String(root.query).trim() !== ""
            width: parent.width
            text: "Nothing matches. Clear the filter to see every socket."
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            wrapMode: Text.WordWrap
          }

          Text {
            visible: !root.backendError && root.rowCount === 0 && String(root.query).trim() === "" && Model.socketCount(root.snapshot) === 0 && Number(root.snapshot.generatedAt) > 0
            width: parent.width
            text: "No sockets"
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
          }

          Repeater {
            model: root.rows

            delegate: Item {
              id: rowItem
              required property var modelData
              required property int index
              width: contentColumn.width
              implicitHeight: rowItem.modelData && rowItem.modelData.kind === "connection"
                ? connRow.implicitHeight
                : procRow.implicitHeight
              height: implicitHeight

              ProcessRow {
                id: procRow
                visible: rowItem.modelData && rowItem.modelData.kind === "process"
                width: parent.width
                process: rowItem.modelData && rowItem.modelData.process ? rowItem.modelData.process : ({})
                count: rowItem.modelData ? rowItem.modelData.count : 0
                expanded: rowItem.modelData && rowItem.modelData.process
                  ? Model.isExpanded(root.expandedKeys, rowItem.modelData.process.key)
                  : false
                appeared: rowItem.modelData ? rowItem.modelData.appeared : false
                hasCursor: rowItem.index === root.cursor
                foreground: root.foreground
                accent: root.accent
                dim: root.dim
                fontFamily: root.fontFamily
                iconSource: root.processIcon(rowItem.modelData ? rowItem.modelData.process : null)
                onHovered: root.cursor = rowItem.index
                onActivated: {
                  root.cursor = rowItem.index
                  root.activateCursor()
                }
              }

              ConnectionRow {
                id: connRow
                visible: rowItem.modelData && rowItem.modelData.kind === "connection"
                width: parent.width
                connection: rowItem.modelData && rowItem.modelData.connection ? rowItem.modelData.connection : ({})
                appeared: rowItem.modelData ? rowItem.modelData.appeared : false
                hasCursor: rowItem.index === root.cursor
                foreground: root.foreground
                accent: root.accent
                dim: root.dim
                fontFamily: root.fontFamily
                onHovered: root.cursor = rowItem.index
                onActivated: {
                  root.cursor = rowItem.index
                  root.activateCursor()
                }
              }
            }
          }

          Row {
            width: parent.width
            spacing: Style.space(8)

            Button {
              text: "Expand all"
              foreground: root.foreground
              accent: root.accent
              fontSize: Style.font.caption
              onClicked: root.expandAll()
            }

            Button {
              text: "Collapse"
              foreground: root.foreground
              accent: root.accent
              fontSize: Style.font.caption
              onClicked: root.collapseAll()
            }

            Button {
              text: "Copy JSON"
              foreground: root.foreground
              accent: root.accent
              fontSize: Style.font.caption
              onClicked: root.copyJson()
            }
          }

          Text {
            width: parent.width
            text: root.statusCaption
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }
        }
      }
    }
  }
}
