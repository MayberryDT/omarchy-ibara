import QtQuick
import qs.Commons
import "StatusModel.js" as StatusModel

// An agent's question on one computer, as a toast in the console's stack and at the top of the
// quick panel: the computer, the question, when it was asked, one button per answer the agent
// offered (in Title Case on the button; the answer sent is the agent's own text) or a field and
// Send when it offered none, and Dismiss, which tells the agent nobody will answer. It stays
// until it is answered or dismissed here or elsewhere, or its task's control ends; it leaves when
// the computer confirms.
Toast {
  id: root
  property var service: null
  // { computer_id, label, ref, summary, options, at, unreachable } from fleet-attention
  // (StatusModel.attentionView).
  property var item: null
  // The quick panel is narrow: the heading has the line to itself.
  property bool compact: false
  property string chosen: ""
  readonly property string name: item ? String(item.label || (service ? service.computerLabelFor(item.computer_id) : "")) : ""
  readonly property bool answering: !!service && !!item && !!service.busy["answer:" + item.ref]
  readonly property bool unreachable: !!item && item.unreachable === true
  readonly property string unreachableReason: name + " isn't answering right now. You can answer once it's back."
  readonly property var options: item && Array.isArray(item.options) ? item.options : []
  readonly property string asked: {
    var at = item ? Number(item.at || 0) : 0
    if (!at || !service) return ""
    return "asked " + StatusModel.ageLabel(new Date(at).toISOString(), service.nowMs)
  }
  readonly property string heading: "An agent on " + name + " asks you"
  readonly property string question: item ? String(item.summary || "An agent is waiting for your answer.") : ""

  function answer(value) {
    if (!service || !item || answering || unreachable) return
    chosen = String(value)
    if (!service.answerQuestion(item.ref, chosen)) chosen = ""
  }
  function dismissQuestion() {
    if (!service || !item || answering) return
    chosen = "\u0000dismiss"
    if (!service.dismissQuestion(item.ref)) chosen = ""
  }
  onAnsweringChanged: if (!answering) chosen = ""

  edge: Color.urgent
  tinted: true
  dismissable: false
  firstControl: options.length ? optionButtons.itemAt(0) : answerField
  Accessible.name: heading + ": " + question

  Row {
    width: parent.width
    spacing: Style.space(10)
    Copy {
      id: headingText
      width: Math.min(implicitWidth, parent.width - (askedText.visible ? askedText.implicitWidth + parent.spacing : 0))
      text: root.heading
      font.bold: true
      color: Color.urgent
      wrapMode: Text.NoWrap
      elide: Text.ElideRight
    }
    Copy {
      id: askedText
      visible: text !== "" && !root.compact
      text: root.unreachable ? "not answering right now" : root.asked
      dimmed: true
      font.pixelSize: Style.font.bodySmall
      anchors.baseline: headingText.baseline
      wrapMode: Text.NoWrap
    }
  }
  Copy { width: parent.width; text: root.question; maximumLineCount: 5; elide: Text.ElideRight }
  Copy { visible: root.unreachable; width: parent.width; text: root.unreachableReason; dimmed: true; font.pixelSize: Style.font.bodySmall }
  // No answers offered: any short answer.
  FieldInput {
    id: answerField
    visible: root.options.length === 0
    width: parent.width
    maximumLength: 1000
    placeholder: "Your answer"
    accessibleName: "Your answer to the agent on " + root.name
    onAccepted: if (text.trim() !== "") root.answer(text)
  }
  Flow {
    width: parent.width
    spacing: Style.space(8)
    Repeater {
      id: optionButtons
      model: root.options
      delegate: ActionButton {
        required property string modelData
        required property int index
        label: root.answering && root.chosen === modelData ? "Sending…" : StatusModel.clip(StatusModel.titleCase(modelData), 60)
        role: index === 0 ? "primary" : "secondary"
        size: "small"
        blocked: root.answering || root.unreachable
        disabledReason: root.answering ? "ibara is sending your answer." : root.unreachable ? root.unreachableReason : ""
        tooltipText: blocked ? disabledReason : modelData.length > 60 ? modelData : ""
        Accessible.name: "Answer " + modelData + " to the agent on " + root.name
        onClicked: if (!blocked) root.answer(modelData)
      }
    }
    ActionButton {
      visible: root.options.length === 0
      label: root.answering && root.chosen !== "\u0000dismiss" ? "Sending…" : "Send"
      role: "primary"
      size: "small"
      blocked: root.answering || root.unreachable || answerField.text.trim() === ""
      disabledReason: root.answering ? "ibara is sending your answer." : root.unreachable ? root.unreachableReason : "Type an answer first."
      Accessible.name: "Send your answer to the agent on " + root.name
      onClicked: if (!blocked) root.answer(answerField.text)
    }
    ActionButton {
      label: root.answering && root.chosen === "\u0000dismiss" ? "Dismissing…" : "Dismiss"
      role: "quiet"
      size: "small"
      blocked: root.answering
      disabledReason: root.answering ? "ibara is sending your answer." : ""
      tooltipText: blocked ? disabledReason : "Tell the agent nobody will answer"
      Accessible.name: "Dismiss the question from the agent on " + root.name
      onClicked: if (!blocked) root.dismissQuestion()
    }
  }
}
