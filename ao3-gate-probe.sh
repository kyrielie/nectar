#!/bin/sh
# W3 probe: does AO3 honor ?view_adult=true on the exact query Nectar sends?
#
# Usage:
#   ./ao3-gate-probe.sh [WORK_ID ...]        default: 87955346
#   ./ao3-gate-probe.sh --analyze FILE.html  analyze a saved page, no network
#
# Requests are cookieless (no cookie jar), matching Nectar's transport, and
# use Nectar's Info.plist User-Agent. Results are saved to ./probe-out/.
# Pick work IDs that are public (no lock icon) and rated Mature or Explicit.

UA='Nectar (https://github.com/kyrielie/nectar)'
OUT=probe-out

analyze() {
  f=$1
  gate=$(grep -c 'Adult Content Warning' "$f")
  skin=$(grep -c 'id="workskin"' "$f")
  # tr -s squeezes whitespace; BSD grep (macOS) caps {m,n} at 255.
  rating=$(tr '\n' ' ' < "$f" | tr -s ' ' | grep -Eo 'class="rating tags".{0,200}' \
    | grep -Eo 'Mature|Explicit|General Audiences|Teen And Up Audiences|Not Rated' | head -1)
  link=$(grep -Eo 'href="/works/[0-9]+(/chapters/[0-9]+)?\?view_adult=true"' "$f" | head -1)
  echo "    gate_marker=$gate workskin=$skin rating=${rating:-n/a} continue_link=${link:-none}"
  if [ "$gate" -ge 1 ]; then
    echo "    VERDICT: GATED"
  elif [ "$skin" -ge 1 ]; then
    echo "    VERDICT: WORK CONTENT RETURNED (gate not shown)"
  else
    echo "    VERDICT: NEITHER (login wall, 404, challenge or unknown page; open the file)"
  fi
}

if [ "$1" = "--analyze" ]; then
  analyze "$2"
  exit 0
fi

mkdir -p "$OUT"
[ $# -eq 0 ] && set -- 87955346

for id in "$@"; do
  for variant in nectar control; do
    if [ "$variant" = nectar ]; then
      q='?view_full_work=true&view_adult=true'
    else
      q=''   # control: no parameters, should gate if the work is Mature/Explicit
    fi
    file="$OUT/$id-$variant.html"
    echo "== work $id [$variant] https://archiveofourown.org/works/$id$q"
    curl -sL -A "$UA" -o "$file" -w '    status=%{http_code} final_url=%{url_effective}\n' \
      "https://archiveofourown.org/works/$id$q"
    analyze "$file"
    sleep 5   # be polite; AO3 rate limits
  done
done

echo
echo "Paste everything above back to me. Keep $OUT/ if you want the captures as fixtures."
