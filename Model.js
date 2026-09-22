// Pure logic for the Help plugin: parsing the daemon's JSON lines and
// formatting them for display. No I/O — loads fine in Quickshell and in a
// plain node test runner (`node -e "require('./Model.js').parseHoverLine(...)"`).

// Daemon emits one JSON line per resolved hover, tier in
// ["bar", "atspi", "window", "none"]. Never throws — a malformed line
// (partial write, daemon restart mid-line) degrades to a "none" hover
// rather than taking the whole overlay down.
function parseHoverLine(line) {
  var fallback = { tier: "none", name: "", role: "", detail: "", x: 0, y: 0 };
  if (!line) return fallback;
  var parsed;
  try {
    parsed = JSON.parse(line);
  } catch (e) {
    return fallback;
  }
  if (!parsed || typeof parsed !== "object") return fallback;
  return {
    tier: typeof parsed.tier === "string" ? parsed.tier : "none",
    name: typeof parsed.name === "string" ? parsed.name : "",
    role: typeof parsed.role === "string" ? parsed.role : "",
    detail: typeof parsed.detail === "string" ? parsed.detail : "",
    x: Number(parsed.x) || 0,
    y: Number(parsed.y) || 0,
  };
}

// Short badge text shown on the card so coverage gaps are visible
// per-hover instead of silently inconsistent.
function tierBadge(tier) {
  switch (tier) {
    case "bar": return "Bar";
    case "atspi": return "AT-SPI";
    case "window": return "Window";
    default: return "";
  }
}

// True when there's anything worth drawing a card for.
function hasContent(hover) {
  return !!(hover && hover.tier !== "none" && (hover.name || hover.detail));
}

if (typeof module !== "undefined") {
  module.exports = { parseHoverLine: parseHoverLine, tierBadge: tierBadge, hasContent: hasContent }
}
