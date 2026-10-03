import QtQuick

// Shared by the console, question/login cards and desktop pop-ups.
ActionButton {
  id: root
  property var service: null
  property var host: null
  property string computerId: ""
  property string keyHint: ""
  property var confirmation: null
  readonly property bool connecting: !!service && service.connectingOn(computerId)
  label: connecting ? "Connecting…" : "Join" + keyHint
  role: "primary"
  blocked: !service || service.controlBlockedReason(computerId) !== ""
  disabledReason: service ? service.controlBlockedReason(computerId) : "This computer is not available."
  tooltipText: ""
  onHotChanged: if (hot && service) service.warmComputer(computerId)
  onActiveFocusChanged: if (activeFocus && service) service.warmComputer(computerId)
  onClicked: {
    if (!service || connecting) return
    service.requestTakeControl(computerId, function(options) {
      if (root.host && typeof root.host.askConfirm === "function") { root.host.askConfirm(Object.assign({}, options, { anchor: root })); return }
      if (root.confirmation) { root.cancelConfirm(); return }
      root.confirmation = Object.assign({}, options, { anchor: root })
    })
  }
  function cancelConfirm() { confirmation = null; forceActiveFocus() }
  function runConfirm() {
    var pending = confirmation
    confirmation = null
    if (pending && pending.valid()) pending.run()
    else if (service) service.actionError = "Control changed. Try Join again."
    forceActiveFocus()
  }
  onComputerIdChanged: confirmation = null
  NearbyConfirm { host: root }
}
