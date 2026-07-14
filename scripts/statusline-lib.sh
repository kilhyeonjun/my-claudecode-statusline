# Shared helpers for statusline custom-command widgets. Source, don't execute.
#
#   fmt_dur SECONDS       -> "45s" / "10m" / "3h20m" / "2d3h"  (rounded to minute)
#   burn_project USED_PCT ELAPSED_SEC WINDOW_SEC
#                         -> "🔥 4.0x → 100% in 15m" / "⚠ 1.1x → ends ~94%" /
#                            "✓ 0.8x → ends ~65%" / "· 0.2x → ends ~25%" / ""

fmt_dur() {
  awk -v s="$1" 'BEGIN {
    if (s < 60) { printf "%ds", int(s); exit }
    r = int(s/60 + 0.5) * 60
    if (r < 3600) {
      printf "%dm", int(r/60)
    } else if (r < 86400) {
      h = int(r/3600); m = int((r % 3600) / 60)
      if (m == 0) printf "%dh", h
      else printf "%dh%dm", h, m
    } else {
      d = int(r/86400); h = int((r % 86400) / 3600)
      if (h == 0) printf "%dd", d
      else printf "%dd%dh", d, h
    }
  }'
}

burn_project() {
  local used="$1" elapsed="$2" window="$3"
  awk -v used="$used" -v elapsed="$elapsed" -v window="$window" '
  function fmt(s,   h, m, d) {
    if (s < 60) return sprintf("%ds", s)
    if (s < 3600) return sprintf("%dm", int(s/60))
    if (s < 86400) {
      h = int(s/3600); m = int((s - h*3600)/60)
      if (m == 0) return sprintf("%dh", h)
      return sprintf("%dh%dm", h, m)
    }
    d = int(s/86400); h = int((s - d*86400)/3600)
    if (h == 0) return sprintf("%dd", d)
    return sprintf("%dd%dh", d, h)
  }
  BEGIN {
    if (used <= 0 || elapsed <= 0) exit
    rate = used / elapsed
    if (rate <= 0) exit
    projected = rate * window
    burn = projected / 100
    if (projected >= 100) {
      remain_pct = 100 - used
      if (remain_pct <= 0) {
        exit
      }
      eta = remain_pct / rate
      printf "🔥 %.1fx → 100%% in %s", burn, fmt(eta)
    } else if (projected >= 90) {
      printf "⚠ %.1fx → ends ~%d%%", burn, int(projected + 0.5)
    } else if (projected >= 60) {
      printf "✓ %.1fx → ends ~%d%%", burn, int(projected + 0.5)
    } else {
      printf "· %.1fx → ends ~%d%%", burn, int(projected + 0.5)
    }
  }
  '
}
