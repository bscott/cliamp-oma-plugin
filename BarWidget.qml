import QtQuick
import Quickshell
import qs.Ui
import qs.Commons
import "Model.js" as Model

// Bar entry for CLIAMP: a play-state glyph plus a scrolling now-playing
// label. Left click toggles play/pause, middle click skips ahead, the wheel
// moves through the playlist, and right click opens a popup with full track
// details and transport controls.
BarWidget {
  id: root
  moduleName: "io.github.bscott.cliamp"

  readonly property var cliamp: bar && bar.shell ? bar.shell.serviceFor(moduleName) : null
  readonly property bool available: cliamp ? cliamp.available : false
  readonly property bool playing: cliamp ? cliamp.playing : false
  readonly property bool hasTrack: cliamp ? cliamp.hasTrack : false
  readonly property string title: cliamp ? cliamp.title : ""
  readonly property string artist: cliamp ? cliamp.artist : ""

  readonly property string playIcon: !available ? "󰝚" : (playing ? "󰏤" : "󰐊")
  readonly property real maxLabelWidth: setting("maxLabelWidth", 180)
  readonly property bool hideWhenUnavailable: setting("hideWhenUnavailable", false) === true

  property bool popupOpen: false

  function close() { popupOpen = false }

  // The service polls on the widget's configured cadence, but the shell only
  // hands settings to widget slots, so relay them across.
  Binding {
    target: root.cliamp
    property: "settings"
    value: root.settings
    when: root.cliamp !== null
  }

  visible: !hideWhenUnavailable || available
  implicitWidth: visible ? row.implicitWidth + Style.space(14) : 0
  implicitHeight: barSize

  Row {
    id: row
    anchors.centerIn: parent
    spacing: Style.space(6)

    Text {
      id: glyph
      anchors.verticalCenter: parent.verticalCenter
      text: root.playIcon
      color: root.available && root.playing
        ? root.bar.barForeground : Qt.darker(root.bar.barForeground, 1.5)
      font.family: root.bar.fontFamily
      font.pixelSize: Style.font.body
      Behavior on color {
        enabled: !root.bar || root.bar.foregroundAnimationEnabled
        ColorAnimation { duration: 160 }
      }
    }

    Item {
      id: scrollClip
      width: Math.min(root.maxLabelWidth, labelText.implicitWidth)
      height: glyph.height
      clip: true
      anchors.verticalCenter: parent.verticalCenter
      visible: !root.bar.vertical && root.title !== ""

      Text {
        id: labelText
        text: root.title + (root.artist ? "  ·  " + root.artist : "")
        color: root.bar.barForeground
        font.family: root.bar.fontFamily
        font.pixelSize: Style.font.body
        anchors.verticalCenter: parent.verticalCenter

        property bool needsScroll: implicitWidth > scrollClip.width

        NumberAnimation on x {
          running: labelText.needsScroll && !root.popupOpen && !root.bar.vertical
          loops: Animation.Infinite
          duration: Math.max(6000, labelText.implicitWidth * 25)
          from: scrollClip.width
          to: -labelText.implicitWidth
          easing.type: Easing.Linear
        }
      }
    }
  }

  MouseArea {
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: root.available ? Qt.PointingHandCursor : Qt.ArrowCursor
    acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton

    onClicked: function(mouse) {
      if (mouse.button === Qt.RightButton) {
        root.popupOpen = !root.popupOpen
        return
      }
      if (!root.cliamp || !root.available) return
      if (mouse.button === Qt.MiddleButton) root.cliamp.runAction("next", false)
      else root.cliamp.runAction("playPause", false)
    }
    onWheel: function(wheel) {
      if (!root.cliamp || !root.available) return
      if (wheel.angleDelta.y > 0) root.cliamp.runAction("previous", false)
      else if (wheel.angleDelta.y < 0) root.cliamp.runAction("next", false)
    }
    onEntered: if (root.bar) root.bar.showTooltip(root,
      root.available ? Model.summary(root.title, root.artist) : "cliamp is not running")
    onExited: if (root.bar) root.bar.hideTooltip(root)
  }

  PopupCard {
    id: popup
    anchorItem: root
    bar: root.bar
    owner: root
    open: root.popupOpen
    contentWidth: popup.fittedContentWidth(Style.space(320))
    contentHeight: popup.fittedContentHeight(column.implicitHeight)

    Column {
      id: column
      anchors.fill: parent
      spacing: Style.space(10)

      Row {
        spacing: Style.space(10)
        width: parent.width

        BorderSurface {
          width: Style.space(64)
          height: Style.space(64)
          radius: Style.spacing.labelGap
          color: Style.normalFillFor(root.bar.foreground, Color.accent)
          borderSpec: Border.controlSpec("normal", root.bar.foreground, Color.accent)

          Text {
            anchors.centerIn: parent
            text: root.cliamp && root.cliamp.isStream ? "󰐻" : "󰝚"
            color: root.bar.foreground
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.displayLarge
          }
        }

        Column {
          spacing: Style.space(4)
          width: parent.width - Style.space(74)
          anchors.verticalCenter: parent.verticalCenter

          Text {
            text: root.available
              ? (root.title || "Nothing playing")
              : "cliamp is not running"
            color: root.bar.foreground
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.subtitle
            font.bold: true
            elide: Text.ElideRight
            width: parent.width
          }

          Text {
            text: root.artist
            color: Qt.darker(root.bar.foreground, 1.3)
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.bodySmall
            elide: Text.ElideRight
            width: parent.width
            visible: text !== ""
          }

          Text {
            text: root.cliamp && root.cliamp.album ? root.cliamp.album : ""
            color: Qt.darker(root.bar.foreground, 1.6)
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.caption
            elide: Text.ElideRight
            width: parent.width
            visible: text !== ""
          }
        }
      }

      // Elapsed/total time with a slim progress bar for regular tracks, or a
      // live badge with elapsed time for endless streams.
      Column {
        width: parent.width
        spacing: Style.space(4)
        visible: root.hasTrack

        Item {
          width: parent.width
          height: positionText.implicitHeight

          Text {
            id: positionText
            anchors.left: parent.left
            text: root.cliamp ? Model.fmtTime(root.cliamp.position) : ""
            color: Qt.darker(root.bar.foreground, 1.3)
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.caption
          }

          Text {
            anchors.right: parent.right
            text: root.cliamp && root.cliamp.isStream
              ? "LIVE"
              : (root.cliamp && root.cliamp.duration > 0 ? Model.fmtTime(root.cliamp.duration) : "")
            color: root.cliamp && root.cliamp.isStream
              ? root.bar.foreground : Qt.darker(root.bar.foreground, 1.3)
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.caption
            font.bold: root.cliamp && root.cliamp.isStream
          }
        }

        Rectangle {
          width: parent.width
          height: Style.space(4)
          radius: height / 2
          color: Qt.darker(root.bar.foreground, 3.0)
          visible: root.cliamp && !root.cliamp.isStream && root.cliamp.duration > 0

          Rectangle {
            height: parent.height
            radius: parent.radius
            color: root.bar.foreground
            width: root.cliamp && root.cliamp.duration > 0
              ? parent.width * Math.min(1, root.cliamp.position / root.cliamp.duration)
              : 0
          }
        }
      }

      Row {
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: Style.space(6)

        Button {
          iconText: "󰒮"
          foreground: root.bar.foreground
          horizontalPadding: Style.spacing.controlPaddingX
          verticalPadding: Style.spacing.controlPaddingY
          enabled: root.available
          opacity: enabled ? 1.0 : 0.4
          onClicked: if (root.cliamp) root.cliamp.runAction("previous", false)
        }

        Button {
          iconText: root.playing ? "󰏤" : "󰐊"
          foreground: root.bar.foreground
          horizontalPadding: Style.spacing.panelGap
          verticalPadding: Style.spacing.controlPaddingY
          iconSize: Style.font.iconLarge
          enabled: root.available
          opacity: enabled ? 1.0 : 0.4
          onClicked: if (root.cliamp) root.cliamp.runAction("playPause", false)
        }

        Button {
          iconText: "󰒭"
          foreground: root.bar.foreground
          horizontalPadding: Style.spacing.controlPaddingX
          verticalPadding: Style.spacing.controlPaddingY
          enabled: root.available
          opacity: enabled ? 1.0 : 0.4
          onClicked: if (root.cliamp) root.cliamp.runAction("next", false)
        }

        Button {
          iconText: "󰓛"
          foreground: root.bar.foreground
          horizontalPadding: Style.spacing.controlPaddingX
          verticalPadding: Style.spacing.controlPaddingY
          enabled: root.available && root.playing
          opacity: enabled ? 1.0 : 0.4
          onClicked: if (root.cliamp) root.cliamp.runAction("stop", false)
        }
      }

      Text {
        anchors.horizontalCenter: parent.horizontalCenter
        text: {
          if (!root.cliamp || !root.available) return ""
          var parts = []
          if (root.cliamp.trackTotal > 0 && root.cliamp.trackIndex >= 0)
            parts.push("Track " + (root.cliamp.trackIndex + 1) + " of " + root.cliamp.trackTotal)
          if (root.cliamp.playlist) parts.push(root.cliamp.playlist)
          return parts.join("  ·  ")
        }
        color: Qt.darker(root.bar.foreground, 1.5)
        font.family: root.bar.fontFamily
        font.pixelSize: Style.font.caption
        elide: Text.ElideRight
        width: Math.min(implicitWidth, parent.width)
        visible: text !== ""
      }

      Text {
        text: root.cliamp ? root.cliamp.lastError : ""
        color: root.bar.urgent
        font.family: root.bar.fontFamily
        font.pixelSize: Style.font.caption
        wrapMode: Text.WordWrap
        width: parent.width
        visible: text !== ""
      }
    }
  }
}
