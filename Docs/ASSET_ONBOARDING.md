# Local asset onboarding

`AssetManifest.json` is authoritative. Adding a USDZ without exactly one manifest entry does **not** make it a supported app asset.

1. Install Git LFS (`git lfs install`).
2. After cloning, fetch binary objects with `git lfs pull`.
3. Add the source USDZ under `3MF/USDZ/` when applicable and the optimized copy under `App Ready USDZ/`.
4. Add a real, decodable thumbnail under `Thumbnails/`.
5. Add exactly one `Little World Builder/AssetManifest.json` entry with a stable ID and exact filenames.
6. Choose an explicit category and placement role.
7. Set a finite, positive default scale (normally `1.0`).
8. Set positive integer grid-footprint width and depth (metadata only; no grid behavior exists yet).
9. Choose `ground`, `water`, `floating`, or `free` snap behavior (metadata only).
10. Run `python3 Scripts/validate_assets.py`.
11. Build the app and manually place the asset using free placement.
12. Save the world, restore it at another surface, and confirm the layout round trip.

## Saved-world compatibility

Schema V2 stores stable placed-instance and catalog IDs, exact filenames, and position/rotation/scale relative to the generic build root. Pre-V2 files lack reliable anchor transforms, so the app logs them as unsupported, leaves them on disk, and does not fabricate a migration.
