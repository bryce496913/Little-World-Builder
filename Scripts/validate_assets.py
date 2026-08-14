#!/usr/bin/env python3
"""Validate the authoritative local asset catalog. Run from any directory."""
import json, math, pathlib, struct, sys, zipfile, zlib
root=pathlib.Path(__file__).resolve().parents[1]
manifest=root/'Little World Builder'/'AssetManifest.json'; assets=root/'App Ready USDZ'; thumbs=root/'Thumbnails'
errors=[]

def validate_png(path):
 """Decode the PNG's compressed image stream without third-party dependencies."""
 data=path.read_bytes()
 if not data.startswith(b'\x89PNG\r\n\x1a\n'): raise ValueError('not a PNG file')
 offset=8; width=height=None; image_data=bytearray(); saw_end=False
 while offset < len(data):
  if offset+12 > len(data): raise ValueError('truncated PNG chunk')
  length=struct.unpack('>I',data[offset:offset+4])[0]; kind=data[offset+4:offset+8]
  end=offset+12+length
  if end > len(data): raise ValueError('truncated PNG chunk data')
  payload=data[offset+8:offset+8+length]
  if kind == b'IHDR': width,height=struct.unpack('>II',payload[:8])
  elif kind == b'IDAT': image_data.extend(payload)
  elif kind == b'IEND': saw_end=True; break
  offset=end
 if not width or not height or not image_data or not saw_end: raise ValueError('missing required PNG chunks')
 zlib.decompress(image_data)
if not manifest.is_file(): errors.append(f'missing manifest: {manifest}'); entries=[]
else:
 try: entries=json.loads(manifest.read_text())
 except Exception as e: errors.append(f'malformed manifest: {e}'); entries=[]
ids=set(); names=set()
for i,e in enumerate(entries):
 label=e.get('id') or f'entry {i}'
 for key in ('id','fileName','displayName','category','thumbnailFileName','defaultScale','rotationXDegrees','placementRole','gridFootprint','snapBehavior'):
  if key not in e: errors.append(f'{label}: missing {key}')
 if not e.get('id','').strip(): errors.append(f'{label}: empty id')
 if e.get('id') in ids: errors.append(f'duplicate manifest id: {e.get("id")}')
 ids.add(e.get('id'))
 if e.get('fileName') in names: errors.append(f'duplicate manifest filename: {e.get("fileName")}')
 names.add(e.get('fileName'))
 if pathlib.Path(e.get('fileName','')).stem != pathlib.Path(e.get('thumbnailFileName','')).stem:
  errors.append(f'{label}: thumbnail filename must match USDZ filename')
 if e.get('category') not in {'land','water','trees','plants','creatures','vehicles','structures','decor','misc'}: errors.append(f'{label}: invalid category')
 if e.get('placementRole') not in {'base','water','decor','tree','plant','creature','structure','vehicle','misc'}: errors.append(f'{label}: invalid placementRole')
 if e.get('snapBehavior') not in {'ground','water','floating','free'}: errors.append(f'{label}: invalid snapBehavior')
 scale=e.get('defaultScale');
 if not isinstance(scale,(int,float)) or isinstance(scale,bool) or not math.isfinite(scale) or scale <= 0:
  errors.append(f'{label}: defaultScale must be positive and finite')
 rotation=e.get('rotationXDegrees')
 if not isinstance(rotation,(int,float)) or isinstance(rotation,bool) or not math.isfinite(rotation):
  errors.append(f'{label}: rotationXDegrees must be explicit and finite')
 fp=e.get('gridFootprint',{})
 if not all(isinstance(fp.get(k),int) and fp[k]>0 for k in ('width','depth')): errors.append(f'{label}: footprint dimensions must be positive integers')
 asset=assets/e.get('fileName','')
 if not asset.is_file(): errors.append(f'{label}: missing USDZ {asset.name}')
 else:
  data=asset.read_bytes()[:256]
  if data.startswith(b'version https://git-lfs.github.com/spec/v1'):
   errors.append(f'{label}: {asset.name} is an unresolved Git LFS pointer. Run: git lfs install && git lfs pull')
  elif asset.stat().st_size < 1024: errors.append(f'{label}: {asset.name} is implausibly small ({asset.stat().st_size} bytes)')
  elif not zipfile.is_zipfile(asset): errors.append(f'{label}: {asset.name} is not a valid USDZ archive')
  else:
   with zipfile.ZipFile(asset) as archive:
    if not any(pathlib.Path(name).suffix.lower() in {'.usd','.usda','.usdc'} for name in archive.namelist()):
     errors.append(f'{label}: {asset.name} contains no USD scene')
 thumb=thumbs/e.get('thumbnailFileName','')
 if not thumb.is_file(): errors.append(f'{label}: missing thumbnail {thumb.name}')
 else:
  try:
   if thumb.read_bytes()[:256].startswith(b'version https://git-lfs.github.com/spec/v1'):
    raise ValueError('unresolved Git LFS pointer')
   if thumb.suffix.lower() == '.png': validate_png(thumb)
   else: raise ValueError('only PNG manifest thumbnails are supported')
  except Exception as exc: errors.append(f'{label}: invalid thumbnail {thumb.name}: {exc}')
bundled={p.name for p in assets.glob('*.usdz')}; listed={n for n in names if n}
if assets.is_dir():
 for path in sorted(assets.iterdir()):
  if path.is_dir(): errors.append(f'subdirectory not allowed in live asset folder: {path.relative_to(assets)}')
  elif path.suffix.lower() != '.usdz': errors.append(f'non-USDZ file in live asset folder: {path.relative_to(assets)}')
for name in sorted(bundled-listed): errors.append(f'unlisted bundled USDZ: {name}')
for name in sorted(listed-bundled): errors.append(f'manifest USDZ missing from bundle: {name}')
print(f'Asset manifest entries: {len(entries)}; bundled USDZ files: {len(bundled)}')
if errors:
 print('\n'.join('ERROR: '+e for e in errors)); sys.exit(1)
print('Asset validation passed.')
