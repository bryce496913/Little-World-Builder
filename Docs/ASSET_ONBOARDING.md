# Local asset onboarding

`AssetManifest.json` is authoritative. Adding a USDZ without exactly one manifest entry does **not** make it a supported app asset.

1. Install Git LFS (`git lfs install`).
2. After cloning, fetch binary objects with `git lfs pull`.
3. Add the source USDZ under `3MF/USDZ/` when applicable and the optimized copy under `App Ready USDZ/`.
4. Add a real, decodable PNG thumbnail under `Thumbnails/`. Its basename must exactly match the USDZ filename (for example, `tree.usdz` uses `tree.png`). Remove superseded thumbnails rather than retaining aliases.
5. Add exactly one `Little World Builder/AssetManifest.json` entry with a stable ID and exact filenames.
6. Choose an explicit category and placement role.
7. Set a finite, positive default scale (normally `1.0`). The app first normalizes the asset's largest visual dimension to `0.18 m` per grid-footprint cell, then applies `defaultScale` once as a final display-size multiplier. For example, `0.5` renders at half the normalized size; it is not an authoring-unit correction.
8. Set positive integer grid-footprint width and depth.
9. Choose `ground`, `water`, `floating`, or `free` snap behavior. Ground and water currently share the build-root plane; floating preserves raycast height and free bypasses grid snapping.
10. Run `python3 Scripts/validate_assets.py`.
11. Build the app and manually place the asset using free placement.
12. Save the world, restore it at another surface, and confirm the layout round trip.

Only manifest-listed, release-ready files belong directly in `App Ready USDZ/` and `Thumbnails/`. Move superseded or incomplete USDZ files to `3MF/USDZ/Old/` and thumbnails to `Thumbnails/Old/`; never keep an archive subdirectory inside `App Ready USDZ/`, because that entire directory is copied into the app bundle.

## Saved-world compatibility

Schema V2 stores stable placed-instance and catalog IDs, exact filenames, and position/rotation/scale relative to the generic build root. Pre-V2 files lack reliable anchor transforms, so the app logs them as unsupported, leaves them on disk, and does not fabricate a migration.
