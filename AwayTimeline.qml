import QtQuick
import qs.Commons

// While you were away, as a toast: how much happened on how many computers since this console
// last looked (`away`). Details opens each computer's latest events inside it, one a line, oldest first,
// where a computer's name opens it. It stays until it is read or put away: Mark All Seen hides
// them until something new happens; dismissing the toast hides it until the console opens again.
Toast {
  id: root
  property var host: null
  property var service: null
  property bool open: false
  readonly property Tokens tokens: Tokens {}
  readonly property var computers: service && service.away ? service.away.computers : []
  readonly property double since: service && service.away ? Number(service.away.since || 0) : 0
  readonly property int eventCount: computers.reduce(function(sum, c) { return sum + (c.total || c.events.length) }, 0)
  // Each computer shows its latest events; earlier ones are counted.
  readonly property int shownEvents: 4
  readonly property real nameWidth: Style.space(130)
  readonly property string heading: "While you were away" + (since > 0 ? " (since " + when(since) + ")" : "") + ": " +
    (eventCount === 1 ? "1 thing happened" : eventCount + " things happened") + " on " + (computers.length === 1 ? "1 computer." : computers.length + " computers.")

  function when(ms) {
    if (!ms) return ""
    return tokens.changedLabel(new Date(ms).toISOString(), service ? service.nowMs : Date.now())
  }
  function closeDetails() { if (!open) return false; open = false; return true }

  holding: open
  firstControl: detailsButton
  dismissName: "Dismiss While you were away until the console opens again"
  Accessible.name: heading

  Copy { width: parent.width; text: root.heading; font.pixelSize: Style.font.bodySmall }
  Repeater {
    model: root.open ? root.computers : []
    delegate: Item {
      required property var modelData
      readonly property var events: modelData.events.slice(-root.shownEvents)
      readonly property int earlier: (modelData.total || modelData.events.length) - events.length
      width: parent ? parent.width : 0
      height: Math.max(nameButton.implicitHeight, line.y + line.implicitHeight)
      ActionButton {
        id: nameButton
        width: Math.min(implicitWidth, root.nameWidth)
        size: "small"
        role: "quiet"
        label: String(modelData.label || (root.service ? root.service.computerLabelFor(modelData.computer_id) : ""))
        Accessible.name: "Open " + label
        tooltipText: "Open " + label
        onClicked: if (root.host) root.host.showComputer(String(modelData.computer_id))
      }
      Copy {
        id: line
        x: root.nameWidth + Style.space(8)
        // The first line sits level with the computer's name.
        y: Math.max(0, Math.round((nameButton.implicitHeight - line.implicitHeight / Math.max(1, line.lineCount)) / 2))
        width: parent.width - x
        text: (earlier > 0 ? ["+" + earlier + " earlier"] : []).concat(events.map(function(event) { return root.when(event.at) + "  " + event.summary })).join("\n")
        font.pixelSize: Style.font.bodySmall
      }
    }
  }
  Row {
    spacing: Style.space(8)
    ActionButton {
      id: detailsButton
      size: "small"
      role: "quiet"
      selected: root.open
      label: root.open ? "Hide Details" : "Details"
      Accessible.name: root.open ? "Hide what happened on each computer" : "Show what happened on each computer"
      onClicked: root.open = !root.open
    }
    ActionButton {
      size: "small"
      label: root.service && root.service.busy["away-seen"] ? "Marking…" : "Mark All Seen"
      blocked: !!root.service && !!root.service.busy["away-seen"]
      tooltipText: "Hide these until something new happens"
      onClicked: if (!blocked && root.service) root.service.markAwaySeen()
    }
  }
}
