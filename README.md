# TheLocads Screen Player (ViewSys)

TheLocads Screen Player is a robust digital signage application built with Flutter. It is designed to run on various devices (Android, Windows, etc.) to display dynamic merchant content, advertisements, and menus. It connects to TheLocads CMS to fetch schedules, layouts, and media files, and features offline caching for seamless continuous playback even when the internet connection is lost.

## Features
- **Device Pairing:** Secure 6-digit code pairing with the CMS.
- **Dynamic Layouts:** Supports multiple screen layouts including Fullscreen, Half Split, Menu Board, Sidebar, Four Grid, and Triple layouts.
- **Offline Caching:** Media files (images and videos) are downloaded and cached locally to prevent playback interruption during network outages.
- **Multi-Zone Playback:** Synchronized playback of different content in different zones of the screen.
- **Remote Management:** Device settings (orientation, sync interval, layouts) are controlled remotely from the CMS.
- **Heartbeat & Screenshots:** Periodically sends device heartbeat and screenshots to the CMS to monitor the screen's health.

## Project Architecture & Folder Structure
The project follows a standard Feature-by-Layer Flutter architecture, making it highly scalable and easy to maintain.

```text
lib/
├── main.dart                 # Single entry point of the application
├── models/                   # Data structures and models
│   ├── media_item.dart       # Represents a piece of media (image/video/webview)
│   └── ticker_item.dart      # Represents scrolling text content
├── providers/                # Riverpod state management
│   ├── player_provider.dart  # Manages main playlist state and activation state
│   └── zone_content_provider.dart # Manages state for multi-zone layouts
├── screens/                  # All full-page UI screens
│   ├── splash_screen.dart    # Initial loading and routing logic
│   ├── activation_screen.dart# Device pairing and linking UI
│   ├── player_shell.dart     # Main player container that orchestrates layouts
│   └── layouts/              # Specialized UI structures for different split-screens
│       ├── half_split_layout.dart
│       ├── menu_board_layout.dart
│       └── ...
├── services/                 # Backend APIs, OS communication, and background tasks
│   ├── sync_service.dart     # Polls CMS for main schedule updates
│   ├── zone_content_service.dart # Polls CMS for zone-specific content
│   ├── file_manager.dart     # Handles downloading and local caching of media
│   ├── heartbeat_service.dart# Sends device health status to the CMS
│   └── screenshot_service.dart # Captures and uploads proof-of-play screenshots
└── widgets/                  # Reusable UI components
    ├── video_player_widget.dart # Handles video playback and looping
    ├── zone_media_viewer.dart   # Renders images/videos/webviews for zones
    └── ticker_bar.dart          # Scrolling text banner at the bottom
```

## Application Flow

Here is the step-by-step lifecycle and flow of the application:

1. **Initialization (`main.dart` & `splash_screen.dart`):**
   - The app starts at `main.dart` which loads `SplashScreen`.
   - `SplashScreen` checks local storage (`SharedPreferences`) to see if the device is already activated.
   - If **Not Activated**: Navigates to `ActivationScreen`.
   - If **Activated**: Bypasses activation and navigates directly to `PlayerShell`.

2. **Device Pairing (`activation_screen.dart`):**
   - Generates a 6-digit code and polls the `api/player/login` endpoint.
   - Once the user enters the code on the CMS portal, the API authorizes the device.
   - The app saves the configuration (screen ID, company ID, orientation, sync interval, layout type) to local storage and routes to the `PlayerShell`.

3. **Orchestration (`player_shell.dart`):**
   - This is the "brain" of the visual UI. It reads the `layout` setting (e.g., `fullscreen`, `half_split`) and loads the appropriate layout widget from `screens/layouts/`.
   - It also initializes the background polling services (`SyncService`, `ZoneContentService`, `HeartbeatService`).

4. **Data Synchronization (`services/sync_service.dart` & `zone_content_service.dart`):**
   - **SyncService:** Continuously fetches the main schedule API (`api/player/schedule`) based on the configured interval. It updates the `playlistProvider` with the latest media items.
   - **ZoneContentService:** If a multi-zone layout is active, this service fetches content for the secondary zones (e.g., right zone, bottom zone) and updates the respective zone providers.

5. **Media Caching (`services/file_manager.dart`):**
   - Whenever the sync services detect a new video or image in the schedule, the `FileManager` downloads the physical file to the device's local storage.
   - Once downloaded, the provider state is updated with the `localPath`, allowing the widget to play it from the disk instead of streaming it from the internet.

6. **Playback (`widgets/video_player_widget.dart` & `zone_media_viewer.dart`):**
   - The UI listens to the Riverpod providers (`playlistProvider`, `zoneContentProvider`, etc.).
   - Media viewers automatically transition between items based on their `duration` or video completion.
   - If the internet disconnects, the app continues to loop through the cached `localPath` items seamlessly.

7. **Monitoring (`services/heartbeat_service.dart` & `screenshot_service.dart`):**
   - While playing, the app periodically sends a heartbeat to the CMS to indicate it is online.
   - It also captures screenshots of the display and uploads them to the CMS so administrators can verify what is currently being shown on the physical screen.
