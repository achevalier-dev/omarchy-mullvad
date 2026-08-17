import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// Bar button plus popup, in the shape the first-party panels use: the Panel
// base owns the open/close lifecycle, this file owns the button, the keyboard
// state machine, and the content.
Panel {
  id: root
  moduleName: "io.github.achevalier-dev.mullvad"
  ipcTarget: "io.github.achevalier-dev.mullvad"

  // ── Tunnel state, streamed from the daemon ─────────────────────────────────
  property string tunnel: "unknown"
  property string country: ""
  property string city: ""
  property string relay: ""

  // ── Settings, read back after every change ─────────────────────────────────
  property var values: ({})
  property string constraint: ""
  property string device: ""
  property string expires: ""
  readonly property bool loggedIn: String(values.loggedin || "") === "yes"

  property int cursorIndex: 0
  property bool cursorActive: false

  readonly property bool connected: tunnel === "connected"
  readonly property bool inFlight: tunnel === "connecting" || tunnel === "disconnecting"
  readonly property bool blocked: tunnel === "error" || tunnel === "blocked"
  readonly property bool showLocation: setting("showLocation", true) === true
  property string pendingKey: ""
  readonly property bool busy: actionProc.running || inFlight

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property color barIconColor: connected ? barForeground : Qt.darker(barForeground, 1.55)

  // Relay hostnames lead with their country code: fr-par-wg-301 → FR.
  readonly property string code: relay ? relay.split("-")[0].toUpperCase() : ""

  readonly property string barLabel: {
    if (!showLocation) return "󱇱"
    if (connected && code) return "󱇱  " + code
    if (inFlight) return "󱇱  ···"
    return "󱇱"
  }

  readonly property string stateText: {
    if (!loggedIn) return "Not logged in"
    if (connected) return "Connected"
    if (tunnel === "connecting") return "Connecting…"
    if (tunnel === "disconnecting") return "Disconnecting…"
    if (blocked) return "Blocking traffic"
    return "Disconnected"
  }

  readonly property string whereText: {
    var where = [city, country].filter(function (part) { return !!part }).join(", ")
    if (connected) return where + (relay ? " · " + relay : "")
    return where ? "Your real location: " + where : ""
  }

  // The hero's detail is a pill beside the title, so it has to stay a badge —
  // anything longer squeezes the title out of the row.
  readonly property string badgeText: loggedIn && connected && code ? code : ""

  // ── Rows: one list drives both the keyboard cursor and the mouse ───────────
  readonly property var actionKeys: ["reconnect", "location", "status"]
  readonly property var settingKeys: ["lockdown", "autoconnect", "lan", "multihop", "daita", "quantum"]
  readonly property var accountKeys: ["devices", "logout"]
  // Without an account there is exactly one thing worth offering.
  readonly property var rowKeys: loggedIn
    ? ["power"].concat(actionKeys).concat(settingKeys).concat(accountKeys)
    : ["login"]

  function labelFor(key) {
    switch (key) {
    case "power": return connected ? "Disconnect" : "Connect"
    case "reconnect": return "Reconnect"
    case "location": return "Change location…"
    case "status": return "Notify status"
    case "lockdown": return "Lockdown mode"
    case "autoconnect": return "Auto-connect"
    case "lan": return "Local network sharing"
    case "multihop": return "Multihop"
    case "daita": return "DAITA"
    case "quantum": return "Quantum resistance"
    case "login": return "Log in…"
    case "logout": return "Log out…"
    case "devices": return "Devices on this account"
    }
    return key
  }

  // Each setting reports itself in its own vocabulary; one truth for the UI.
  function isOn(key) {
    var value = String(values[key] || "")
    return value === "on" || value === "allow" || value === "enabled" || value === "true"
  }

  function commandFor(key) {
    switch (key) {
    case "power": return "mullvad-menu toggle"
    case "reconnect": return "mullvad-menu reconnect"
    case "status": return "mullvad-menu status"
    case "lockdown": return "mullvad-menu toggle-lockdown"
    case "autoconnect": return "mullvad-menu toggle-autoconnect"
    case "lan": return "mullvad-menu toggle-lan"
    case "multihop": return "mullvad-menu toggle-multihop"
    case "daita": return "mullvad-menu toggle-daita"
    case "quantum": return "mullvad-menu toggle-quantum"
    case "login": return "mullvad-menu login"
    case "logout": return "mullvad-menu logout"
    case "devices": return "mullvad-menu devices"
    }
    return ""
  }

  function activate(key) {
    // The relay pickers are the menu's job — it already draws them, and it is
    // one keystroke away from everything else the menu offers.
    if (key === "location" || key === "login" || key === "logout" || key === "devices") {
      close()
      if (bar) bar.run(key === "location" ? "omarchy-menu summon mullvad.location" : commandFor(key))
      return
    }

    var command = commandFor(key)
    if (!command || actionProc.running) return
    root.pendingKey = key
    actionProc.command = ["bash", "-lc", command]
    actionProc.running = true
  }

  function activateCursor() {
    activate(rowKeys[Math.max(0, Math.min(rowKeys.length - 1, cursorIndex))])
  }

  function moveCursor(dx, dy) {
    cursorActive = true
    if (dy === 0) return
    cursorIndex = Math.max(0, Math.min(rowKeys.length - 1, cursorIndex + dy))
  }

  function setCursor(key) {
    cursorActive = true
    var index = rowKeys.indexOf(key)
    if (index >= 0) cursorIndex = index
  }

  function hasCursor(key) {
    return cursorActive && rowKeys[cursorIndex] === key
  }

  function refreshSettings() {
    if (settingsProc.running) return
    settingsProc.running = true
  }

  function applyStatus(line) {
    if (!line) return

    var payload
    try {
      payload = JSON.parse(line)
    } catch (e) {
      return
    }
    if (!payload || !payload.state) return

    root.tunnel = String(payload.state)

    var location = payload.details && payload.details.location ? payload.details.location : null
    root.country = location && location.country ? String(location.country) : ""
    root.city = location && location.city ? String(location.city) : ""
    root.relay = location && location.hostname ? String(location.hostname) : ""
  }

  visible: tunnel !== "unknown"
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onOpenedChanged: {
    if (opened) {
      cursorActive = false
      cursorIndex = 0
      refreshSettings()
    }
  }

  // `mullvad status -j listen` prints the current state immediately and then
  // one JSON line per change, so the bar stays current without polling.
  Process {
    id: listener
    command: ["mullvad", "status", "-j", "listen"]
    running: true
    stdout: SplitParser {
      onRead: function (data) {
        relisten.interval = 3000
        root.applyStatus(data)
      }
    }
    // A daemon restart takes the listener down with it. Come back for the new
    // one instead of leaving a stale state on screen — but back off, because
    // without the mullvad CLI this exits instantly and a fixed retry would be
    // a respawn loop for as long as the shell lives.
    onExited: {
      relisten.interval = Math.min(relisten.interval * 2, 60000)
      relisten.start()
    }
  }

  Timer {
    id: relisten
    interval: 3000
    onTriggered: listener.running = true
  }

  Process {
    id: settingsProc
    command: ["bash", "-lc",
      "printf 'lockdown=%s\\nautoconnect=%s\\nlan=%s\\nmultihop=%s\\ndaita=%s\\nquantum=%s\\nconstraint=%s\\nloggedin=%s\\ndevice=%s\\nexpires=%s\\n'"
      + " \"$(mullvad lockdown-mode get | sed 's/.*: //')\""
      + " \"$(mullvad auto-connect get | sed 's/.*: //')\""
      + " \"$(mullvad lan get | sed 's/.*: //')\""
      + " \"$(mullvad relay get | sed -n 's/^[[:space:]]*Multihop state:[[:space:]]*//p')\""
      + " \"$(mullvad tunnel get | sed -n 's/^[[:space:]]*DAITA:[[:space:]]*//p')\""
      + " \"$(mullvad tunnel get | sed -n 's/^[[:space:]]*Quantum resistance:[[:space:]]*//p')\""
      + " \"$(mullvad relay get | sed -n 's/^[[:space:]]*Location:[[:space:]]*//p')\""
      + " \"$(mullvad account get >/dev/null 2>&1 && echo yes || echo no)\""
      + " \"$(mullvad account get 2>/dev/null | sed -n 's/^Device name:[[:space:]]*//p')\""
      + " \"$(mullvad account get 2>/dev/null | sed -n 's/^Expires at:[[:space:]]*//p' | cut -d' ' -f1)\""]
    stdout: SplitParser {
      onRead: function (data) {
        var parts = String(data).split("=")
        if (parts.length < 2) return
        var key = parts.shift()
        var value = parts.join("=").trim()
        if (key === "constraint") {
          root.constraint = value
          return
        }
        if (key === "device") {
          root.device = value
          return
        }
        if (key === "expires") {
          root.expires = value
          return
        }
        var next = ({})
        for (var k in root.values) next[k] = root.values[k]
        next[key] = value
        root.values = next
      }
    }
  }

  // mullvad-menu waits for the daemon to agree before it returns, so a refresh
  // on exit reads settled values rather than the ones being replaced.
  Process {
    id: actionProc
    onExited: {
      root.pendingKey = ""
      root.refreshSettings()
    }
  }

  // WidgetButton, not BarIconButton: the icon button pins its width to a
  // single icon slot, so the country code spilled over its neighbours.
  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.barLabel
    active: root.blocked
    dimmed: !root.connected && !root.inFlight
    horizontalMargin: 8.75
    verticalPadding: 8.75
    tooltipText: root.stateText + (root.whereText ? " — " + root.whereText : "")

    onPressed: function (b) {
      if (b === Qt.RightButton) root.activate("power")
      else if (b === Qt.MiddleButton) root.activate("status")
      else root.toggle()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(340))
    contentHeight: panel.fittedContentHeight(column.implicitHeight, Style.space(860))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent

      onMoveRequested: function (dx, dy) {
        if (!root.cursorActive) {
          root.cursorActive = true
          return
        }
        root.moveCursor(dx, dy)
      }
      onActivateRequested: if (root.cursorActive) root.activateCursor()
      onCloseRequested: root.close()
      onTabRequested: function (direction) { root.switchPanel(direction) }
      onTextKey: function (t) {
        var key = String(t).toLowerCase()
        if (key === "t") root.activate("power")
        else if (key === "r") root.activate("reconnect")
        else if (key === "l") root.activate("location")
        else if (key === "s") root.activate("status")
      }

      Flickable {
        id: panelFlick
        anchors.fill: parent
        contentWidth: width
        contentHeight: column.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        interactive: contentHeight > height
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        Column {
          id: column
          width: panelFlick.width
          spacing: Style.space(12)

          // Hero: state, where the tunnel comes out, and the power switch.
          Item {
            id: header
            width: parent.width
            implicitHeight: hero.implicitHeight

            // The trailing control's `root` resolves to PanelHero, so panel
            // state is reached through this wrapper instead.
            readonly property bool ringVisible: root.hasCursor("power")
            readonly property bool on: root.connected
            readonly property bool working: root.pendingKey === "power" || root.inFlight
            function claimCursor() { root.setCursor("power") }
            function fire() { root.activate("power") }

            PanelHero {
              id: hero
              width: parent.width
              title: "Mullvad"
              meta: root.stateText
              detail: root.badgeText
              foreground: root.foreground
              fontFamily: root.fontFamily
              iconOpacity: root.connected ? 1.0 : 0.5

              iconComponent: Component {
                Text {
                  text: "󱇱"
                  color: root.connected ? root.foreground : root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.display
                }
              }

              trailingControl: Component {
                ToggleSwitch {
                  visible: root.loggedIn
                  checked: header.on
                  busy: header.working
                  hasCursor: header.ringVisible
                  foreground: root.foreground
                  onHovered: function (on) { if (on) header.claimCursor() }
                  onToggled: header.fire()
                }
              }
            }
          }

          Text {
            width: parent.width
            text: root.whereText
            visible: text !== "" && root.loggedIn
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            elide: Text.ElideRight
          }

          // Logged out: one thing to offer, and a word on what it does.
          Column {
            width: parent.width
            visible: !root.loggedIn
            spacing: Style.space(8)

            Text {
              width: parent.width
              text: "Log in with your Mullvad account number to use the tunnel. The number is typed into a terminal, never onto a command line."
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              wrapMode: Text.WordWrap
            }

            Rectangle {
              width: parent.width
              implicitHeight: Style.space(34)
              radius: Style.cornerRadius > 0 ? Style.space(8) : 0
              color: root.hasCursor("login") ? Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.12) : "transparent"

              Text {
                anchors.verticalCenter: parent.verticalCenter
                anchors.left: parent.left
                anchors.leftMargin: Style.space(10)
                text: root.labelFor("login")
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
              }

              MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onEntered: root.setCursor("login")
                onClicked: root.activate("login")
              }
            }
          }

          PanelSeparator {
            foreground: root.foreground
            visible: root.loggedIn
          }

          Column {
            width: parent.width
            visible: root.loggedIn
            spacing: Style.space(6)

            Repeater {
              model: root.actionKeys

              Rectangle {
                required property string modelData
                width: parent.width
                implicitHeight: Style.space(34)
                radius: Style.cornerRadius > 0 ? Style.space(8) : 0
                color: root.hasCursor(modelData) ? Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.12) : "transparent"

                Text {
                  anchors.verticalCenter: parent.verticalCenter
                  anchors.left: parent.left
                  anchors.leftMargin: Style.space(10)
                  text: root.labelFor(parent.modelData)
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                }

                MouseArea {
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onEntered: root.setCursor(parent.modelData)
                  onClicked: root.activate(parent.modelData)
                }
              }
            }
          }

          PanelSeparator {
            foreground: root.foreground
            visible: root.loggedIn
          }

          Column {
            width: parent.width
            visible: root.loggedIn
            spacing: Style.space(6)

            PanelSectionHeader {
              text: "SETTINGS"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            Repeater {
              model: root.settingKeys

              Rectangle {
                id: settingRow
                required property string modelData
                width: parent.width
                implicitHeight: Style.space(34)
                radius: Style.cornerRadius > 0 ? Style.space(8) : 0
                color: root.hasCursor(modelData) ? Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.12) : "transparent"

                Text {
                  anchors.verticalCenter: parent.verticalCenter
                  anchors.left: parent.left
                  anchors.leftMargin: Style.space(10)
                  text: root.labelFor(settingRow.modelData)
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                }

                ToggleSwitch {
                  anchors.verticalCenter: parent.verticalCenter
                  anchors.right: parent.right
                  anchors.rightMargin: Style.space(8)
                  checked: root.isOn(settingRow.modelData)
                  busy: root.pendingKey === settingRow.modelData
                  hasCursor: root.hasCursor(settingRow.modelData)
                  foreground: root.foreground
                  onHovered: function (on) { if (on) root.setCursor(settingRow.modelData) }
                  onToggled: root.activate(settingRow.modelData)
                }

                MouseArea {
                  anchors.fill: parent
                  anchors.rightMargin: Style.space(64)
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onEntered: root.setCursor(settingRow.modelData)
                  onClicked: root.activate(settingRow.modelData)
                }
              }
            }
          }

          PanelSeparator {
            foreground: root.foreground
            visible: root.loggedIn
          }

          Column {
            width: parent.width
            visible: root.loggedIn
            spacing: Style.space(6)

            PanelSectionHeader {
              text: "ACCOUNT"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            Text {
              width: parent.width
              text: (root.device ? root.device : "This device") + (root.expires ? " · paid through " + root.expires : "")
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              elide: Text.ElideRight
            }

            Repeater {
              model: root.accountKeys

              Rectangle {
                required property string modelData
                width: parent.width
                implicitHeight: Style.space(34)
                radius: Style.cornerRadius > 0 ? Style.space(8) : 0
                color: root.hasCursor(modelData) ? Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.12) : "transparent"

                Text {
                  anchors.verticalCenter: parent.verticalCenter
                  anchors.left: parent.left
                  anchors.leftMargin: Style.space(10)
                  text: root.labelFor(parent.modelData)
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                }

                MouseArea {
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onEntered: root.setCursor(parent.modelData)
                  onClicked: root.activate(parent.modelData)
                }
              }
            }
          }

          Text {
            width: parent.width
            text: root.constraint ? "Selected relay: " + root.constraint : ""
            visible: text !== "" && root.loggedIn
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            elide: Text.ElideRight
          }

          Text {
            width: parent.width
            text: root.loggedIn ? "t connect · r reconnect · l location · s notify · esc close" : "enter log in · esc close"
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
          }
        }
      }
    }
  }
}
