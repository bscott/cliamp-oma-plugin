// Pure helpers for the CLIAMP plugin: parsing `cliamp status --json` output
// and formatting values for display. Kept free of QML dependencies so the
// logic stays testable and the QML files stay declarative.

// Parses the raw stdout of `cliamp status --json`. Returns an object with
// `ok: false` when the output is unusable, otherwise `ok: true` plus the
// normalized playback fields. cliamp reports `total` as the playlist track
// count and `index` as the zero-based position within it; `duration` is the
// track length in seconds and is absent for live streams.
function parseStatus(raw) {
  var text = String(raw || "").trim()
  if (text === "") return { ok: false, error: "empty status output" }

  var data
  try {
    data = JSON.parse(text)
  } catch (e) {
    return { ok: false, error: "unparseable status output: " + e }
  }

  if (!data || data.ok !== true) {
    return { ok: false, error: data && data.error ? String(data.error) : "cliamp reported an error" }
  }

  var track = data.track || {}
  return {
    ok: true,
    playbackState: String(data.state || "stopped"),
    title: String(track.title || ""),
    artist: String(track.artist || ""),
    album: String(track.album || ""),
    path: String(track.path || ""),
    isStream: track.stream === true,
    position: isFinite(data.position) ? Number(data.position) : 0,
    duration: isFinite(data.duration) ? Number(data.duration) : 0,
    trackIndex: isFinite(data.index) ? Number(data.index) : -1,
    trackTotal: isFinite(data.total) ? Number(data.total) : 0,
    playlist: String(data.playlist || ""),
    volumeDb: isFinite(data.volume) ? Number(data.volume) : 0,
    shuffle: data.shuffle === true,
    repeat: String(data.repeat || "")
  }
}

// Extracts the xesam:url from an MPRIS player's metadata, the only reliable
// way to tell a YouTube tab apart from any other media-playing browser tab.
function mprisUrl(player) {
  try {
    var md = player ? player.metadata : null
    return md ? String(md["xesam:url"] || "") : ""
  } catch (e) {
    return ""
  }
}

function isSpotifyPlayer(player) {
  if (!player) return false
  var id = (String(player.desktopEntry || "") + " " + String(player.identity || "") + " "
    + String(player.dbusName || "")).toLowerCase()
  return id.indexOf("spotify") !== -1
}

// YouTube (including YouTube Music) usually plays inside a browser whose
// MPRIS identity only names the browser, so match on the track URL first and
// fall back to the identity for dedicated apps and PWAs.
function isYoutubePlayer(player) {
  if (!player) return false
  if (/(\/\/|\.)(www\.|music\.|m\.)?(youtube\.com|youtu\.be)\//i.test(mprisUrl(player) + "/")) return true
  var id = (String(player.identity || "") + " " + String(player.desktopEntry || "")).toLowerCase()
  return id.indexOf("youtube") !== -1
}

function sourceLabel(kind) {
  if (kind === "spotify") return "Spotify"
  if (kind === "youtube") return "YouTube"
  return "CLIAMP"
}

function sourceIcon(kind, isStream) {
  if (kind === "spotify") return "󰓇"
  if (kind === "youtube") return "󰗃"
  return isStream ? "󰐻" : "󰝚"
}

// Formats a duration in seconds as m:ss, or h:mm:ss past the hour mark.
function fmtTime(seconds) {
  var s = Math.max(0, Math.floor(Number(seconds) || 0))
  var h = Math.floor(s / 3600)
  var m = Math.floor((s % 3600) / 60)
  var sec = s % 60
  var pad = function(n) { return n < 10 ? "0" + n : String(n) }
  return h > 0 ? h + ":" + pad(m) + ":" + pad(sec) : m + ":" + pad(sec)
}

// One-line summary used for tooltips and OSD messages.
function summary(title, artist) {
  if (!title) return "Nothing playing"
  return artist ? title + " — " + artist : title
}

// Collapses whitespace and bounds error text so a multi-line CLI failure
// never blows up a bar tooltip or popup row.
function elide(text, max) {
  var value = String(text || "").replace(/\s+/g, " ").trim()
  var limit = max || 140
  return value.length > limit ? value.substring(0, limit - 3) + "…" : value
}
