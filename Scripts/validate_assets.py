#!/usr/bin/env python3
"""Validate the authoritative local asset catalog. Run from any directory."""
import json, pathlib, sys
root=pathlib.Path(__file__).resolve().parents[1]
manifest=root/'Little World Builder'/'AssetManifest.json'; assets=root/'App Ready USDZ'; thumbs=root/'Thumbnails'
errors=[]
if not manifest.is_file(): errors.append(f'missing manifest: {manifest}'); entries=[]
else:
 try: entries=json.loads(manifest.read_text())
 except Exception as e: errors.append(f'malformed manifest: {e}'); entries=[]
ids=set(); names=set()
for i,e in enumerate(entries):
 label=e.get('id') or f'entry {i}'
 for key in ('id','fileName','displayName','category','thumbnailFileName','defaultScale','placementRole','gridFootprint','snapBehavior'):
  if key not in e: errors.append(f'{label}: missing {key}')
 if not e.get('id','').strip(): errors.append(f'{label}: empty id')
 if e.get('id') in ids: errors.append(f'duplicate manifest id: {e.get("id")}')
 ids.add(e.get('id'))
 if e.get('fileName') in names: errors.append(f'duplicate manifest filename: {e.get("fileName")}')
 names.add(e.get('fileName'))
 if e.get('category') not in {'land','water','trees','plants','creatures','vehicles','structures','decor','misc'}: errors.append(f'{label}: invalid category')
 if e.get('placementRole') not in {'base','water','decor','tree','plant','creature','structure','vehicle','misc'}: errors.append(f'{label}: invalid placementRole')
 if e.get('snapBehavior') not in {'ground','water','floating','free'}: errors.append(f'{label}: invalid snapBehavior')
 scale=e.get('defaultScale');
 if not isinstance(scale,(int,float)) or scale <= 0: errors.append(f'{label}: defaultScale must be positive')
 fp=e.get('gridFootprint',{})
 if not all(isinstance(fp.get(k),int) and fp[k]>0 for k in ('width','depth')): errors.append(f'{label}: footprint dimensions must be positive integers')
 asset=assets/e.get('fileName','')
 if not asset.is_file(): errors.append(f'{label}: missing USDZ {asset.name}')
 else:
  data=asset.read_bytes()[:256]
  if data.startswith(b'version https://git-lfs.github.com/spec/v1'):
   errors.append(f'{label}: {asset.name} is an unresolved Git LFS pointer. Run: git lfs install && git lfs pull')
  elif asset.stat().st_size < 1024: errors.append(f'{label}: {asset.name} is implausibly small ({asset.stat().st_size} bytes)')
 thumb=thumbs/e.get('thumbnailFileName','')
 if not thumb.is_file(): errors.append(f'{label}: missing thumbnail {thumb.name}')
bundled={p.name for p in assets.glob('*.usdz')}; listed={n for n in names if n}
for name in sorted(bundled-listed): errors.append(f'unlisted bundled USDZ: {name}')
for name in sorted(listed-bundled): errors.append(f'manifest USDZ missing from bundle: {name}')
print(f'Asset manifest entries: {len(entries)}; bundled USDZ files: {len(bundled)}')
if errors:
 print('\n'.join('ERROR: '+e for e in errors)); sys.exit(1)
print('Asset validation passed.')
