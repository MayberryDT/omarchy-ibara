import QtQuick
import qs.Commons
import qs.Ui
import "StatusModel.js" as StatusModel

// Tasks, procedures awaiting review and task results on this computer, with the
// selected record's detail and evidence. Reads are scoped to the open computer by Service.
Item {
  id: root
  property var host: null
  property var service: null
  property string computerId: ""
  property var computer: null
  property string detailKind: "task"
  property bool showTechnicalDetail: false
  property int extendSeconds: 300
  readonly property Tokens tokens: Tokens {}
  readonly property string computerLabel: tokens.label(computer)
  readonly property var tasks: service ? service.tasks || [] : []
  readonly property var procedures: service ? service.procedures || [] : []
  readonly property var artifacts: service ? service.artifacts || [] : []
  readonly property var followed: service && service.followedTasks ? service.followedTasks[computerId] : null
  readonly property var detail: service ? service.selectedTaskDetail || ({}) : ({})
  readonly property var selectedTaskRecord: {
    if (!service || !service.selectedTaskRef) return null
    var extra = service.selectedTaskDetailRef === service.selectedTaskRef ? service.selectedTask || {} : {}
    for (var i = 0; i < tasks.length; i++)
      if (tasks[i].task_ref === service.selectedTaskRef) return Object.assign({}, tasks[i], extra)
    return extra
  }
  readonly property var selectedArtifact: {
    if (!service || !service.selectedArtifactRef) return null
    for (var i = 0; i < artifacts.length; i++) if (artifacts[i].artifact_ref === service.selectedArtifactRef) return artifacts[i]
    return null
  }
  readonly property string actionReason: !service ? "Connecting." : service.denied ? "You don't have access." : service.mutating ? "Wait for the current action to finish." : ""

  function reload() {
    if (!service || !visible || !computerId) return
    service.loadTasks()
    service.loadProcedures()
    service.loadArtifacts()
  }
  onVisibleChanged: reload()
  onComputerIdChanged: { detailKind = "task"; showTechnicalDetail = false; reload() }

  // ---- task wording (unchanged meaning from the single-computer console)
  function taskState(task) {
    task = task || ({})
    if (task.live || task.state === "active" || task.state === "running") return "In progress"
    if (task.state === "completed" || task.completion_outcome === "complete" || task.completion_outcome === "completed") return "Finished"
    return tokens.sentence(task.state || task.completion_outcome) || "Unknown"
  }
  function taskStateColor(task) {
    var state = taskState(task)
    return state === "In progress" ? tokens.workingColor : state === "Finished" ? tokens.readyColor : tokens.pausedColor
  }
  function taskProjection(item) {
    item = item || ({})
    var task = item.task || item
    return item.completion_projection || task.completion_projection || task.verification || ({})
  }
  // Whether ibara checked that the task did what it said, in plain words.
  function taskProof(item) {
    var task = (item || {}).task || item || {}
    var proof = taskProjection(item)
    if (proof.verified_complete === true) return "ibara checked the result"
    if (!Object.keys(proof).length) return task.live ? "ibara hasn't checked the result yet" : "ibara didn't check the result"
    return "ibara couldn't confirm the result"
  }
  // The agent the way the fleet names it: "agent from relay".
  function taskAgent(task) { return task && task.principal ? "agent from " + String(task.principal) : "" }
  function taskReceipts(item) { return StatusModel.listOf(item || ({}), "receipts") }
  function taskWarning(item) {
    var proof = taskProjection(item)
    if (Array.isArray(proof.unresolved_request_refs) && proof.unresolved_request_refs.length) return "Some steps may not have finished. See What it did below before running them again."
    var receipts = taskReceipts(item)
    for (var i = 0; i < receipts.length; i++)
      if (receipts[i].dependency_state === "unresolved" || receipts[i].requires_reconciliation || receipts[i].execution === "unknown" || receipts[i].effect === "unknown") return "Some steps may not have finished. See What it did below before running them again."
    return ""
  }
  function taskCriteria(item) {
    var projection = taskProjection(item)
    return Array.isArray(item && item.criteria) ? item.criteria : Array.isArray(projection.criteria) ? projection.criteria : []
  }
  function taskDeliveries(item) {
    var projection = taskProjection(item)
    return Array.isArray(item && item.deliveries) ? item.deliveries : Array.isArray(projection.deliveries) ? projection.deliveries : []
  }
  function taskReceiptState(item) {
    if (!item) return "Outcome unknown"
    if (item.dependency_state === "unresolved" || item.requires_reconciliation || item.execution === "unknown" || item.effect === "unknown") return "Needs review · do not repeat"
    if (item.error) return "Failed · " + StatusModel.clip(item.error, 140)
    return "Effect " + (tokens.sentence(item.effect).toLowerCase() || "unknown") + " · verification " + (tokens.sentence(item.verification).toLowerCase() || "unknown")
  }
  function taskCleanup(item) {
    var proof = taskProjection(item)
    if (proof.cleanup) return tokens.sentence(proof.cleanup)
    if (proof.cleanup_settled === true) return "Settled"
    if (proof.cleanup_settled === false) return "Unsettled"
    return "Not confirmed"
  }
  function procedureTitle(record) {
    return String((record && record.definition && record.definition.title) || "Untitled procedure")
  }
  // The version being approved: the digest the review showed.
  function procedureDigest(record) {
    return record ? String(record.source_sha256 || record.content_sha256 || "") : ""
  }
  function fileState(item) {
    if (!item) return "Unknown"
    if (item.bytes_available === false || item.delivery === "unavailable") return "Unavailable"
    if (item.delivery === "verified") return "Collected"
    if (item.bytes_available === true) return "Available"
    return "Availability unknown"
  }

  // ---- actions that change something go through the console's confirmation
  function selectTask(ref) { detailKind = "task"; showTechnicalDetail = false; service.inspectTask(ref) }
  function selectProcedure(ref) { detailKind = "procedure"; service.inspectProcedure(ref) }
  function selectArtifact(ref) { detailKind = "file"; service.selectedArtifactRef = ref }
  function confirmTask(message, label, danger, run) {
    var ref = String(service.selectedTaskRef || ""), scope = computerId
    if (!ref || !host) return
    host.askConfirm({ message: message, confirmLabel: label, danger: danger,
      run: function() { run(ref) },
      valid: function() { return root.service.selectedTaskRef === ref && String(root.service.scopedComputerId || "") === scope } })
  }
  function confirmProcedure(message, label, run) {
    var ref = String(service.selectedProcedureRef || ""), scope = computerId
    var digest = procedureDigest(service.selectedProcedure)
    if (!ref || !host) return
    host.askConfirm({ message: message.replace("%DIGEST%", digest.substring(0, 12)), confirmLabel: label,
      run: function() { run(ref, digest) },
      valid: function() {
        return root.service.selectedProcedureRef === ref && String(root.service.scopedComputerId || "") === scope &&
          (!digest || root.procedureDigest(root.service.selectedProcedure) === digest)
      } })
  }

  component RecordRow: Rectangle {
    id: recordRow
    property string title: ""
    property string meta: ""
    property color markerColor: Color.accent
    property bool current: false
    property int row: -1
    readonly property RowWindow rows: ListView.view ? ListView.view.parent as RowWindow : null
    signal picked()
    width: parent ? parent.width : 0
    height: rows ? rows.rowHeight : 0
    radius: 0
    color: current ? Qt.alpha(Color.accent, 0.14) : rowHover.hovered ? Qt.alpha(Color.popups.text, 0.05) : "transparent"
    border.width: activeFocus ? Math.max(2, Style.space(2)) : current ? 1 : 0
    border.color: activeFocus ? Color.accent : Qt.alpha(Color.accent, 0.6)
    activeFocusOnTab: true
    Accessible.role: Accessible.Button
    Accessible.name: title + ", " + meta
    Keys.onReturnPressed: picked()
    Keys.onEnterPressed: picked()
    Keys.onSpacePressed: picked()
    Keys.onTabPressed: function(event) { event.accepted = recordRow.rows.step(recordRow.row, recordRow, event) }
    Keys.onBacktabPressed: function(event) { event.accepted = recordRow.rows.step(recordRow.row, recordRow, event) }
    onActiveFocusChanged: if (activeFocus) rows.focused(row, recordRow)
    HoverHandler { id: rowHover }
    MouseArea { anchors.fill: parent; onClicked: { recordRow.forceActiveFocus(); recordRow.picked() } }
    Rectangle { x: Style.space(10); anchors.verticalCenter: parent.verticalCenter; width: Style.space(8); height: width; radius: 0; color: recordRow.markerColor }
    Copy {
      id: rowTitle
      x: Style.space(28)
      y: Style.space(7)
      width: parent.width - x - Style.space(10)
      text: recordRow.title
      wrapMode: Text.NoWrap
      elide: Text.ElideRight
    }
    Copy {
      x: Style.space(28)
      anchors.top: rowTitle.bottom
      anchors.topMargin: Style.space(2)
      width: parent.width - x - Style.space(10)
      text: recordRow.meta
      dimmed: true
      font.pixelSize: Style.font.bodySmall
      wrapMode: Text.NoWrap
      elide: Text.ElideRight
    }
  }

  component RecordList: RowWindow {
    flick: listScroll
    width: listColumn.width
    rowHeight: Style.space(48)
    spacing: Style.space(6)
  }

  // ---- left: follow, tasks, procedures, results
  Flickable {
    id: listScroll
    anchors.left: parent.left
    anchors.top: parent.top
    anchors.bottom: parent.bottom
    width: Math.min(Style.space(440), parent.width * 0.42)
    clip: true
    contentWidth: width
    contentHeight: listColumn.implicitHeight
    boundsBehavior: Flickable.StopAtBounds
    flickableDirection: Flickable.VerticalFlick
    Column {
      id: listColumn
      width: listScroll.width - Style.space(8)
      spacing: Style.space(6)
      Row {
        spacing: Style.space(10)
        ActionButton {
          label: root.followed ? "Stop Following" : "Follow Current Task"
          selected: !!root.followed
          blocked: !root.followed && !(root.computer && root.computer.active_task_ref)
          disabledReason: blocked ? "Nothing is running on " + root.computerLabel + " to follow." : ""
          onClicked: {
            if (blocked || !root.service) return
            if (root.followed) root.service.unfollowTask(root.computerId)
            else root.service.followTask(root.computerId)
          }
        }
        ActionButton {
          label: "Refresh"
          onClicked: root.reload()
        }
      }
      DataAge {
        at: root.service && root.service.scopedReadAt.tasks || 0
        refreshing: !!root.service && (root.service.readPending("tasks") || root.service.readPending("artifacts") || root.service.readPending("procedures"))
        nowMs: root.service ? root.service.nowMs : Date.now()
      }
      Copy {
        visible: !!root.followed
        width: parent.width
        text: "You'll get a notification when " + root.computerLabel + "'s current task is checked as finished."
        dimmed: true
        font.pixelSize: Style.font.bodySmall
      }
      Item { width: 1; height: Style.space(6) }

      Copy { eyebrow: true; text: "Tasks" + (root.service && root.service.tasksLoaded ? " · " + root.tasks.length : "") }
      RecordList {
        model: root.tasks
        delegate: RecordRow {
          width: listColumn.width
          row: index
          title: StatusModel.clip(StatusModel.taskTitle(modelData), 90)
          meta: root.taskState(modelData) + (root.taskAgent(modelData) ? " · " + root.taskAgent(modelData) : "")
          markerColor: root.taskStateColor(modelData)
          current: root.detailKind === "task" && !!root.service && root.service.selectedTaskRef === modelData.task_ref
          onPicked: root.selectTask(modelData.task_ref)
        }
      }
      Copy {
        visible: root.tasks.length === 0
        width: parent.width
        text: root.service && root.service.readPending("tasks") ? "Loading…" : root.service && root.service.readErrors.tasks ? StatusModel.clip(root.service.readErrors.tasks, 200) : "No tasks yet."
        dimmed: true
        font.pixelSize: Style.font.bodySmall
      }
      Item { width: 1; height: Style.space(8) }

      Copy { eyebrow: true; text: "Procedures awaiting review" }
      RecordList {
        model: root.procedures
        delegate: RecordRow {
          width: listColumn.width
          row: index
          title: StatusModel.clip(root.procedureTitle(modelData), 90)
          meta: root.tokens.sentence(modelData.status) || "Candidate"
          markerColor: root.tokens.pausedColor
          current: root.detailKind === "procedure" && !!root.service && root.service.selectedProcedureRef === modelData.procedure_ref
          onPicked: root.selectProcedure(modelData.procedure_ref)
        }
      }
      Copy {
        visible: root.procedures.length === 0
        width: parent.width
        text: root.service && root.service.readPending("procedures") ? "Loading…" : root.service && root.service.readErrors.procedures ? StatusModel.clip(root.service.readErrors.procedures, 200) : "Nothing to review."
        dimmed: true
        font.pixelSize: Style.font.bodySmall
      }
      Item { width: 1; height: Style.space(8) }

      Copy { eyebrow: true; text: "Task results" }
      RecordList {
        model: root.artifacts
        delegate: RecordRow {
          width: listColumn.width
          row: index
          title: StatusModel.clip(String(modelData.name || "Unnamed file"), 90)
          meta: root.fileState(modelData) + " · " + StatusModel.bytesLabel(modelData.size_bytes)
          markerColor: root.tokens.readyColor
          current: root.detailKind === "file" && !!root.service && root.service.selectedArtifactRef === modelData.artifact_ref
          onPicked: root.selectArtifact(modelData.artifact_ref)
        }
      }
      Copy {
        visible: root.artifacts.length === 0
        width: parent.width
        text: root.service && root.service.readPending("artifacts") ? "Loading…" : root.service && root.service.readErrors.artifacts ? StatusModel.clip(root.service.readErrors.artifacts, 200) : "No results yet."
        dimmed: true
        font.pixelSize: Style.font.bodySmall
      }
    }
  }

  // ---- right: the selected record
  Rectangle {
    anchors.left: listScroll.right
    anchors.leftMargin: Style.space(20)
    anchors.right: parent.right
    anchors.top: parent.top
    anchors.bottom: parent.bottom
    radius: 0
    color: root.tokens.surface
    border.width: 1
    border.color: root.tokens.rule
    Flickable {
      id: detailScroll
      anchors.fill: parent
      anchors.margins: Style.space(18)
      clip: true
      contentWidth: width
      contentHeight: detailColumn.implicitHeight
      boundsBehavior: Flickable.StopAtBounds
      flickableDirection: Flickable.VerticalFlick
      Column {
        id: detailColumn
        width: detailScroll.width
        spacing: Style.space(10)

        // Task
        Column {
          visible: root.detailKind === "task"
          width: parent.width
          spacing: Style.space(10)
          readonly property bool hasTask: !!(root.service && root.service.selectedTaskRef)
          Copy {
            width: parent.width
            text: root.selectedTaskRecord ? StatusModel.taskTitle(root.selectedTaskRecord) : "Select a task"
            font.pixelSize: Style.font.heading + Style.space(2)
            font.bold: true
          }
          Copy {
            visible: parent.hasTask
            width: parent.width
            text: root.taskState(root.selectedTaskRecord || {}) + (root.taskAgent(root.selectedTaskRecord) ? " · " + root.taskAgent(root.selectedTaskRecord) : "") + " · " + root.taskProof(root.detail)
          }
          Copy {
            visible: parent.hasTask && !!(root.service && root.service.selectedTaskDetailObservedAt)
            width: parent.width
            text: root.service ? "Updated " + StatusModel.ageLabel(root.service.selectedTaskDetailObservedAt, root.service.nowMs) : ""
            dimmed: true
            font.pixelSize: Style.font.caption
          }
          Copy { visible: parent.hasTask && !!(root.service && root.service.selectedTaskLoading); text: "Updating task details…"; dimmed: true; font.pixelSize: Style.font.bodySmall }
          Copy {
            visible: !!(root.service && root.service.readErrors.task)
            width: parent.width
            text: root.service ? StatusModel.clip(root.service.readErrors.task, 200) : ""
            color: Color.urgent
            font.pixelSize: Style.font.bodySmall
          }
          Copy { visible: parent.hasTask && root.taskWarning(root.detail) !== ""; width: parent.width; text: root.taskWarning(root.detail); color: Color.urgent; font.pixelSize: Style.font.bodySmall }
          Flow {
            visible: parent.hasTask
            width: parent.width
            spacing: Style.space(6)
            ActionButton {
              label: root.showTechnicalDetail ? "Hide Technical Details" : "Technical Details"
              selected: root.showTechnicalDetail
              onClicked: {
                root.showTechnicalDetail = !root.showTechnicalDetail
                if (root.service.selectedTaskDetailRef !== root.service.selectedTaskRef) root.service.inspectTask(root.service.selectedTaskRef)
              }
            }
            ActionButton {
              label: "Add 5 Minutes"
              blocked: root.actionReason !== ""
              disabledReason: root.actionReason
              onClicked: if (!blocked) root.service.extendTask(root.service.selectedTaskRef, root.extendSeconds)
            }
            ActionButton {
              label: "End Task"
              role: "danger"
              blocked: root.actionReason !== ""
              disabledReason: root.actionReason
              onClicked: if (!blocked) root.confirmTask("End this task on " + root.computerLabel + "? Other agents keep working.", "End Task", true,
                function(ref) { root.service.revokeTask(ref) })
            }
          }
          Copy {
            visible: parent.hasTask && !(root.service && root.service.selectedTaskLoading) && root.taskCriteria(root.detail).length === 0 && root.taskReceipts(root.detail).length === 0 && root.taskDeliveries(root.detail).length === 0
            width: parent.width
            text: "No detailed evidence is recorded for this task."
            dimmed: true
            font.pixelSize: Style.font.bodySmall
          }
          Copy { visible: parent.hasTask && root.taskCriteria(root.detail).length > 0; eyebrow: true; text: "Checks" }
          Repeater {
            model: parent.hasTask ? root.taskCriteria(root.detail) : []
            delegate: Column {
              width: detailColumn.width
              spacing: Style.space(3)
              property var criterion: modelData
              Copy { width: parent.width; text: String(criterion.description || criterion.id || criterion.criterion_id || "Check"); font.bold: true }
              Copy { width: parent.width; text: (root.tokens.sentence(criterion.state || criterion.outcome) || "Unverified") + (criterion.required === false ? " · optional" : " · required"); dimmed: true; font.pixelSize: Style.font.bodySmall }
              Repeater {
                model: Array.isArray(criterion.evidence) ? criterion.evidence : []
                delegate: Copy { width: detailColumn.width; text: String(modelData.summary || modelData.outcome || "Evidence available"); font.pixelSize: Style.font.bodySmall }
              }
            }
          }
          Copy { visible: parent.hasTask && root.taskReceipts(root.detail).length > 0; eyebrow: true; text: "What it did" }
          Repeater {
            model: parent.hasTask ? root.taskReceipts(root.detail) : []
            delegate: Column {
              width: detailColumn.width
              spacing: Style.space(3)
              property var receipt: modelData
              Copy { width: parent.width; text: String(receipt.summary || root.tokens.sentence(receipt.tool) || "Action"); font.bold: true }
              Copy {
                width: parent.width
                text: root.taskReceiptState(receipt)
                font.pixelSize: Style.font.bodySmall
                color: receipt.dependency_state === "unresolved" || receipt.requires_reconciliation || receipt.effect === "unknown" ? Color.urgent : Color.popups.text
              }
            }
          }
          Copy {
            visible: parent.hasTask && !!(root.detail && root.detail.receipt_next_cursor)
            width: parent.width
            text: "More activity exists; this shows part of it."
            dimmed: true
            font.pixelSize: Style.font.bodySmall
          }
          Copy { visible: parent.hasTask && root.taskDeliveries(root.detail).length > 0; eyebrow: true; text: "Required results" }
          Repeater {
            model: parent.hasTask ? root.taskDeliveries(root.detail) : []
            delegate: Column {
              width: detailColumn.width
              spacing: Style.space(3)
              property var delivery: modelData
              Copy { width: parent.width; text: String(delivery.host_id || delivery.destination_host || delivery.host || "Unknown computer") + " · " + String(delivery.destination_path || delivery.path || "Destination unavailable"); font.bold: true }
              Copy { width: parent.width; text: root.tokens.sentence(delivery.state) || "Pending"; font.pixelSize: Style.font.bodySmall }
            }
          }
          Copy {
            visible: parent.hasTask && Object.keys(root.taskProjection(root.detail)).length > 0
            width: parent.width
            text: "Cleanup · " + root.taskCleanup(root.detail)
            font.pixelSize: Style.font.bodySmall
          }
          Repeater {
            model: parent.hasTask && root.showTechnicalDetail && root.service && root.service.selectedTaskDetail ? StatusModel.evidenceLines(root.service.selectedTaskDetail) : []
            delegate: Copy { width: detailColumn.width; text: String(modelData); dimmed: true; font.pixelSize: Style.font.caption; wrapMode: Text.WrapAnywhere }
          }
        }

        // Procedure
        Column {
          visible: root.detailKind === "procedure"
          width: parent.width
          spacing: Style.space(10)
          readonly property var record: root.service ? root.service.selectedProcedure : null
          Copy {
            width: parent.width
            text: parent.record ? root.procedureTitle(parent.record) : root.service && root.service.selectedProcedureLoading ? "Loading procedure…" : "Select a procedure"
            font.pixelSize: Style.font.heading + Style.space(2)
            font.bold: true
          }
          // Status, revision, applicability, evidence warnings, then the steps: one shared wording.
          Repeater {
            model: parent.record ? StatusModel.procedureLines(parent.record).slice(1) : []
            delegate: Copy { width: detailColumn.width; text: String(modelData); font.pixelSize: Style.font.bodySmall }
          }
          Copy {
            visible: !!(root.service && root.service.readErrors.procedure)
            width: parent.width
            text: root.service ? StatusModel.clip(root.service.readErrors.procedure, 200) : ""
            color: Color.urgent
            font.pixelSize: Style.font.bodySmall
          }
          Row {
            visible: !!(root.service && root.service.selectedProcedureRef)
            spacing: Style.space(6)
            ActionButton {
              readonly property bool reviewed: !!(parent.parent.record && parent.parent.record.procedure_ref === root.service.selectedProcedureRef && root.procedureDigest(parent.parent.record))
              label: "Approve This Version"
              blocked: root.actionReason !== "" || !reviewed
              disabledReason: root.actionReason || (reviewed ? "" : root.service && root.service.selectedProcedureLoading ? "ibara is still loading this procedure." : "This procedure has no version to approve.")
              onClicked: if (!blocked) root.confirmProcedure("Approve version %DIGEST% of this procedure on " + root.computerLabel + "?", "Approve",
                function(ref, digest) { root.service.approveProcedure(ref, digest) })
            }
            ActionButton {
              label: "Withdraw"
              role: "danger"
              blocked: root.actionReason !== ""
              disabledReason: root.actionReason
              onClicked: if (!blocked) root.confirmProcedure("Withdraw this procedure on " + root.computerLabel + " from approved results?", "Withdraw",
                function(ref) { root.service.quarantineProcedure(ref) })
            }
          }
        }

        // Task result
        Column {
          visible: root.detailKind === "file"
          width: parent.width
          spacing: Style.space(10)
          Copy {
            width: parent.width
            text: root.selectedArtifact ? String(root.selectedArtifact.name || "Unnamed file") : "Select a result"
            font.pixelSize: Style.font.heading + Style.space(2)
            font.bold: true
          }
          Copy {
            visible: !!root.selectedArtifact
            width: parent.width
            text: root.selectedArtifact ? root.fileState(root.selectedArtifact) + " · " + StatusModel.bytesLabel(root.selectedArtifact.size_bytes) : ""
          }
          Copy {
            visible: !!root.selectedArtifact
            width: parent.width
            text: "A saved copy may not satisfy the task's delivery check."
            dimmed: true
            font.pixelSize: Style.font.bodySmall
          }
          ActionButton {
            visible: !!root.selectedArtifact
            label: "Collect File"
            blocked: root.actionReason !== ""
            disabledReason: root.actionReason
            onClicked: if (!blocked) root.service.fetchArtifact(root.service.selectedArtifactRef, root.selectedArtifact.name)
          }
        }
      }
    }
  }
}
