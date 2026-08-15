import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris
import "Model.js" as Model

// Headless singleton that owns all communication with the media sources. It
// polls `cliamp status --json` on a timer and runs cliamp control commands,
// and it also watches the session's MPRIS players for Spotify and YouTube so
// the widget can show and control whichever source is actually playing.
// Keeping the process handling here means every bar surface (one per
// monitor) reads the same state instead of each spawning its own pollers.
Item {
  id: root

  property var shell: null

  // Inline widget settings, pushed in by the bar widget since the shell only
  // injects settings into widget slots, not services.
  property var settings: ({})

  // ------------------------------------------------------------ cliamp state

  property bool installed: false
  property bool installChecked: false
  property bool available: false
  property string playbackState: "stopped"
  property string title: ""
  property string artist: ""
  property string album: ""
  property string trackPath: ""
  property bool isStream: false
  property real position: 0
  property real duration: 0
  property int trackIndex: -1
  property int trackTotal: 0
  property string playlist: ""
  property real volumeDb: 0
  property bool shuffle: false
  property string repeat: ""
  property string lastError: ""

  // Consecutive failed polls. A single failure right after a control command
  // is normal — cliamp briefly stops answering while it opens a stream — so
  // the widget only flips to unavailable after two misses in a row.
  property int _pollMisses: 0

  // Optimistic play/pause override so the UI flips the instant a control is
  // clicked instead of waiting out the poll interval. -1 follows the real
  // state; 0/1 hold the expected state until a status refresh confirms it.
  property int _desired: -1
  readonly property bool playing: _desired === -1
    ? playbackState === "playing" : _desired === 1

  readonly property int refreshIntervalSec: intSetting("refreshIntervalSec", 2, 1, 60)

  // ------------------------------------------------------------- party mode

  property bool partyMode: false
  readonly property bool partyBeatReactive: boolSetting("partyBeatReactive", true)

  // Effective intensity in 0..1. The popup's quick controls set a runtime
  // override; when unset (-1) it follows the persisted setting.
  property int _intensityOverride: -1
  readonly property int partyIntensityPct: _intensityOverride >= 0
    ? _intensityOverride : intSetting("partyIntensity", 34, 8, 60)
  readonly property real partyIntensity: partyIntensityPct / 100

  function bumpIntensity(deltaPct) {
    _intensityOverride = Math.min(60, Math.max(8, partyIntensityPct + deltaPct))
    return _intensityOverride
  }

  // Visual style: "bars" (cliamp-style spectrum analyser) or "gradient" (the
  // scrolling synthwave wash). The popup can override the persisted setting at
  // runtime.
  property string _styleOverride: ""
  readonly property string partyStyle: _styleOverride !== ""
    ? _styleOverride : (boolSetting("partyBars", true) ? "bars" : "gradient")

  function setStyle(s) {
    if (s !== "bars" && s !== "gradient") return partyStyle
    _styleOverride = s
    return partyStyle
  }

  function toggleStyle() { return setStyle(partyStyle === "bars" ? "gradient" : "bars") }

  // Smoothed 0..1 audio level driving the overall beat pulse, plus the smoothed
  // per-band spectrum driving the visualizer bars. Both are fed by cliamp's
  // band stream when it is the active playing source, and by a gentle synthetic
  // wave otherwise so Spotify/YouTube still dance.
  property real partyLevel: 0.35
  property var bands: [0, 0, 0, 0, 0, 0, 0, 0, 0, 0]

  // Smooths a fresh band frame into the running spectrum: fast attack so bars
  // jump on transients, slower release so they fall away like a real analyser.
  function pushBands(raw, expand) {
    var out = []
    for (var i = 0; i < raw.length; i++) {
      var tgt = Number(raw[i])
      if (!isFinite(tgt)) tgt = 0
      tgt = Math.min(1, Math.max(0, tgt))
      if (expand) tgt = Math.pow(tgt, 0.8)
      var prev = i < bands.length ? Number(bands[i]) : 0
      var k = tgt > prev ? 0.7 : 0.22
      out.push(prev + (tgt - prev) * k)
    }
    bands = out
  }

  readonly property bool _beatFromCliamp: partyMode && partyBeatReactive
    && activeSource === "cliamp" && playing

  function toggleParty() { return setParty(!partyMode) }

  function setParty(on) {
    if (partyMode === on) return partyMode
    partyMode = on
    if (!shell) return partyMode
    if (on) shell.summon("io.github.bscott.cliamp", "{}")
    else shell.hide("io.github.bscott.cliamp")
    return partyMode
  }

  // ------------------------------------------------------------ MPRIS state

  readonly property var mprisPlayers: Mpris.players ? Mpris.players.values : []

  // Detection reads player metadata through plain function calls, which QML
  // cannot track, so metadata and play-state changes bump this revision to
  // force the derived properties to recompute.
  property int _mprisRev: 0

  readonly property var spotifyPlayer: findPlayer("spotify", _mprisRev)
  readonly property var youtubePlayer: findPlayer("youtube", _mprisRev)

  function findPlayer(kind, rev) {
    for (var i = 0; i < mprisPlayers.length; i++) {
      var p = mprisPlayers[i]
      if (kind === "spotify" ? Model.isSpotifyPlayer(p) : Model.isYoutubePlayer(p)) return p
    }
    return null
  }

  // --------------------------------------------------------- source routing

  // The user's explicit source pin from the popup. Empty means auto-follow:
  // whichever source is playing wins, in cliamp > Spotify > YouTube order.
  property string preferredSource: ""

  readonly property string activeSource: pickActive(_mprisRev, available, playing, preferredSource)

  function pickActive() {
    var detected = {
      cliamp: available,
      spotify: spotifyPlayer !== null,
      youtube: youtubePlayer !== null
    }
    var playingNow = {
      cliamp: available && playing,
      spotify: !!(spotifyPlayer && spotifyPlayer.isPlaying),
      youtube: !!(youtubePlayer && youtubePlayer.isPlaying)
    }
    if (preferredSource !== "" && detected[preferredSource]) return preferredSource
    var order = ["cliamp", "spotify", "youtube"]
    for (var i = 0; i < order.length; i++) if (playingNow[order[i]]) return order[i]
    for (var j = 0; j < order.length; j++) if (detected[order[j]]) return order[j]
    return ""
  }

  function selectSource(kind) {
    if (kind !== "cliamp" && kind !== "spotify" && kind !== "youtube") return false
    preferredSource = kind
    return true
  }

  // Drop a stale pin once its source disappears, so the pin doesn't
  // unexpectedly reassert itself when the source comes back later.
  readonly property bool _preferredDetected: preferredSource === ""
    || (preferredSource === "cliamp" ? available
      : preferredSource === "spotify" ? spotifyPlayer !== null
      : youtubePlayer !== null)
  on_PreferredDetectedChanged: if (!_preferredDetected) preferredSource = ""

  // ----------------------------------------------------- unified now-playing

  readonly property var activePlayer: activeSource === "spotify" ? spotifyPlayer
    : activeSource === "youtube" ? youtubePlayer : null
  readonly property bool anySource: available || spotifyPlayer !== null || youtubePlayer !== null
  readonly property bool nowPlaying: activeSource === "cliamp" ? playing
    : !!(activePlayer && activePlayer.isPlaying)
  readonly property string nowTitle: activeSource === "cliamp" ? title
    : (activePlayer ? String(activePlayer.trackTitle || "") : "")
  readonly property string nowArtist: activeSource === "cliamp" ? artist
    : (activePlayer ? String(activePlayer.trackArtist || "") : "")
  readonly property string nowAlbum: activeSource === "cliamp" ? album
    : (activePlayer ? String(activePlayer.trackAlbum || "") : "")
  readonly property string nowArtUrl: activePlayer ? String(activePlayer.trackArtUrl || "") : ""
  readonly property bool nowIsStream: activeSource === "cliamp" && isStream
  readonly property real nowPosition: activeSource === "cliamp" ? position
    : (activePlayer && activePlayer.positionSupported ? activePlayer.position : 0)
  readonly property real nowDuration: activeSource === "cliamp" ? duration
    : (activePlayer && activePlayer.lengthSupported ? activePlayer.length : 0)
  readonly property bool hasTrack: anySource && nowTitle !== ""
  readonly property bool canNext: activeSource === "cliamp" ? available
    : !!(activePlayer && activePlayer.canGoNext)
  readonly property bool canPrevious: activeSource === "cliamp" ? available
    : !!(activePlayer && activePlayer.canGoPrevious)

  // Detected sources for the popup's picker, in routing priority order.
  readonly property var sources: buildSources(_mprisRev, available, playing, title)

  function buildSources() {
    var list = []
    if (available) list.push({ kind: "cliamp", title: title, playing: playing })
    if (spotifyPlayer) list.push({
      kind: "spotify",
      title: String(spotifyPlayer.trackTitle || ""),
      playing: !!spotifyPlayer.isPlaying
    })
    if (youtubePlayer) list.push({
      kind: "youtube",
      title: String(youtubePlayer.trackTitle || ""),
      playing: !!youtubePlayer.isPlaying
    })
    return list
  }

  // ---------------------------------------------------------------- helpers

  function intSetting(name, fallback, min, max) {
    var value = settings ? settings[name] : undefined
    var n = parseInt(String(value === undefined || value === null ? fallback : value), 10)
    if (!isFinite(n)) n = fallback
    return Math.min(max, Math.max(min, n))
  }

  function boolSetting(name, fallback) {
    var value = settings ? settings[name] : undefined
    return value === undefined || value === null ? fallback : value === true
  }

  function refresh() {
    if (!installChecked || !installed) {
      if (!whichProcess.running) {
        whichProcess.command = ["which", "cliamp"]
        whichProcess.running = true
      }
      return
    }
    if (statusProcess.running) return
    statusProcess.command = ["cliamp", "status", "--json"]
    statusProcess.running = true
    if (!pollWatchdog.running) pollWatchdog.start()
  }

  function resetUnavailable(message) {
    available = false
    _desired = -1
    playbackState = "stopped"
    title = ""
    artist = ""
    album = ""
    trackPath = ""
    isStream = false
    position = 0
    duration = 0
    trackIndex = -1
    trackTotal = 0
    playlist = ""
    lastError = message || ""
  }

  function pollFailed(message) {
    _pollMisses += 1
    if (_pollMisses >= 2 || !available) resetUnavailable(message)
    else delayedRefresh.restart()
  }

  function applyStatus(parsed) {
    _pollMisses = 0
    available = true
    playbackState = parsed.playbackState
    // Reality caught up to the pending toggle — stop overriding.
    if (_desired !== -1 && (playbackState === "playing") === (_desired === 1)) _desired = -1
    title = parsed.title
    artist = parsed.artist
    album = parsed.album
    trackPath = parsed.path
    isStream = parsed.isStream
    position = parsed.position
    duration = parsed.duration
    trackIndex = parsed.trackIndex
    trackTotal = parsed.trackTotal
    playlist = parsed.playlist
    volumeDb = parsed.volumeDb
    shuffle = parsed.shuffle
    repeat = parsed.repeat
    lastError = ""
  }

  // ---------------------------------------------------------------- actions

  // Runs a playback control against whichever source is active. Returns
  // false when the action is unknown or no source is reachable.
  function runAction(action, showFeedback) {
    if (activeSource === "cliamp") return runCliampAction(action, showFeedback)
    if (activePlayer) return runMprisAction(activePlayer, action, showFeedback)
    return false
  }

  // Maps actions onto cliamp CLI verbs; "playPause" becomes cliamp's
  // `toggle`.
  function runCliampAction(action, showFeedback) {
    if (!installed || !available) return false

    var verbs = {
      playPause: "toggle",
      play: "play",
      pause: "pause",
      next: "next",
      previous: "prev",
      stop: "stop"
    }
    var verb = verbs[action]
    if (!verb) return false

    var icon = actionIcon(action, playing)

    if (action === "playPause") _desired = playing ? 0 : 1
    else if (action === "play") _desired = 1
    else if (action === "pause" || action === "stop") _desired = 0

    if (actionProcess.running) actionProcess.running = false
    actionProcess.command = ["cliamp", verb]
    actionProcess.running = true

    if (showFeedback === true) showOsd(icon)
    return true
  }

  function runMprisAction(p, action, showFeedback) {
    var icon = actionIcon(action, !!p.isPlaying)
    var handled = false

    if (action === "playPause") {
      if (p.canTogglePlaying) { p.togglePlaying(); handled = true }
      else if (p.isPlaying && p.canPause) { p.pause(); handled = true }
      else if (!p.isPlaying && p.canPlay) { p.play(); handled = true }
    } else if (action === "play") {
      if (p.canPlay) { p.play(); handled = true }
      else if (p.canTogglePlaying && !p.isPlaying) { p.togglePlaying(); handled = true }
    } else if (action === "pause") {
      if (p.canPause) { p.pause(); handled = true }
      else if (p.canTogglePlaying && p.isPlaying) { p.togglePlaying(); handled = true }
    } else if (action === "next") {
      if (p.canGoNext) { p.next(); handled = true }
    } else if (action === "previous") {
      if (p.canGoPrevious) { p.previous(); handled = true }
    } else if (action === "stop") {
      if (p.canControl) { p.stop(); handled = true }
      else if (p.canPause && p.isPlaying) { p.pause(); handled = true }
    }

    if (handled && showFeedback === true) showOsd(icon)
    return handled
  }

  // OSD icon for an action, given whether the source was playing before the
  // action ran.
  function actionIcon(action, wasPlaying) {
    if (action === "playPause") return wasPlaying ? "media-pause" : "media-play"
    if (action === "play") return "media-play"
    if (action === "next") return "media-next"
    if (action === "previous") return "media-previous"
    return "media-pause"
  }

  function showOsd(iconName) {
    if (!shell) return
    shell.summon("omarchy.osd", JSON.stringify({
      icon: iconName,
      message: Model.summary(nowTitle, nowArtist)
    }))
  }

  function statusJson() {
    var kinds = []
    for (var i = 0; i < sources.length; i++) kinds.push(sources[i].kind)
    return JSON.stringify({
      available: anySource,
      source: activeSource,
      sources: kinds,
      state: activeSource === "cliamp" ? playbackState : (nowPlaying ? "playing" : "paused"),
      playing: nowPlaying,
      title: nowTitle,
      artist: nowArtist,
      album: nowAlbum,
      stream: nowIsStream,
      position: nowPosition,
      duration: nowDuration,
      index: activeSource === "cliamp" ? trackIndex : -1,
      total: activeSource === "cliamp" ? trackTotal : 0,
      playlist: activeSource === "cliamp" ? playlist : "",
      party: partyMode,
      partyStyle: partyStyle,
      partyIntensity: partyIntensityPct
    })
  }

  // ------------------------------------------------------- timers/processes

  Timer {
    id: refreshTimer
    interval: root.refreshIntervalSec * 1000
    repeat: true
    running: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  Timer {
    id: delayedRefresh
    interval: 400
    repeat: false
    onTriggered: root.refresh()
  }

  // Advances the popup's progress display between polls. cliamp positions
  // tick locally and resync on every real poll; MPRIS players track position
  // internally and just need their change signal poked to refresh bindings.
  Timer {
    interval: 1000
    repeat: true
    running: root.anySource && root.nowPlaying
    onTriggered: {
      if (root.activeSource === "cliamp") {
        var next = root.position + 1
        if (root.duration > 0 && next > root.duration) next = root.duration
        root.position = next
      } else if (root.activePlayer) {
        root.activePlayer.positionChanged()
      }
    }
  }

  // A status call that never exits would otherwise block every future poll,
  // since refresh() skips while its process is still running. Reap anything
  // still going well before the next poll can be due.
  Timer {
    id: pollWatchdog
    interval: 10000
    repeat: false
    onTriggered: if (statusProcess.running) statusProcess.running = false
  }

  // Streams cliamp's visualizer bands while Party Mode wants a live beat, and
  // decays the level toward zero when the stream stops. `running` on a Process
  // toggles the child process, so binding it to the beat condition starts and
  // stops the stream automatically.
  Process {
    id: visstreamProcess
    running: root._beatFromCliamp
    command: ["cliamp", "visstream", "--fps", "30"]
    stdout: SplitParser {
      onRead: function(line) {
        if (!root._beatFromCliamp) return
        try {
          var frame = JSON.parse(line)
          if (!frame.bands) return
          // Feed the real spectrum to the visualizer bars, and collapse it to
          // an overall level for the gradient's beat pulse. Expanding the
          // dynamic range makes quiet and loud read very differently.
          root.pushBands(frame.bands, true)
          var target = Math.min(1, Math.max(0, (Model.bandLevel(frame.bands) - 0.08) * 1.7))
          var k = target > root.partyLevel ? 0.85 : 0.18
          root.partyLevel = root.partyLevel + (target - root.partyLevel) * k
        } catch (e) {
          // Ignore partial or non-JSON lines.
        }
      }
    }
  }

  // Synthetic spectrum for sources without real band data. cliamp gets the
  // true analyser via visstream; Spotify and YouTube can't expose one over
  // MPRIS, so while they play we animate a lively pseudo-spectrum that dances
  // and settles to near-flat the moment playback pauses.
  property real _wavePhase: 0
  Timer {
    interval: 45
    repeat: true
    running: root.partyMode && !root._beatFromCliamp
    onTriggered: {
      root._wavePhase += 0.09
      var dancing = root.partyBeatReactive && root.nowPlaying
      var gentle = !root.partyBeatReactive && root.nowPlaying
      var out = []
      for (var i = 0; i < 10; i++) {
        var target
        if (dancing) {
          // Per-band oscillators at different rates plus a shared "kick"
          // envelope give it a beat-like bounce, weighted toward the bass.
          var osc = Math.abs(Math.sin(root._wavePhase * (0.8 + 0.28 * i) + i * 1.3))
          var kick = Math.pow(0.5 + 0.5 * Math.sin(root._wavePhase * 1.7), 2)
          var bass = 1.0 - i * 0.045
          target = Math.min(1, Math.max(0, (0.2 + 0.7 * osc) * (0.45 + 0.75 * kick) * bass))
        } else if (gentle) {
          target = Math.min(1, Math.max(0, 0.32 + 0.24 * Math.sin(root._wavePhase + i * 0.5)))
        } else {
          target = 0.04
        }
        var prev = i < bands.length ? Number(bands[i]) : 0
        var k = target > prev ? 0.5 : 0.16
        out.push(prev + (target - prev) * k)
      }
      bands = out
      var lvl = Model.bandLevel(out)
      root.partyLevel = root.partyLevel + (lvl - root.partyLevel) * 0.3
    }
  }

  // Wires each live player's metadata and play-state signals to the
  // revision counter driving source detection and routing.
  Instantiator {
    model: root.mprisPlayers
    delegate: Connections {
      required property var modelData
      target: modelData
      function onMetadataChanged() { root._mprisRev++ }
      function onIsPlayingChanged() { root._mprisRev++ }
    }
  }

  Process {
    id: whichProcess
    running: false
    command: []
    onExited: function(exitCode) {
      root.installChecked = true
      root.installed = exitCode === 0
      if (root.installed) root.refresh()
      else root.resetUnavailable("cliamp is not installed")
    }
  }

  Process {
    id: statusProcess
    running: false
    command: []
    stdout: StdioCollector { id: statusStdout; waitForEnd: true }
    stderr: StdioCollector { id: statusStderr; waitForEnd: true }
    onExited: function(exitCode) {
      if (exitCode !== 0) {
        root.pollFailed(Model.elide(statusStderr.text || "cliamp is not running"))
        return
      }
      var parsed = Model.parseStatus(statusStdout.text)
      if (parsed.ok) root.applyStatus(parsed)
      else root.pollFailed(Model.elide(parsed.error))
    }
  }

  Process {
    id: actionProcess
    running: false
    command: []
    stdout: StdioCollector { id: actionStdout; waitForEnd: true }
    stderr: StdioCollector { id: actionStderr; waitForEnd: true }
    onExited: function(exitCode) {
      if (exitCode !== 0) {
        root._desired = -1
        root.lastError = Model.elide(actionStderr.text || actionStdout.text || "cliamp command failed")
      }
      delayedRefresh.restart()
    }
  }

  // Scriptable surface, e.g. `omarchy-shell cliamp playPause` from a Hyprland
  // keybinding. Actions triggered here show OSD feedback since there is no
  // popup on screen to confirm them.
  IpcHandler {
    target: "cliamp"

    function status(): string {
      return root.statusJson()
    }

    function playPause(): string {
      return root.runAction("playPause", true) ? "ok" : "unhandled"
    }

    function play(): string {
      return root.runAction("play", true) ? "ok" : "unhandled"
    }

    function pause(): string {
      return root.runAction("pause", true) ? "ok" : "unhandled"
    }

    function next(): string {
      return root.runAction("next", true) ? "ok" : "unhandled"
    }

    function previous(): string {
      return root.runAction("previous", true) ? "ok" : "unhandled"
    }

    function stop(): string {
      return root.runAction("stop", true) ? "ok" : "unhandled"
    }

    function source(kind: string): string {
      return root.selectSource(kind) ? "ok" : "unhandled"
    }

    function party(): string {
      return root.toggleParty() ? "on" : "off"
    }

    function partyOn(): string {
      root.setParty(true)
      return "on"
    }

    function partyOff(): string {
      root.setParty(false)
      return "off"
    }

    function partyStyle(kind: string): string {
      return root.setStyle(kind)
    }

    function partyStyleToggle(): string {
      return root.toggleStyle()
    }

    function refresh(): string {
      root.refresh()
      return "ok"
    }

    function ping(): string {
      return "ok"
    }
  }
}
