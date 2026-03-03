# Project Knowledge Base

## 1. Project Overview

**DankPod** is an iPod Classic emulator iOS application written in Swift. It recreates the iconic iPod Classic user interface — including the click wheel, gradient navigation bar, and hierarchical menu navigation — as a native iOS app that plays music from the device's Apple Music library.

- **Purpose**: Fun/hobby project emulating the iPod Classic experience on modern iPhones
- **Author**: Alistair Pullen (Apullen Developments Ltd.)
- **Created**: May 22, 2020
- **License**: MIT
- **Status**: Work in progress — Music browsing/playback works; Photos, Videos, Extras, and Settings sections are not implemented; queue system is partially implemented via force touch

### Key Features
- Full iPod Classic click wheel with circular gesture recognition
- Music library browsing (Playlists, Artists, Albums, Songs, Genres)
- Now Playing screen with album art, progress bar, and volume control
- Shuffle Songs mode
- Play/pause from any screen
- Force touch (3D Touch) support for additional actions
- Haptic feedback on all click wheel interactions
- Battery level indicator in iPod-style nav bar
- Partial queue management system (via force touch + hold combos)

## 2. Architecture Overview

### High-Level Architecture

The app follows a **UIKit programmatic UI** pattern (no storyboards used at runtime). The architecture is built around a central `BasePodView` that manages the iPod chrome (nav bar + click wheel), with child view controllers swapped into a screen content area.

```
┌─────────────────────────────────────────┐
│  AppDelegate                            │
│  ├── static music: Music                │ ← Global music service singleton
│  └── static baseVC: MainViewController  │ ← Global base view controller
│       ├── NavBar (gradient, title, icons)│
│       ├── Screen area (child VC content) │
│       └── Click Wheel (gesture input)   │
│            └── ClickWheelProtocol       │ ← Delegate pattern to active VC
└─────────────────────────────────────────┘
```

### Component Responsibilities

| Component | Responsibility |
|-----------|---------------|
| **AppDelegate** | App lifecycle; holds static references to `Music` and `MainViewController` |
| **SceneDelegate** | iOS 13+ scene lifecycle; creates window and sets `SplashScreenViewController` as root |
| **SplashScreenViewController** | 2-second splash screen → presents `MainViewController` |
| **MainViewController** | Subclass of `BasePodView`; manages `UINavigationController` for screen content |
| **BasePodView** | iPod chrome: nav bar with gradient/title/icons, click wheel with gesture recognizers |
| **Music** | Wrapper around `MPMusicPlayerController.systemMusicPlayer`; all library queries and playback |
| **ClickWheelProtocol** | Protocol for screen VCs to receive click wheel events |
| **Screen VCs** | Individual screens (Home, Music, Songs, Albums, etc.) implementing `ClickWheelProtocol` |

### Data Flow

1. **Input**: User touches on click wheel → `CircleGestureRecogniser` / `ForceTouchTapGestureRecogniser` / `UILongPressGestureRecognizer`
2. **Routing**: `BasePodView` determines which button zone was touched and calls the appropriate `ClickWheelProtocol` method on `clickWheelDelegate`
3. **Processing**: Active screen VC handles the event (scroll list, navigate, play/pause, etc.)
4. **Music Queries**: Screen VCs call `AppDelegate.music.getXxx()` methods which query `MPMediaQuery`
5. **Playback**: `PlaybackViewController` sets queue on `MPMusicPlayerController.systemMusicPlayer` and controls playback

### Navigation Flow

```
SplashScreenViewController → MainViewController
                              └── UINavigationController
                                   └── HomeViewController ("iPod")
                                        ├── Music → MusicViewController
                                        │   ├── Playlists → PlaylistsViewController → SongsViewController → PlaybackViewController
                                        │   ├── Artists → ArtistsViewController → AlbumsViewController → SongsViewController → PlaybackViewController
                                        │   ├── Albums → AlbumsViewController → SongsViewController → PlaybackViewController
                                        │   ├── Songs → SongsViewController → PlaybackViewController
                                        │   └── Genres → GenresViewController → SongsViewController → PlaybackViewController
                                        ├── Photos → (stub: MusicViewController)
                                        ├── Videos → (stub: MusicViewController)
                                        ├── Extras → (stub: MusicViewController)
                                        ├── Settings → (stub: MusicViewController)
                                        ├── Shuffle Songs → PlaybackViewController (all songs shuffled)
                                        └── Now Playing → PlaybackViewController (current queue)
```

## 3. Tech Stack

| Category | Technology |
|----------|-----------|
| **Language** | Swift 5.0 |
| **Platform** | iOS (iPhone only), Deployment Target: iOS 10.0 (but effectively iOS 13+ due to Scene APIs) |
| **UI Framework** | UIKit (100% programmatic — no Interface Builder/storyboards used at runtime) |
| **Music Framework** | MediaPlayer (`MPMusicPlayerController`, `MPMediaQuery`, `MPMediaItem`) |
| **Audio** | AVFoundation (`AVAudioSession` for volume reading) |
| **Build Tool** | Xcode 11.5 / Xcode project (`.xcodeproj`) |
| **Dependencies** | **None** — zero external dependencies (no CocoaPods, Carthage, or SPM) |
| **Testing** | XCTest (template only — no actual tests implemented) |
| **Design Tool** | Sketch (`design.sketch` in root) |
| **Bundle ID** | `com.apullen.DankPod` |

## 4. Directory Structure

```
DankPod/                          ← Repository root
├── README.md                     ← Project description and status
├── LICENSE                       ← MIT License
├── design.sketch                 ← Sketch design file for UI mockups
├── DankPod.ipa                   ← Pre-built IPA binary
├── DankPod.xcodeproj/            ← Xcode project configuration
│   └── project.pbxproj           ← Build settings, targets, file references
│
├── DankPod/                      ← Main app source code
│   ├── AppDelegate.swift         ← App lifecycle, static Music and baseVC references
│   ├── SceneDelegate.swift       ← iOS 13+ scene lifecycle, window setup
│   ├── Info.plist                ← App configuration (permissions, orientation, etc.)
│   │
│   ├── BasePodView.swift         ← iPod chrome: nav bar, click wheel, gesture handling
│   ├── MainViewController.swift  ← Root VC, subclass of BasePodView, hosts UINavigationController
│   ├── SplashScreenViewController.swift ← 2-second splash screen with DankPod branding
│   ├── ViewController.swift      ← Appears orphaned / duplicate of BasePodView reference
│   │
│   ├── Music.swift               ← Music service: library queries, playback, queue management
│   ├── ClickWheelProtocol.swift  ← Protocol for click wheel event handling
│   ├── CircularGestureRecogniser.swift  ← Custom circular pan gesture for click wheel
│   ├── ForceTouchGestureRecogniser.swift ← Force touch (3D Touch) tap gesture
│   ├── CustomTableViewCell.swift ← iPod-style table cell with blue gradient selection
│   ├── Globals.swift             ← UIColor/UIView extensions, utility functions
│   │
│   ├── Screens/                  ← Screen view controllers (all implement ClickWheelProtocol)
│   │   ├── HomeViewController.swift      ← Root menu: Music/Photos/Videos/Extras/Settings/Shuffle
│   │   ├── MusicViewController.swift     ← Music sub-menu: Playlists/Artists/Albums/Songs/Genres
│   │   ├── PlaylistsViewController.swift ← Lists user playlists
│   │   ├── ArtistsViewController.swift   ← Lists all artists
│   │   ├── AlbumsViewController.swift    ← Lists albums (all or filtered by artist/genre)
│   │   ├── ArtistsAlbumsViewController.swift ← Alternate/earlier version of AlbumsViewController (⚠️ duplicate class name)
│   │   ├── SongsViewController.swift     ← Lists songs (all or filtered by album)
│   │   ├── GenresViewController.swift    ← Lists all genres
│   │   └── PlaybackViewController.swift  ← Now Playing: album art, progress, volume, track info
│   │
│   ├── Assets.xcassets/          ← Image assets (app icons, UI elements)
│   ├── Base.lproj/               ← Storyboards (LaunchScreen used; Main.storyboard orphaned)
│   └── DankPodTests/             ← Unit test target (template only)
│
├── DankPodUITests/               ← UI test target (template only)
└── Resources/                    ← Raw image resources (duplicated in Assets.xcassets)
```

### Naming Conventions
- View controllers: `XxxViewController.swift`
- Screen VCs in `Screens/` directory
- Core UI in root `DankPod/` directory
- British spelling in some filenames: `Recogniser` (not `Recognizer`)
- Custom colors prefixed with `gradient` (e.g., `gradientLightBlue`)

## 5. Key Entry Points

### Application Entry
- `@UIApplicationMain` attribute on `AppDelegate` class
- `AppDelegate.application(_:didFinishLaunchingWithOptions:)` initializes `Music()` and enables battery monitoring
- iOS 13+: `SceneDelegate.scene(_:willConnectTo:)` creates `MainViewController` and presents `SplashScreenViewController`
- iOS <13: `AppDelegate` directly sets up window with `SplashScreenViewController`

### Screen Flow Entry
- `SplashScreenViewController` → 2-second delay → presents `MainViewController` (full screen modal)
- `MainViewController` creates `UINavigationController` with `HomeViewController` as root

### Music Playback Entry
- `AppDelegate.music` (static `Music` instance) — all music operations go through this singleton
- `Music.musicPlayer` is `MPMusicPlayerController.systemMusicPlayer`

## 6. Core Concepts

### Click Wheel System
The click wheel is the central input mechanism, emulating the iPod Classic's physical wheel:

- **Rotation**: `CircleGestureRecogniser` (subclass of `UIPanGestureRecognizer`) tracks circular finger movement around the wheel center point, computing rotation angle changes
- **Button Zones**: The wheel is divided into 5 touch zones (Menu/top, Next/right, Previous/left, Play-Pause/bottom, Center) — detected by hit-testing touch coordinates against overlaid UIView frames
- **Force Touch**: `ForceTouchTapGestureRecogniser` detects 3D Touch pressure (threshold 0.9) for enhanced actions
- **Long Press**: `UILongPressGestureRecognizer` handles force touch end states
- **Haptic Feedback**: `UISelectionFeedbackGenerator` for rotation ticks; `UIImpactFeedbackGenerator` (light/heavy) for button presses
- **Resolution**: Click wheel sensitivity dynamically adjusts based on swipe velocity (faster = fewer events per rotation)

### ClickWheelProtocol
```swift
protocol ClickWheelProtocol {
    func clickWheelDidRotate(rotationDirection: RotationDirection)  // .CLOCKWISE / .COUNTER_CLOCKWISE
    func playPausePressed(pressure: ClickWheelTouchPressure)       // .NORMAL / .FORCE / .FORCE_ENDED
    func nextSongPressed(pressure: ClickWheelTouchPressure)
    func previousSongPressed(pressure: ClickWheelTouchPressure)
    func menuPressed(pressure: ClickWheelTouchPressure)
    func centerPressed(pressure: ClickWheelTouchPressure)
}
```

### Delegate Reassignment Pattern
Every screen VC sets `AppDelegate.baseVC.clickWheelDelegate = self` in `viewWillAppear` — this is how click wheel input gets routed to the currently visible screen.

### Counter-Based Selection
All list VCs maintain a `counter: Int` tracking the selected row. Click wheel rotation increments/decrements the counter, and the table view scrolls to match. Center press acts on the item at `counter`.

### Music Service (`Music` class)
- Wraps `MPMusicPlayerController.systemMusicPlayer` (the system-wide music player)
- Provides query methods: `getSongs()`, `getArtists()`, `getAlbums(forArtist:)`, `getAllAlbums()`, `getSongsInAlbum(forAlbum:)`, `getPlaylists()`, `getGenres()`, `getSongsByGenre(genre:)`
- Playback control: `playPause()`, `setVolume(_:)`
- Queue management (partial): `toggleQueueMode()`, `clearQueue()`, `pushToHeadOfQueue(song:)`, `pushToTailOfQueue(song:)`, `removeFromQueue(song:)`, `getCurrentQueue()`, `printQueue()`

### Key Enums
```swift
enum RotationDirection { case CLOCKWISE, COUNTER_CLOCKWISE }
enum PlaybackState { case playing, paused, stopped }
enum ClickWheelTouchPressure { case NORMAL, FORCE, FORCE_ENDED }
```

## 7. Development Patterns

### Code Organization
- **Static singletons via AppDelegate**: `AppDelegate.music` and `AppDelegate.baseVC` are static properties accessed globally throughout the app
- **Programmatic UI everywhere**: All views, constraints, and layouts are created in code — no Interface Builder
- **Protocol-delegate pattern**: `ClickWheelProtocol` for routing input to the active VC
- **Lazy UI setup**: All VCs use a `hasSetupUI: Bool` flag to ensure `setupUI()` runs only once (in `viewWillAppear`), while delegate/title reassignment happens every appear
- **Pre-instantiated VCs**: Menu screens (Home, Music) pre-create destination VC arrays in their initializers

### Error Handling
- Minimal error handling — force unwraps are used in several places (e.g., `query.collections!`, `representativeItem?.albumTitle ?? ""`)
- No custom error types or error reporting

### UI Conventions
- **iPod gradient nav bar**: Light grey to dark grey gradient (`gradientVeryLightGrey` → `gradientDarkGrey`)
- **Selection highlight**: Blue gradient (`gradientLightBlue` → `gradientDarkBlue`) on selected table cells
- **Font**: Helvetica-Bold throughout (17pt for nav bar, 15pt for cells, 14pt for playback labels)
- **Table cells**: 30pt row height, no separators, disclosure indicators
- **Menu button convention**: Normal press = pop one level; Force press = pop to root VC

### Configuration
- Apple Music permission: `NSAppleMusicUsageDescription` in Info.plist
- Status bar hidden (`UIStatusBarHidden = true`)
- Light mode forced (`UIUserInterfaceStyle = Light`)
- Portrait only on iPhone
- Battery monitoring enabled at launch

### Global Utilities (`Globals.swift`)
- `UIColor` extensions for custom gradient colors
- `UIView` extensions for applying/removing `CAGradientLayer`s
- `FloatingPoint` extension for degree/radian conversion
- `secondsToHoursMinutesSeconds(seconds:)` utility
- `map(n:start1:stop1:start2:stop2:)` value mapping utility

## 8. Testing Strategy

### Current State
- **No actual tests are implemented** — both test targets contain only Xcode-generated template code
- Unit test target: `DankPodTests/DankPodTests.swift` — empty `XCTest` boilerplate
- UI test target: `DankPodUITests/DankPodUITests.swift` — only launches the app

### Testing Considerations
- The app has **zero external dependencies**, simplifying test setup
- Music queries depend on `MPMediaQuery` which requires a real device with music — mocking would be needed
- Click wheel gesture recognition is complex and would benefit from unit tests
- The `Music` class could be extracted behind a protocol for testability

## 9. Getting Started

### Prerequisites
- macOS with **Xcode 11.5+** (project created with Xcode 11.5)
- Swift 5.0
- iOS device for testing (Apple Music library access required — Simulator has no media library)
- Apple Developer account for code signing

### Setup
1. Clone the repository
2. Open `DankPod.xcodeproj` in Xcode
3. Set your development team in Signing & Capabilities (replacing `WPY678LZM4`)
4. Connect an iOS device
5. Build and run (⌘R)

### Important Notes
- The app requires **Apple Music permission** — it will prompt on first launch
- The device must have **music in its library** for the app to display anything
- A pre-built `DankPod.ipa` is included in the repository root
- The `design.sketch` file contains the UI design mockups (requires Sketch app)

### Common Development Tasks
- **Add a new screen**: Create a VC implementing `ClickWheelProtocol`, add it to the parent menu's `vcs` array
- **Modify click wheel behavior**: Edit `BasePodView.swift` (gesture handlers: `rotateGesture`, `wheelClicked`, `wheelLongPress`)
- **Add music queries**: Add methods to `Music.swift` using `MPMediaQuery` with `MPMediaPropertyPredicate`
- **Change iPod appearance**: Edit `BasePodView.swift` for chrome, `CustomTableViewCell.swift` for list styling, `Globals.swift` for colors

## 10. Areas of Complexity

### Click Wheel Gesture System (`BasePodView.swift` + `CircularGestureRecogniser.swift`)
- The most complex subsystem — handles simultaneous circle rotation, tap detection, force touch, and long press gestures
- Dynamic rotation resolution based on velocity (faster swipes = coarser ticks)
- Hit-testing against 5 invisible button zones using frame coordinates
- Force touch state tracking across `wheelClicked` and `wheelLongPress` handlers
- Three gesture recognizers must work simultaneously (via `shouldRecognizeSimultaneouslyWith: true`)

### Queue Management System (`Music.swift`)
- The queue system is **incomplete/work-in-progress** — activated by holding both next and previous song buttons simultaneously
- Uses an undocumented private API: `musicPlayer.value(forKey: "queueAsQuery")` to read the current queue
- `clearQueue()` uses a play-then-stop trick to reset the queue
- `pushToHeadOfQueue(song:)` is not implemented (empty method body)
- `pushToTailOfQueue(song:)` is partially implemented but has edge cases around the `justClearedQueue` flag

### Duplicate Class Issue
- `ArtistsAlbumsViewController.swift` and `AlbumsViewController.swift` both declare `class AlbumsViewController` — one must be excluded from the Xcode build target to avoid compilation errors. The project.pbxproj file includes only `AlbumsViewController.swift` in Sources.

### Deployment Target Mismatch
- Project sets deployment target to iOS 10.0, but the app uses iOS 13+ Scene APIs (`UIApplicationSceneManifest`, `UIWindowSceneDelegate`). The app would crash on iOS 10-12. This is effectively an iOS 13+ app.

### Potential Bug: Playlist Song Fetching
- `PlaylistsViewController` fetches songs via `getSongsInAlbum(forAlbum:)` using the playlist's representative item's album title, rather than iterating the actual playlist tracks. This would show album songs instead of playlist contents.

### Private API Usage
- `Music.getCurrentQueue()` uses `musicPlayer.value(forKey: "queueAsQuery")` which is an undocumented/private `MPMusicPlayerController` property. This could break with iOS updates and may cause App Store rejection.

### Force Unwraps
- Several force unwraps throughout the codebase (especially in `Music.swift` genre parsing and `PlaybackViewController` time display) could cause runtime crashes if data is missing.

### Volume Control
- `MPVolumeView.setVolume()` extension uses a `UISlider` extraction hack from `MPVolumeView` subviews — this is fragile and could break with iOS updates.
