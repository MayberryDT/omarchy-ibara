import QtQuick
import qs.Commons
import "StatusModel.js" as StatusModel

// An agent asking for your login to one or more sites, as a toast in the console's stack and in
// the quick panel: who asks, on which computer, for which task and which sites, with a tick for
// each site when there are several. Share allows the ticked sites on that computer, Share With All
// Computers allows them on every computer, and Don't Share refuses this time without a rule; the
// sites left unticked are not shared. Details has the page, whether a site signs in through another
// (irs.gov through id.me), and Never Share, which denies the ticked sites on every computer. It is
// answered only on the computer your logins come from: elsewhere it says where, and while no
// computer shares it offers Turn On Login Sharing. A site you're signed out of in your browser
// keeps the request open with Retry.
Toast {
  id: root
  property var service: null
  // An attention item of kind `login` (StatusModel.attentionView), whose `login` holds its details.
  property var item: null
  readonly property Tokens tokens: Tokens {}
  property bool compact: false
  // Turn On Login Sharing with more than one browser to choose from goes to Settings.
  signal settingsWanted()

  readonly property var login: item && item.login ? item.login : null
  readonly property var sites: login ? login.sites : []
  readonly property bool several: sites.length > 1
  readonly property string ref: item ? String(item.ref) : ""
  readonly property string computerId: item ? String(item.computer_id || "") : ""
  property bool warmed: false
  function warm() { if (visible && !warmed && service && computerId) warmed = service.warmComputer(computerId) }
  Component.onCompleted: warm()
  onServiceChanged: { warmed = false; warm() }
  onVisibleChanged: { warmed = false; warm() }
  onComputerIdChanged: { warmed = false; warm() }
  Connections {
    target: root.service
    function onSessionsChanged() { root.warm() }
  }
  readonly property string name: item ? String(item.label || (service ? service.computerLabelFor(item.computer_id) : "")) : ""
  readonly property var settings: service ? service.loginSettings : null
  readonly property string browser: service ? service.loginBrowserName : "your browser"
  readonly property string elsewhere: service && item ? service.loginSourceElsewhere(item) : ""
  readonly property var outcome: service && service.loginOutcomes[ref] ? service.loginOutcomes[ref] : null
  readonly property bool answering: !!service && !!service.busy["answer:" + ref]
  readonly property bool unreachable: !!item && item.unreachable === true
  // What the card offers: "older" (this ibara can't share logins), "elsewhere" (another computer
  // answers), "off" (no computer shares), "signedOut" (Retry) or "answer".
  readonly property string mode: !settings ? "older" : elsewhere ? "elsewhere" : !settings.enabled ? "off" : outcome && outcome.signedOut.length ? "signedOut" : "answer"
  // Sites the person unticked, by name.
  property var unticked: ({})
  readonly property int tickedCount: sites.filter(function(s) { return !unticked[s.site] }).length
  property string chosen: ""
  property bool detailsOpen: false
  readonly property string asked: {
    var at = item ? Number(item.at || 0) : 0
    if (!at || !service) return ""
    return "asked " + StatusModel.ageLabel(new Date(at).toISOString(), service.nowMs)
  }
  readonly property var through: StatusModel.loginThrough(sites)
  readonly property var facts: {
    if (!login) return []
    var out = []
    if (login.agent) out.push({ label: "Who", value: login.agent + (login.own ? "" : ", from someone else's computer, so it's asked every time") })
    out.push({ label: "Computer", value: name })
    if (login.goal) out.push({ label: "Task", value: login.goal })
    out.push({ label: several ? "Sites" : "Site", value: StatusModel.listWords(sites.map(function(s) { return s.site })) })
    if (login.page) out.push({ label: "Page", value: login.page })
    for (var i = 0; i < through.length; i++) out.push({ label: "Note", value: through[i] })
    return out
  }
  readonly property string turnOnReason: settings && settings.targetRole ? "This computer also runs agents, so it can't share logins yet. Turn on sharing from the computer you use." : ""
  readonly property string busyReason: answering ? "ibara is sending your answer." : unreachable ? name + " isn't answering right now. You can answer once it's back." : ""

  function answer(choice) {
    if (!service || !login || answering || unreachable) return
    if (choice !== "decline" && !tickedCount) return
    chosen = choice
    service.answerLogin(ref, StatusModel.loginDecisions(sites, unticked, choice), false, popup)
  }
  function retry() {
    if (!service || !outcome || answering) return
    chosen = "retry"
    service.answerLogin(ref, outcome.decisions, true)
  }
  function toggleSite(site) {
    var next = Object.assign({}, unticked)
    if (next[site]) delete next[site]; else next[site] = true
    unticked = next
  }
  // With one browser and profile to choose, Turn On Login Sharing turns it on here; with more,
  // Settings under Logins has the choice.
  function turnOn(button) {
    if (!service || turnOnReason) return
    var choices = settings.browsers.filter(function(b) { return b.supported }).reduce(function(n, b) { return n + b.profiles.length }, 0)
    if (choices === 1 && service.loginPick) {
      if (host && typeof host.turnOnLogins === "function") host.turnOnLogins(button)
      else service.turnOnLogins(false)
    } else settingsWanted()
  }
  function toggleDetails() { detailsOpen = !detailsOpen }
  function closeDetails() { if (!detailsOpen) return false; detailsOpen = false; return true }
  function focusApprove() { var first = firstControl; if (first && first.visible) first.forceActiveFocus() }
  onRefChanged: { unticked = ({}); detailsOpen = false }
  onAnsweringChanged: if (!answering) chosen = ""
  // The console, when the card is in its stack (Toasts sets it); null in the quick panel.
  property var host: null

  edge: popup ? tokens.humanColor : Color.urgent
  tinted: true
  dismissable: popup
  holding: detailsOpen
  firstControl: mode === "answer" ? shareButton : mode === "signedOut" ? retryButton : mode === "off" && !turnOnReason ? turnOnButton : detailsButton
  Accessible.name: name + " needs your approval: " + (item ? item.summary : "")

  Row {
    width: parent.width
    spacing: Style.space(10)
    Copy {
      id: headingText
      width: Math.min(implicitWidth, parent.width - (askedText.visible ? askedText.implicitWidth + parent.spacing : 0))
      text: root.popup ? StatusModel.requestHeading(root.item, root.name, root.service && root.item ? root.service.sessions[root.item.computer_id] : null) : root.name + " needs your approval"
      font.bold: true
      color: root.tokens.textTint(root.popup ? root.edge : root.tokens.attentionColor)
      wrapMode: Text.NoWrap
      elide: Text.ElideRight
    }
    Copy {
      id: askedText
      visible: text !== "" && !root.compact && !root.popup
      text: root.unreachable ? "not answering right now" : root.asked
      color: root.unreachable ? root.tokens.textTint(root.tokens.pausedColor) : root.tokens.dim
      font.pixelSize: Style.font.bodySmall
      anchors.baseline: headingText.baseline
      wrapMode: Text.NoWrap
    }
  }
  // The request in words, whole: "codex@laptop, working on “…” on AcePC AK2, wants your login for sos.ok.gov".
  Copy {
    width: parent.width
    text: root.popup ? StatusModel.requestPopupText(root.item) : root.item ? root.item.summary : ""
    maximumLineCount: root.popup ? 1 : 2147483647
    elide: Text.ElideRight
    font.pixelSize: root.compact ? Style.font.bodySmall : Style.font.body
  }
  // Several sites: a tick for each; only the ticked ones are shared.
  Flow {
    visible: !root.popup && root.several && (root.mode === "answer" || root.mode === "off")
    width: parent.width
    spacing: Style.space(6)
    Repeater {
      model: root.sites
      delegate: ActionButton {
        required property var modelData
        readonly property bool ticked: !root.unticked[modelData.site]
        size: "small"
        role: "quiet"
        glyph: ticked ? "✓" : " "
        label: modelData.site
        selected: ticked
        blocked: root.answering
        disabledReason: root.busyReason
        Accessible.role: Accessible.CheckBox
        Accessible.checkable: true
        Accessible.checked: ticked
        Accessible.name: "Share " + modelData.site
        tooltipText: ticked ? "Leave " + modelData.site + " out of this answer" : "Include " + modelData.site
        onClicked: if (!blocked) root.toggleSite(modelData.site)
      }
    }
  }
  // Where and why it can't be answered here, or what the last answer left.
  Copy {
    visible: text !== ""
    width: parent.width
    maximumLineCount: root.popup ? 1 : 2147483647
    elide: Text.ElideRight
    text: root.mode === "older" ? "ibara on this computer can't share logins. Update ibara here to answer this."
      : root.mode === "elsewhere" ? "Answer this on " + root.elsewhere + "."
      : root.mode === "off" ? (root.turnOnReason ? "Login sharing is off. " + root.turnOnReason : "Login sharing is off. Turn it on to share your login from " + root.browser + " on this computer.")
      : root.mode === "signedOut" ? StatusModel.loginSignedOutWords(root.outcome.signedOut, root.browser)
      : root.unreachable ? root.busyReason : ""
    color: root.mode === "signedOut" ? root.tokens.textTint(root.tokens.attentionColor) : root.tokens.textTint(root.tokens.pausedColor)
    font.pixelSize: Style.font.bodySmall
    font.bold: root.mode === "elsewhere"
  }
  Flickable {
    id: detailsBox
    visible: root.detailsOpen && !root.popup
    width: parent.width
    height: Math.min(factsColumn.implicitHeight, Style.space(root.compact ? 120 : 200))
    contentWidth: width
    contentHeight: factsColumn.implicitHeight
    clip: true
    interactive: contentHeight > height
    boundsBehavior: Flickable.StopAtBounds
    flickableDirection: Flickable.VerticalFlick
    Accessible.role: Accessible.StaticText
    Accessible.name: "Details: " + root.facts.map(function(f) { return f.label + ": " + f.value }).join(". ")
    Column {
      id: factsColumn
      width: detailsBox.width
      spacing: Style.space(3)
      Repeater {
        model: root.facts
        delegate: Item {
          required property var modelData
          width: factsColumn.width
          height: Math.max(factLabel.implicitHeight, factValue.implicitHeight)
          Copy { id: factLabel; width: Style.space(96); text: modelData.label; dimmed: true; font.pixelSize: Style.font.bodySmall }
          Copy { id: factValue; x: Style.space(104); width: parent.width - x; textFormat: Text.StyledText; text: root.tokens.detailMarkup(modelData.label, modelData.value, "send"); font.pixelSize: Style.font.bodySmall; wrapMode: Text.WrapAtWordBoundaryOrAnywhere }
        }
      }
    }
  }
  Flow {
    width: parent.width
    spacing: Style.space(8)
    ActionButton {
      id: shareButton
      // Sharing remains independent of the person's remote desktop control.
      visible: root.mode === "answer"
      label: root.answering && root.chosen === "share" ? "Sharing…" : "Share"
      role: "primary"
      size: "small"
      blocked: root.answering || root.unreachable || !root.tickedCount
      disabledReason: root.busyReason || (!root.tickedCount ? "Tick a site to share." : "")
      tooltipText: disabledReason || "Share with " + root.name + " now, and from now on without asking"
      Accessible.name: "Share on " + root.name + ": " + (root.item ? root.item.summary : "")
      onClicked: if (!blocked) root.answer("share")
    }
    ActionButton {
      visible: root.mode === "answer"
      label: root.answering && root.chosen === "share_all" ? "Sharing…" : "Share With All Computers"
      size: "small"
      blocked: root.answering || root.unreachable || !root.tickedCount
      disabledReason: root.busyReason || (!root.tickedCount ? "Tick a site to share." : "")
      tooltipText: disabledReason || "Share now, and let every computer of yours have it without asking from now on"
      Accessible.name: "Share with all computers: " + (root.item ? root.item.summary : "")
      onClicked: if (!blocked) root.answer("share_all")
    }
    ActionButton {
      id: retryButton
      visible: root.mode === "signedOut"
      label: root.answering && root.chosen === "retry" ? "Retrying…" : "Retry"
      role: "primary"
      size: "small"
      blocked: root.answering || root.unreachable
      disabledReason: root.busyReason
      Accessible.name: "Retry sharing on " + root.name
      onClicked: if (!blocked) root.retry()
    }
    ActionButton {
      id: turnOnButton
      visible: root.mode === "off" && !root.turnOnReason
      label: root.service && root.service.busy["login-on"] ? "Turning On…" : "Turn On Login Sharing"
      role: "primary"
      size: "small"
      blocked: !!root.service && !!root.service.busy["login-on"]
      disabledReason: blocked ? "ibara is turning it on." : ""
      tooltipText: disabledReason || "Share logins from " + root.browser + " on this computer, only when you allow them"
      onClicked: if (!blocked) root.turnOn(turnOnButton)
    }
    ActionButton {
      visible: root.mode === "answer" || root.mode === "signedOut" || root.mode === "off"
      label: root.answering && root.chosen === "decline" ? "Answering…" : "Don't Share"
      role: "danger"
      size: "small"
      blocked: root.answering || root.unreachable
      disabledReason: root.busyReason
      tooltipText: disabledReason || "Refuse this time; nothing changes for later"
      Accessible.name: "Don't share on " + root.name + ": " + (root.item ? root.item.summary : "")
      onClicked: if (!blocked) root.answer("decline")
    }
    TakeControlButton {
      service: root.service
      host: root.host
      computerId: root.computerId
      visible: !root.popup && computerId !== "" && (!root.service || !root.service.holdsControlOn(computerId) || connecting)
      size: "small"
      role: "secondary"
    }
    ActionButton {
      id: detailsButton
      visible: !root.popup
      label: root.detailsOpen ? "Hide Details" : "Details"
      role: "quiet"
      size: "small"
      selected: root.detailsOpen
      Accessible.name: (root.detailsOpen ? "Hide the details of " : "Show the details of ") + "the login request on " + root.name
      onClicked: root.toggleDetails()
    }
    ActionButton {
      visible: root.detailsOpen && !root.popup && root.mode === "answer"
      label: root.answering && root.chosen === "never" ? "Answering…" : "Never Share"
      role: "danger"
      size: "small"
      blocked: root.answering || root.unreachable || !root.tickedCount
      disabledReason: root.busyReason || (!root.tickedCount ? "Tick a site to deny." : "")
      tooltipText: disabledReason || "Deny " + (root.several ? "the ticked sites" : root.sites.length ? root.sites[0].site : "this site") + " on every computer, so agents are never asked for it again"
      Accessible.name: "Never share, on any computer: " + StatusModel.listWords(root.sites.filter(function(s) { return !root.unticked[s.site] }).map(function(s) { return s.site }))
      onClicked: if (!blocked) root.answer("never")
    }
  }
}
