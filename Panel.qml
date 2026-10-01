import QtQuick
import Quickshell
import qs.Commons
import qs.Ui
import "Model.js" as Model

// The layout picker: country / language on the left, the variants of the
// highlighted one on the right, search on top. Same two-step choice GNOME
// asks for. Picking a variant applies it on the spot.
//
// BarWidget.qml owns the data and the apply step; this panel only draws it.
Panel {
  id: root
  moduleName: "io.github.andreas.keymap"
  ipcTarget: "io.github.andreas.keymap"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  readonly property var barIdentity: hostWidget || root

  readonly property var layouts: hostWidget ? hostWidget.layouts : []
  readonly property string currentLayout: hostWidget ? hostWidget.currentLayout : ""
  readonly property string currentVariant: hostWidget ? hostWidget.currentVariant : ""
  readonly property bool asking: hostWidget ? hostWidget.askingToSave : false
  readonly property var saveChoice: hostWidget ? hostWidget.saveChoice : null

  // What the left list shows, and which entry of it is highlighted. Browsing
  // never changes the layout; only picking a variant does.
  property string query: ""
  property string browsedName: ""
  property int variantIndex: 0
  property string focusPane: "layouts"

  readonly property var shown: Model.filterLayouts(layouts, query)
  readonly property int browsedIndex: {
    for (var i = 0; i < shown.length; i++) if (shown[i].name === browsedName) return i
    return -1
  }
  readonly property var browsedLayout: browsedIndex >= 0 ? shown[browsedIndex] : null
  readonly property var rows: Model.variantRows(browsedLayout)

  readonly property color contentForeground: bar ? bar.foreground : Color.foreground
  readonly property string contentFontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property color dim: Qt.darker(contentForeground, 1.5)

  function open() {
    query = ""
    searchField.text = ""
    browse(currentLayout !== "" ? currentLayout : (shown.length > 0 ? shown[0].name : ""))
    focusPane = "layouts"
    root.controller.show()
    Qt.callLater(function() {
      layoutList.positionViewAtIndex(Math.max(0, browsedIndex), ListView.Center)
    })
  }

  function close() { root.controller.hide() }
  function toggle() { if (root.opened) root.close(); else root.open() }

  function browse(name) {
    browsedName = name
    variantIndex = 0
    if (name === currentLayout) {
      for (var i = 0; i < rows.length; i++)
        if (rows[i].value === currentVariant) { variantIndex = i; break }
    }
  }

  function moveLayout(delta) {
    if (shown.length === 0) return
    var next = Math.max(0, Math.min(shown.length - 1, (browsedIndex < 0 ? 0 : browsedIndex) + delta))
    browse(shown[next].name)
    layoutList.positionViewAtIndex(next, ListView.Contain)
  }

  function moveVariant(delta) {
    if (rows.length === 0) return
    variantIndex = Math.max(0, Math.min(rows.length - 1, variantIndex + delta))
    variantList.positionViewAtIndex(variantIndex, ListView.Contain)
  }

  function applyRow(index) {
    if (!browsedLayout || !hostWidget || index < 0 || index >= rows.length) return
    hostWidget.requestApply(browsedLayout.name, rows[index].value)
  }

  // A layout with no variants has nothing to choose on the right, so picking
  // it applies it directly.
  function pickLayout(name) {
    browse(name)
    if (browsedLayout && browsedLayout.variants.length === 0) applyRow(0)
    else focusPane = "variants"
  }

  onShownChanged: {
    if (browsedIndex < 0 && shown.length > 0) browse(shown[0].name)
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    focusTarget: searchField
    contentWidth: panel.fittedContentWidth(Style.space(640))
    contentHeight: panel.fittedContentHeight(Style.space(440))

    Item {
      anchors.fill: parent

      // ---- Header: what is active now.
      Item {
        id: header
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: Style.space(40)

        Text {
          id: headerIcon
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
          text: "󰌌"
          color: root.contentForeground
          font.family: root.contentFontFamily
          font.pixelSize: Style.space(28)
        }

        Column {
          anchors.left: headerIcon.right
          anchors.leftMargin: Style.space(12)
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.space(2)

          Text {
            width: parent.width
            textFormat: Text.PlainText
            text: "KEYBOARD LAYOUT"
            color: root.dim
            font.family: root.contentFontFamily
            font.pixelSize: Style.font.caption
            font.letterSpacing: 1
          }

          Text {
            width: parent.width
            textFormat: Text.PlainText
            text: root.hostWidget && root.hostWidget.currentDescription !== ""
              ? root.hostWidget.currentDescription : "Unknown"
            color: root.contentForeground
            font.family: root.contentFontFamily
            font.pixelSize: Style.font.body
            font.bold: true
            elide: Text.ElideRight
          }
        }
      }

      TextField {
        id: searchField
        anchors.top: header.bottom
        anchors.topMargin: Style.space(10)
        anchors.left: parent.left
        anchors.right: parent.right
        placeholderText: "Search country, language or variant"
        foreground: root.contentForeground
        font.family: root.contentFontFamily

        onTextChanged: root.query = text

        Keys.onPressed: function(event) {
          if (root.asking) {
            if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) root.hostWidget.confirmSave(true)
            else if (event.key === Qt.Key_Escape) root.hostWidget.cancelSave()
            else if (event.key === Qt.Key_S) root.hostWidget.confirmSave(false)
            event.accepted = true
            return
          }
          var onVariants = root.focusPane === "variants"
          if (event.key === Qt.Key_Escape) {
            root.close()
          } else if (event.key === Qt.Key_Down) {
            if (onVariants) root.moveVariant(1); else root.moveLayout(1)
          } else if (event.key === Qt.Key_Up) {
            if (onVariants) root.moveVariant(-1); else root.moveLayout(-1)
          } else if (event.key === Qt.Key_Right) {
            if (root.browsedLayout) root.focusPane = "variants"
          } else if (event.key === Qt.Key_Left) {
            root.focusPane = "layouts"
          } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            if (onVariants) root.applyRow(root.variantIndex)
            else if (root.browsedLayout) root.pickLayout(root.browsedLayout.name)
          } else {
            return
          }
          event.accepted = true
        }
      }

      // ---- Footer: result of the last apply, or the key hints; once saving has
      //      been decided, a switch to change that decision.
      Item {
        id: footer
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        height: Style.space(18)

        Text {
          anchors.left: parent.left
          anchors.right: saveToggle.visible ? saveToggle.left : parent.right
          anchors.rightMargin: Style.space(10)
          anchors.verticalCenter: parent.verticalCenter
          textFormat: Text.PlainText
          elide: Text.ElideRight
          text: root.hostWidget && root.hostWidget.statusText !== ""
            ? root.hostWidget.statusText
            : "↑↓ move   ←→ switch list   Enter apply   Esc close"
          color: root.hostWidget && root.hostWidget.statusIsError ? Color.urgent : root.dim
          font.family: root.contentFontFamily
          font.pixelSize: Style.font.caption
        }

        Text {
          id: saveToggle
          visible: root.saveChoice !== null
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          textFormat: Text.PlainText
          text: "Remember in input.lua: " + (root.saveChoice === true ? "on" : "off")
          color: saveToggleMouse.containsMouse ? root.contentForeground : root.dim
          font.family: root.contentFontFamily
          font.pixelSize: Style.font.caption

          MouseArea {
            id: saveToggleMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.hostWidget.setSaveChoice(root.saveChoice !== true)
          }
        }
      }

      // ---- The two lists.
      Row {
        id: lists
        anchors.top: searchField.bottom
        anchors.topMargin: Style.space(12)
        anchors.bottom: footer.top
        anchors.bottomMargin: Style.space(8)
        anchors.left: parent.left
        anchors.right: parent.right
        spacing: Style.space(14)

        readonly property real columnWidth: (width - spacing) / 2

        Item {
          width: lists.columnWidth
          height: lists.height

          Text {
            id: layoutsLabel
            textFormat: Text.PlainText
            text: "COUNTRY / LANGUAGE"
            color: root.focusPane === "layouts" ? root.contentForeground : root.dim
            font.family: root.contentFontFamily
            font.pixelSize: Style.font.caption
            font.letterSpacing: 1
          }

          ListView {
            id: layoutList
            anchors.top: layoutsLabel.bottom
            anchors.topMargin: Style.space(6)
            anchors.bottom: parent.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            model: root.shown
            currentIndex: root.browsedIndex
            keyNavigationEnabled: false

            delegate: Rectangle {
              required property var modelData
              required property int index
              readonly property bool browsed: index === root.browsedIndex
              readonly property bool active: modelData.name === root.currentLayout

              width: layoutList.width
              height: Style.spacing.popupRowHeight
              radius: Style.cornerRadius
              color: browsed
                ? Style.selectedFillFor(root.contentForeground, Color.accent)
                : (layoutHover.hovered ? Style.hoverFillFor(root.contentForeground, Color.accent) : "transparent")

              HoverHandler { id: layoutHover }

              Text {
                anchors.left: parent.left
                anchors.right: layoutTick.left
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: Style.spacing.controlPaddingX
                textFormat: Text.PlainText
                text: modelData.description
                elide: Text.ElideRight
                color: browsed ? Style.selectedStateColor(root.contentForeground, Color.accent) : root.contentForeground
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.body
              }

              Text {
                id: layoutTick
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.rightMargin: Style.spacing.controlPaddingX
                visible: active
                text: "󰄬"
                color: Style.selectedStateColor(root.contentForeground, Color.accent)
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.body
              }

              MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                  searchField.forceActiveFocus()
                  root.pickLayout(modelData.name)
                }
              }
            }

            Text {
              anchors.centerIn: parent
              visible: root.shown.length === 0
              textFormat: Text.PlainText
              text: root.layouts.length === 0 ? "Loading layouts…" : "No matches"
              color: root.dim
              font.family: root.contentFontFamily
              font.pixelSize: Style.font.body
            }
          }
        }

        Item {
          width: lists.columnWidth
          height: lists.height

          Text {
            id: variantsLabel
            textFormat: Text.PlainText
            text: root.browsedLayout ? "VARIANT · " + root.browsedLayout.name.toUpperCase() : "VARIANT"
            color: root.focusPane === "variants" ? root.contentForeground : root.dim
            font.family: root.contentFontFamily
            font.pixelSize: Style.font.caption
            font.letterSpacing: 1
          }

          ListView {
            id: variantList
            anchors.top: variantsLabel.bottom
            anchors.topMargin: Style.space(6)
            anchors.bottom: parent.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            model: root.rows
            currentIndex: root.variantIndex
            keyNavigationEnabled: false

            delegate: Rectangle {
              required property var modelData
              required property int index
              readonly property bool cursor: index === root.variantIndex && root.focusPane === "variants"
              readonly property bool active: root.browsedLayout !== null
                && root.browsedLayout.name === root.currentLayout
                && modelData.value === root.currentVariant

              width: variantList.width
              height: Style.spacing.popupRowHeight
              radius: Style.cornerRadius
              color: cursor
                ? Style.selectedFillFor(root.contentForeground, Color.accent)
                : (variantHover.hovered ? Style.hoverFillFor(root.contentForeground, Color.accent) : "transparent")

              HoverHandler { id: variantHover }

              Text {
                anchors.left: parent.left
                anchors.right: variantTick.left
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: Style.spacing.controlPaddingX
                textFormat: Text.PlainText
                text: modelData.label
                elide: Text.ElideRight
                color: cursor ? Style.selectedStateColor(root.contentForeground, Color.accent) : root.contentForeground
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.body
              }

              Text {
                id: variantTick
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.rightMargin: Style.spacing.controlPaddingX
                visible: active
                text: "󰄬"
                color: Style.selectedStateColor(root.contentForeground, Color.accent)
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.body
              }

              MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                  searchField.forceActiveFocus()
                  root.focusPane = "variants"
                  root.variantIndex = index
                  root.applyRow(index)
                }
              }
            }
          }
        }
      }

      // ---- Asked once, before anything is written to disk.
      Rectangle {
        id: savePrompt
        visible: root.asking
        anchors.fill: lists
        color: Color.popups.background
        radius: Style.cornerRadius

        MouseArea { anchors.fill: parent; acceptedButtons: Qt.AllButtons }

        Column {
          anchors.centerIn: parent
          width: Math.min(parent.width - Style.space(40), Style.space(480))
          spacing: Style.space(14)

          Text {
            width: parent.width
            textFormat: Text.PlainText
            text: "Remember this layout?"
            color: root.contentForeground
            font.family: root.contentFontFamily
            font.pixelSize: Style.font.body
            font.bold: true
          }

          Text {
            width: parent.width
            textFormat: Text.PlainText
            wrapMode: Text.WordWrap
            text: "To keep your layout after a restart, Keymap Picker adds a small block at the end of ~/.config/hypr/input.lua. A backup is saved first and the rest of the file is left alone.\n\nOr apply it for this session only and nothing is written."
            color: root.dim
            font.family: root.contentFontFamily
            font.pixelSize: Style.font.bodySmall
            lineHeight: 1.15
          }

          Row {
            spacing: Style.space(10)

            Button {
              text: "Save and apply  ⏎"
              bordered: true
              foreground: root.contentForeground
              fontFamily: root.contentFontFamily
              onClicked: root.hostWidget.confirmSave(true)
            }

            Button {
              text: "This session only  S"
              bordered: true
              foreground: root.contentForeground
              fontFamily: root.contentFontFamily
              onClicked: root.hostWidget.confirmSave(false)
            }

            Button {
              text: "Cancel  Esc"
              bordered: true
              foreground: root.contentForeground
              fontFamily: root.contentFontFamily
              onClicked: root.hostWidget.cancelSave()
            }
          }
        }
      }
    }
  }
}
