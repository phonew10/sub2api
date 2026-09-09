#!/usr/bin/env bash
# Re-run the xxcapi.top gpt-image-2 relay test. Needs XXCAPI_KEY / XXCAPI_BASE_URL in ops/.env.
#   ./ops/e2e/xxcapi/run.sh gen   [model] [size]     # generation from reverse_prompt.txt
#   ./ops/e2e/xxcapi/run.sh edit  [model] [size]     # background edit of original.jpg
#   ./ops/e2e/xxcapi/run.sh mask  [model] [size]     # masked edit (mask_wall.png)
# Every call asks for output_format=jpeg + output_compression=80 to re-check whether the relay honors them.
set -euo pipefail
H="$(cd "$(dirname "$0")" && pwd)"; ENV_FILE="$H/../../.env"
[[ -f "$ENV_FILE" ]] && set -a && . "$ENV_FILE" && set +a
: "${XXCAPI_KEY:?put XXCAPI_KEY in ops/.env}"; BASE=${XXCAPI_BASE_URL:-https://xxcapi.top}
cmd=${1:-gen}; MODEL=${2:-gpt-image-2-medium}; SIZE=${3:-2048x2048}
OUT="$H/out"; mkdir -p "$OUT"; cd "$OUT"; cp -n "$H/samples/original.jpg" original.jpg 2>/dev/null || true
EDIT_PROMPT="Keep the navy carafe, the exploded six-layer diagram, all text banners and labels exactly as they are. Replace the dark olive-green textured wall with a clean warm light-beige studio backdrop, and change the tabletop to a light oak wood surface. Keep composition, lighting and typography unchanged."
MASK_PROMPT="In the editable area only, add a small potted green plant on a wooden shelf mounted on the wall. Do not change anything outside the editable area: keep the carafe, the layer diagram, all text and the background exactly as they are."
case "$cmd" in
  gen)
    python3 -c "import json,sys;print(json.dumps({'model':'$MODEL','prompt':open('$H/reverse_prompt.txt').read().strip(),'size':'$SIZE','n':1,'output_format':'jpeg','output_compression':80}))" > gen_req.json
    curl -s -m 900 -o gen.json -w "gen http=%{http_code} time=%{time_total}s\n" "$BASE/v1/images/generations" -H "Authorization: Bearer $XXCAPI_KEY" -H "Content-Type: application/json" -d @gen_req.json
    python3 "$H/check.py" gen ;;
  edit)
    curl -s -m 900 -o edit.json -w "edit http=%{http_code} time=%{time_total}s\n" "$BASE/v1/images/edits" -H "Authorization: Bearer $XXCAPI_KEY" -F "model=$MODEL" -F "image=@original.jpg" -F "prompt=$EDIT_PROMPT" -F "size=$SIZE" -F "output_format=jpeg" -F "output_compression=80"
    python3 "$H/check.py" edit ;;
  mask)
    curl -s -m 900 -o mask.json -w "mask http=%{http_code} time=%{time_total}s\n" "$BASE/v1/images/edits" -H "Authorization: Bearer $XXCAPI_KEY" -F "model=$MODEL" -F "image=@original.jpg" -F "mask=@$H/mask_wall.png" -F "prompt=$MASK_PROMPT" -F "size=$SIZE" -F "output_format=jpeg" -F "output_compression=80"
    python3 "$H/check.py" mask ;;
  *) sed -n '2,6p' "$0"; exit 1 ;;
esac
echo "outputs in $OUT"
