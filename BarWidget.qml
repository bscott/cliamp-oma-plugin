import QtQuick
import Quickshell
import qs.Ui
import qs.Commons
import "Model.js" as Model

// Bar entry for CLIAMP: a play-state glyph plus a scrolling now-playing
// label. Left click toggles play/pause, middle click skips ahead, the wheel
// moves through the playlist, and right click opens a popup with full track
// details and transport controls. When Spotify or YouTube playback is
// detected over MPRIS, the widget follows and controls whichever source is
// active, with a picker in the popup.
BarWidget {
  id: root
  moduleName: "io.github.bscott.cliamp"

  readonly property var cliamp: bar && bar.shell ? bar.shell.serviceFor(moduleName) : null
  readonly property bool available: cliamp ? cliamp.anySource : false
  readonly property bool playing: cliamp ? cliamp.nowPlaying : false
  readonly property bool hasTrack: cliamp ? cliamp.hasTrack : false
  readonly property string title: cliamp ? cliamp.nowTitle : ""
  readonly property string artist: cliamp ? cliamp.nowArtist : ""
  readonly property string sourceKind: cliamp ? cliamp.activeSource : ""
  readonly property var sourceList: cliamp ? cliamp.sources : []

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
        x: 0

        readonly property bool needsScroll: implicitWidth > scrollClip.width
        readonly property bool canScroll: needsScroll && !root.popupOpen && !root.bar.vertical

        // Restart the marquee explicitly on any change that affects it, and
        // park the label at x:0 when it should not scroll. A `running`-bound
        // property-source animation can be left stopped when the text or width
        // flickers — e.g. the active source briefly changing during a pause —
        // and never resume; driving start/stop ourselves keeps it reliable.
        function syncScroll() {
          scrollAnim.stop()
          labelText.x = 0
          if (canScroll) scrollAnim.start()
        }
        onCanScrollChanged: syncScroll()
        onTextChanged: syncScroll()
        onImplicitWidthChanged: syncScroll()
        Component.onCompleted: syncScroll()

        NumberAnimation {
          id: scrollAnim
          target: labelText
          property: "x"
          from: scrollClip.width
          to: -labelText.implicitWidth
          duration: Math.max(6000, labelText.implicitWidth * 25)
          loops: Animation.Infinite
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
      root.available
        ? Model.summary(root.title, root.artist)
          + (root.sourceKind !== "cliamp" && root.sourceKind !== ""
            ? "  ·  " + Model.sourceLabel(root.sourceKind) : "")
        : "No media source detected")
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

          Image {
            id: artImage
            anchors.fill: parent
            anchors.margins: Style.space(2)
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            source: root.cliamp ? root.cliamp.nowArtUrl : ""
            visible: source !== "" && status === Image.Ready
          }

          Text {
            anchors.centerIn: parent
            visible: !artImage.visible
            text: Model.sourceIcon(root.sourceKind, root.cliamp && root.cliamp.nowIsStream)
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
              : "No media source detected"
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
            text: root.cliamp ? root.cliamp.nowAlbum : ""
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
      // live badge with elapsed time for endless streams. Hidden entirely for
      // sources that report no timing data, like some browser players.
      Column {
        width: parent.width
        spacing: Style.space(4)
        visible: root.hasTrack && root.cliamp
          && (root.cliamp.nowIsStream || root.cliamp.nowDuration > 0 || root.cliamp.nowPosition > 0)

        Item {
          width: parent.width
          height: positionText.implicitHeight

          Text {
            id: positionText
            anchors.left: parent.left
            text: root.cliamp ? Model.fmtTime(root.cliamp.nowPosition) : ""
            color: Qt.darker(root.bar.foreground, 1.3)
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.caption
          }

          Text {
            anchors.right: parent.right
            text: root.cliamp && root.cliamp.nowIsStream
              ? "LIVE"
              : (root.cliamp && root.cliamp.nowDuration > 0 ? Model.fmtTime(root.cliamp.nowDuration) : "")
            color: root.cliamp && root.cliamp.nowIsStream
              ? root.bar.foreground : Qt.darker(root.bar.foreground, 1.3)
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.caption
            font.bold: root.cliamp && root.cliamp.nowIsStream
          }
        }

        Rectangle {
          width: parent.width
          height: Style.space(4)
          radius: height / 2
          color: Qt.darker(root.bar.foreground, 3.0)
          visible: root.cliamp && !root.cliamp.nowIsStream && root.cliamp.nowDuration > 0

          Rectangle {
            height: parent.height
            radius: parent.radius
            color: root.bar.foreground
            width: root.cliamp && root.cliamp.nowDuration > 0
              ? parent.width * Math.min(1, root.cliamp.nowPosition / root.cliamp.nowDuration)
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
          enabled: root.cliamp ? root.cliamp.canPrevious : false
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
          enabled: root.cliamp ? root.cliamp.canNext : false
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
          if (!root.cliamp || root.sourceKind !== "cliamp") return ""
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

      // Party Mode toggle: washes the whole top bar in a beat-reactive
      // synthwave gradient. Highlights while active.
      BorderSurface {
        id: partyToggle
        readonly property bool on: root.cliamp ? root.cliamp.partyMode : false

        width: parent.width
        height: partyRow.implicitHeight + Style.space(12)
        radius: Style.spacing.labelGap
        color: on ? Style.selectedFillFor(root.bar.foreground, Color.accent) : "transparent"
        borderSpec: Border.controlSpec("normal", root.bar.foreground, Color.accent)

        Row {
          id: partyRow
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          anchors.leftMargin: partyToggle.borderLeft + Style.space(10)
          anchors.rightMargin: partyToggle.borderRight + Style.space(10)
          spacing: Style.space(10)

          Text {
            text: "󰓎"
            color: partyToggle.on ? Color.accent : root.bar.foreground
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.body
            width: Style.space(18)
            horizontalAlignment: Text.AlignHCenter
            anchors.verticalCenter: parent.verticalCenter
          }

          Column {
            width: parent.width - Style.space(80)
            spacing: Style.space(1)
            anchors.verticalCenter: parent.verticalCenter

            Text {
              text: "Party Mode"
              color: root.bar.foreground
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.bodySmall
              font.bold: partyToggle.on
            }

            Text {
              text: "Synthwave the top bar"
              color: Qt.darker(root.bar.foreground, 1.5)
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.caption
            }
          }

          Text {
            text: partyToggle.on ? "ON" : "OFF"
            color: partyToggle.on ? Color.accent : Qt.darker(root.bar.foreground, 1.5)
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.caption
            font.bold: partyToggle.on
            width: Style.space(30)
            horizontalAlignment: Text.AlignRight
            anchors.verticalCenter: parent.verticalCenter
          }
        }

        MouseArea {
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: if (root.cliamp) root.cliamp.toggleParty()
        }
      }

      // Party Mode controls: pick the visual style and nudge the intensity.
      // Revealed only while Party Mode is on.
      Row {
        width: parent.width
        spacing: Style.space(8)
        visible: root.cliamp ? root.cliamp.partyMode : false

        // Style segmented control: Bars | Gradient.
        Row {
          spacing: 0

          Repeater {
            model: [{ k: "bars", label: "Bars" }, { k: "gradient", label: "Gradient" }]

            BorderSurface {
              id: styleSeg
              required property var modelData
              required property int index
              readonly property bool sel: root.cliamp && root.cliamp.partyStyle === modelData.k

              width: Style.space(64)
              height: styleLabel.implicitHeight + Style.space(10)
              radius: Style.spacing.labelGap
              color: sel ? Style.selectedFillFor(root.bar.foreground, Color.accent) : "transparent"
              borderSpec: Border.controlSpec("normal", root.bar.foreground, Color.accent)

              Text {
                id: styleLabel
                anchors.centerIn: parent
                text: styleSeg.modelData.label
                color: styleSeg.sel ? Color.accent : root.bar.foreground
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: styleSeg.sel
              }

              MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: if (root.cliamp) root.cliamp.setStyle(styleSeg.modelData.k)
              }
            }
          }
        }

        Item { width: Style.space(4); height: 1 }

        // Intensity stepper: −  NN%  +
        Row {
          spacing: Style.space(4)
          anchors.verticalCenter: parent.verticalCenter

          Button {
            iconText: "󰍷"
            foreground: root.bar.foreground
            horizontalPadding: Style.spacing.controlPaddingX
            verticalPadding: Style.spacing.controlPaddingY
            onClicked: if (root.cliamp) root.cliamp.bumpIntensity(-4)
          }

          Text {
            text: (root.cliamp ? root.cliamp.partyIntensityPct : 0) + "%"
            color: root.bar.foreground
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.caption
            width: Style.space(34)
            horizontalAlignment: Text.AlignHCenter
            anchors.verticalCenter: parent.verticalCenter
          }

          Button {
            iconText: "󰐕"
            foreground: root.bar.foreground
            horizontalPadding: Style.spacing.controlPaddingX
            verticalPadding: Style.spacing.controlPaddingY
            onClicked: if (root.cliamp) root.cliamp.bumpIntensity(4)
          }
        }
      }

      PanelSeparator {
        visible: root.sourceList.length > 1
        foreground: root.bar.foreground
      }

      // Picker shown when more than one source is detected. Clicking a row
      // pins the widget to that source until it goes away.
      Column {
        id: sourcePicker
        visible: root.sourceList.length > 1
        width: parent.width
        spacing: Style.space(4)

        Repeater {
          model: root.sourceList

          BorderSurface {
            id: sourceRow
            required property var modelData

            readonly property bool selected: root.sourceKind === modelData.kind

            width: sourcePicker.width
            height: sourceInner.implicitHeight + Style.space(10)
            radius: Style.spacing.labelGap
            color: selected ? Style.selectedFillFor(root.bar.foreground, Color.accent) : "transparent"
            borderSpec: selected ? Border.controlSpec("normal", root.bar.foreground, Color.accent) : Border.none()

            Row {
              id: sourceInner
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              anchors.leftMargin: sourceRow.borderLeft + Style.space(8)
              anchors.rightMargin: sourceRow.borderRight + Style.space(8)
              spacing: Style.space(8)

              Text {
                text: Model.sourceIcon(sourceRow.modelData.kind, false)
                color: root.bar.foreground
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.body
                width: Style.space(18)
                horizontalAlignment: Text.AlignHCenter
                anchors.verticalCenter: parent.verticalCenter
              }

              Column {
                width: parent.width - Style.space(52)
                spacing: Style.space(1)
                anchors.verticalCenter: parent.verticalCenter

                Text {
                  text: Model.sourceLabel(sourceRow.modelData.kind)
                  color: root.bar.foreground
                  font.family: root.bar.fontFamily
                  font.pixelSize: Style.font.bodySmall
                  font.bold: sourceRow.selected
                  elide: Text.ElideRight
                  width: parent.width
                }

                Text {
                  text: sourceRow.modelData.title
                  color: Qt.darker(root.bar.foreground, 1.5)
                  font.family: root.bar.fontFamily
                  font.pixelSize: Style.font.caption
                  elide: Text.ElideRight
                  width: parent.width
                  visible: text !== ""
                }
              }

              Text {
                text: sourceRow.modelData.playing ? "󰐊" : ""
                color: root.bar.foreground
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.bodySmall
                width: Style.space(18)
                horizontalAlignment: Text.AlignHCenter
                anchors.verticalCenter: parent.verticalCenter
              }
            }

            MouseArea {
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: if (root.cliamp) root.cliamp.selectSource(sourceRow.modelData.kind)
            }
          }
        }
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
