# Grid placement

Grid placement is an optional layer after `NativePlacementManager`'s native surface raycast. The
raycast remains responsible only for finding a world-space surface transform. `ARViewContainer`
converts that transform to the one active `build-root` coordinate space and passes the local
transform and authoritative manifest metadata to `GridSnapResolver`.

The root-local X/Z plane is the grid plane and local Y is vertical. Odd footprint dimensions use
whole-cell centers; even dimensions use a half-cell phase. The 90-degree yaw is resolved before
footprint parity, so odd quarter turns exchange footprint width and depth. Ground and water assets
use local Y zero, floating assets preserve local Y, and `free` assets bypass the resolver even when
the overlay is enabled. Free Build always uses the unmodified local raycast transform.

`SavedGridConfiguration` is optional within schema 2. Existing schema-2 worlds therefore decode as
Free Build without moving their saved assets. Asset transforms remain authoritative root-relative
transforms; overlays, preview entities, and grid coordinates are never persisted. Restoring a world
does not re-snap its assets.

The existing RealityKit translation, rotation, and scale gestures are retained. RealityKit's
installed gesture API used by this project does not provide a reliable gesture-completion callback,
so already placed objects are not post-snapped in this pass. Scaling is intentionally never snapped.
A grid-size selector is also deferred; validated configuration is isolated and currently uses the
10 cm product default.
