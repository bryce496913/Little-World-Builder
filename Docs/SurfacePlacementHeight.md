# Ground placement on multilevel islands

## Scope and platform decision

This pass targets iOS 18.0 as explicitly requested. The project, app, and unit-test Debug/Release deployment settings are 18.0; the UI-test target inherits that project setting. Eligible land/base supports use `ShapeResource.generateStaticMesh(from:)`, available on iOS 18.0. The earlier custom ray/triangle tree is removed from this local patch. No application team, bundle identifier, schema, asset files, or grid dimensions change.

This change is scoped to native support-surface querying and captured bottom alignment. Height history, Undo/Reset, support relationships, and persistence redesign are excluded.

## Root cause and evidence

The baseline calls `generateCollisionShapes(recursive:)`, then treats `CollisionCastHit.position` as the native placement target. A convex approximation can bridge a concave beach or valley. Static inspection finds no downstream replacement with the island's bounds: local conversion and the existing Grid resolver retain the incoming Y. Therefore a wrong incoming collision hit cannot be repaired with a supporting-bounds adjustment.

Independent synthetic geometry demonstrates the problem with one connected multilevel mesh: its convex envelope returns Y=0.50 over a lower beach at Y=0.14, a middle level at Y=0.30, and an upper level at Y=0.50. Exact triangle intersections give each local height. This is mathematical reproduction, not an executed RealityKit or iPhone measurement. The native-collision regression test compares the old generated shape with iOS 18 static meshes on this fixture; it remains unexecuted here.

Actual before/after iPhone hit values are unavailable. DEBUG diagnostics must establish those values on a real island before the device fix is declared verified.

## Native collision correction

The existing convex geometry remains available for selection. For eligible placement-support assets only, preparation starts one asynchronous native static-mesh conversion for each visible model node at placement/restore configuration time. Generated triangle shapes are retained in the nodes' `CollisionComponent`s. No collision generation, mesh conversion, or custom triangle traversal runs in the frame update.

A transient readiness component prevents an island from being targeted before all its native shapes are ready. A failed conversion, invalid hit/normal, incomplete preparation, or missing/deleted/unregistered support retains safe rejection or the existing AR-plane fallback. Saved-world root placement remains plane-only. A generation identity and original-parent check reject superseded or detached preparation results.

No persistent support relationship is created. All placed objects remain direct children of `build-root`; moving the island later does not move them.

## Captured height and bottom alignment

The pipeline is:

```text
native static-mesh CollisionCastHit.position/normal
→ category/role and upward-normal eligibility
→ world-to-build-root-local transform
→ Free or existing Grid X/Z/yaw resolution, retaining captured local Y
→ selected asset's cached prepared bottom alignment
→ pending vertical offset
→ captured guide transform and captured registered-root transform
→ confirmation copies the captured registered-root transform
```

Model preparation evaluates catalog rotation, existing size normalization, and manifest `defaultScale` once per model load. It bottom-centers an isolated clone, validates the bounds, and caches only geometry metadata and the normalized root transform. Child/source geometry is never moved in place.

Let `P` be the cached normalized model-root transform, `R` the resolved placement rotation/scale without translation, and `b` the minimum Y of the selected asset's prepared bounds transformed by `R`. Then:

```text
alignedRoot = resolvedContact * P
alignedRoot.translation.y -= b
finalRoot.translation.y = alignedRoot.translation.y + pendingHeightOffset
final visible bottom Y = captured local surface Y + pendingHeightOffset
```

This accounts for centered, bottom-aligned, and below-root geometry; catalog rotation; normalization; manifest scale; pending yaw; and positive finite user scale. Upright object placement has yaw only. Supporting-model bounds are diagnostic values, never alignment inputs. The registered root Y need not equal the visible bottom because it includes the authored-pivot correction.

The guide and final root transforms, model-preparation identity, support ID, captured surface height, and height offset are captured together. Confirmation performs no raycast, scale normalization, or new Y calculation. It rejects another asset, stale solution, changed preparation, missing selection, or deleted/unready supporting root. Invalid model bounds are rejected instead of placing an invisible asset.

Free keeps the raw hit X/Z and orientation behavior. Grid snaps X/Z and yaw with the existing resolver while retaining captured surface Y. Free-behavior assets still bypass snapping. Floating and water behavior and manifest metadata are unchanged. There is no downward re-query from snapped X/Z: visible height differences when snapping across a slope are a separate follow-up.

## Validation and device procedure

Focused tests cover native lower/middle/upper surface hits, edited support/child transforms, the exact 0.50 support / 0.14 hit case, affected manifest entries, pivot variations, Free/Grid, signed/zero offsets, user scale, captured transforms, ordinary schema-2 round-trip compatibility, invalid geometry, missing selection, non-finite transforms, and stale/deleted/unready supports. Existing grid, world-to-local, fallback/normal, first-placement, and persistence assertions are retained.

Run asset validation, focused tests, the full unit suite, `xcodebuild -list`, Debug and Release simulator builds, and generic iOS compilation with signing disabled on a Mac with Xcode 16 or newer. This Linux environment has no Xcode, Swift compiler, simulator, iOS SDK, or iPhone, so those runtime/build checks cannot be reported as passing.

On an iOS 18+ iPhone:

1. Start a fresh world on a real floor. Confirm the root remains on the floor when pending height changes.
2. On one multilevel island, place Tree low, Rock in the middle, Flowers high, Crabs on a low beach/ledge, and Grass at two levels. Repeat in Free and Grid.
3. Confirm each visible bottom matches the guide and its captured local surface, not the support's maximum Y. Test positive, zero, and negative offsets, yaw, and scale.
4. Move the guide from island to floor; confirm no island height/ID remains. Test later floor placement.
5. Confirm all objects remain direct `build-root` children; moving the island does not move them.
6. Save, clear, restore once at another physical location, and compare the placed local transforms and continued Edit behavior. No persistence redesign is included.

Each confirmation prints one DEBUG-only `PLACEMENT_HEIGHT` line: support asset ID/source; raw collision world position/Y/normal; selected surface world position/Y/normal; collision and hit local positions; support bounds min/max local Y; resolved contact Y; captured pending offset; prepared asset minimum Y; final registered-root Y; and visible bottom Y. Compare the last value to `hitLocal.y + offset` within floating-point tolerance. Logging is not per frame and is absent from Release.
