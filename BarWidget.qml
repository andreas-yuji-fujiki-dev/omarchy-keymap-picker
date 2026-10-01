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
  moduleName: "io.github.andreas.keymap"

  property var layouts: []
  property string currentLayout: ""
  property string currentVariant: ""
  property string statusText: ""
  property bool statusIsError: false
  property bool applying: false

  // Writing to ~/.config/hypr/input.lua needs the user's say-so. The choice is
  // kept in this widget's shell.json entry: true saves layouts to input.lua,
  // false only changes the running session, and unset means "ask first".
  readonly property var saveChoice: setting("saveToConfig", null)
  property bool askingToSave: false
  property string askLayout: ""
  property string askVariant: ""

  readonly property string applyPath: Qt.resolvedUrl("keymap-apply").toString().replace(/^file:\/\//, "")
  readonly property string badge: currentLayout === "" ? "··" : Model.badgeText(currentLayout)
  readonly property string currentDescription: currentLayout === "" ? "" : Model.describe(layouts, currentLayout, currentVariant)

  function refreshCurrent() {
    if (!layoutRead.running) layoutRead.running = true
  }

  // Layout and variant are checked here as well as in keymap-apply, so a bad
  // name never reaches a process.
  function validPair(layout, variant) {
    var name = String(layout || "")
    return name !== "" && Model.isValidName(name) && Model.isValidName(String(variant || ""))
  }

  function applyLayout(layout, variant, save) {
    if (applying || !validPair(layout, variant)) return
    var name = String(layout)
    var flavor = String(variant || "")
    applying = true
    statusText = ""
    applyProcess.pendingLayout = name
    applyProcess.pendingVariant = flavor
    applyProcess.pendingSave = save === true
    applyProcess.command = save === true ? [applyPath, name, flavor] : [applyPath, "--no-save", name, flavor]
    applyProcess.running = true
  }

  // What a click in the panel calls. Until the user has decided whether
  // layouts may be saved to input.lua it stops and asks instead of applying.
  function requestApply(layout, variant) {
    if (applying || !validPair(layout, variant)) return
    if (saveChoice === null) {
      askLayout = String(layout)
      askVariant = String(variant || "")
      askingToSave = true
      return
    }
    applyLayout(layout, variant, saveChoice === true)
  }

  // remember: true saves this and every later pick; false changes only the
  // running session and asks again next time.
  function confirmSave(remember) {
    var layout = askLayout
    var variant = askVariant
    askingToSave = false
    if (remember) persistSettings({ saveToConfig: true })
    applyLayout(layout, variant, remember)
  }

  function cancelSave() { askingToSave = false }

  function setSaveChoice(value) { persistSettings({ saveToConfig: value === true }) }

  function persistSettings(values) {
    var entry = { id: root.moduleName }
    for (var existing in root.settings) if (existing !== "id") entry[existing] = root.settings[existing]
    for (var key in values) entry[key] = values[key]

    root.settings = entry
    if (root.bar && root.bar.shell && typeof root.bar.shell.updateEntryInline === "function")
      root.bar.shell.updateEntryInline(root.moduleName, entry)
  }

  // ---- Popup host. Shape contract for shell.summon/hide/toggle routing:
  //      Bar.findPanelWidget requires open/close/opened on the widget root.
  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false

  function open() {
    refreshCurrent()
    if (panelLoader.item) panelLoader.item.open()
  }

  function close() {
    askingToSave = false
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
    property bool pendingSave: false

    stderr: StdioCollector { id: applyErrors }

    onExited: function(exitCode) {
      root.applying = false
      if (exitCode === 0) {
        root.statusIsError = false
        root.statusText = "Applied " + Model.describe(root.layouts, pendingLayout, pendingVariant)
          + (pendingSave ? "" : " (this session only)")
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
    target: "io.github.andreas.keymap"

    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.togglePanel() }
    function refresh(): void { root.broadcast("refreshCurrent") }
    // Scripts never trigger the prompt: they save only if saving was already allowed.
    function set(layout: string, variant: string): void { root.applyLayout(layout, variant, root.saveChoice === true) }
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
