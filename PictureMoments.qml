import QtQuick
import qs.Commons

// What happens on a computer's picture, over it: a click by its agent ripples where it landed;
// a finished task gets its Done moment; going offline fades the picture to gray, and coming
// back brings it up from dark. Fill the picture's box with it, after the picture and before the
// labels on it. The service says when an agent clicked or finished (agentClicked, taskDone).
Item {
  id: root
  property var service: null
  property string computerId: ""
  property Tokens tokens: null
  // The picture it lays over: scaled as it comes back online; its frameAspect places the ripples.
  property Item preview: null
  property string fleetState: ""
  readonly property bool offline: fleetState === "offline"
  readonly property real frameAspect: preview && preview.frameAspect > 0 ? preview.frameAspect : 0
  // The picture's shown rectangle inside the box (it keeps its shape and sits in the middle).
  readonly property rect shown: {
    if (frameAspect <= 0 || width <= 0 || height <= 0) return Qt.rect(0, 0, width, height)
    if (width / height > frameAspect) { var w = height * frameAspect; return Qt.rect((width - w) / 2, 0, w, height) }
    var h = width / frameAspect
    return Qt.rect(0, (height - h) / 2, width, h)
  }
  Accessible.ignored: true

  function ripple(fx, fy) {
    rip.px = shown.x + Math.max(0, Math.min(1, fx)) * shown.width
    rip.py = shown.y + Math.max(0, Math.min(1, fy)) * shown.height
    ripAnim.restart()
  }
  function done() { doneAnim.restart() }

  Connections {
    target: root.service
    ignoreUnknownSignals: true
    function onAgentClicked(id, x, y) { if (id === root.computerId && root.visible) root.ripple(x, y) }
    function onTaskDone(id) { if (id === root.computerId && root.visible) root.done() }
  }

  // Coming back online: only after it was offline, not after connecting at the start.
  property bool wasOffline: false
  Component.onCompleted: wasOffline = offline
  // Another computer in the same place (the Screen tab's list) starts fresh.
  onComputerIdChanged: { wasOffline = offline; onlineAnim.complete(); ripAnim.complete(); doneAnim.complete() }
  onFleetStateChanged: {
    if (offline) wasOffline = true
    else if (wasOffline && fleetState !== "connecting") {
      wasOffline = false
      if (visible) onlineAnim.restart()
    }
  }

  // Offline: the picture fades to gray.
  Rectangle {
    anchors.fill: parent
    color: Qt.alpha(Color.popups.background, 0.8)
    opacity: root.offline ? 1 : 0
    Behavior on opacity { NumberAnimation { duration: 600; easing.type: Easing.InOutQuad } }
  }
  // Online again: up from dark, settling from a little larger.
  Rectangle { id: dark; anchors.fill: parent; color: Color.popups.background; opacity: 0 }
  ParallelAnimation {
    id: onlineAnim
    NumberAnimation { target: dark; property: "opacity"; from: 1; to: 0; duration: 900; easing.type: Easing.InOutQuad }
    NumberAnimation { target: root.preview; property: "scale"; from: 1.06; to: 1; duration: 900; easing.type: Easing.OutCubic }
  }
  // A click: a square ring in the working color spreads from the spot.
  Rectangle {
    id: rip
    property real px: 0
    property real py: 0
    property real size: 0
    width: size
    height: size
    x: px - size / 2
    y: py - size / 2
    radius: 0
    color: "transparent"
    border.width: Style.space(3)
    border.color: root.tokens ? root.tokens.stateColor("working") : Color.accent
    opacity: 0
    ParallelAnimation {
      id: ripAnim
      NumberAnimation { target: rip; property: "size"; from: Style.space(6); to: Style.space(80); duration: 650; easing.type: Easing.OutCubic }
      NumberAnimation { target: rip; property: "opacity"; from: 1; to: 0; duration: 650; easing.type: Easing.InQuad }
    }
  }
  // Done: a wash of the ready color, a big check springing in, then it fades.
  Item {
    id: doneLayer
    anchors.fill: parent
    visible: opacity > 0
    opacity: 0
    readonly property color readyColor: root.tokens ? root.tokens.stateColor("ready") : Color.accent
    Rectangle { anchors.fill: parent; radius: 0; color: Qt.alpha(doneLayer.readyColor, 0.28) }
    Column {
      anchors.centerIn: parent
      spacing: Style.space(4)
      // Smaller pictures get a smaller check.
      readonly property real unit: Math.min(1, root.height / Style.space(260))
      Text {
        id: check
        anchors.horizontalCenter: parent.horizontalCenter
        text: "✓"
        color: doneLayer.readyColor
        font.pixelSize: Math.max(Style.space(36), Style.space(96) * parent.unit)
        font.bold: true
        style: Text.Outline
        styleColor: Color.popups.background
      }
      Text {
        anchors.horizontalCenter: parent.horizontalCenter
        text: "Done"
        color: Color.popups.text
        font.family: Style.font.family
        font.pixelSize: Math.max(Style.space(16), Style.space(26) * parent.unit)
        font.bold: true
        style: Text.Outline
        styleColor: Color.popups.background
      }
    }
  }
  SequentialAnimation {
    id: doneAnim
    ParallelAnimation {
      NumberAnimation { target: doneLayer; property: "opacity"; from: 0; to: 1; duration: 200 }
      NumberAnimation { target: check; property: "scale"; from: 0.4; to: 1; duration: 420; easing.type: Easing.OutBack; easing.overshoot: 2.2 }
    }
    PauseAnimation { duration: 1800 }
    NumberAnimation { target: doneLayer; property: "opacity"; to: 0; duration: 500 }
  }
}
