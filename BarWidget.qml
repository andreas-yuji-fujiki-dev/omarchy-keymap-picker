import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

// Bar badge showing the active keyboard layout ("US", "BR"), and the host for
// the picker popup. Owns the layout list and the current/apply state; the
// panel is only the view over it.
//
// Click opens the picker. Layouts come from xkeyboard-config's rules file, so
// the list is the same one GNOME offers.
BarWidget {
  id: root
  moduleName: "andreas.keymap"

  property var layouts: []
  property string currentLayout: ""
  property string currentVariant: ""
  property string statusText: ""
  property bool statusIsError: false
  property bool applying: false

  readonly property string applyPath: Qt.resolvedUrl("keymap-apply").toString().replace(/^file:\/\//, "")
  readonly property string badge: currentLayout === "" ? "··" : Model.badgeText(currentLayout)
  readonly property string currentDescription: currentLayout === "" ? "" : Model.describe(layouts, currentLayout, currentVariant)

  function refreshCurrent() {
    if (!layoutRead.running) layoutRead.running = true
  }

  // Layout and variant are checked here as well as in keymap-apply, so a bad
  // name never reaches a process.
  function applyLayout(layout, variant) {
    var name = String(layout || "")
    var flavor = String(variant || "")
    if (applying || name === "" || !Model.isValidName(name) || !Model.isValidName(flavor)) return
    applying = true
    statusText = ""
    applyProcess.pendingLayout = name
    applyProcess.pendingVariant = flavor
    applyProcess.command = [applyPath, name, flavor]
    applyProcess.running = true
  }

  // ---- Popup host. Shape contract for shell.summon/hide/toggle routing:
  //      Bar.findPanelWidget requires open/close/opened on the widget root.
  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false

  function open() {
    refreshCurrent()
    if (panelLoader.item) panelLoader.item.open()
  }

  function close() {
    if (panelLoader.item) panelLoader.item.close()
  }

  function togglePanel() {
    if (opened) close()
    else open()
  }

  readonly property bool popoutSwitchClosing: panelLoader.item ? panelLoader.item.popoutSwitchClosing === true : false

  function closeForPopoutSwitch() {
    if (panelLoader.item) panelLoader.item.closeForPopoutSwitch()
  }

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    if ("bar" in target) target.bar = root.bar
    if ("settings" in target) target.settings = root.settings
    if ("anchorItem" in target) target.anchorItem = button
    if ("hostWidget" in target) target.hostWidget = root
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onBarChanged: injectPanel()
  onSettingsChanged: injectPanel()
  Component.onCompleted: refreshCurrent()

  FileView {
    path: Model.XKB_RULES
    printErrors: false
    onLoaded: root.layouts = Model.parseLayouts(text())
  }

  Process {
    id: layoutRead
    command: ["hyprctl", "-j", "getoption", "input:kb_layout"]
    stdout: StdioCollector {
      onStreamFinished: {
        try { root.currentLayout = Model.firstOf(JSON.parse(text).str) } catch (error) {}
        variantRead.running = true
      }
    }
  }

  Process {
    id: variantRead
    command: ["hyprctl", "-j", "getoption", "input:kb_variant"]
    stdout: StdioCollector {
      onStreamFinished: {
        try { root.currentVariant = Model.firstOf(JSON.parse(text).str) } catch (error) {}
      }
    }
  }

  Process {
    id: applyProcess
    property string pendingLayout: ""
    property string pendingVariant: ""

    stderr: StdioCollector { id: applyErrors }

    onExited: function(exitCode) {
      root.applying = false
      if (exitCode === 0) {
        root.statusIsError = false
        root.statusText = "Applied " + Model.describe(root.layouts, pendingLayout, pendingVariant)
        root.broadcast("refreshCurrent")
      } else {
        root.statusIsError = true
        root.statusText = String(applyErrors.text || "").trim().split("\n")[0] || "Could not apply the layout"
      }
    }
  }

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
  }

  IpcHandler {
    target: "andreas.keymap"

    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.togglePanel() }
    function refresh(): void { root.broadcast("refreshCurrent") }
    function set(layout: string, variant: string): void { root.applyLayout(layout, variant) }
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.badge
    hasVisualContent: true
    active: root.opened
    useActiveColor: false
    tooltipText: root.currentDescription !== "" ? "Keyboard: " + root.currentDescription : "Keyboard layout"
    horizontalMargin: 8.75
    verticalPadding: 8.75

    onPressed: function(b) {
      if (b === Qt.LeftButton) root.togglePanel()
    }
  }
}
