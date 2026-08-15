import QtQuick
import Quickshell
import Quickshell.Io
import "Model.js" as Model

// Headless singleton that owns all communication with cliamp. It polls
// `cliamp status --json` on a timer, exposes the parsed playback state as
// properties for the bar widget, and runs control commands. Keeping the
// process handling here means every bar surface (one per monitor) reads the
// same state instead of each spawning its own pollers.
Item {
  id: root

  property var shell: null

  // Inline widget settings, pushed in by the bar widget since the shell only
  // injects settings into widget slots, not services.
  property var settings: ({})

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

  readonly property bool hasTrack: available && title !== ""
  readonly property int refreshIntervalSec: intSetting("refreshIntervalSec", 2, 1, 60)

  function intSetting(name, fallback, min, max) {
    var value = settings ? settings[name] : undefined
    var n = parseInt(String(value === undefined || value === null ? fallback : value), 10)
    if (!isFinite(n)) n = fallback
    return Math.min(max, Math.max(min, n))
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

  // Runs a playback control. Actions map directly onto cliamp CLI verbs;
  // "playPause" becomes cliamp's `toggle`. Returns false when the action is
  // unknown or cliamp is unreachable.
  function runAction(action, showFeedback) {
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

    if (action === "playPause") _desired = playing ? 0 : 1
    else if (action === "play") _desired = 1
    else if (action === "pause" || action === "stop") _desired = 0

    if (actionProcess.running) actionProcess.running = false
    actionProcess.command = ["cliamp", verb]
    actionProcess.running = true

    if (showFeedback === true) {
      var icons = {
        playPause: playing ? "media-play" : "media-pause",
        play: "media-play",
        pause: "media-pause",
        next: "media-next",
        previous: "media-previous",
        stop: "media-pause"
      }
      showOsd(icons[action] || "media")
    }
    return true
  }

  function showOsd(iconName) {
    if (!shell) return
    shell.summon("omarchy.osd", JSON.stringify({
      icon: iconName,
      message: Model.summary(title, artist)
    }))
  }

  function statusJson() {
    return JSON.stringify({
      available: available,
      state: playbackState,
      playing: playing,
      title: title,
      artist: artist,
      album: album,
      stream: isStream,
      position: position,
      duration: duration,
      index: trackIndex,
      total: trackTotal,
      playlist: playlist
    })
  }

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

  // Advances the position locally between polls so the popup's progress bar
  // moves smoothly. Every real poll resyncs to cliamp's reported position.
  Timer {
    interval: 1000
    repeat: true
    running: root.available && root.playing
    onTriggered: {
      var next = root.position + 1
      if (root.duration > 0 && next > root.duration) next = root.duration
      root.position = next
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

    function refresh(): string {
      root.refresh()
      return "ok"
    }

    function ping(): string {
      return "ok"
    }
  }
}
