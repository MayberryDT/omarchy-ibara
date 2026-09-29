import QtQuick
import qs.Commons
import "StatusModel.js" as StatusModel

// A request from another computer to use this one, as a toast in the console's stack and at the
// bottom of the quick panel: who asks, the code both screens show, and Accept or Decline. The
// person here checks that the other screen shows the same code before accepting; nothing else is
// asked. It stays until it is answered or the request ends.
Toast {
  id: root
  property var service: null
  property var request: null
  readonly property Tokens tokens: Tokens {}
  readonly property string name: StatusModel.computerName(request ? request.from_computer : "")
  readonly property string who: name + (request && request.from_owner ? " (" + request.from_owner + ")" : "")
  readonly property string code: request ? String(request.code) : ""
  readonly property string answering: service && request && service.pairAnswers[request.request_id] ? String(service.pairAnswers[request.request_id]) : ""
  readonly property string busyReason: answering ? "ibara is sending your answer." : ""

  function answer(value) { if (service && request && !answering) service.answerPairRequest(request.request_id, value) }

  edge: tokens.pausedColor
  tinted: true
  dismissable: false
  firstControl: accept
  Accessible.name: who + " wants to use this computer. Code " + code

  Copy { width: parent.width; text: root.who + " wants to use this computer"; font.bold: true }
  Row {
    spacing: Style.space(8)
    Copy { anchors.baseline: codeText.baseline; text: "Accept only if " + root.name + " shows"; dimmed: true; font.pixelSize: Style.font.bodySmall }
    Copy { id: codeText; text: root.code; font.family: "monospace"; font.bold: true; font.pixelSize: Style.font.heading + Style.space(2); Accessible.ignored: true }
  }
  Row {
    spacing: Style.space(8)
    ActionButton {
      id: accept
      label: root.answering === "accept" ? "Accepting…" : "Accept"
      role: "primary"
      size: "small"
      blocked: root.answering !== ""
      disabledReason: root.busyReason
      Accessible.name: "Accept " + root.name + ", code " + root.code
      onClicked: if (!blocked) root.answer("accept")
    }
    ActionButton {
      label: root.answering === "decline" ? "Declining…" : "Decline"
      size: "small"
      blocked: root.answering !== ""
      disabledReason: root.busyReason
      Accessible.name: "Decline " + root.name
      onClicked: if (!blocked) root.answer("decline")
    }
  }
}
