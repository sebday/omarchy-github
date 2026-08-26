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
  readonly property int trendChartHeight: 64
  readonly property int trendsSpacing: 3
  readonly property var sparkBars: hasData ? Model.sparkBars(cells, palette, trendMax) : []
  readonly property var legendColors: palette
  readonly property string todayLabel: (data && data.today === 1)
    ? "contribution today"
    : "contributions today"
  readonly property color todayIconColor: hasData
    ? Model.contributionColor(data.today, palette)
    : foreground

  readonly property string statusScript: Qt.resolvedUrl("bin/github-status").toString().replace("file://", "")
  readonly property int refreshMinutes: Math.max(5, parseInt(setting("refreshMinutes", 15), 10) || 15)

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
  }

  function refresh() {
    if (!statusScript || statusProc.running) return
    if (!hasData) loading = true
    statusProc.command = ["bash", statusScript]
    statusProc.running = true
  }

  function openProfile() {
    var url = data && data.profileUrl ? String(data.profileUrl) : "https://github.com/"
    Quickshell.execDetached(["xdg-open", url])
    root.close()
  }

  function openFromHotkey() {
    root.controller.show()
    root.refresh()
  }

  function toggle() {
    if (root.opened) root.close()
    else root.openFromHotkey()
  }

  Component.onCompleted: {
    data = emptyData()
    refresh()
  }

  onOpenedChanged: if (opened) {
    refresh()
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
    contentHeight: panel.fittedContentHeight(column.implicitHeight, Style.space(520))

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
                Text {
                  text: root.loading ? "…" : String(root.data.today)
                  color: root.accent
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.displayLarge
                  font.bold: true
                }
              }
            }
          }

          Row {
            visible: !root.loading && root.hasData
            width: parent.width
            spacing: Style.space(8)

            StatTile {
              width: (parent.width - parent.spacing * 2) / 3
              value: String(root.data.total30)
              label: "30 days"
            }

            StatTile {
              width: (parent.width - parent.spacing * 2) / 3
              value: root.data.streak > 0
                ? root.data.streak + (root.data.streak === 1 ? " day" : " days")
                : "—"
              label: "streak"
              valueColor: root.data.streak > 0 ? root.accent : root.foreground
            }

            StatTile {
              width: (parent.width - parent.spacing * 2) / 3
              value: root.data.best > 0 ? String(root.data.best) : "—"
              label: "best day"
            }
          }

          PanelSeparator {
            visible: !root.loading && root.hasData
            foreground: root.foreground
          }

          PanelSectionHeader {
            visible: !root.loading && root.hasData
            width: parent.width
            text: "TRENDS"
            foreground: root.foreground
            fontFamily: root.fontFamily
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

                  width: trendsTrack.cellWidth
                  implicitHeight: trendsColumn.implicitHeight

                  Column {
                    id: trendsColumn
                    width: parent.width
                    spacing: Style.spacing.sm

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
                        opacity: 0.85
                      }
                    }

                    Rectangle {
                      width: parent.width
                      height: width
                      radius: Math.max(2, Style.cornerRadius)
                      color: modelData.color
                        || root.palette[Math.max(0, Math.min(4, parseInt(modelData.level, 10) || 0))]
                      opacity: (modelData.count || 0) > 0 ? 1 : 0.35
                      border.width: index === root.cells.length - 1 ? 1 : 0
                      border.color: root.accent
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

          Row {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: Style.spacing.sm
            visible: !root.loading && root.hasData && root.cells.length > 0

            Text {
              text: "Less"
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }

            Repeater {
              model: root.legendColors

              Rectangle {
                required property string modelData
                width: 12
                height: 12
                radius: Math.max(2, Style.cornerRadius)
                color: modelData
              }
            }

            Text {
              text: "More"
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }
          }
        }
      }
    }
  }

  component StatTile: BorderSurface {
    id: tile
    property string value: ""
    property string label: ""
    property color valueColor: root.accent

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
        text: tile.value
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
