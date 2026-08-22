pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

BarWidget {
  id: root
  moduleName: "io.github.thebenwalther.wiretap"

  property var manifest: null
  property var snapshot: Model.emptySnapshot()
  property var appearedIds: []
  property var newProcessKeys: []
  property bool pulsing: false
  property bool refreshing: false
  property bool usingLastGood: false
  property string lastOutput: ""
  property string lastError: ""
  property int lastExitCode: -1

  readonly property string commandPath: {
    if (manifest && manifest.__sourceDir) return manifest.__sourceDir + "/bin/wiretap"
    var url = String(Qt.resolvedUrl("bin/wiretap"))
    return decodeURIComponent(url.replace(/^file:\/\//, ""))
  }
  readonly property int openPollMs: Math.max(1, Math.min(5, Number(setting("pollOpenSeconds", 2)) || 2)) * 1000
  readonly property int idlePollMs: Math.max(3, Math.min(30, Number(setting("pollIdleSeconds", 5)) || 5)) * 1000
  readonly property bool hideSystem: setting("hideSystem", true) !== false
  readonly property bool hideUnix: setting("hideUnix", true) !== false
  readonly property bool hideUnconnectedUdp: setting("hideUnconnectedUdp", true) !== false
  readonly property bool showListenOnBar: setting("showListenOnBar", false) === true
  readonly property string scope: String(setting("scope", "all") || "all")
  readonly property int internetEstab: Model.internetEstab(root.snapshot)
  readonly property int listenCount: Model.listenCount(root.snapshot)
  readonly property string badgeText: {
    if (root.vertical) return ""
    if (root.internetEstab > 0) return String(root.internetEstab)
    if (root.showListenOnBar && root.listenCount > 0) return "L" + root.listenCount
    return ""
  }
  readonly property bool backendError: root.lastExitCode > 0 && Model.socketCount(root.snapshot) === 0
  readonly property string tooltipLine: {
    if (root.opened) return ""
    if (root.lastError !== "" && root.backendError) return root.lastError
    return Model.tooltip(root.snapshot)
  }

  function snapshotArgs() {
    var args = [root.commandPath, "snapshot"]
    if (!root.hideSystem) args.push("--include-system")
    if (!root.hideUnix) args.push("--include-unix")
    if (!root.hideUnconnectedUdp) args.push("--include-unconnected-udp")
    return args
  }

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    target.bar = root.bar
    target.settings = root.settings
    target.anchorItem = button
    target.hostWidget = root
    target.snapshot = root.snapshot
    target.appearedIds = root.appearedIds
    target.newProcessKeys = root.newProcessKeys
    target.usingLastGood = root.usingLastGood
    target.backendError = root.backendError
    target.backendErrorText = root.lastError
    target.commandPath = root.commandPath
    target.scope = root.scope
    target.hideSystem = root.hideSystem
  }

  function adoptSnapshot(next, fromError) {
    if (!next) return
    var delta = Model.diff(root.snapshot, next)
    root.snapshot = next
    root.appearedIds = delta.appearedIds
    root.newProcessKeys = delta.newProcessKeys
    root.usingLastGood = !!fromError
    if (delta.appearedInternetEstab) {
      root.pulsing = true
      pulseTimer.restart()
    }
    injectPanel()
  }

  function refresh() {
    if (root.commandPath === "" || snapshotProc.running) return
    root.refreshing = true
    root.lastOutput = ""
    root.lastError = ""
    root.lastExitCode = -1
    watchdog.restart()
    snapshotProc.command = root.snapshotArgs()
    snapshotProc.running = true
  }

  function persistSetting(key, value) {
    var entry = { id: root.moduleName }
    for (var name in root.settings) if (name !== "id") entry[name] = root.settings[name]
    entry[key] = value
    root.settings = entry
    if (root.bar && root.bar.shell && typeof root.bar.shell.updateEntryInline === "function")
      root.bar.shell.updateEntryInline(root.moduleName, entry)
  }

  function cycleScope() {
    root.persistSetting("scope", Model.nextScope(root.scope))
  }

  function setScope(value) {
    root.persistSetting("scope", String(value || "all"))
  }

  function toggleHideSystem() {
    root.persistSetting("hideSystem", !root.hideSystem)
    Qt.callLater(root.refresh)
  }

  function open() {
    if (panelLoader.item) panelLoader.item.open()
  }

  function close() {
    if (panelLoader.item) panelLoader.item.close()
  }

  function togglePanel() {
    if (panelLoader.item) panelLoader.item.toggle()
  }

  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false
  readonly property bool popoutSwitchClosing: panelLoader.item ? panelLoader.item.popoutSwitchClosing === true : false
  readonly property real openPanelIndicatorWidth: button.implicitWidth
  readonly property real openPanelIndicatorHeight: Math.max(Style.space(10), Math.round(Style.bar.iconSlot * 0.55))

  function closeForPopoutSwitch() {
    if (panelLoader.item) panelLoader.item.closeForPopoutSwitch()
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onBarChanged: injectPanel()
  onSettingsChanged: injectPanel()
  onManifestChanged: {
    injectPanel()
    Qt.callLater(refresh)
  }
  onHideSystemChanged: Qt.callLater(refresh)
  onHideUnixChanged: Qt.callLater(refresh)
  onHideUnconnectedUdpChanged: Qt.callLater(refresh)

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
  }

  Process {
    id: snapshotProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        root.lastOutput = String(text || "")
        var next = Model.parseSnapshot(root.lastOutput)
        if (next) root.adoptSnapshot(next, false)
      }
    }
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.lastError = String(text || "").trim()
    }
    onExited: function(exitCode) {
      watchdog.stop()
      root.lastExitCode = exitCode
      root.refreshing = false
      if (exitCode > 0) {
        var next = Model.parseSnapshot(root.lastOutput)
        if (next) root.adoptSnapshot(next, true)
        else root.usingLastGood = Model.socketCount(root.snapshot) > 0
        if (root.lastError === "" && next && next.error) root.lastError = String(next.error)
      }
      root.injectPanel()
    }
  }

  Timer {
    id: watchdog
    interval: 750
    repeat: false
    onTriggered: {
      if (!snapshotProc.running) return
      snapshotProc.running = false
      root.refreshing = false
      root.usingLastGood = Model.socketCount(root.snapshot) > 0
      root.lastError = root.lastError || "ss timed out"
      root.injectPanel()
    }
  }

  Timer {
    interval: root.opened ? root.openPollMs : root.idlePollMs
    repeat: true
    running: root.commandPath !== ""
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  Timer {
    id: pulseTimer
    interval: 180
    onTriggered: root.pulsing = false
  }

  IpcHandler {
    target: root.moduleName

    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.togglePanel() }
    function refresh(): string { root.broadcast("refresh"); return "ok" }
    function snapshot(): string { return JSON.stringify(root.snapshot) }
    function debug(): string {
      return JSON.stringify({
        commandPath: root.commandPath,
        refreshing: root.refreshing,
        lastExitCode: root.lastExitCode,
        lastError: root.lastError,
        usingLastGood: root.usingLastGood,
        totals: root.snapshot ? root.snapshot.totals : {}
      })
    }
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    labelVisible: false
    hasVisualContent: true
    horizontalMargin: root.badgeText !== "" ? 10 : 8.5
    tooltipText: root.tooltipLine
    active: root.internetEstab > 0
    activeColor: Color.accent
    fixedWidth: root.vertical ? -1 : Math.ceil(contents.implicitWidth + button.scaledHorizontalMargin * 2)
    fixedHeight: root.vertical ? Style.bar.iconSlot : -1

    onPressed: function(buttonCode) {
      if (buttonCode === Qt.RightButton) root.cycleScope()
      else if (buttonCode === Qt.MiddleButton) root.refresh()
      else root.togglePanel()
    }

    Row {
      id: contents
      anchors.centerIn: parent
      spacing: Style.space(4)

      WiretapIcon {
        iconSize: Style.bar.iconCanvas
        color: button.active && button.useActiveColor ? button.activeColor : button.foreground
        accent: Color.accent
        pulse: root.pulsing
        anchors.verticalCenter: parent.verticalCenter
      }

      Text {
        visible: root.badgeText !== ""
        text: root.badgeText
        color: button.active && button.useActiveColor ? button.activeColor : button.foreground
        font.family: button.fontFamily
        font.pixelSize: Style.font.caption
        font.bold: true
        anchors.verticalCenter: parent.verticalCenter
      }
    }
  }
}
