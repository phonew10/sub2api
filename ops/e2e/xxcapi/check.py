import sys,json,base64,struct,os
from PIL import Image
name=sys.argv[1]; d=json.load(open(name+'.json'))
if d.get('error') or 'data' not in d: print(name,'ERROR:',json.dumps(d)[:500]); sys.exit(1)
im=d['data'][0]
if im.get('b64_json'): b=base64.b64decode(im['b64_json']); src='b64'
elif im.get('url'):
    import urllib.request; b=urllib.request.urlopen(im['url'],timeout=120).read(); src='url'
else: print(name,'no image in',list(im)); sys.exit(1)
kind='PNG' if b[:8]==b'\x89PNG\r\n\x1a\n' else 'JPEG' if b[:2]==b'\xff\xd8' else 'WEBP' if b[:4]==b'RIFF' else 'unknown'
ext={'PNG':'png','JPEG':'jpg','WEBP':'webp'}.get(kind,'bin'); out=f'{name}.{ext}'; open(out,'wb').write(b)
img=Image.open(out)
print(f'{name}: {kind} {img.size} {len(b)/1024:.0f} KB via {src} | resp size={d.get("size")} quality={d.get("quality")} output_format={d.get("output_format")} usage={d.get("usage")}')
