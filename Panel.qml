import QtQuick
import QtQuick.Controls
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

  Behavior on shownToday {
    enabled: !root.loading
    NumberAnimation { duration: 500; easing.type: Easing.OutCubic }
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

  readonly property int trendMax: 40
  readonly property int trendChartHeight: 88
  readonly property int trendsSpacing: 3
  readonly property var sparkBars: hasData ? Model.sparkBars(cells, palette, trendMax) : []
  readonly property string todayLabel: (data && data.today === 1)
    ? "contribution today"
    : "contributions today"
  readonly property color todayIconColor: hasData
    ? Model.contributionColor(data.today, palette)
    : foreground

  readonly property string statusScript: Qt.resolvedUrl("bin/github-status").toString().replace("file://", "")
  readonly property string repoScript: Qt.resolvedUrl("bin/repo-dirty-status").toString().replace("file://", "")
  readonly property int refreshMinutes: Math.max(5, parseInt(setting("refreshMinutes", 15), 10) || 15)

  property bool repoLoading: true
  property bool repoLoaded: false
  property var repoData: ({ ok: true, repos: [], error: "" })
  readonly property var repoList: (repoData && repoData.ok === true && repoData.repos instanceof Array)
    ? repoData.repos : []
  readonly property bool repoError: !repoLoading && !(repoData && repoData.ok === true)
  readonly property string repoStatusText: repoData && repoData.error ? String(repoData.error) : ""
  readonly property int repoMaxVisible: 3
  readonly property int repoRowHeight: Style.space(40)
  readonly property var repoTotals: Model.repoTotals(root.repoList)
  readonly property int dirtyRepoCount: repoTotals.dirtyRepos
  property int trendsHoveredIndex: -1
  readonly property string trendsHoverText: {
    if (trendsHoveredIndex < 0 || trendsHoveredIndex >= cells.length)
      return ""
    var cell = cells[trendsHoveredIndex] || {}
    return Model.formatCellTooltip(cell.date, cell.count)
  }

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
      shownToday = 0
      shownTotal30 = 0
      shownStreak = 0
      shownBest = 0
      return
    }

    shownToday = data.today || 0
    shownTotal30 = data.total30 || 0
    shownStreak = data.streak || 0
    shownBest = data.best || 0
  }

  function refresh(forceRepos) {
    refreshGithub()
    refreshRepos(forceRepos === true)
  }

  function refreshGithub() {
    if (!statusScript || statusProc.running) return
    if (!hasData) loading = true
    statusProc.command = ["bash", statusScript]
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
    repoData = {
      ok: parsed.ok === true,
      repos: parsed.ok && parsed.repos instanceof Array ? parsed.repos : [],
      error: parsed.ok ? "" : (parsed.error || "Scan failed")
    }
  }

  function openRepo(path) {
    var dir = path ? String(path) : ""
    if (!dir) return
    Quickshell.execDetached(["xdg-terminal-exec", "--dir=" + dir])
    root.close()
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
    refreshGithub()
    refreshRepos(true)
    trendsHoveredIndex = -1
    revealProgress = 0
    revealAnimation.restart()
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
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

          PanelSeparator {
            visible: !root.loading && root.hasData
            foreground: root.foreground
          }

          Item {
            id: trendsHeader
            width: parent.width
            visible: !root.loading && root.hasData
            height: trendsTitle.height

            PanelSectionHeader {
              id: trendsTitle
              width: parent.width
              text: "TRENDS"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            Text {
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              width: parent.width * 0.68
              visible: root.trendsHoveredIndex >= 0
              text: root.trendsHoverText
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              horizontalAlignment: Text.AlignRight
              elide: Text.ElideLeft
            }
          }

          Item {
            id: trendsTrack
            width: parent.width
            visible: !root.loading && root.hasData && root.cells.length > 0
            implicitHeight: trendsRow.height

            readonly property int cellCount: root.cells.length
            readonly property int cellWidth: cellCount > 0
              ? Math.max(6, Math.min(10, Math.floor(
                  (width - Math.max(0, cellCount - 1) * root.trendsSpacing) / cellCount)))
              : 8
            readonly property int chartWidth: cellCount > 0
              ? cellCount * cellWidth + Math.max(0, cellCount - 1) * root.trendsSpacing
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
                  readonly property var bar: root.sparkBars[index] || {}
                  readonly property bool cellHovered: hitArea.containsMouse
                  readonly property real cellReveal: Math.min(
                    1, Math.max(0, root.revealProgress * trendsTrack.cellCount - index))

                  width: trendsTrack.cellWidth
                  implicitHeight: root.trendChartHeight
                  opacity: cellReveal
                  scale: 0.85 + 0.15 * cellReveal
                  transformOrigin: Item.Bottom

                  Item {
                    width: parent.width
                    height: root.trendChartHeight

                    Rectangle {
                      width: parent.width
                      height: bar.level > 0
                        ? Math.max(2, parent.height * bar.level / 7)
                        : 0
                      anchors.bottom: parent.bottom
                      radius: Math.max(2, Style.cornerRadius)
                      color: bar.color || root.accent
                      opacity: cellHovered ? 1 : 0.85
                      transformOrigin: Item.Bottom
                      scale: cellHovered ? 1.06 : 1

                      Behavior on scale {
                        NumberAnimation { duration: 90; easing.type: Easing.OutCubic }
                      }
                    }
                  }

                  MouseArea {
                    id: hitArea
                    anchors.fill: parent
                    hoverEnabled: true
                    onContainsMouseChanged: {
                      if (containsMouse)
                        root.trendsHoveredIndex = index
                      else if (root.trendsHoveredIndex === index)
                        root.trendsHoveredIndex = -1
                    }
                  }
                }
              }
            }
          }

          Text {
            width: parent.width
            visible: !root.loading && root.hasData && root.cells.length === 0
            text: "No activity data"
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
          }

          PanelSeparator {
            visible: !root.repoLoading || root.repoList.length > 0
            foreground: root.foreground
          }

          PanelSectionHeader {
            visible: !root.repoLoading || root.repoList.length > 0
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

          Text {
            width: parent.width
            visible: !root.repoLoading && !root.repoError && root.repoList.length === 0
            text: "All clean in ~/projects and ~/work"
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            horizontalAlignment: Text.AlignHCenter
          }

          Item {
            width: parent.width
            visible: !root.repoLoading && !root.repoError && root.repoList.length > 0
            height: Math.min(root.repoList.length, root.repoMaxVisible) * root.repoRowHeight

            Flickable {
              anchors.fill: parent
              clip: true
              boundsBehavior: Flickable.StopAtBounds
              flickableDirection: Flickable.VerticalFlick
              interactive: root.repoList.length > root.repoMaxVisible
              contentHeight: root.repoList.length * root.repoRowHeight

              Column {
                width: parent.width
                spacing: 0

                Repeater {
                  model: root.repoList

                  MouseArea {
                    id: repoHit
                    required property var modelData
                    width: column.width
                    height: root.repoRowHeight
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.openRepo(modelData.path)

                    Row {
                      id: repoRow
                      anchors.verticalCenter: parent.verticalCenter
                      width: parent.width
                      spacing: Style.space(8)

                      Column {
                        width: parent.width - statusPills.width - parent.spacing
                        spacing: Style.spacing.labelGap

                        Text {
                          width: parent.width
                          text: modelData.name || ""
                          color: repoHit.containsMouse ? root.accent : root.foreground
                          font.family: root.fontFamily
                          font.pixelSize: Style.font.bodySmall
                          font.bold: true
                          elide: Text.ElideRight
                        }

                        Text {
                          width: parent.width
                          text: "~/" + (modelData.parent || "projects") + "/" + (modelData.name || "")
                          color: root.dim
                          font.family: root.fontFamily
                          font.pixelSize: Style.font.caption
                          elide: Text.ElideRight
                        }
                      }

                      Row {
                        id: statusPills
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: Style.spacing.xs

                        StatusPill {
                          visible: modelData.unstaged === true
                          text: String(parseInt(modelData.dirtyCount, 10) || 0)
                          textColor: root.urgent
                          foreground: root.foreground
                          fontFamily: root.fontFamily
                        }

                        StatusPill {
                          visible: (parseInt(modelData.unpushed, 10) || 0) > 0
                          text: String(parseInt(modelData.unpushed, 10) || 0) + "↑"
                          textColor: root.accent
                          foreground: root.foreground
                          fontFamily: root.fontFamily
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

  component TodayCountBadge: Rectangle {
    property bool loading: false
    property real value: 0
    property color fillColor: Color.accent
    property string fontFamily: Style.font.family

    readonly property int rounded: Math.round(value)

    implicitWidth: countText.implicitWidth + Style.spacing.lg * 2
    implicitHeight: countText.implicitHeight + Style.spacing.sm * 2
    radius: implicitHeight / 2
    color: Qt.rgba(fillColor.r, fillColor.g, fillColor.b, 0.14)

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
    radius: implicitHeight / 2
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
