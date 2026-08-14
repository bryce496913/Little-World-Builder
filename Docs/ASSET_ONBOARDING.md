# Local asset onboarding

`AssetManifest.json` is authoritative. Adding a USDZ without exactly one manifest entry does **not** make it a supported app asset.

Codex passes must be text-only: Codex may update the manifest, Swift source, documentation, tests, and scripts, but must not add, modify, move, rename, delete, regenerate, re-track, normalize, or stage binary assets. The project owner must manage all binary files manually with local Git.

1. Install Git LFS (`git lfs install`).
2. After cloning, fetch binary objects with `git lfs pull`.
3. As the project owner, manually add the source USDZ under `3MF/USDZ/` when applicable and the optimized copy under `App Ready USDZ/` using local Git.
4. As the project owner, manually add a real, decodable PNG thumbnail under the root `Thumbnails/` folder using local Git. Active thumbnails are normal PNG files, not Codex-generated or Codex-modified files. Their basenames must exactly match their USDZ filenames (for example, `tree.usdz` uses `tree.png`). Manually remove superseded thumbnails rather than retaining aliases.
5. Add exactly one `Little World Builder/AssetManifest.json` entry with a stable ID and exact filenames.
6. Choose an explicit category and placement role.
7. Set a finite, positive default scale (normally `1.0`). The app first normalizes the asset's largest visual dimension to `0.18 m` per grid-footprint cell, then applies `defaultScale` once as a final display-size multiplier. For example, `0.5` renders at half the normalized size; it is not an authoring-unit correction.
8. Set positive integer grid-footprint width and depth.
9. Choose `ground`, `water`, `floating`, or `free` snap behavior. Ground and water currently share the build-root plane; floating preserves raycast height and free bypasses grid snapping.
10. After manually adding or moving binary files, run `python3 Scripts/validate_assets.py`.
11. Build the app and manually place the asset using free placement.
12. Save the world, restore it at another surface, and confirm the layout round trip.

`App Ready USDZ/` is the live app asset folder. It may contain only active, manifest-listed `.usdz` files at its root; subdirectories and source or archive content are forbidden because the entire folder is copied into the app bundle. In particular, `App Ready USDZ/Old` is not allowed. The project owner must manually move archived USDZ assets outside the live folder, for example to `3MF/USDZ/Old/` or `Archive/USDZ/`.

Only active, manifest-listed thumbnails belong in root `Thumbnails/`. Binary additions, moves, and deletions must always be performed manually by the project owner, followed by `python3 Scripts/validate_assets.py`.

## Saved-world compatibility

Schema V2 stores stable placed-instance and catalog IDs, exact filenames, and position/rotation/scale relative to the generic build root. Pre-V2 files lack reliable anchor transforms, so the app logs them as unsupported, leaves them on disk, and does not fabricate a migration.
