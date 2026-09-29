import QtQuick
import QtQuick.Window
import Quickshell
import qs.Commons
import qs.Ui
import "StatusModel.js" as StatusModel

// The console window: routes fleet, computer and add, one confirmation at a time attached to
// the control that asked (NearbyConfirm.qml), Connect an Agent attached to its toolbar button
// (AgentConnectDialog.qml), and every message as a toast over the page's bottom-right corner
// (Toasts.qml). Nothing is ever drawn between a page's header and its content. Service owns
// every record.
Panel {
  id: root
  moduleName: "io.zet.ibara"
  manageIpc: false

  property var shell: null
  property var manifest: null
  property var service: null
  property string route: "fleet"
  property string computerId: ""
  property string tab: "screen"
  property int seenRouteSerial: -1
  property bool routing: false
  property var favorites: ({})
  // { message, confirmLabel, danger, run, valid, route, computerId }
  property var confirmation: null
  property var confirmReturnItem: null
  // Where the keyboard goes once the next page is built: { kind: "approval", ref } from the bar.
  property var pendingFocus: null
  readonly property var computerTabs: ["screen", "activity", "files", "access", "system", "settings"]
  readonly property Tokens tokens: Tokens {}
  readonly property var computers: service && Array.isArray(service.computers) ? service.computers : []
  readonly property var computer: computerById(computerId)
  readonly property Item activeRoute: windowLoader.item ? windowLoader.item.activeRoute : null
  readonly property var focusedItem: windowLoader.item ? windowLoader.item.focusedItem : null
  // Every message is a row here, oldest first, shown as a toast (Toasts.qml); the newest shows at
  // the bottom. Rows: { key, kind, ref, text, tone, serial, action }. A message row ("message")
  // comes from one source: action-error, action-note, refresh, page-error, page-note, undo,
  // added. A standing row lasts as long as its condition (StatusModel.standingToasts): an
  // approval, an agent's question or a request to use this computer, which stays until answered;
  // a computer that needs a person, or is offline or needs attention for a minute or more (what
  // makes the bar red, on every page); files on their way to the open computer; What's New; a
  // theme run; While you were away; and the pointer to Connect an Agent. `tone` is "approval",
  // "request", "error" or "note".
  readonly property ListModel toastModel: ListModel {}
  property int toastSerial: 0
  // A toast's action (Undo) runs the function kept here under its source; the model keeps only its label.
  property var toastActions: ({})
  // The refresh failure the operator dismissed; it shows again only once it changes.
  property string dismissedRefresh: ""
  // Standing toasts put away: While you were away until the console opens again, and the Connect
  // an Agent pointer for as long as ibara runs. A need or a problem is put away in Service, so the
  // bar drops it too.
  property bool awayHidden: false
  property bool connectHintDone: false
  // Connect an Agent, open in a card attached to the control that asked.
  property bool connectOpen: false
  property Item connectAnchor: null
  readonly property Item toastStack: windowLoader.item ? windowLoader.item.toastStack : null

  function computerById(id) {
    var key = String(id || "")
    if (!key) return null
    for (var i = 0; i < computers.length; i++) if (String(computers[i].computer_id) === key) return computers[i]
    return null
  }

  // ---- messages. A toast never moves the page: an error stays until dismissed or its
  // condition clears, a note leaves after a few seconds, and a message already showing
  // under another source is not shown twice. An empty text removes that source's toast.
  function toastIndex(key) {
    for (var i = 0; i < toastModel.count; i++) if (toastModel.get(i).key === key) return i
    return -1
  }
  function showToast(key, text, error, actionLabel) {
    var message = StatusModel.clip(text, 400)
    var at = toastIndex(key)
    var action = String(actionLabel || "")
    if (!message) { if (at !== -1) toastModel.remove(at); forgetToastAction(key); return }
    for (var i = 0; i < toastModel.count; i++) {
      var other = toastModel.get(i)
      if (other.key !== key && other.kind === "message" && other.text === message) { if (at !== -1) toastModel.remove(at); return }
    }
    toastSerial += 1
    var tone = error === true ? "error" : "note"
    if (at !== -1) { toastModel.set(at, { text: message, tone: tone, serial: toastSerial, action: action }); return }
    toastModel.append({ key: key, kind: "message", ref: "", text: message, tone: tone, serial: toastSerial, action: action })
  }
  function forgetToastAction(key) {
    if (!toastActions[key]) return
    var actions = Object.assign({}, toastActions)
    delete actions[key]
    toastActions = actions
  }
  // ✕, Escape or a note's time running out. An approval or a request to use this computer
  // can't be dismissed: it stays until it is answered.
  function dismissToast(key) {
    var at = toastIndex(key)
    forgetToastAction(key)
    if (at === -1) return
    var row = toastModel.get(at), kind = row.kind, ref = row.ref
    if (kind === "approval" || kind === "pair" || kind === "question") return
    toastModel.remove(at)
    if (!service) return
    if (key === "action-error") service.actionError = ""
    else if (key === "action-note") service.actionNotice = ""
    else if (key === "refresh") dismissedRefresh = String(service.lastError || "")
    else if (kind === "need") service.hideNeed(ref)
    else if (kind === "problem") service.hideProblem(ref)
    else if (kind === "drop") service.dismissDrop(ref)
    else if (kind === "news") service.dismissWhatsNew()
    else if (kind === "theme") service.dismissThemeRun()
    else if (kind === "away") awayHidden = true
    else if (kind === "connect") connectHintDone = true
  }
  // The standing toasts follow their conditions: new ones join at the bottom, gone ones leave,
  // and one that stays keeps its place (and the keyboard, if it has it).
  function syncStanding() {
    if (!service) return
    var open = route === "computer" ? computer : null
    var wanted = StatusModel.standingToasts({
      route: route, computerId: computerId,
      approvals: service.approvals, questions: service.questions, pairRequests: service.pairRequests,
      needs: service.needsYou, problems: service.problems,
      drop: open && service.drops ? service.drops[computerId] || null : null,
      whatsNew: service.whatsNew, themeRun: service.themeRun,
      awayCount: service.away && Array.isArray(service.away.computers) ? service.away.computers.length : 0, awayHidden: awayHidden,
      connectPrompt: service.connectPrompt, firstTaskDone: service.firstTaskDone, connectHintDone: connectHintDone,
      serviceStopped: service.serviceStopped === true
    })
    var want = ({})
    for (var w = 0; w < wanted.length; w++) want[wanted[w].key] = wanted[w]
    for (var i = toastModel.count - 1; i >= 0; i--) {
      var row = toastModel.get(i)
      if (row.kind !== "message" && !want[row.key]) toastModel.remove(i)
    }
    for (var j = 0; j < wanted.length; j++) {
      var at = toastIndex(wanted[j].key)
      if (at !== -1) { if (toastModel.get(at).tone !== wanted[j].tone) toastModel.setProperty(at, "tone", wanted[j].tone); continue }
      toastSerial += 1
      toastModel.append({ key: wanted[j].key, kind: wanted[j].kind, ref: wanted[j].ref, text: "", tone: wanted[j].tone, serial: toastSerial, action: "" })
    }
  }
  function syncStandingLater() { Qt.callLater(syncStanding) }
  onRouteChanged: syncStandingLater()
  onComputerIdChanged: syncStandingLater()
  onAwayHiddenChanged: syncStandingLater()
  onConnectHintDoneChanged: syncStandingLater()
  // The keyboard back on the page, where it was before the toasts took it.
  function focusPage() { if (activeRoute) activeRoute.focusDefault() }
  // F6: the keyboard goes to the toasts, and from there back to the page.
  function toggleToastFocus() {
    if (!toastStack) return
    if (toastStack.activeFocus) focusPage()
    else toastStack.focusStack()
  }
  // The bar opened one approval: the keyboard lands on its Approve.
  function focusApproval(ref) { return !!toastStack && toastStack.focusKey("approval:" + ref, true) }

  // ---- Connect an Agent: the prompt in a card attached to the control that opened it, the
  // fleet's toolbar button unless another is given. Opening it again from there closes it.
  function openConnect(anchor) {
    var button = activeRoute && activeRoute.connectButton && activeRoute.connectButton.visible ? activeRoute.connectButton : null
    var at = anchor || button || focusedItem
    if (connectOpen && connectAnchor === at) { closeConnect(); return }
    confirmation = null
    connectHintDone = true
    if (service && !service.connectPrompt) service.loadConnectPrompt()
    connectAnchor = at
    connectOpen = true
  }
  function closeConnect() {
    if (!connectOpen) return
    var item = connectAnchor
    connectOpen = false
    connectAnchor = null
    returnFocus(item)
  }
  // A message with one action beside it (Undo, Add Another). The action runs once, then the message goes.
  function offerAction(key, text, actionLabel, run) {
    if (typeof run !== "function") return
    var actions = Object.assign({}, toastActions)
    actions[key] = run
    toastActions = actions
    showToast(key, text, false, actionLabel)
  }
  // A change that already applied, with Undo beside it.
  function offerUndo(text, run) { offerAction("undo", text, "Undo", run) }
  // Computers added since the last time nothing was being added (Add All adds several at once).
  property var addedLabels: []
  // A computer was added. When nothing else is still being added or went wrong on Add Computer,
  // the console goes back to the fleet, where the new cards are, and offers Add Another.
  function computerAdded(label) {
    if (!opened || !service) return
    var pairings = service.pairings || ({})
    var idle = !service.pairingActive
    var clean = idle && Object.keys(pairings).every(function(node) { return pairings[node].state === "paired" })
    var labels = addedLabels.concat([String(label)])
    addedLabels = idle ? [] : labels
    var names = labels.length === 1 ? labels[0] : labels.slice(0, -1).join(", ") + " and " + labels[labels.length - 1]
    var onFleet = "Added " + names + (labels.length === 1 ? ". It's on your fleet now." : ". They're on your fleet now.")
    if (route === "add" && clean) {
      showFleet()
      offerAction("added", onFleet, "Add Another", function() { root.showAdd() })
    } else if (route === "add") {
      offerAction("added", "Added " + names + ".", "Show Fleet", function() { root.showFleet() })
    } else {
      showToast("added", onFleet, false)
    }
  }
  function runToastAction(key) {
    var run = toastActions[key]
    dismissToast(key)
    if (typeof run === "function") run()
  }
  // A page's own message about what just happened there. A page may keep its own "page-…" toast
  // (the Files tab's folder error); every one of them goes when the page does.
  function notify(text, error) { showToast(error ? "page-error" : "page-note", text, error === true) }
  function clearPageToasts() {
    for (var i = toastModel.count - 1; i >= 0; i--) {
      var key = toastModel.get(i).key
      if (key.indexOf("page-") === 0 || key === "undo") { toastModel.remove(i); forgetToastAction(key) }
    }
  }
  // An error with a known fix offers Fix It beside it; Fix It runs that fix on the computer.
  function syncActionError() {
    var text = service ? String(service.actionError || "") : ""
    var fix = service && text && !service.denied ? service.actionErrorFix : null
    if (fix && fix.computerId && fix.fix) {
      var actions = Object.assign({}, toastActions)
      actions["action-error"] = function() { if (root.service) root.service.repair(fix.computerId, fix.fix) }
      toastActions = actions
      showToast("action-error", text, true, "Fix It")
      return
    }
    forgetToastAction("action-error")
    showToast("action-error", text && service.denied ? "You don't have access." : text, true)
  }
  function syncActionNotice() { showToast("action-note", service ? String(service.actionNotice || "") : "", false) }
  function syncRefresh() {
    var text = service ? String(service.lastError || "") : ""
    if (text !== dismissedRefresh) dismissedRefresh = ""
    showToast("refresh", text !== dismissedRefresh ? text : "", true)
  }
  function syncToasts() { syncActionError(); syncActionNotice(); syncRefresh(); syncStanding() }
  onServiceChanged: syncToasts()

  // ---- lifecycle
  function open(payloadJson) {
    var payload = ({})
    try { payload = JSON.parse(payloadJson || "{}") || ({}) } catch (error) {}
    if (service && typeof service.setSurfaceOpen === "function") service.setSurfaceOpen("console", true)
    // The route is chosen before the window exists, so only that route's page is built.
    if (payload.route === "computer" && typeof payload.computerId === "string" && payload.computerId) {
      // The bar opens one approval directly: the keyboard lands on its Approve.
      pendingFocus = payload.focus === "approval" && typeof payload.ref === "string" ? { kind: "approval", ref: payload.ref } : null
      showComputer(payload.computerId, payload.tab)
    }
    else if (payload.route === "add" || payload.view === "setup") showAdd()
    else if (payload.route === "settings") showSettings()
    else if (payload.route === "share") showShare()
    else if (payload.route === "fleet") showFleet()
    else if (service && service.routeSerial !== undefined && service.routeSerial !== seenRouteSerial) applyServiceRoute()
    // Fleet first: without an explicit or pending request the console opens on the wall.
    else showFleet()
    syncToasts()
    root.controller.show()
  }
  function close() {
    root.controller.hide()
    resetOnClose()
  }
  function requestClose() {
    if (shell && typeof shell.hide === "function") shell.hide("io.zet.ibara")
    else close()
  }
  // Closing forgets the open computer, its scope and any pending route, so the next plain
  // open lands on the fleet. The reset is silent: no route change is shown while hidden.
  function resetOnClose() {
    confirmation = null
    connectOpen = false
    connectAnchor = null
    pendingFocus = null
    addedLabels = []
    clearPageToasts()
    // While you were away shows again next time, until Mark All Seen.
    awayHidden = false
    if (!service) return
    if (typeof service.setSurfaceOpen === "function") service.setSurfaceOpen("console", false)
    routing = true
    if (typeof service.openFleet === "function") service.openFleet()
    routing = false
    applyRoute("fleet", "", "")
  }
  onOpenedChanged: if (!opened) resetOnClose()

  function showFleet() {
    routing = true
    if (service && typeof service.openFleet === "function") service.openFleet()
    routing = false
    applyRoute("fleet", "", "")
  }
  function showComputer(id, nextTab) {
    var key = String(id || "")
    if (!computerById(key)) { showFleet(); return }
    routing = true
    var accepted = !(service && typeof service.openComputer === "function") || service.openComputer(key) !== false
    routing = false
    if (!accepted) { showFleet(); return }
    applyRoute("computer", key, nextTab || (key === computerId ? tab : "screen"))
  }
  function showAdd() {
    routing = true
    if (service && typeof service.openAdd === "function") service.openAdd()
    routing = false
    applyRoute("add", "", "")
  }
  // Share This Computer: invites for friends to use this computer.
  function showShare() {
    routing = true
    if (service && typeof service.openShare === "function") service.openShare()
    routing = false
    applyRoute("share", "", "")
  }
  // This console's own settings. Each computer's own are on its Settings tab.
  function showSettings() {
    routing = true
    if (service && typeof service.openFleet === "function") service.openFleet()
    routing = false
    applyRoute("settings", "", "")
  }
  function applyServiceRoute() {
    if (!service) return
    seenRouteSerial = service.routeSerial
    var next = String(service.requestedRoute || "fleet")
    if (next === "computer" && computerById(service.requestedComputerId)) applyRoute("computer", String(service.requestedComputerId), "screen")
    else if (next === "add") applyRoute("add", "", "")
    else if (next === "share") applyRoute("share", "", "")
    else applyRoute("fleet", "", "")
  }
  function toggleFavorite(id) {
    var next = Object.assign({}, favorites)
    if (next[id]) delete next[id]; else next[id] = true
    favorites = next
  }
  function applyRoute(nextRoute, id, nextTab) {
    var changed = nextRoute !== route || String(id || "") !== computerId
    if (changed) { confirmation = null; connectOpen = false; connectAnchor = null; clearPageToasts() }
    // The computer and tab are set before the route, so a computer view built by this
    // change starts on them and builds only that tab. Leaving a computer clears it after
    // the route has moved, so the cleared computer does not route back to the fleet.
    if (nextRoute === "computer") {
      computerId = String(id || "")
      tab = computerTabs.indexOf(nextTab) !== -1 ? nextTab : "screen"
    }
    route = nextRoute
    if (nextRoute !== "computer") computerId = ""
    if (service && service.routeSerial !== undefined) seenRouteSerial = service.routeSerial
    Qt.callLater(function() {
      if (!root.opened) return
      root.publishVisibility()
      if (root.activeRoute && (changed || !root.focusInside(root.activeRoute))) root.activeRoute.focusDefault()
    })
  }
  function focusInside(ancestor) {
    for (var item = root.focusedItem; item; item = item.parent) if (item === ancestor) return true
    return false
  }
  function setTab(nextTab) {
    if (route !== "computer" || computerTabs.indexOf(nextTab) === -1) return
    if (nextTab !== tab) confirmation = null
    tab = nextTab
  }
  function publishVisibility() {
    if (!service || typeof service.setVisibleComputerIds !== "function") return
    if (activeRoute && typeof activeRoute.publishVisibility === "function") activeRoute.publishVisibility()
    else service.setVisibleComputerIds([])
  }
  Connections {
    target: root.service
    ignoreUnknownSignals: true
    function onOpenComputerRequested(computerId) { root.serviceRouteRequested() }
    function onOpenFleetRequested() { root.serviceRouteRequested() }
    function onOpenAddRequested() { root.serviceRouteRequested() }
    function onOpenShareRequested() { root.serviceRouteRequested() }
    function onPairingAdded(node, label) { root.computerAdded(label) }
    function onActionErrorChanged() { root.syncActionError() }
    function onDeniedChanged() { root.syncActionError() }
    function onActionNoticeChanged() { root.syncActionNotice() }
    function onAgentAllowed(computerId, text) { root.offerAction("allowed", text, "Open Access", function() { root.showComputer(computerId, "access") }) }
    function onLastErrorChanged() { root.syncRefresh() }
    function onActionErrorFixChanged() { root.syncActionError() }
    // Standing toasts: approvals, questions, requests to use this computer, computers that need
    // you or are offline, files on their way, What's New, a theme run, While you were away and
    // whether an agent has begun a task.
    function onApprovalsChanged() { root.syncStandingLater() }
    function onQuestionsChanged() { root.syncStandingLater() }
    function onNeedsYouChanged() { root.syncStandingLater() }
    function onProblemsChanged() { root.syncStandingLater() }
    function onPairRequestsChanged() { root.syncStandingLater() }
    function onDropsChanged() { root.syncStandingLater() }
    function onWhatsNewChanged() { root.syncStandingLater() }
    function onThemeRunChanged() { root.syncStandingLater() }
    function onAwayChanged() { root.syncStandingLater() }
    function onConnectPromptChanged() { root.syncStandingLater() }
    function onFirstTaskDoneChanged() { root.syncStandingLater() }
    // ibara isn't running here: one toast in place of every other standing one.
    function onServiceStoppedChanged() { root.syncStandingLater() }
    // Pause and Resume undo each other; a settings change goes back to what it was.
    function onAgentsPaused(computerId, paused) {
      var name = root.tokens.label(root.computerById(computerId))
      root.offerUndo(paused ? "Paused the agents on " + name + "." : "The agents on " + name + " can work again.", function() {
        if (paused) root.service.resumeAgents(computerId); else root.service.pauseAgents(computerId)
      })
    }
    function onSettingsApplied(computerId, changes, text) {
      root.offerUndo(text, function() { root.service.restoreSettings(computerId, changes) })
    }
  }
  function serviceRouteRequested() {
    if (!routing && service && service.routeSerial !== seenRouteSerial) applyServiceRoute()
  }
  // Selected-quality previews run only while the open computer's Screen tab is showing.
  Binding {
    target: root.service
    property: "watchVisible"
    value: root.opened && root.route === "computer" && root.tab === "screen"
    when: !!root.service
  }
  // A computer that leaves the directory closes its view; its repair can start or end any time.
  onComputerChanged: { if (route === "computer" && !computer) showFleet(); syncStandingLater() }

  // ---- confirmation: a small card attached to the control that asked (NearbyConfirm.qml).
  // options: { message, confirmLabel, danger, run, valid?, anchor?, subject?, staleMessage? }.
  // The anchor defaults to the focused control, which is the button just clicked or pressed.
  // Asking again from the same control closes it instead.
  function askConfirm(options) {
    if (!options || typeof options.run !== "function") return
    var anchor = options.anchor || root.focusedItem || null
    if (confirmation && anchor && confirmation.anchor === anchor) { cancelConfirm(); return }
    confirmReturnItem = anchor
    confirmation = {
      message: String(options.message || ""),
      confirmLabel: String(options.confirmLabel || "Confirm"),
      danger: options.danger === true,
      run: options.run,
      valid: typeof options.valid === "function" ? options.valid : null,
      anchor: anchor,
      subject: String(options.subject || ""),
      staleMessage: String(options.staleMessage || ""),
      route: route, computerId: computerId
    }
  }
  // Focus goes back to the control that asked (an Access cell's own button), else the page's default.
  function returnFocus(item) {
    Qt.callLater(function() {
      if (item && item.visible) { if (typeof item.focusTrigger === "function") item.focusTrigger(); else item.forceActiveFocus() }
      else if (root.activeRoute) root.activeRoute.focusDefault()
    })
  }
  function cancelConfirm() {
    var item = confirmReturnItem
    confirmation = null
    confirmReturnItem = null
    returnFocus(item)
  }
  function runConfirm() {
    var pending = confirmation
    var item = confirmReturnItem
    confirmation = null
    confirmReturnItem = null
    if (!pending || !service) return
    if (pending.route !== route || pending.computerId !== computerId) return
    if (pending.valid && !pending.valid()) {
      if (pending.staleMessage) notify(pending.staleMessage, true)
      else service.actionError = "Nothing was changed: the computer changed while you were confirming. Choose the action again to see what it will do now."
    } else {
      pending.run()
    }
    returnFocus(item)
  }

  // ---- shared computer actions
  function holds(id) { return !!service && typeof service.holdsControlOn === "function" && service.holdsControlOn(id) }
  function controlBlockedReason(c) {
    if (!c || !service) return "This computer is not available."
    if (service.denied) return "You don't have access."
    if (holds(c.computer_id)) return service.mutating ? "Wait for the current action to finish." : ""
    if (c.trust_state !== "verified") return "This computer isn't paired from here. Pair it again from Add Computer."
    if (c.interactive_control !== "available_if_exclusive") return "Take Control isn't available on this computer: it doesn't let this computer take control, or its screen sharing is being repaired or isn't installed."
    if (StatusModel.computerState(c) === "offline") return "This computer is not answering."
    if (service.mutating) return "Wait for the current action to finish."
    return ""
  }
  function takeControl(id) {
    var c = computerById(id)
    if (!c || controlBlockedReason(c)) return
    if (holds(id)) { service.openViewerFor(id); return }
    var owner = String(c.owner_name || ""), revision = String(c.ownership_revision || "")
    var who = tokens.actor(c)
    var name = tokens.label(c)
    askConfirm({
      message: "Take control of " + name + "?" + (who && who !== "you" ? " " + who.charAt(0).toUpperCase() + who.slice(1) + " is using it now." : "") +
        " Taking control pauses its agent. Closing the viewer does not hand it back.",
      confirmLabel: "Take Control",
      subject: id,
      run: function() { service.takeControlFor(id) },
      valid: function() {
        var now = root.computerById(id)
        return !!now && String(now.owner_name || "") === owner && String(now.ownership_revision || "") === revision
      }
    })
  }
  function handBack(id) {
    if (!holds(id) || !service || service.mutating) return
    service.handBackFor(id)
  }
  // Restart, Shut Down, Sleep, Lock Screen and Update can't be undone from here, so each asks
  // first, beside the control that asked, and says what happens next.
  function confirmPower(id, action, anchor) {
    var c = computerById(id)
    if (!c || !service) return
    var name = tokens.label(c), wakeable = !!c.wake
    var text = ({
      restart: "Restart " + name + "? Its agents stop until it's back." + (c.disk_password === true ? " Its disk asks for its password when it starts, so someone must type it there before ibara can reach it again." : " ibara reconnects when it's back."),
      shutdown: "Shut down " + name + "?" + (wakeable ? " Wake can turn it on again from here." : " Someone must turn it on again there."),
      sleep: "Put " + name + " to sleep?" + (wakeable ? " Wake wakes it from here." : " ibara has no way to wake it from here, so someone must wake it there."),
      lock: "Lock " + name + "'s screen? Agents can't use its desktop until someone unlocks it there.",
      update: "Update " + name + "? It may restart when the update finishes."
    })[action]
    if (!text) return
    askConfirm({
      anchor: anchor,
      message: text,
      confirmLabel: ({ restart: "Restart", shutdown: "Shut Down", sleep: "Sleep", lock: "Lock Screen", update: "Update" })[action],
      danger: ["restart", "shutdown", "sleep"].indexOf(action) !== -1,
      subject: id,
      run: function() { root.service.power(id, action) },
      valid: function() { return !!root.computerById(id) }
    })
  }

  // Remove Computer takes a computer out of this fleet (after a reinstall, say); Add Computer adds
  // it again with the same checks as the first time.
  function confirmRemove(id, anchor) {
    var c = computerById(id)
    if (!c || !service) return
    askConfirm({
      anchor: anchor,
      message: "Remove " + tokens.label(c) + " from your fleet? You can add it again from Add Computer.",
      confirmLabel: "Remove Computer",
      danger: true,
      subject: id,
      run: function() { root.service.removeComputer(id) },
      valid: function() { return !!root.computerById(id) }
    })
  }

  // ---- keyboard: Escape backs out, F5 refreshes, / finds, Ctrl+, opens Settings, F6 moves between
  // the page and its toasts. Tab and arrows follow focus.
  function textFocused() {
    var item = root.focusedItem
    return !!item && (item.cursorPosition !== undefined && item.selectByMouse !== undefined)
  }
  function handleKey(event) {
    if (event.key === Qt.Key_Escape) {
      // Escape closes what floats first: the confirmation, then the newest message that can go.
      if (confirmation) cancelConfirm()
      else if (connectOpen) closeConnect()
      else if (toastStack && toastStack.dismissNewest()) {}
      else if (route !== "fleet") showFleet()
      else requestClose()
      event.accepted = true
      return
    }
    if (event.key === Qt.Key_F6) {
      toggleToastFocus()
      event.accepted = true
      return
    }
    if (event.key === Qt.Key_F5) {
      if (service) service.refresh()
      if (activeRoute && typeof activeRoute.reload === "function") activeRoute.reload()
      event.accepted = true
      return
    }
    if (event.key === Qt.Key_Comma && (event.modifiers & Qt.ControlModifier)) {
      showSettings()
      event.accepted = true
      return
    }
    if (event.key === Qt.Key_Slash && !textFocused() && activeRoute && typeof activeRoute.focusSearch === "function") {
      activeRoute.focusSearch()
      event.accepted = true
    }
  }

  // A route's page is built the first time it is shown in this opening and kept until the
  // console closes. It stays hidden until built, so it sees the same hidden-to-shown change
  // that starts its reads and focus as when every page was built up front. The latch is set
  // from handlers (a binding on `active` would re-enter itself while the page loads) and only
  // once creation has settled, so a passing initial value never builds a page.
  component RoutePage: Loader {
    property string page
    property string current
    property bool settled: false
    anchors.fill: parent
    active: false
    visible: current === page && status === Loader.Ready
    onCurrentChanged: if (settled && current === page) active = true
    Component.onCompleted: { settled = true; if (current === page) active = true }
  }

  // A closed console owns no QML page tree or native rendering resources.
  Loader {
    id: windowLoader
    active: root.opened
    onActiveChanged: if (!active) Qt.callLater(function() { gc() })
    sourceComponent: Component {
  FloatingWindow {
    id: panel
    readonly property Item activeRoute: root.route === "computer" ? computerRoute.item : root.route === "add" ? addRoute.item : root.route === "settings" ? settingsRoute.item : root.route === "share" ? shareRoute.item : fleetRoute.item
    readonly property var focusedItem: keyboardSurface.Window.activeFocusItem
    readonly property Item toastStack: toasts
    title: "ibara · console"
    visible: root.opened
    color: Color.popups.background
    implicitWidth: Style.space(1700)
    implicitHeight: Style.space(920)
    minimumSize: Qt.size(Style.space(900), Style.space(560))
    onVisibleChanged: if (!visible && root.opened) root.requestClose()

    FocusScope {
      id: keyboardSurface
      anchors.fill: parent
      // Pages start just under the window's top edge: 8 px above the header, 14 around the rest.
      anchors.margins: Style.space(14)
      anchors.topMargin: Style.space(8)
      focus: true
      Keys.onPressed: function(event) { root.handleKey(event) }

      RoutePage {
        id: fleetRoute
        page: "fleet"
        current: root.route
        sourceComponent: Component {
          FleetWall {
            host: root
            service: root.service
          }
        }
      }
      RoutePage {
        id: computerRoute
        page: "computer"
        current: root.route
        sourceComponent: Component {
          ComputerView {
            host: root
            service: root.service
            computerId: root.computerId
            computer: root.computer
            tab: root.tab
          }
        }
      }
      RoutePage {
        id: addRoute
        page: "add"
        current: root.route
        sourceComponent: Component {
          AddComputer {
            host: root
            service: root.service
          }
        }
      }
      RoutePage {
        id: shareRoute
        page: "share"
        current: root.route
        sourceComponent: Component {
          SharePage {
            host: root
            service: root.service
          }
        }
      }
      RoutePage {
        id: settingsRoute
        page: "settings"
        current: root.route
        sourceComponent: Component {
          SettingsPage {
            host: root
            service: root.service
          }
        }
      }

      // Every message, over the page's bottom-right corner under its header; the page never
      // moves for them.
      Toasts {
        id: toasts
        host: root
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        width: Math.min(parent.width, Style.space(560))
        room: parent.height - (panel.activeRoute && panel.activeRoute.headerHeight !== undefined ? panel.activeRoute.headerHeight : 0) - Style.space(8)
      }
      // The pending confirmation, attached to the control that asked.
      NearbyConfirm { host: root }
      // Connect an Agent, attached to the button that opened it.
      AgentConnectDialog { host: root }
    }
  }
  }
  }
}
