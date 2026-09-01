import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

Panel {
  id: root
  moduleName: "evo.github"
  ipcTarget: "evo.github"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  readonly property var barIdentity: hostWidget || root

  readonly property color foreground: Color.foreground
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property color accent: Color.accent
  readonly property color dim: Qt.darker(foreground, 1.4)
  readonly property color surface: Color.popups.background
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property var palette: Model.heatmapColors(accent)

  property bool loading: false
  property var data: null
  property string statusText: ""

  property real shownToday: 0
  property real shownTotal30: 0
  property real shownStreak: 0
  property real shownBest: 0
  property real revealProgress: 0
  property int todayCelebrateToken: 0

  NumberAnimation {
    id: todayCountAnim
    target: root
    property: "shownToday"
    easing.type: Easing.OutCubic
    onFinished: root.todayCelebrateToken++
  }

  Behavior on shownTotal30 {
    enabled: !root.loading
    NumberAnimation { duration: 500; easing.type: Easing.OutCubic }
  }

  Behavior on shownStreak {
    enabled: !root.loading
    NumberAnimation { duration: 500; easing.type: Easing.OutCubic }
  }

  Behavior on shownBest {
    enabled: !root.loading
    NumberAnimation { duration: 500; easing.type: Easing.OutCubic }
  }

  NumberAnimation {
    id: revealAnimation
    target: root
    property: "revealProgress"
    from: 0
    to: 1
    duration: 400
    easing.type: Easing.OutCubic
  }

  readonly property bool hasData: !!(data && data.ok === true)
  readonly property var cells: (data && data.cells instanceof Array) ? data.cells : []
  readonly property bool iconActive: hasData && (data.today || 0) > 0
  readonly property bool iconError: !loading && !hasData && statusText !== ""
  readonly property bool iconBusy: loading
  readonly property bool iconMuted: false
  readonly property string barTooltip: hasData
    ? (data.today + " contribution" + (data.today === 1 ? "" : "s") + " today")
    : "GitHub contributions"

  readonly property int trendsSpacing: 3
  readonly property var trendCells: hasData ? Model.sparkBars(cells, palette, 40) : []
  readonly property string todayLabel: (data && data.today === 1)
    ? "contribution today"
    : "contributions today"
  readonly property color todayIconColor: hasData
    ? Model.contributionColor(data.today, palette)
    : foreground

  readonly property string statusScript: Qt.resolvedUrl("bin/github-status").toString().replace("file://", "")
  readonly property string repoScript: Qt.resolvedUrl("bin/repo-dirty-status").toString().replace("file://", "")
  readonly property string repoSettingsScript: Qt.resolvedUrl("bin/repo-settings").toString().replace("file://", "")
  readonly property string repoCommitScript: Qt.resolvedUrl("bin/repo-agent-commit").toString().replace("file://", "")
  readonly property string repoPushScript: Qt.resolvedUrl("bin/repo-git-push").toString().replace("file://", "")
  readonly property int refreshMinutes: Math.max(5, parseInt(setting("refreshMinutes", 15), 10) || 15)

  property bool repoLoading: true
  property bool repoLoaded: false
  property var repoData: ({ ok: true, repos: [], error: "" })
  property bool repoUnconfigured: false
  property var configuredRepoRoots: []
  property var repoSetupCandidates: []
  property string repoSetupError: ""
  property bool repoSetupSaving: false
  readonly property var repoList: (repoData && repoData.ok === true && repoData.repos instanceof Array)
    ? repoData.repos : []
  readonly property bool repoError: !repoLoading && !(repoData && repoData.ok === true)
  readonly property string repoStatusText: repoData && repoData.error ? String(repoData.error) : ""
  readonly property bool showRepoSection: root.hasData && (
    root.repoLoading || root.repoUnconfigured || root.repoList.length > 0
      || root.configuredRepoRoots.length > 0 || root.repoSetupCandidates.length > 0)
  readonly property string repoCleanMessage: Model.repoCleanMessage(root.configuredRepoRoots)
  property string expandedRepoPath: ""
  readonly property var repoTotals: Model.repoTotals(root.repoList)
  readonly property int dirtyRepoCount: repoTotals.dirtyRepos

  function emptyData() {
    return {
      ok: false,
      today: 0,
      total30: 0,
      streak: 0,
      best: 0,
      username: "",
      profileUrl: "https://github.com/",
      cells: []
    }
  }

  function applyPayload(raw) {
    loading = false
    var parsed = Model.parsePayload(raw)
    data = {
      ok: parsed.ok === true,
      today: parsed.ok ? (parsed.today || 0) : 0,
      total30: parsed.ok ? (parsed.total30 || 0) : 0,
      streak: parsed.ok ? (parsed.streak || 0) : 0,
      best: parsed.ok ? (parsed.best || 0) : 0,
      username: parsed.ok ? (parsed.username || "") : "",
      profileUrl: parsed.ok ? (parsed.profileUrl || "https://github.com/") : "https://github.com/",
      cells: parsed.ok && parsed.cells instanceof Array ? parsed.cells : []
    }
    statusText = parsed.ok ? "" : (parsed.error || "No data")
    syncAnimatedStats()
  }

  function syncAnimatedStats() {
    if (!hasData) {
      todayCountAnim.stop()
      shownToday = 0
      shownTotal30 = 0
      shownStreak = 0
      shownBest = 0
      return
    }

    animateTodayCountTo(data.today || 0, false)
    shownTotal30 = data.total30 || 0
    shownStreak = data.streak || 0
    shownBest = data.best || 0
  }

  function animateTodayCountTo(target, fromZero) {
    var next = Number(target) || 0
    var start = fromZero ? 0 : shownToday
    if (!fromZero && Math.round(start) === Math.round(next)) {
      shownToday = next
      return
    }

    todayCountAnim.stop()
    todayCountAnim.from = fromZero ? 0 : start
    todayCountAnim.to = next
    todayCountAnim.duration = Math.min(1100, Math.max(480, next * 24))
    todayCountAnim.start()
  }

  function refresh(force) {
    refreshGithub(force === true)
    refreshRepos(force === true)
  }

  function refreshGithub(forceRefresh) {
    if (!statusScript || statusProc.running) return
    if (!hasData) loading = true
    var cmd = ["bash", statusScript]
    if (forceRefresh === true) cmd.push("--refresh")
    statusProc.command = cmd
    statusProc.running = true
  }

  function refreshRepos(forceRefresh) {
    if (!repoScript || repoProc.running) return
    if (!repoLoaded) repoLoading = true
    var cmd = ["bash", repoScript]
    if (forceRefresh === true) cmd.push("--refresh")
    repoProc.command = cmd
    repoProc.running = true
  }

  function applyRepoPayload(raw) {
    repoLoading = false
    repoLoaded = true
    var parsed = Model.parseRepoPayload(raw)
    repoUnconfigured = parsed.unconfigured === true
    if (!repoUnconfigured && parsed.repoRoots instanceof Array)
      configuredRepoRoots = parsed.repoRoots
    repoData = {
      ok: parsed.ok === true,
      repos: parsed.ok && parsed.repos instanceof Array ? parsed.repos : [],
      error: parsed.ok ? "" : (parsed.error || "Scan failed")
    }
    if (repoUnconfigured)
      loadRepoSetup()
  }

  function loadRepoSetup() {
    if (!repoSettingsScript || repoSetupProc.running) return
    repoSetupError = ""
    repoSetupProc.command = ["bash", repoSettingsScript, "detect"]
    repoSetupProc.running = true
  }

  function setSetupSelected(index, selected) {
    if (index < 0 || index >= repoSetupCandidates.length) return
    var next = repoSetupCandidates.slice()
    var item = next[index]
    next[index] = {
      path: item.path,
      label: item.label,
      exists: item.exists,
      selected: selected === true
    }
    repoSetupCandidates = next
  }

  function saveRepoRoots() {
    if (!repoSettingsScript || repoSettingsSaveProc.running) return
    var roots = []
    for (var i = 0; i < repoSetupCandidates.length; i++) {
      var item = repoSetupCandidates[i]
      if (item && item.selected === true)
        roots.push({ path: String(item.path || ""), label: String(item.label || "") })
    }
    repoSetupSaving = true
    repoSetupError = ""
    repoSettingsSaveProc.rootsJson = JSON.stringify(roots)
    repoSettingsSaveProc.command = ["bash", repoSettingsScript, "set", repoSettingsSaveProc.rootsJson]
    repoSettingsSaveProc.running = true
  }

  function openRepo(path) {
    var dir = path ? String(path) : ""
    if (!dir) return
    Quickshell.execDetached(["xdg-terminal-exec", "--dir=" + dir])
    root.close()
  }

  function notify(title, body) {
    Quickshell.execDetached([
      "notify-send", "-a", "evo.github", "-t", "5000",
      String(title || "GitHub"), String(body || "")
    ])
  }

  function runRepoAction(script, path, action, repoName) {
    var dir = path ? String(path) : ""
    if (!dir || !script) return
    var name = repoName ? String(repoName) : (dir.split("/").pop() || "repo")
    var body = ""
    if (action === "commit")
      body = "Starting Omarchy agent in " + name
    else if (action === "push")
      body = "Opening git push for " + name
    else
      body = "Opening terminal for " + name
    notify("GitHub", body)
    Quickshell.execDetached(["bash", script, dir])
  }

  function toggleRepoExpand(path) {
    var dir = path ? String(path) : ""
    if (!dir) return
    expandedRepoPath = expandedRepoPath === dir ? "" : dir
  }

  function repoExpanded(path) {
    return expandedRepoPath !== "" && expandedRepoPath === String(path || "")
  }

  function openProfile() {
    var url = data && data.profileUrl ? String(data.profileUrl) : "https://github.com/"
    Quickshell.execDetached(["xdg-open", url])
    root.close()
  }

  function openFromHotkey() {
    var wasOpen = root.opened
    root.controller.show()
    if (wasOpen)
      root.refresh(true)
  }

  function toggle() {
    if (root.opened) root.close()
    else root.openFromHotkey()
  }

  Component.onCompleted: {
    data = emptyData()
    refreshGithub()
    refreshRepos()
  }

  onOpenedChanged: if (opened) {
    refreshGithub(true)
    refreshRepos(true)
    revealProgress = 0
    revealAnimation.restart()
    animateTodayCountTo(hasData ? (data.today || 0) : 0, true)
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  } else {
    expandedRepoPath = ""
  }

  Process {
    id: statusProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var raw = String(text || "").trim()
        if (!raw) {
          root.loading = false
          if (!root.hasData) {
            root.applyPayload('{"class":"error","text":"No data"}')
            root.statusText = "No data"
          }
          return
        }
        root.applyPayload(raw)
      }
    }
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        if (String(text || "").trim() !== "" && !root.hasData)
          root.applyPayload(String(text || ""))
      }
    }
  }

  Timer {
    id: refreshTimer
    interval: root.refreshMinutes * 60 * 1000
    running: true
    repeat: true
    onTriggered: root.refresh()
  }

  Process {
    id: repoProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var raw = String(text || "").trim()
        if (!raw) {
          root.repoLoading = false
          return
        }
        root.applyRepoPayload(raw)
      }
    }
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        if (String(text || "").trim() !== "" && root.repoLoading)
          root.applyRepoPayload('{"ok":false,"error":"' + String(text).replace(/"/g, '\\"') + '"}')
      }
    }
  }

  Process {
    id: repoSetupProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var parsed = Model.parseRepoDetectPayload(String(text || ""))
        if (parsed.ok !== true) {
          root.repoSetupError = parsed.error || "Detect failed"
          root.repoSetupCandidates = []
          return
        }
        root.repoSetupCandidates = parsed.candidates
      }
    }
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        if (String(text || "").trim() !== "")
          root.repoSetupError = String(text || "").trim()
      }
    }
  }

  Process {
    id: repoSettingsSaveProc
    property string rootsJson: "[]"
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        root.repoSetupSaving = false
        var parsed = Model.parseRepoSettingsPayload(String(text || ""))
        if (parsed.ok !== true) {
          root.repoSetupError = parsed.error || "Save failed"
          return
        }
        root.repoUnconfigured = false
        root.configuredRepoRoots = parsed.repoRoots instanceof Array ? parsed.repoRoots : []
        root.repoSetupCandidates = []
        root.refreshRepos(true)
      }
    }
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        root.repoSetupSaving = false
        if (String(text || "").trim() !== "")
          root.repoSetupError = String(text || "").trim()
      }
    }
  }



  IpcHandler {
    target: root.ipcTarget

    function open(): void { root.openFromHotkey() }
    function close(): void { root.close() }
    function show(): void { root.openFromHotkey() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
    function refresh(): string { root.refresh(); return "ok" }
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(380))
    contentHeight: panel.fittedContentHeight(column.implicitHeight, Style.space(640))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function(direction) {
        if (root.bar && typeof root.bar.switchPanelFrom === "function")
          root.bar.switchPanelFrom(root.barIdentity, direction)
      }

      Flickable {
        id: panelFlick
        anchors.fill: parent
        contentWidth: width
        contentHeight: column.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        interactive: contentHeight > height
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        Column {
          id: column
          width: panelFlick.width
          spacing: Style.space(12)

          Text {
            width: parent.width
            visible: root.loading
            text: "Loading contributions…"
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            wrapMode: Text.WordWrap
            horizontalAlignment: Text.AlignHCenter
          }

          Text {
            width: parent.width
            visible: !root.loading && !root.hasData
            text: root.statusText
            color: root.urgent
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            wrapMode: Text.WordWrap
            horizontalAlignment: Text.AlignHCenter
          }

          MouseArea {
            width: parent.width
            visible: !root.loading && root.hasData
            implicitHeight: hero.implicitHeight
            cursorShape: Qt.PointingHandCursor
            onClicked: root.openProfile()

            PanelHero {
              id: hero
              width: parent.width
              title: root.data.username ? ("@" + root.data.username) : "GitHub"
              meta: root.todayLabel
              foreground: root.foreground
              fontFamily: root.fontFamily

              iconComponent: Component {
                Text {
                  text: "󰊤"
                  color: root.todayIconColor
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.display
                  opacity: 0.92
                }
              }

              trailingControl: Component {
                TodayCountBadge {
                  loading: root.loading
                  value: root.shownToday
                  fillColor: root.todayIconColor
                  fontFamily: root.fontFamily
                  celebrateToken: root.todayCelebrateToken
                }
              }
            }
          }

          Row {
            visible: !root.loading && root.hasData
            width: parent.width
            spacing: Style.space(8)

            StatTile {
              width: (parent.width - parent.spacing * 3) / 4
              animatedValue: root.shownTotal30
              label: "30 days"
            }

            StatTile {
              width: (parent.width - parent.spacing * 3) / 4
              animatedValue: root.shownStreak
              streakFormat: true
              label: "streak"
              valueColor: root.data.streak > 0 ? root.accent : root.foreground
            }

            StatTile {
              width: (parent.width - parent.spacing * 3) / 4
              animatedValue: root.shownBest
              showDashWhenZero: true
              label: "best day"
            }

            StatTile {
              width: (parent.width - parent.spacing * 3) / 4
              animatedValue: root.dirtyRepoCount
              label: "dirty repos"
              valueColor: root.urgent
            }
          }

          Column {
            width: parent.width
            spacing: Style.space(4)
            visible: !root.loading && root.hasData

            Item {
              id: trendsTrack
              width: parent.width
              visible: root.cells.length > 0
              implicitHeight: trendsRow.height

              readonly property int cellCount: root.cells.length
              readonly property int cellSize: cellCount > 0
                ? Math.max(7, Math.min(11, Math.floor(
                    (width - Math.max(0, cellCount - 1) * root.trendsSpacing) / cellCount)))
                : 8
              readonly property int rowHeight: cellSize + Style.space(2)
              readonly property int chartWidth: cellCount > 0
                ? cellCount * cellSize + Math.max(0, cellCount - 1) * root.trendsSpacing
                : 0

              Row {
                id: trendsRow
                anchors.horizontalCenter: parent.horizontalCenter
                width: trendsTrack.chartWidth
                spacing: root.trendsSpacing

                Repeater {
                  model: root.cells

                  Item {
                    required property var modelData
                    required property int index
                    readonly property var cell: root.trendCells[index] || {}
                    readonly property bool cellHovered: hitArea.containsMouse
                    readonly property real cellReveal: Math.min(
                      1, Math.max(0, root.revealProgress * trendsTrack.cellCount - index))

                    width: trendsTrack.cellSize
                    height: trendsTrack.rowHeight
                    opacity: cellReveal
                    scale: 0.85 + 0.15 * cellReveal
                    transformOrigin: Item.Bottom

                    Rectangle {
                      width: trendsTrack.cellSize
                      height: trendsTrack.cellSize
                      anchors.bottom: parent.bottom
                      anchors.horizontalCenter: parent.horizontalCenter
                      radius: 1
                      color: parent.cell.color || root.palette[0]
                      opacity: parent.cellHovered ? 1 : ((parent.cell.value || 0) > 0 ? 0.92 : 0.55)
                      scale: parent.cellHovered ? 1.12 : 1
                      transformOrigin: Item.Center

                      Behavior on scale {
                        NumberAnimation { duration: 90; easing.type: Easing.OutCubic }
                      }
                    }

                    MouseArea {
                      id: hitArea
                      anchors.fill: parent
                      hoverEnabled: true
                      acceptedButtons: Qt.NoButton
                    }
                  }
                }
              }
            }

            Text {
              width: parent.width
              visible: root.cells.length === 0
              text: "No activity data"
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              horizontalAlignment: Text.AlignHCenter
            }
          }

          PanelSeparator {
            visible: root.showRepoSection
            foreground: root.foreground
          }

          PanelSectionHeader {
            visible: root.showRepoSection
            width: parent.width
            text: "LOCAL REPOS"
            foreground: root.foreground
            fontFamily: root.fontFamily
          }

          Text {
            width: parent.width
            visible: root.repoLoading
            text: "Scanning repos…"
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            horizontalAlignment: Text.AlignHCenter
          }

          Text {
            width: parent.width
            visible: root.repoError
            text: root.repoStatusText
            color: root.urgent
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.WordWrap
            horizontalAlignment: Text.AlignHCenter
          }

          Column {
            width: parent.width
            visible: root.repoUnconfigured && !root.repoLoading && !root.repoError
            spacing: Style.space(8)

            Text {
              width: parent.width
              text: "Choose folders to scan for dirty repos"
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              wrapMode: Text.WordWrap
            }

            Repeater {
              model: root.repoSetupCandidates

              CheckBox {
                required property var modelData
                required property int index
                width: parent.width
                text: "~/" + (modelData.label || "")
                checked: modelData.selected === true
                enabled: !root.repoSetupSaving
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
                onCheckedChanged: if (checked !== (modelData.selected === true))
                  root.setSetupSelected(index, checked)
              }
            }

            Text {
              width: parent.width
              visible: root.repoSetupCandidates.length === 0 && root.repoSetupError === ""
              text: "No ~/projects, ~/Projects, ~/work, or ~/Work folders found. Add paths in shell.json or run omarchy bar set evo.github repoRoots."
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              wrapMode: Text.WordWrap
            }

            Text {
              width: parent.width
              visible: root.repoSetupError !== ""
              text: root.repoSetupError
              color: root.urgent
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              wrapMode: Text.WordWrap
            }

            MouseArea {
              width: saveRepoRootsLabel.implicitWidth + Style.space(12)
              height: saveRepoRootsLabel.implicitHeight + Style.space(8)
              enabled: !root.repoSetupSaving
              hoverEnabled: true
              cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
              onClicked: root.saveRepoRoots()

              Text {
                id: saveRepoRootsLabel
                anchors.centerIn: parent
                text: root.repoSetupSaving ? "Saving…" : "Save folders"
                color: parent.enabled && parent.containsMouse ? root.accent : root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
                font.bold: true
              }
            }
          }

          Text {
            width: parent.width
            visible: !root.repoLoading && !root.repoError && !root.repoUnconfigured && root.repoList.length === 0
            text: root.repoCleanMessage
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            horizontalAlignment: Text.AlignHCenter
          }

          Column {
            id: repoColumn
            width: parent.width
            visible: !root.repoLoading && !root.repoError && !root.repoUnconfigured && root.repoList.length > 0
            spacing: Style.space(4)

            Repeater {
              model: root.repoList

              Item {
                required property var modelData
                readonly property bool repoOpen: root.repoExpanded(modelData.path)
                width: repoColumn.width
                implicitHeight: repoCard.implicitHeight

                Rectangle {
                  id: repoCard
                  width: parent.width
                  implicitHeight: repoCardColumn.implicitHeight + Style.space(8)
                  radius: Style.cornerRadius
                  color: (repoHeaderHit.containsMouse || root.repoExpanded(modelData.path))
                    ? Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.08)
                    : "transparent"

                  Column {
                    id: repoCardColumn
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.leftMargin: Style.space(4)
                    anchors.rightMargin: Style.space(4)
                    anchors.topMargin: Style.space(4)
                    spacing: Style.spacing.labelGap

                    Item {
                      id: repoHeader
                      width: parent.width
                      implicitHeight: repoHeaderLayout.implicitHeight

                      RowLayout {
                        id: repoHeaderLayout
                        width: parent.width
                        spacing: Style.space(8)

                        ColumnLayout {
                          Layout.fillWidth: true
                          Layout.alignment: Qt.AlignVCenter
                          spacing: Style.spacing.labelGap

                          Text {
                            Layout.fillWidth: true
                            text: modelData.name || ""
                            color: (repoHeaderHit.containsMouse || root.repoExpanded(modelData.path))
                              ? root.accent : root.foreground
                            font.family: root.fontFamily
                            font.pixelSize: Style.font.bodySmall
                            font.bold: true
                            elide: Text.ElideRight
                          }

                          Text {
                            Layout.fillWidth: true
                            text: "~/" + (modelData.parent || "projects") + "/" + (modelData.name || "")
                            color: root.dim
                            font.family: root.fontFamily
                            font.pixelSize: Style.font.caption
                            elide: Text.ElideRight
                          }
                        }

                        RowLayout {
                          Layout.alignment: Qt.AlignVCenter
                          spacing: Style.spacing.xs

                          StatusPill {
                            visible: modelData.unstaged === true
                            text: Model.unstagedPillLabel(modelData.dirtyCount)
                            textColor: root.urgent
                            foreground: root.foreground
                            fontFamily: root.fontFamily
                          }

                          StatusPill {
                            visible: (parseInt(modelData.unpushed, 10) || 0) > 0
                            text: Model.unpushedPillLabel(modelData.unpushed)
                            textColor: root.accent
                            foreground: root.foreground
                            fontFamily: root.fontFamily
                          }
                        }
                      }

                      MouseArea {
                        id: repoHeaderHit
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.toggleRepoExpand(modelData.path)
                      }
                    }

                    Item {
                      id: repoDetailsClip
                      width: parent.width
                      height: repoOpen ? detailsColumn.implicitHeight : 0
                      clip: true

                      Behavior on height {
                        NumberAnimation { duration: 260; easing.type: Easing.OutCubic }
                      }

                      Column {
                        id: detailsColumn
                        width: parent.width
                        spacing: Style.spacing.labelGap
                        topPadding: Style.space(2)
                        bottomPadding: Style.space(2)
                        y: repoOpen ? 0 : -Style.space(6)
                        opacity: repoOpen ? 1 : 0

                        Behavior on y {
                          NumberAnimation { duration: 260; easing.type: Easing.OutCubic }
                        }

                        Behavior on opacity {
                          NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
                        }

                        Repeater {
                          model: Model.repoDetailItems(modelData)

                          Row {
                            required property var modelData
                            width: parent.width
                            spacing: Style.space(8)

                            Text {
                              width: Style.space(72)
                              text: modelData.label
                              color: root.dim
                              font.family: root.fontFamily
                              font.pixelSize: Style.font.caption
                            }

                            Text {
                              width: parent.width - Style.space(72) - parent.spacing
                              text: modelData.value
                              color: root.foreground
                              font.family: root.fontFamily
                              font.pixelSize: Style.font.caption
                              wrapMode: Text.Wrap
                            }
                          }
                        }

                        Row {
                          width: parent.width
                          spacing: Style.space(2)
                          topPadding: Style.space(4)

                          RepoIconButton {
                            icon: "󰜘"
                            tooltip: "Commit with agent"
                            visible: modelData.unstaged === true
                            iconColor: root.urgent
                            onClicked: root.runRepoAction(root.repoCommitScript, modelData.path, "commit", modelData.name)
                          }

                          RepoIconButton {
                            icon: "󰁝"
                            tooltip: "Push"
                            visible: (parseInt(modelData.unpushed, 10) || 0) > 0
                            onClicked: root.runRepoAction(root.repoPushScript, modelData.path, "push", modelData.name)
                          }

                          RepoIconButton {
                            icon: "󰆍"
                            tooltip: "Open in terminal"
                            onClicked: root.openRepo(modelData.path)
                          }
                        }
                      }
                    }
                  }
                }
              }
            }
          }
        }
      }
    }
  }

  component RepoIconButton: MouseArea {
    property string icon: ""
    property string tooltip: ""
    property color iconColor: root.dim
    property color hoverColor: root.accent
    property string fontFamily: root.fontFamily

    width: iconText.implicitWidth + Style.space(10)
    height: iconText.implicitHeight + Style.space(6)
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor

    Text {
      id: iconText
      anchors.centerIn: parent
      text: parent.icon
      color: parent.containsMouse ? parent.hoverColor : parent.iconColor
      font.family: parent.fontFamily
      font.pixelSize: Style.font.body
    }

    PanelToolTip {
      visible: parent.containsMouse
      text: parent.tooltip
      fontFamily: parent.fontFamily
    }
  }

  component TodayCountBadge: Rectangle {
    id: badge
    property bool loading: false
    property real value: 0
    property color fillColor: Color.accent
    property string fontFamily: Style.font.family
    property int celebrateToken: 0

    readonly property int rounded: Math.round(value)
    property real popScale: 1

    onCelebrateTokenChanged: if (celebrateToken > 0) celebrate()

    function celebrate() {
      if (loading || rounded <= 0)
        return
      popAnim.restart()
    }

    implicitWidth: countText.implicitWidth + Style.spacing.lg * 2
    implicitHeight: countText.implicitHeight + Style.spacing.sm * 2
    radius: implicitHeight / 2
    color: Qt.rgba(fillColor.r, fillColor.g, fillColor.b, 0.14)
    scale: popScale
    transformOrigin: Item.Center

    SequentialAnimation {
      id: popAnim
      NumberAnimation {
        target: badge
        property: "popScale"
        to: 1.07
        duration: 140
        easing.type: Easing.OutCubic
      }
      NumberAnimation {
        target: badge
        property: "popScale"
        to: 1
        duration: 220
        easing.type: Easing.OutBack
      }
    }

    Text {
      id: countText
      anchors.centerIn: parent
      text: parent.loading ? "…" : String(parent.rounded)
      color: parent.fillColor
      font.family: parent.fontFamily
      font.pixelSize: Style.font.displayLarge
      font.bold: true
    }
  }

  component StatusPill: Rectangle {
    property string text: ""
    property color textColor: foreground
    property color foreground: Color.foreground
    property string fontFamily: Style.font.family

    implicitWidth: pillText.implicitWidth + Style.spacing.lg * 2
    implicitHeight: pillText.implicitHeight + Style.spacing.sm * 2
    radius: 0
    color: Qt.rgba(textColor.r, textColor.g, textColor.b, 0.14)

    Text {
      id: pillText
      anchors.centerIn: parent
      text: parent.text
      color: parent.textColor
      font.family: parent.fontFamily
      font.pixelSize: Style.font.caption
      font.bold: true
    }
  }

  component StatTile: BorderSurface {
    id: tile
    property string value: ""
    property string label: ""
    property color valueColor: root.accent
    property real animatedValue: -1
    property bool streakFormat: false
    property bool showDashWhenZero: false

    readonly property string displayValue: {
      if (animatedValue < 0)
        return value

      var n = Math.round(animatedValue)
      if (streakFormat)
        return n > 0 ? n + (n === 1 ? " day" : " days") : "—"
      if (showDashWhenZero && n <= 0)
        return "—"
      return String(n)
    }

    implicitHeight: tileColumn.implicitHeight + Style.spacing.lg * 2
    color: Color.popups.background
    borderSpec: Border.surfaceSpec("popups", "border", Color.popups.border, 1)
    radius: Style.cornerRadius

    Column {
      id: tileColumn
      anchors.centerIn: parent
      width: parent.width - Style.spacing.lg * 2
      spacing: Style.spacing.labelGap

      Text {
        width: parent.width
        text: tile.displayValue
        color: tile.valueColor
        font.family: root.fontFamily
        font.pixelSize: Style.font.title
        font.bold: true
        horizontalAlignment: Text.AlignHCenter
        elide: Text.ElideRight
      }

      Text {
        width: parent.width
        text: tile.label
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        horizontalAlignment: Text.AlignHCenter
        elide: Text.ElideRight
      }
    }
  }
}
