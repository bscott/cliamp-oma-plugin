import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Commons
import "Model.js" as Model

// Party Mode surface: a layer-shell overlay floating just over the top bar on
// every monitor, painting a seamlessly scrolling synthwave wash whose colors
// are derived from the active Omarchy theme accent and whose brightness pulses
// to the beat (fed by the service's partyLevel). The surface takes no input —
// its mask is empty — so every click, scroll, and hover passes straight
// through to the real bar underneath.
Item {
  id: root

  // Injected by the host shell.
  property var shell: null
  property var service: null
  property var manifest: null

  property bool opened: false
  function open(payload) { opened = true }
  function close() { opened = false }
  Component.onCompleted: opened = true

  readonly property real barHeight: Style.bar.sizeHorizontal
  readonly property real intensity: service ? service.partyIntensity : 0.34
  readonly property real level: service ? service.partyLevel : 0.4

  // Perceptual level: a gentle gamma lifts the mids so quiet passages still
  // move and loud hits punch harder, making the motion track the soundtrack.
  readonly property real motion: Math.pow(Math.min(1, Math.max(0, level)), 0.7)

  // Scroll phase in cycles, advanced every frame at a rate that rises with the
  // beat — so the whole bar visibly speeds up on louder passages and eases on
  // quiet ones. A shared phase keeps every monitor in sync.
  property real phase: 0
  property real huePhase: 0
  Timer {
    interval: 16
    repeat: true
    running: root.opened
    onTriggered: {
      root.phase += (0.30 + 2.1 * root.motion) * 0.016
      root.huePhase = 26 * Math.sin(root.phase * 1.1)
    }
  }

  readonly property string style: service ? service.partyStyle : "bars"

  // Neon palette anchored on the live Omarchy theme accent — reading Color.accent
  // here means a theme change re-derives the whole palette automatically — then
  // hue-shimmered by huePhase so the colours keep evolving. Kept as hex so the
  // spectrum bars can interpolate along them.
  readonly property var stops: Model.synthwaveStops(Color.accent)
  readonly property string h0: Model.rotateHue(root.stops[0], root.huePhase)
  readonly property string h1: Model.rotateHue(root.stops[1], root.huePhase)
  readonly property string h2: Model.rotateHue(root.stops[2], root.huePhase)
  readonly property string h3: Model.rotateHue(root.stops[3], root.huePhase)
  readonly property color c0: root.h0
  readonly property color c1: root.h1
  readonly property color c2: root.h2
  readonly property color c3: root.h3

  // Live smoothed spectrum from the service (real for cliamp, synthetic for
  // Spotify/YouTube). Sampled with interpolation so a handful of bands can
  // drive a denser bar row.
  readonly property var bands: service ? service.bands : []
  function bandAt(frac) {
    var b = root.bands
    if (!b || b.length === 0) return 0
    var f = Math.min(1, Math.max(0, frac)) * (b.length - 1)
    var i = Math.floor(f)
    var v0 = Number(b[i]) || 0
    var v1 = Number(b[Math.min(b.length - 1, i + 1)]) || 0
    return v0 + (v1 - v0) * (f - i)
  }

  Variants {
    model: Quickshell.screens

    delegate: PanelWindow {
      id: win
      required property var modelData
      screen: modelData

      color: "transparent"
      // Ignore the bar's exclusive zone so the surface overlaps the bar
      // instead of being pushed below it; it reserves no space of its own.
      exclusionMode: ExclusionMode.Ignore
      WlrLayershell.namespace: "io.github.bscott.cliamp-party"
      WlrLayershell.layer: WlrLayer.Overlay
      WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

      anchors { top: true; left: true; right: true }
      implicitHeight: root.barHeight

      // Empty input region: the overlay is purely decorative and never steals
      // pointer or keyboard events from the bar below it.
      mask: Region {}

      Item {
        id: fx
        anchors.fill: parent
        clip: true

        // Scroll offsets derived from the shared beat-driven phase, so all
        // motion accelerates and eases with the music rather than running at a
        // fixed rate. Each layer takes the phase at its own multiplier.
        readonly property real w: width
        function scrollLeft(mult) { return -((root.phase * mult) % 1.0) * fx.w }
        function scrollRight(mult) { return -(1.0 - ((root.phase * mult) % 1.0)) * fx.w }

        opacity: root.opened ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }

        // ---------------------------------------------------------- gradient
        // The scrolling synthwave wash. Shown when the style is "gradient".
        Item {
          anchors.fill: parent
          visible: root.style === "gradient"
          opacity: Math.min(0.82, root.intensity * (1.35 + 1.9 * root.motion))

          // Base wash: the four-colour neon cycle laid down twice across double
          // width, so a one-width scroll step loops seamlessly.
          Rectangle {
            height: parent.height
            width: fx.w * 2
            x: fx.scrollLeft(1.0)
            gradient: Gradient {
              orientation: Gradient.Horizontal
              GradientStop { position: 0.000; color: root.c0 }
              GradientStop { position: 0.125; color: root.c1 }
              GradientStop { position: 0.250; color: root.c2 }
              GradientStop { position: 0.375; color: root.c3 }
              GradientStop { position: 0.500; color: root.c0 }
              GradientStop { position: 0.625; color: root.c1 }
              GradientStop { position: 0.750; color: root.c2 }
              GradientStop { position: 0.875; color: root.c3 }
              GradientStop { position: 1.000; color: root.c0 }
            }
          }

          // Second wash, phase-shifted and drifting the other way at a slower
          // rate. Lighter opacity so it shimmers over the base without
          // averaging the complementary hues into grey.
          Rectangle {
            height: parent.height
            width: fx.w * 2
            x: fx.scrollRight(0.62)
            opacity: 0.4
            gradient: Gradient {
              orientation: Gradient.Horizontal
              GradientStop { position: 0.000; color: root.c2 }
              GradientStop { position: 0.125; color: root.c3 }
              GradientStop { position: 0.250; color: root.c0 }
              GradientStop { position: 0.375; color: root.c1 }
              GradientStop { position: 0.500; color: root.c2 }
              GradientStop { position: 0.625; color: root.c3 }
              GradientStop { position: 0.750; color: root.c0 }
              GradientStop { position: 0.875; color: root.c1 }
              GradientStop { position: 1.000; color: root.c2 }
            }
          }

          // Two hot light-sweeps streaking across in opposite directions,
          // white-hot at the centre and brighter on the beat.
          Repeater {
            model: 2
            Rectangle {
              required property int index
              readonly property real dir: index === 0 ? 1 : -1
              readonly property real span: fx.w + width
              height: fx.height
              width: fx.w * 0.32
              opacity: Math.min(0.9, 0.3 + 0.65 * root.motion)
              x: {
                var p = (root.phase * (1.5 + index * 0.4)) % 1.0
                return dir > 0 ? p * span - width : fx.w - p * span
              }
              gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0.0; color: "transparent" }
                GradientStop { position: 0.5; color: index === 0 ? "#ffffff" : root.c2 }
                GradientStop { position: 1.0; color: "transparent" }
              }
            }
          }
        }

        // -------------------------------------------------------------- bars
        // cliamp-style spectrum analyser. Shown when the style is "bars". Each
        // bar's height tracks a slice of the live spectrum, coloured along the
        // theme palette and lit brighter by the overall beat.
        Item {
          id: barsLayer
          anchors.fill: parent
          visible: root.style === "bars"
          readonly property int count: Math.max(24, Math.min(48, Math.round(fx.w / 60)))
          readonly property real slot: fx.w / count
          readonly property real maxH: fx.height * 0.92
          opacity: Math.min(1.0, 0.6 + 0.8 * root.intensity)

          // Shapes a raw band value into a bar fraction. A mild lift keeps
          // quiet bands visible while the bass still towers, giving a real
          // bass-to-treble silhouette rather than a flat block or flat line.
          function shape(v) { return Math.pow(Math.min(1, Math.max(0, v)), 0.75) }

          // Peak-hold: each bar keeps a peak that snaps up to the current value
          // and drifts down, drawn as a falling cap for the classic analyser
          // look. Recomputed on a timer so the caps ease independently.
          property var peaks: []
          Timer {
            interval: 40
            repeat: true
            running: barsLayer.visible && root.opened
            onTriggered: {
              var n = barsLayer.count
              var out = []
              for (var i = 0; i < n; i++) {
                var cur = barsLayer.shape(root.bandAt(n > 1 ? i / (n - 1) : 0))
                var prev = i < barsLayer.peaks.length ? barsLayer.peaks[i] : 0
                out.push(cur > prev ? cur : Math.max(0, prev - 0.03))
              }
              barsLayer.peaks = out
            }
          }

          Repeater {
            model: barsLayer.count
            Item {
              id: slotItem
              required property int index
              readonly property real frac: barsLayer.count > 1 ? index / (barsLayer.count - 1) : 0
              readonly property real bv: barsLayer.shape(root.bandAt(frac))
              readonly property real peak: index < barsLayer.peaks.length ? barsLayer.peaks[index] : 0
              readonly property color col: Model.paletteAt([root.h0, root.h1, root.h2, root.h3], frac)

              x: index * barsLayer.slot
              width: barsLayer.slot
              height: parent.height

              // The bar, brighter at the top for a lit look.
              Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: parent.bottom
                width: barsLayer.slot * 0.58
                height: Math.max(2, slotItem.bv * barsLayer.maxH)
                radius: Math.min(width * 0.5, 3)
                gradient: Gradient {
                  GradientStop { position: 0.0; color: Qt.lighter(slotItem.col, 1.25) }
                  GradientStop { position: 1.0; color: slotItem.col }
                }
                Behavior on height { NumberAnimation { duration: 55; easing.type: Easing.OutQuad } }
              }

              // Falling peak cap.
              Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                width: barsLayer.slot * 0.58
                height: Math.max(1.5, barsLayer.maxH * 0.06)
                radius: height / 2
                color: Qt.lighter(slotItem.col, 1.4)
                y: parent.height - Math.max(2, slotItem.peak * barsLayer.maxH) - height
                Behavior on y { NumberAnimation { duration: 70; easing.type: Easing.OutQuad } }
              }
            }
          }

          // A lit baseline so even silent bands leave a neon floor.
          Rectangle {
            anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
            height: Math.max(1, Math.round(root.barHeight * 0.07))
            opacity: Math.min(0.9, 0.45 + 0.55 * root.motion)
            gradient: Gradient {
              orientation: Gradient.Horizontal
              GradientStop { position: 0.0; color: root.h0 }
              GradientStop { position: 0.5; color: root.h2 }
              GradientStop { position: 1.0; color: root.h3 }
            }
          }
        }
      }
    }
  }
}
