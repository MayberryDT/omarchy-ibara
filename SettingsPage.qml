import QtQuick
import qs.Commons
import qs.Ui
import "StatusModel.js" as StatusModel

// This console's own settings (`settings`): notifications, where files from other computers are
// saved, and how often the fleet's pictures refresh. A change applies at once, and a message
// offers Undo. Each computer's own settings are on its Settings tab. Escape returns to the fleet.
// Under This Computer, Start without the disk password (`unattended-boot`) changes in a terminal,
// because it needs root and the disk password; Lock the screen at sign-in changes at once.
// Under Logins (`login-settings`): the switch that makes this the computer your logins come from
// (turning it off asks first), the browser and profile they come from, and the All Computers
// rules, whose Denied sites are never shared, with a field to add one.
Item {
  id: root
  property var host: null
  property var service: null
  // The header is as tall as its tallest line plus a hairline margin, as on the fleet.
  readonly property real headerHeight: Math.ceil(Math.max(crumb.implicitHeight, backButton.implicitHeight)) + Style.space(6)
  readonly property Tokens tokens: Tokens {}
  readonly property var logins: service ? service.loginSettings : null
  readonly property string targetRoleText: "This computer also runs agents, so it can't share logins yet. Turn on sharing from the computer you use."
  // Logins, as one setting (the switch) with the rest under it; shown once ibara here can share logins.
  readonly property var loginSections: logins ? [{ id: "logins", title: "Logins", settings: [{
    // Its default is what it is now: Reset makes no sense for the computer your logins come from.
    key: "login_sharing", title: "Let agents use your logins", type: "bool", value: logins.enabled, "default": logins.enabled, scope: "console",
    help: "When an agent reaches a sign-in page, ibara asks you first, then copies just that site's login from your browser to the agent's computer. Your browser shows “Managed by your organization” while this is on."
  }] }] : []

  function focusDefault() { list.focusDefault() }
  function focusSearch() { list.focusSearch() }
  function reload() { if (service && visible) { service.loadConsoleSettings(); service.loadUnattendedBoot(); service.loadLoginSettings() } }
  function isThisComputer(key) { return key === "unattended_boot" || key === "lock_at_sign_in" }
  function setThisComputer(key, on) { return key === "lock_at_sign_in" ? service.setSignInLock(on) : service.setUnattendedBoot(on) }
  // On runs at once; off asks first, since what's shared stays until it runs out or is removed.
  function setLogins(on) {
    if (!service || !logins) return
    if (!on) { if (host) host.confirmLoginsOff(host.focusedItem); return }
    if (logins.targetRole) { service.actionError = targetRoleText; return }
    if (host) host.turnOnLogins(host.focusedItem)
  }
  onVisibleChanged: reload()

  // ---- top bar: Back returns to the fleet, as Escape does; close stays apart past a rule.
  Item {
    id: header
    width: parent.width
    height: root.headerHeight
    IbaraMark {
      id: mark
      width: Style.space(22)
      height: width
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
      color: Color.accent
    }
    ActionButton {
      id: backButton
      anchors.left: mark.right
      anchors.leftMargin: Style.space(10)
      anchors.verticalCenter: parent.verticalCenter
      glyph: "‹"
      label: "Fleet"
      Accessible.name: "Back to the fleet"
      tooltipText: "Back to the fleet (Escape)"
      onClicked: if (root.host) root.host.showFleet()
    }
    Copy {
      id: crumb
      anchors.left: backButton.right
      anchors.leftMargin: Style.space(14)
      anchors.verticalCenter: parent.verticalCenter
      text: "Settings"
      font.pixelSize: Style.font.heading + Style.space(4)
      font.bold: true
    }
    // Which settings these are, beside the title: nothing sits between the header and the list.
    Copy {
      anchors.left: crumb.right
      anchors.leftMargin: Style.space(14)
      anchors.right: closeRule.left
      anchors.rightMargin: Style.space(14)
      anchors.baseline: crumb.baseline
      text: "For ibara on this computer. Each computer's own settings are on its Settings tab."
      dimmed: true
      wrapMode: Text.NoWrap
      elide: Text.ElideRight
    }
    Rectangle {
      id: closeRule
      anchors.right: closeButton.left
      anchors.rightMargin: Style.space(10)
      anchors.verticalCenter: parent.verticalCenter
      width: 1
      height: closeButton.height
      radius: 0
      color: root.tokens.rule
    }
    ActionButton {
      id: closeButton
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      label: "✕"
      role: "quiet"
      Accessible.name: "Close console"
      tooltipText: "Close the console"
      onClicked: if (root.host) root.host.requestClose()
    }
    Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; radius: 0; color: root.tokens.rule }
  }

  SettingsList {
    id: list
    y: root.headerHeight + Style.space(12)
    height: parent.height - y
    width: parent.width
    centered: true
    sections: root.service ? root.service.requestSettingsSections.concat(root.service.consoleSettings.map(function(section) { return Object.assign({}, section, { settings: section.settings.filter(function(s) { return s.key !== "approval_notifications" }) }) }), root.service.unattendedBootSections, root.loginSections) : []
    busy: root.service ? Object.assign({}, root.service.settingsBusyFor(""), root.service.busy["login-on"] ? { login_sharing: root.service.busy["login-on"] } : {}) : ({})
    errors: root.service ? root.service.settingsErrorsFor("") : ({})
    // Live Video: each computer that can't stream says why, and so does a desktop that can't play it.
    notes: root.service ? {
      live_video: [root.service.videoPlayerWorks ? "" : "Video can't play here: install qt6-multimedia and qt6-multimedia-ffmpeg.", root.service.videoReasons].filter(function(line) { return line !== "" }).join("\n"),
      login_sharing: !root.logins ? "" : root.logins.targetRole ? root.targetRoleText
        : !root.logins.enabled && root.service.loginSourceElsewhere(null) ? "Logins for your computers come from " + root.service.loginSourceElsewhere(null) + " now. Turning this on shares from this computer instead."
        : root.logins.enabled && !root.logins.connected ? "Open " + root.service.loginBrowserName + " so ibara can share from it. Requests wait until it runs."
        : ""
    } : ({})
    extras: ({ login_sharing: loginExtras })
    emptyText: root.service && root.service.consoleSettingsError ? root.service.consoleSettingsError : "Loading settings…"
    onChangeRequested: (key, value) => {
      if (!root.service) return
      if (key === "login_sharing") root.setLogins(value === "true")
      else if (root.isThisComputer(key)) root.setThisComputer(key, value === "true")
      else root.service.changeSetting("", key, value)
    }
    onResetRequested: key => {
      if (!root.service) return
      if (key === "login_sharing") root.setLogins(false)
      else if (root.isThisComputer(key)) root.setThisComputer(key, false)
      else root.service.resetSetting("", key)
    }
    onSectionResetRequested: sectionId => {
      if (!root.service) return
      if (sectionId === "logins") root.setLogins(false)
      else if (sectionId === "this_computer") root.service.resetThisComputer()
      else root.service.resetSection("", sectionId)
    }
  }

  // Under Let agents use your logins: the browser and profile logins come from (chosen while
  // sharing is off), then the All Computers rules. A Denied site is never shared with any computer.
  Component {
    id: loginExtras
    Column {
      id: extras
      spacing: Style.space(8)
      readonly property var s: root.logins
      readonly property var pick: root.service ? root.service.loginPick : null
      readonly property var choices: {
        var out = [], list = s ? s.browsers : []
        for (var i = 0; i < list.length; i++) for (var j = 0; j < list[i].profiles.length; j++)
          if (list[i].supported) out.push({ id: list[i].browser + "\n" + list[i].profiles[j], browser: list[i].browser, profile: list[i].profiles[j], label: list[i].name + " · " + list[i].profiles[j],
            selected: !!extras.pick && extras.pick.browser === list[i].browser && extras.pick.profile === list[i].profiles[j] })
        return out
      }
      readonly property var sites: s ? Object.keys(s.allRules).sort() : []
      readonly property string pickLabel: pick ? root.service.loginBrowserName + " · " + pick.profile : ""
      Item { width: 1; height: Style.space(2) }
      Row {
        spacing: Style.space(8)
        Copy {
          anchors.verticalCenter: parent.verticalCenter
          text: !extras.s ? "" : extras.s.enabled ? "Logins come from " + root.service.loginBrowserName + " · " + extras.s.profile + " on this computer."
            : extras.choices.length ? "Logins would come from" : "ibara found no Chromium, Google Chrome or Brave on this computer."
          color: root.tokens.textTint(extras.s && extras.s.enabled ? root.tokens.readyColor : root.tokens.pausedColor)
          font.pixelSize: Style.font.bodySmall
        }
        ActionMenu {
          visible: !!extras.s && !extras.s.enabled && extras.choices.length > 0
          anchors.verticalCenter: parent.verticalCenter
          size: "small"
          role: "secondary"
          label: extras.pickLabel + " ▾"
          accessibleName: "Share logins from: " + extras.pickLabel
          items: extras.choices
          onTriggered: id => { var parts = id.split("\n"); root.service.chooseLoginBrowser(parts[0], parts[1]) }
        }
      }
      Copy {
        visible: !!extras.s && extras.s.enabled
        width: parent.width
        text: "To use another browser or profile, turn this off, choose it, and turn it on again."
        dimmed: true
        font.pixelSize: Style.font.bodySmall
      }
      Copy {
        width: parent.width
        topPadding: Style.space(6)
        text: "All Computers"
        font.bold: true
      }
      Copy {
        width: parent.width
        text: extras.sites.length ? "These rules hold on every computer. Denied wins over Ask First, and Ask First over Allowed, as on the Access tab; Denied sites are never shared."
          : "No rules for All Computers yet. Share With All Computers on a request adds one; so does Never Share, below or on a request."
        dimmed: true
        font.pixelSize: Style.font.bodySmall
      }
      Repeater {
        model: extras.sites
        delegate: Item {
          required property string modelData
          width: extras.width
          height: Math.max(siteText.implicitHeight, siteRule.implicitHeight) + Style.space(4)
          Copy { id: siteText; anchors.verticalCenter: parent.verticalCenter; text: modelData; font.pixelSize: Style.font.bodySmall }
          RuleMenu {
            id: siteRule
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            rule: extras.s ? extras.s.allRules[modelData] || "ask" : "ask"
            blocked: !extras.s || !extras.s.enabled || !!root.service.busy["login-rule:all:" + modelData]
            disabledReason: extras.s && !extras.s.enabled ? "Turn login sharing on to change its rules." : ""
            accessibleName: modelData + " on all computers"
            onChosen: function(value) { root.service.setLoginRule("all", modelData, value) }
          }
        }
      }
      // Never Share a site before any agent asks: Denied for All Computers.
      Row {
        spacing: Style.space(8)
        FieldInput {
          id: neverField
          width: Math.min(Style.space(260), extras.width - neverButton.width - Style.space(8))
          placeholder: "chase.com"
          accessibleName: "A site to never share"
          onAccepted: neverButton.clicked()
          onEdited: neverError.text = ""
        }
        ActionButton {
          id: neverButton
          anchors.verticalCenter: parent.verticalCenter
          label: "Never Share"
          role: "danger"
          size: "small"
          blocked: !extras.s || !extras.s.enabled || neverField.text.trim() === ""
          disabledReason: extras.s && !extras.s.enabled ? "Turn login sharing on to change its rules." : neverField.text.trim() === "" ? "Type a site, like chase.com." : ""
          tooltipText: disabledReason || "Deny this site on every computer, so no agent is ever given its login"
          onClicked: {
            if (blocked) return
            var site = StatusModel.loginSite(neverField.text)
            if (!site) { neverError.text = "Type one site, like chase.com, without https:// or a path."; return }
            if (root.service.setLoginRule("all", site, "deny")) { neverField.text = ""; neverError.text = "" }
          }
        }
      }
      Copy { id: neverError; visible: text !== ""; width: parent.width; color: root.tokens.textTint(root.tokens.attentionColor); font.pixelSize: Style.font.bodySmall }
    }
  }
}
