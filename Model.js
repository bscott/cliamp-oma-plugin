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

// -------------------------------------------------------------- party mode

function _hexToRgb(hex) {
  var h = String(hex || "").replace("#", "")
  if (h.length === 3) h = h[0] + h[0] + h[1] + h[1] + h[2] + h[2]
  if (h.length < 6) return { r: 200, g: 200, b: 200 }
  return {
    r: parseInt(h.substring(0, 2), 16),
    g: parseInt(h.substring(2, 4), 16),
    b: parseInt(h.substring(4, 6), 16)
  }
}

function _rgbToHex(c) {
  var to = function(n) {
    var v = Math.round(Math.min(255, Math.max(0, n)))
    var s = v.toString(16)
    return s.length === 1 ? "0" + s : s
  }
  return "#" + to(c.r) + to(c.g) + to(c.b)
}

function _mix(a, b, t) {
  return { r: a.r + (b.r - a.r) * t, g: a.g + (b.g - a.g) * t, b: a.b + (b.b - a.b) * t }
}

function _rgbToHsv(c) {
  var r = c.r / 255, g = c.g / 255, b = c.b / 255
  var max = Math.max(r, g, b), min = Math.min(r, g, b), d = max - min
  var h = 0
  if (d !== 0) {
    if (max === r) h = ((g - b) / d) % 6
    else if (max === g) h = (b - r) / d + 2
    else h = (r - g) / d + 4
    h *= 60
    if (h < 0) h += 360
  }
  return { h: h, s: max === 0 ? 0 : d / max, v: max }
}

function _hsvToRgb(hsv) {
  var h = ((hsv.h % 360) + 360) % 360, s = hsv.s, v = hsv.v
  var c = v * s, x = c * (1 - Math.abs((h / 60) % 2 - 1)), m = v - c
  var r = 0, g = 0, b = 0
  if (h < 60) { r = c; g = x } else if (h < 120) { r = x; g = c }
  else if (h < 180) { g = c; b = x } else if (h < 240) { g = x; b = c }
  else if (h < 300) { r = x; b = c } else { r = c; b = x }
  return { r: (r + m) * 255, g: (g + m) * 255, b: (b + m) * 255 }
}

function lerpColor(hexA, hexB, t) {
  return _rgbToHex(_mix(_hexToRgb(hexA), _hexToRgb(hexB), Math.min(1, Math.max(0, t))))
}

// Samples an evenly-spaced list of hex colours at 0..1, interpolating between
// neighbours. Used to colour the spectrum bars smoothly across the bar.
function paletteAt(hexes, frac) {
  if (!hexes || hexes.length === 0) return "#ffffff"
  if (hexes.length === 1) return hexes[0]
  var f = Math.min(1, Math.max(0, frac)) * (hexes.length - 1)
  var i = Math.floor(f)
  if (i >= hexes.length - 1) return hexes[hexes.length - 1]
  return lerpColor(hexes[i], hexes[i + 1], f - i)
}

// Rotates a colour's hue by `deg` degrees. Driving all the wash stops with a
// shared, slowly oscillating rotation makes the palette shimmer through the
// neon family without leaving it.
function rotateHue(hex, deg) {
  var hsv = _rgbToHsv(_hexToRgb(hex))
  hsv.h += deg
  return _rgbToHex(_hsvToRgb(hsv))
}

function _hexFromHsv(h, s, v) {
  return _rgbToHex(_hsvToRgb({ h: h, s: s, v: v }))
}

// Builds the neon gradient stops. The character is a fixed synthwave spread —
// magenta, purple, electric blue, cyan — kept at forced-high saturation so it
// always reads neon. The whole set is then rotated toward the active Omarchy
// theme's accent hue (clamped to a modest range so it never wanders into muddy
// yellows/greens), which both matches the theme and re-derives automatically
// whenever the theme changes. A greyscale accent leaves the pure synthwave set.
function synthwaveStops(accentHex) {
  var hsv = _rgbToHsv(_hexToRgb(accentHex))
  var baseHues = [320, 280, 235, 190] // magenta, purple, blue, cyan
  var sats = [0.95, 0.90, 0.92, 0.95]
  var rot = 0
  if (hsv.s >= 0.18) {
    var delta = hsv.h - 320
    while (delta > 180) delta -= 360
    while (delta < -180) delta += 360
    rot = Math.max(-55, Math.min(55, delta))
  }
  var out = []
  for (var i = 0; i < baseHues.length; i++) {
    out.push(_hexFromHsv(baseHues[i] + rot, sats[i], 1.0))
  }
  return out
}

// Collapses a band frame from `cliamp visstream` into a single 0..1 level,
// weighting the low bands so the pulse tracks the beat rather than hi-hats.
function bandLevel(bands) {
  if (!bands || typeof bands.length !== "number" || bands.length === 0) return 0
  var weights = [1.0, 0.85, 0.7, 0.5, 0.35]
  var sum = 0, wsum = 0
  for (var i = 0; i < bands.length && i < weights.length; i++) {
    var v = Number(bands[i])
    if (!isFinite(v)) v = 0
    sum += v * weights[i]
    wsum += weights[i]
  }
  var level = wsum > 0 ? sum / wsum : 0
  return Math.min(1, Math.max(0, level))
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
