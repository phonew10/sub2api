#!/usr/bin/env bash
# E2E check of image parameters through our relay. Needs an account that can
# generate images (paid ChatGPT OAuth or OpenAI API key) in the key's group.
#   ./ops/e2e/image-params.sh [base_url] [model]
# Reads SUB2API_KEY / SUB2API_BASE_URL from ops/.env (gitignored) if not set.
set -euo pipefail
ENV_FILE="$(cd "$(dirname "$0")/.." && pwd)/.env"
[[ -f "$ENV_FILE" ]] && set -a && . "$ENV_FILE" && set +a
BASE=${1:-${SUB2API_BASE_URL:-https://sub2api.sellersheetai.com}}
MODEL=${2:-gpt-image-2}
: "${SUB2API_KEY:?set SUB2API_KEY or put it in ops/.env}"
OUT=$(mktemp -d); cd "$OUT"

python3 - <<'PY'
from PIL import Image, ImageDraw
src=Image.new('RGB',(1024,1024),(240,240,240)); d=ImageDraw.Draw(src)
d.ellipse((312,312,712,712),fill=(200,30,30)); src.save('src.png')
m=Image.new('RGBA',(1024,1024),(0,0,0,255)); ImageDraw.Draw(m).rectangle((100,100,500,500),fill=(0,0,0,0)); m.save('mask.png')
PY

check() { python3 - "$1" <<'PY'
import sys,json,base64,struct
d=json.load(open(sys.argv[1]))
if d.get('error'): print('  ERROR:',json.dumps(d['error'])[:300]); sys.exit(1)
b=base64.b64decode(d['data'][0]['b64_json'])
kind='PNG' if b[:8]==b'\x89PNG\r\n\x1a\n' else 'JPEG' if b[:2]==b'\xff\xd8' else 'WEBP' if b[:4]==b'RIFF' else 'unknown'
dims=''
if kind=='PNG': dims=struct.unpack('>II',b[16:24])
elif kind=='JPEG':
    i=2
    while i<len(b):
        if b[i]!=0xFF: i+=1; continue
        m=b[i+1]
        if m in (0xC0,0xC1,0xC2): h,w=struct.unpack('>HH',b[i+5:i+9]); dims=(w,h); break
        i+=2+struct.unpack('>H',b[i+2:i+4])[0]
print(f"  ok: {kind} {dims} {len(b)} bytes | resp output_format={d.get('output_format')} size={d.get('size')} quality={d.get('quality')}")
PY
}

echo "1) generations: jpeg + output_compression=40 + size=1024x1536"
curl -s -m 600 "$BASE/v1/images/generations" -H "Authorization: Bearer $SUB2API_KEY" -H "Content-Type: application/json" \
  -d "{\"model\":\"$MODEL\",\"prompt\":\"a green pear on a white table\",\"output_format\":\"jpeg\",\"output_compression\":40,\"size\":\"1024x1536\"}" > gen.json
check gen.json || true

echo "2) edits: mask + jpeg + output_compression=50"
curl -s -m 600 "$BASE/v1/images/edits" -H "Authorization: Bearer $SUB2API_KEY" \
  -F "model=$MODEL" -F "prompt=inside the masked area draw a small yellow star, keep the rest unchanged" \
  -F "image=@src.png" -F "mask=@mask.png" -F "output_format=jpeg" -F "output_compression=50" -F "size=1024x1024" > edit.json
check edit.json || true
echo "outputs in $OUT"
