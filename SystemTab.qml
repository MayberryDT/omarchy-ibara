import QtQuick
import qs.Commons
import qs.Ui
import "StatusModel.js" as StatusModel

// Health, logs and upkeep for the open computer, with power kept apart. What can't be undone
// from here (restart, shut down, sleep, lock, update, Remove Computer) is confirmed by name, right
// beside the button, and runs only if the same computer is still open.
Item {
  id: root
  property var host: null
  property var service: null
  property string computerId: ""
  property var computer: null
  readonly property Tokens tokens: Tokens {}
  readonly property string computerLabel: tokens.label(computer)
  readonly property var health: service ? service.health || ({}) : ({})
  readonly property var healthLines: StatusModel.healthLines(health)
  readonly property bool offline: tokens.stateOf(computer) === "offline"
  readonly property string powerBusy: service && service.busy["power:" + computerId] ? "on its way" : ""
  readonly property string actionReason: !service ? "Connecting." : service.denied ? "You don't have access." : offline ? computerLabel + " isn't answering." : powerBusy ? "ibara is still sending the last one." : ""
  readonly property var lastRepair: health.repair && health.repair.last && typeof health.repair.last === "object" ? health.repair.last : null

  function reload() {
    if (!service || !visible || !computerId) return
    service.loadHealth()
    if (!service.tailnet) service.loadTailnet()
  }
  onVisibleChanged: reload()
  onComputerIdChanged: reload()

  component Group: Rectangle {
    default property alias content: groupColumn.data
    property string title: ""
    property color accentColor: root.tokens.rule
    width: parent ? parent.width : 0
    height: groupColumn.implicitHeight + Style.space(32)
    radius: 0
    color: root.tokens.surface
    border.width: 1
    border.color: accentColor
    Column {
      id: groupColumn
      x: Style.space(16)
      y: Style.space(16)
      width: parent.width - Style.space(32)
      spacing: Style.space(10)
      Copy { text: parent.parent.title; font.pixelSize: Style.font.title; font.bold: true }
    }
  }

  // Wide, health and upkeep on the left, sharing and power on the right; narrower, one column.
  readonly property bool wide: width >= tokens.wideAt
  readonly property real columnWidth: wide ? Math.min(tokens.columnMax, Math.floor((width - tokens.columnGap) / 2)) : Math.min(width, tokens.columnMax)

  Flickable {
    id: scroll
    anchors.fill: parent
    clip: true
    contentWidth: width
    contentHeight: root.wide ? Math.max(column.implicitHeight, side.implicitHeight) : side.y + side.implicitHeight
    boundsBehavior: Flickable.StopAtBounds
    flickableDirection: Flickable.VerticalFlick
    Column {
      id: column
      width: root.columnWidth
      spacing: Style.space(16)

      Group {
        title: "Health and upkeep"
        Repeater {
          model: root.healthLines
          delegate: Copy { text: String(modelData); font.pixelSize: Style.font.bodySmall }
        }
        Copy {
          visible: root.healthLines.length === 0
          text: root.service && root.service.readPending("health") ? "Checking health…" : root.service && root.service.readErrors.health ? StatusModel.clip(root.service.readErrors.health, 200) : "No health report yet. Choose Refresh Health."
          dimmed: true
          font.pixelSize: Style.font.bodySmall
        }
        Copy {
          visible: !!root.lastRepair
          width: parent.width
          text: root.lastRepair ? "Last repair: " + StatusModel.clip(root.lastRepair.summary, 160) + (root.lastRepair.at ? " · " + root.tokens.changedLabel(new Date(StatusModel.timeMs(root.lastRepair.at)).toISOString(), root.service ? root.service.nowMs : Date.now()) : "") : ""
          dimmed: true
          font.pixelSize: Style.font.bodySmall
        }
        DataAge {
          visible: at > 0
          at: root.service && root.service.scopedReadAt.health || 0
          refreshing: !!root.service && root.service.readPending("health")
          nowMs: root.service ? root.service.nowMs : Date.now()
        }
        Flow {
          width: parent.width
          spacing: Style.space(8)
          ActionButton { label: "Refresh Health"; onClicked: root.service.loadHealth() }
          ActionButton {
            label: "Show ibara Log"
            selected: root.service && root.service.logLines.length > 0 && root.service.logsWhich === "ibara"
            onClicked: root.service.loadLogs("ibara")
          }
          ActionButton {
            label: "Show Screen Sharing Log"
            selected: root.service && root.service.logLines.length > 0 && root.service.logsWhich === "viewer"
            onClicked: root.service.loadLogs("viewer")
          }
          ActionButton {
            label: "Open Terminal"
            tooltipText: "A terminal on this desktop, signed in to " + root.computerLabel
            blocked: !root.service || root.service.mutating
            disabledReason: blocked && root.service ? "Wait for the current action to finish." : ""
            onClicked: if (!blocked) root.service.openTerminalFor(root.computerId)
          }
          ActionButton {
            label: "Lock Screen"
            blocked: root.actionReason !== ""
            disabledReason: root.actionReason
            onClicked: if (!blocked && root.host) root.host.confirmPower(root.computerId, "lock")
          }
          ActionButton {
            label: "Update"
            blocked: root.actionReason !== ""
            disabledReason: root.actionReason
            onClicked: if (!blocked && root.host) root.host.confirmPower(root.computerId, "update")
          }
        }
        Copy {
          visible: !!root.service && root.service.readErrors.logs !== undefined
          width: parent.width
          text: root.service && root.service.readErrors.logs ? StatusModel.clip(root.service.readErrors.logs, 200) : ""
          color: Color.urgent
          font.pixelSize: Style.font.bodySmall
        }
        Rectangle {
          visible: !!(root.service && root.service.logLines.length)
          width: parent.width
          height: Math.min(Style.space(260), logsText.implicitHeight + Style.space(20))
          radius: 0
          color: Qt.alpha(Color.popups.text, 0.04)
          border.width: 1
          border.color: root.tokens.rule
          Flickable {
            anchors.fill: parent
            anchors.margins: Style.space(10)
            clip: true
            contentWidth: width
            contentHeight: logsText.implicitHeight
            contentY: Math.max(0, contentHeight - height)
            boundsBehavior: Flickable.StopAtBounds
            flickableDirection: Flickable.VerticalFlick
            Copy {
              id: logsText
              width: parent.width
              text: root.service ? root.service.logLines.join("\n") : ""
              font.family: "monospace"
              font.pixelSize: Style.font.caption
              wrapMode: Text.WrapAnywhere
            }
          }
        }
      }
    }

    Column {
      id: side
      x: root.wide ? root.columnWidth + root.tokens.columnGap : 0
      y: root.wide ? 0 : column.implicitHeight + Style.space(16)
      width: root.columnWidth
      spacing: Style.space(16)

      Group {
        title: "Share with a friend"
        visible: !!root.service && root.service.thisComputerId !== "" && root.computerId === root.service.thisComputerId
        Copy {
          width: parent.width
          text: "Let a friend use this computer from theirs, with what you choose and for as long as you choose."
          dimmed: true
          font.pixelSize: Style.font.bodySmall
        }
        ActionButton { label: "Share This Computer"; onClicked: if (root.host) root.host.showShare() }
      }

      Group {
        title: "Power"
        accentColor: Qt.alpha(Color.urgent, 0.5)
        Copy {
          width: parent.width
          text: root.offline
            ? (root.computer && root.computer.wake ? root.computerLabel + " is off or asleep. Wake sends it the signal to turn on" + (root.computer.wake.kind === "wifi" ? " over Wi-Fi" : "") + "." : root.computerLabel + " isn't answering, and ibara has no way to wake it from here.")
            : "Restart, Shut Down and Sleep stop " + root.computerLabel + "'s agents until it's back." + (root.computer && root.computer.wake ? " Wake turns it on again from here." : "")
          dimmed: true
          font.pixelSize: Style.font.bodySmall
        }
        Copy {
          visible: !!root.computer && (root.computer.disk_password === true || root.health.disk_password === true)
          width: parent.width
          text: root.computerLabel + "'s disk asks for its password when it starts, so after a restart someone must type it there before ibara can reach it again."
          color: Color.urgent
          font.pixelSize: Style.font.bodySmall
        }
        Row {
          spacing: Style.space(8)
          ActionButton {
            visible: root.offline && !!root.computer && !!root.computer.wake
            label: root.service && root.service.busy["wake:" + root.computerId] ? "Waking…" : "Wake"
            role: "primary"
            blocked: !!root.service && !!root.service.busy["wake:" + root.computerId]
            onClicked: if (!blocked) root.service.wake(root.computerId)
          }
          ActionButton {
            label: "Restart"
            role: "danger"
            blocked: root.actionReason !== ""
            disabledReason: root.actionReason
            onClicked: if (!blocked && root.host) root.host.confirmPower(root.computerId, "restart")
          }
          ActionButton {
            label: "Shut Down"
            role: "danger"
            blocked: root.actionReason !== ""
            disabledReason: root.actionReason
            onClicked: if (!blocked && root.host) root.host.confirmPower(root.computerId, "shutdown")
          }
          ActionButton {
            label: "Sleep"
            role: "danger"
            blocked: root.actionReason !== ""
            disabledReason: root.actionReason
            onClicked: if (!blocked && root.host) root.host.confirmPower(root.computerId, "sleep")
          }
        }
      }

      Group {
        title: "Remove from your fleet"
        Copy {
          width: parent.width
          text: "Takes " + root.computerLabel + " off this computer's fleet, as when it was reinstalled and no longer answers as itself. Add Computer adds it again."
          dimmed: true
          font.pixelSize: Style.font.bodySmall
        }
        ActionButton {
          id: removeButton
          label: "Remove Computer"
          role: "danger"
          blocked: !root.service || root.service.mutating
          disabledReason: blocked && root.service ? "Wait for the current action to finish." : ""
          onClicked: if (!blocked && root.host) root.host.confirmRemove(root.computerId, removeButton)
        }
      }
    }
  }
}
