# iCloud Bridge - Reminders Bridge Design

## Overview

A macOS Swift application that bridges iCloud Reminders to external services via a REST API. The app runs 24/7 on a Mac Mini, providing full CRUD access to selected Reminders lists.

## Requirements

- **Platform:** macOS (Mac Mini, 24/7 operation)
- **UI:** Menu bar app with settings window
- **API:** Full CRUD REST API for Reminders
- **Port:** Configurable, default 31337
- **Sync:** On-demand (fresh data on each API request)
- **Auth:** None initially (to be added later)
- **Extensibility:** Structure to support future bridges (calendars, photos, contacts)

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│                    iCloudBridge App                      │
├─────────────────────────────────────────────────────────┤
│  Menu Bar Item          Settings Window (SwiftUI)       │
│  ┌─────┐                ┌─────────────────────────┐     │
│  │ 🔄  │ ──opens──►     │ ☑ Shopping List         │     │
│  └─────┘                │ ☑ Work Tasks            │     │
│                         │ ☐ Personal              │     │
│                         │ Port: [31337]           │     │
│                         │ [Save & Start Server]   │     │
│                         └─────────────────────────┘     │
├─────────────────────────────────────────────────────────┤
│  EventKit Layer              Vapor REST Server          │
│  ┌─────────────────┐         ┌─────────────────────┐    │
│  │ EKEventStore    │◄───────►│ GET/POST/PUT/DELETE │    │
│  │ (Reminders API) │         │ :31337/api/...      │    │
│  └─────────────────┘         └─────────────────────┘    │
├─────────────────────────────────────────────────────────┤
│  Settings Persistence (UserDefaults)                    │
│  - Selected list IDs                                    │
│  - Port number                                          │
└─────────────────────────────────────────────────────────┘
```

### Technology Stack

- **UI Framework:** SwiftUI
- **Web Framework:** Vapor (embedded)
- **iCloud Access:** EventKit
- **Persistence:** UserDefaults

## REST API Design

**Base URL:** `http://localhost:31337/api/v1`

### Endpoints

| Method | Endpoint | Description |
|--------|----------|-------------|
| `GET` | `/lists` | All selected reminder lists |
| `GET` | `/lists/:id` | Single list with its reminders |
| `GET` | `/lists/:id/reminders` | All reminders in a list |
| `POST` | `/lists/:id/reminders` | Create a new reminder |
| `GET` | `/reminders/:id` | Single reminder by ID |
| `PUT` | `/reminders/:id` | Update a reminder |
| `DELETE` | `/reminders/:id` | Delete a reminder |

### Data Models

**Reminder:**
```json
{
  "id": "abc-123",
  "title": "Buy milk",
  "notes": "2% preferred",
  "isCompleted": false,
  "priority": 1,
  "dueDate": "2025-12-28T10:00:00Z",
  "completionDate": null,
  "listId": "list-456"
}
```

**List:**
```json
{
  "id": "list-456",
  "title": "Shopping List",
  "color": "#FF5733",
  "reminderCount": 12
}
```

**Error Response:**
```json
{
  "error": true,
  "reason": "Reminder not found"
}
```

## UI Design

### Menu Bar States

- Red: Server stopped / not configured
- Green: Server running
- Yellow: Starting up / requesting permissions

### Menu Bar Menu

```
┌─────────────────────────┐
│ iCloud Bridge           │
├─────────────────────────┤
│ ● Server Running :31337 │
│ 3 lists · 47 reminders  │
├─────────────────────────┤
│ Open Settings...        │
│ Copy API URL            │
├─────────────────────────┤
│ Quit                    │
└─────────────────────────┘
```

### Settings Window

- Shows on first launch (no saved config)
- Accessible via menu bar click
- Lists refresh from EventKit when window opens
- "Save" persists to UserDefaults and (re)starts server
- Window can close while server keeps running

## App Lifecycle

1. App launches → Check for saved settings
2. If settings exist → Start server automatically
3. If no settings → Show settings window
4. App runs as background agent (no Dock icon when settings closed)

## Permissions & Persistence

### EventKit Permission Flow

1. App requests Reminders access on first launch
2. If denied → Show message in settings with button to open System Preferences
3. Permission status shown in settings window

### UserDefaults Keys

- `selectedListIds`: [String] - Array of EKCalendar identifiers
- `serverPort`: Int - Default 31337
- `serverEnabled`: Bool - Auto-start on launch

### Error Handling

- EventKit access denied → Disable list selection, show guidance
- Port in use → Show error, suggest alternative port
- Server crash → Update menu bar status, log error, allow restart

## Project Structure

```
iCloudBridge/
├── Package.swift                 # SPM with Vapor dependency
├── Sources/
│   └── iCloudBridge/
│       ├── iCloudBridgeApp.swift # App entry, menu bar setup
│       ├── AppState.swift        # Observable state object
│       ├── Views/
│       │   ├── SettingsView.swift
│       │   └── MenuBarView.swift
│       ├── Services/
│       │   ├── RemindersService.swift   # EventKit wrapper
│       │   └── ServerManager.swift      # Vapor lifecycle
│       ├── API/
│       │   ├── Routes.swift             # Route registration
│       │   ├── ListsController.swift    # /lists endpoints
│       │   └── RemindersController.swift # /reminders endpoints
│       └── Models/
│           ├── ReminderDTO.swift        # JSON models
│           └── ListDTO.swift
└── Resources/
    └── Assets.xcassets          # Menu bar icons
```

## Future Extensibility

The modular structure supports adding bridges for:
- Calendars (EventKit)
- Contacts (Contacts framework)
- Photos (PhotoKit)

Each would add new services, controllers, and routes under the `/api/v1/` namespace.
