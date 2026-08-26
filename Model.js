.pragma library

var DEFAULT_HEATMAP_COLORS = ["#45475a", "#89b4fa", "#74c7ec", "#89dceb", "#cba6f7"]

function heatmapColors(accent) {
  var accentColor = String(accent || "#89b4fa")
  return [
    DEFAULT_HEATMAP_COLORS[0],
    accentColor,
    DEFAULT_HEATMAP_COLORS[2],
    DEFAULT_HEATMAP_COLORS[3],
    DEFAULT_HEATMAP_COLORS[4]
  ]
}

function contributionLevel(count) {
  var n = parseInt(count, 10) || 0
  if (n >= 30) return 4
  if (n >= 18) return 3
  if (n >= 10) return 2
  if (n >= 1) return 1
  return 0
}

function contributionColor(count, colors) {
  var palette = colors && colors.length ? colors : DEFAULT_HEATMAP_COLORS
  return palette[contributionLevel(count)] || palette[1]
}

function trendLevel(count, max) {
  var n = parseInt(count, 10) || 0
  var cap = parseInt(max, 10) || 40
  if (n <= 0) return 0
  return Math.max(1, Math.min(7, Math.ceil(n / cap * 7)))
}

function parsePayload(raw) {
  var text = String(raw || "").trim()
  if (!text) return { ok: false, error: "No data" }

  try {
    var json = JSON.parse(text)
  } catch (e) {
    return { ok: false, error: "Invalid response" }
  }

  if (json.class === "error") {
    return {
      ok: false,
      error: String(json.tooltip || json.text || "GitHub error").replace(/<[^>]+>/g, "").trim()
    }
  }

  var cells = Array.isArray(json.cells) ? json.cells : []
  var total30 = parseInt(json.total30, 10) || 0
  var streak = parseInt(json.streak, 10) || 0
  var best = parseInt(json.best, 10) || 0

  if (total30 === 0 && cells.length > 0) {
    var sum = 0
    var bestDay = 0
    for (var i = 0; i < cells.length; i++) {
      var c = parseInt(cells[i].count, 10) || 0
      sum += c
      if (c > bestDay) bestDay = c
    }
    total30 = sum
    if (best === 0) best = bestDay
  }

  if (streak === 0 && cells.length > 0) {
    for (var s = cells.length - 1; s >= 0; s--) {
      if ((parseInt(cells[s].count, 10) || 0) > 0) streak++
      else break
    }
  }

  return {
    ok: true,
    today: parseInt(json.today, 10) || 0,
    total30: total30,
    streak: streak,
    best: best,
    username: String(json.username || ""),
    profileUrl: String(json.profileUrl || (json.username ? ("https://github.com/" + json.username) : "https://github.com/")),
    cells: cells
  }
}

function sparkBars(cells, colors, trendMax) {
  var out = []
  var max = parseInt(trendMax, 10) || 40
  for (var i = 0; i < cells.length; i++) {
    var cell = cells[i] || {}
    var count = parseInt(cell.count, 10) || 0
    out.push({
      value: count,
      level: trendLevel(count, max),
      color: cell.color || contributionColor(count, colors)
    })
  }
  return out
}
