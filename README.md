# Little World Builder - Augmented Reality Model Placer

This ARKit app allows browsing, placing, manipulating, and saving 3D models in your environment using iPhone and iPad.

## Key Features

- **Browse** categorized sets of 3D models  
- **Place** selected models in your surroundings using plane detection
- **Manipulate** placed models with touch gestures for moving, rotating, and scaling
- **Save Scenes** locally between sessions and reload placed models  
- **Multiuser** AR? (early exploration/prototyping)

## Technical Details

The app is built with RealityKit, ARKit, SwiftUI and Firebase services:

**Core AR Components**

- `ARViewContainer` - Initializes ARView, sets up model placement and persistence   
- `CustomARView` - Configures ARSession, Scene, gesture handling
- `PlacementSettings` - Selected models and anchor placements

**Firebase Integration**

- Asset bundles downloaded from Firebase Storage  
- Model metadata fetched from Firestore   
- Authentication for potential multiuser support  

**User Interface**  

- Main app navigation with `ContentView`,  `ControlView`, `BrowseView`   
- Model placement confirmation/cancellation with `PlacementView`  
- AR session settings via `SettingsView`

**Persistence**

- `SceneManager` persists/reloads scenes as ARWorldMaps  
- `ScenePersistenceHelper` handles saving and loading world maps + anchors  

## Getting Started  

Open the Xcode project and run on a physical iOS device with A12 chip or later. Add your own 3D models to Firebase Storage and update Firestore with metadata.   

## Next Steps  

Areas for future improvement:   

- Multiuser collaboration  
- Scale models appropriately    
- Refine UI/UX flows  
- Share persisted scenes  

Excited to see where this goes!
