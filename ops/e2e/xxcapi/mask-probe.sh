#!/usr/bin/env bash
# Decisive test of whether an /v1/images/edits relay honors the `mask` field.
# Design: the mask hole is on a plain wall area the prompt never mentions; the prompt only says
# "fill the editable region red". If the mask is honored, the hole turns red. If it is ignored,
# the model has no idea where "the editable region" is and paints red somewhere else (or nowhere).
# A control call with the same prompt and NO mask must behave differently from the masked call.
#
#   ./ops/e2e/xxcapi/mask-probe.sh [model] [size]        (defaults: gpt-image-2-medium 1024x1024)
#   PROBE_OUT=dir            per-run output directory (default ops/e2e/xxcapi/out)
#   PROBE_EXTRA="k=v k=v"    extra multipart fields, e.g. for the 2.5 aliases:
#                            PROBE_EXTRA="aspect_ratio=1:1 quality=medium output_format=jpeg" ... gpt-image-2.5-flare 1K
# Needs XXCAPI_KEY / XXCAPI_BASE_URL in ops/.env (or exported). Cost: 2 x one 1K edit.
# Verdict rule: honored  = red inside hole > 50% AND red outside hole < 2%
#               ignored  = red inside hole < 5% (masked call looks like the control)
set -euo pipefail
H="$(cd "$(dirname "$0")" && pwd)"; ENV_FILE="$H/../../.env"
[[ -f "$ENV_FILE" ]] && set -a && . "$ENV_FILE" && set +a
: "${XXCAPI_KEY:?put XXCAPI_KEY in ops/.env}"; BASE=${XXCAPI_BASE_URL:-https://xxcapi.top}
MODEL=${1:-gpt-image-2-medium}; SIZE=${2:-1024x1024}
OUT="${PROBE_OUT:-$H/out}"; mkdir -p "$OUT"; cd "$OUT"
PROMPT="Fill the editable region with solid pure red color (#FF0000), flat, no texture. Change nothing else in the image."
H="$H" python3 - <<'PY'
import os
from PIL import Image, ImageDraw
H0=os.environ['H']; im=Image.open(f'{H0}/samples/original.jpg'); W,H=im.size
m=Image.new('RGBA',(W,H),(0,0,0,255)); ImageDraw.Draw(m).rectangle((1000,240,1360,420),fill=(0,0,0,0)); m.save(f'{H0}/mask_probe.png')
PY
EXTRA_FORM=(); for kv in ${PROBE_EXTRA:-}; do EXTRA_FORM+=(-F "$kv"); done
for variant in mask nomask; do
  extra=("${EXTRA_FORM[@]}"); [[ $variant == mask ]] && extra+=(-F "mask=@$H/mask_probe.png")
  curl -s -m 900 -o "probe_$variant.json" -w "probe_$variant http=%{http_code} time=%{time_total}s\n" "$BASE/v1/images/edits" \
    -H "Authorization: Bearer $XXCAPI_KEY" -F "model=$MODEL" -F "image=@$H/samples/original.jpg" "${extra[@]}" -F "prompt=$PROMPT" -F "size=$SIZE"
  python3 "$H/check.py" "probe_$variant" || continue
  python3 "$H/mask_probe.py" "probe_$variant.png" "$H/mask_probe.png" "$H/samples/original.jpg"
done
echo "outputs in $OUT (probe_mask.png / probe_nomask.png). Apply the verdict rule in the header."
