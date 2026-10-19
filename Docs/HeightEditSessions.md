# Multi-step height Undo and Reset Height

## Scope

This standalone PR adds height Undo and Reset Height. The user waived the persistence-verification merge prerequisite and confirmed persistence works on a real iPhone. This pass does not change placement, assets, or saved-world schema 2.

## Behavior

`HeightEditSession` contains the selected instance UUID, its starting build-root-local Y, and a bounded `[Float]` undo stack. Selecting a different object or reentering Edit captures that registered root's actual current Y. Refreshing the same selection during rotation/scale retains the session.

Raise/Lower validates the entire current local transform, records the prior Y, and applies the existing +/-0.02 m step. Undo pops a Y and applies it to the current transform. Reset applies the session baseline and clears history. These operations preserve current X/Z, quaternion, scale, child transforms, and other objects. They never reload or normalize models, reapply manifest scale, or change parenting.

The history limit is **200** changes. Overflow discards the oldest entry; Undo then reaches the oldest retained height. Reset still reaches the original baseline. An adjustment after Undo appends to the remaining linear stack; there is no Redo or forward branch. A step too small to change a very large floating-point Y is rejected without adding history.

Undo is disabled without a valid prior Y. Reset is disabled when current Y exactly equals the captured baseline. Calling Reset safely at the baseline also clears any history from mixed steps. The original float is restored directly, without centimetre rounding.

Sessions end on deselection, deletion, placement entry, saved-world loading, active-world clear/replacement, and the existing AR-view recreation/reset path (`ARViewContainer.makeUIView` resets the active world). Scene updates validate the selection and clear missing/detached roots; height actions independently repeat the validation. Invalid transforms discard the session without changing the entity; selecting a valid object again starts a new session.

The published height state continues to refresh the existing readout and selection outline. Accessibility labels remain `Raise selected object`, `Lower selected object`, `Undo height adjustment`, and `Height, N centimetres`; the new Reset control uses `Reset selected object height`.

Saving continues to serialize only registered roots' final local transforms. Session baseline, history, and Edit selection are not Codable and are not included in saved worlds. Selecting a restored object captures its saved Y as the new baseline.

## Files

- `Little World Builder/VerticalAdjustment.swift`: session model and Reset availability.
- `Little World Builder/WorldManager.swift`: session lifecycle and height actions.
- `Little World Builder/ARViewContainer.swift`: validate stale sessions during scene updates.
- `Little World Builder/EditView.swift`: Reset Height control.
- `Little World BuilderTests/Little_World_BuilderTests.swift`: focused regression cases using existing target/helpers.
- `Docs/HeightEditSessions.md`: implementation and device checklist.

The earlier persistence-verification files remain a separate local pass and are not part of this feature's standalone patch.

## Validation

Added regression coverage for one/four Raises, repeated Lowers, mixed steps, empty/exhausted Undo, adjustment after Undo, bounded history, Reset after adjustments/Undo and at baseline, current-transform preservation, child-to-root resolution, independent objects, Tree/Birds/Fish switching, reselection, deletion, clear/restore/AR-reset lifecycle boundaries, stale selection, missing entities, non-finite transforms, schema-v2 save/restore, and transient-state exclusion.

Asset validation and whitespace checks pass. All 220 USDZ/PNG hashes match the pre-pass baseline. Accessibility labels and the existing outline subscription were reviewed statically.

XCTest, focused/session/persistence/full-suite execution, `xcodebuild -list`, Debug and Release simulator builds, and generic physical-iOS compilation with signing disabled cannot run here: Linux has no Xcode or Apple SDK. No passing build or XCTest result is claimed. The actual AR reset lifecycle is reviewed in production code; tests exercise its manager cleanup boundary rather than running an AR session. Device testing of this new feature is pending; the user's earlier device confirmation applies to persistence.

## Manual on-device completion test

1. Select a Tree.
2. Note its starting height.
3. Press Raise four times.
4. Press Undo four times.
5. Confirm it returns to the exact starting height.
6. Raise three times.
7. Press Reset Height.
8. Confirm it returns directly to the starting height.
9. Raise once.
10. Rotate and scale the Tree.
11. Raise again.
12. Press Undo.
13. Confirm only the final height adjustment reverses.
14. Confirm the newer rotation and scale remain.
15. Select Birds.
16. Raise them several times.
17. Select Fish.
18. Confirm the Birds history is not applied to Fish.
19. Lower Fish and test repeated Undo.
20. Exit Edit and reselect Fish.
21. Confirm a new session begins at Fish's current height.
22. Save, clear and restore.
23. Select Tree, Birds and Fish.
24. Confirm restored heights are their new Reset Height baselines.
25. Confirm no crash or stale history after deletion or scene reset.

The displayed readout rounds to centimetres. Use DEBUG saved/restored local transforms when comparing fractional values numerically.
