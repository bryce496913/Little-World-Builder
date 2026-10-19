# Ground placement on multilevel islands

## Root cause and scope

The baseline path is `ARView.hitTest` → registered placed root → `PlacementTargetPolicy` → world-to-build-root conversion → Free/Grid resolution → pending height offset → captured guide solution → prepared model → registration. Grid resolution preserves local Y. Model preparation bottom-centers the selected asset before composing that solution. Neither stage substitutes the supporting island's bounds.

The inaccurate height enters earlier: generated collision shapes can bridge a concave beach or valley. The old code uses `CollisionCastHit.position` as the surface point. A hit on that envelope is not necessarily on the rendered island mesh, even though ancestor resolution identifies the correct island.

The fix keeps that collision query for root identification, then intersects the same screen-center ray with that root's visible triangles. Mesh instances and child transforms are baked into a cached root-local triangle tree; the current root transform is used for every query. Preparation occurs at placement/restore configuration, not every frame. Temporary nonselectable visuals are excluded. No mesh hit or an unsuitable normal follows the existing AR-plane fallback. Saved-world root placement continues to use real-world planes only.

The refined hit is captured before the existing grid and pending-height steps. Supporting bounds never supply placement height. Objects remain independent children of `build-root`; no support relationship is persisted. Model normalization, catalog scale/rotation, schema 2, and Edit controls are unchanged.

## Reproduction evidence and limits

A synthetic connected mesh has a beach at Y=0, slopes, and plateaus at Y=1. Its convex envelope returns Y=1 for both beach and plateau. Triangle intersections return Y=0 at the beach and Y=1 at the plateau. With a +0.04 m offset, the expected bottoms are 0.04 and 1.04 respectively. An independent Python/SciPy geometry reproduction confirmed this distinction; it is not a RealityKit runtime result.

The XCTest fixture recreates this mesh and compares RealityKit's generated collision hits with the production triangle refinement. Additional cases exercise five affected manifest entries, Free/Grid, signed pending offsets, authored child offsets, catalog rotation/scale, translated/rotated build roots, restoration, edited supports, eligible/steep slopes, oblique rays, temporary visuals, misses, and invalid rays.

Xcode, Swift, iOS SDKs, and a physical iPhone were unavailable in the implementation environment. XCTest compilation/execution and actual island measurements remain required. Asset validation and binary-hash checks passed; no USDZ or PNG changed.

## On-device comparison

1. Run a DEBUG build on an iPhone. Place one multilevel island and select Tree.
2. Aim at a visibly lower beach, confirm placement, and capture the single `PLACEMENT_HEIGHT` line.
3. Repeat on a higher plateau of the same island. Repeat in Free and Grid, then with positive and negative pending height offsets.
4. Repeat with Rock, Flowers, Crabs, and Grass. Check an eligible gentle slope, then move off the island to verify AR-plane fallback.
5. Save, clear, restore elsewhere, and confirm the adjusted bottoms and independent Edit behavior survive.

Each confirmation logs the support asset ID and target source; raw collision world position/Y/normal; refined surface world position/Y/normal; hit position in build-root coordinates; supporting visual-bounds minimum/maximum Y in build-root coordinates; resolved placement Y; captured pending offset; selected model's prepared minimum Y; final registered-root local Y; and final visible bottom local Y.

Compare `visibleBottomLocalY` with `hitLocal.y + offset`, within floating-point tolerance. The registered root's Y can differ because bottom-centering includes the authored model-origin correction. Compare the visible bottom rather than forcing the registered root to equal the surface height. A changed collision Y with an unchanged refined beach height is expected when the convex envelope bridges the beach.

The trace travels with the captured guide solution and prints once at confirmation. It is DEBUG-only and is not part of saved data. If the screen-center ray misses the actual visible mesh, the convex height must not be used as a replacement.

## Required Mac validation

Discover an available simulator and use its destination for the unit suite:

```sh
python3 Scripts/validate_assets.py
xcodebuild -list -project "Little World Builder.xcodeproj"
xcodebuild -project "Little World Builder.xcodeproj" -scheme "Little World Builder" \
  -destination '<available iOS Simulator destination>' \
  -only-testing:Little\ World\ BuilderTests test
xcodebuild -project "Little World Builder.xcodeproj" -scheme "Little World Builder" \
  -configuration Debug -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
xcodebuild -project "Little World Builder.xcodeproj" -scheme "Little World Builder" \
  -configuration Release -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
xcodebuild -project "Little World Builder.xcodeproj" -scheme "Little World Builder" \
  -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```
