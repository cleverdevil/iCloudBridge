<p align="center">
  <img src="assets/icon.png" alt="iCloud Bridge" width="128" height="128">
</p>

<h1 align="center">iCloud Bridge</h1>

<p align="center">
  A macOS menu bar application that exposes your iCloud Reminders, Calendars, and Photos via a REST API.
</p>

## Features

- **Reminders API** - Full CRUD access to your reminder lists and items
- **Calendars API** - Full CRUD access to calendars and events, including recurring events
- **Photos API** - Browse albums, fetch metadata, thumbnails, and full-resolution images
- **Native macOS App** - Runs quietly in your menu bar
- **Python Client** - Ready-to-use Python library with interactive domain objects
- **Authentication** - Bearer token authentication for remote access
- **Privacy-First** - All data stays local; localhost requests require no authentication
- **Selective Sync** - Choose which lists, calendars, and albums to expose

## Requirements

- macOS 14.0 (Sonoma) or later
- Reminders, Calendars, and/or Photos permissions granted to the app

## Quick Start

### 1. Download and Run

Download the latest release and move `iCloud Bridge.app` to your Applications folder. Launch the app - it will appear in your menu bar.

### 2. Grant Permissions

On first launch, you'll be guided through granting access to Reminders, Calendars, and Photos.

### 3. Configure

Select which reminder lists, calendars, and photo albums you want to expose via the API, then click "Save & Start Server".

### 4. Use the API

The API runs on `http://localhost:31337` by default:

```bash
curl http://localhost:31337/health
# {"status":"ok"}

curl http://localhost:31337/api/v1/lists
# Returns your selected reminder lists

curl http://localhost:31337/api/v1/calendars
# Returns your selected calendars
```

## Documentation

- **[REST API Reference](docs/api/)** - Complete API documentation
- **[Python Client](python/)** - Python library documentation and examples

## Python Client

Install the client library:

```bash
pip install ./python
```

### Interactive Objects

Domain objects are interactive and can make API calls directly:

```python
from icloudbridge import iCloudBridge

client = iCloudBridge()

# Iterate albums and their photos
for album in client.albums:
    print(f"{album.title}: {album.photo_count} photos")
    for photo in album.photos:  # auto-paginates
        thumb = photo.thumbnail_medium  # download thumbnail
        break

# Iterate reminder lists and manage reminders
for lst in client.reminder_lists:
    print(f"{lst.title}: {lst.reminder_count} reminders")
    for reminder in lst.reminders:
        print(f"  - {reminder.title}")

# Create and manage reminders
lst = next(client.reminder_lists)
reminder = lst.create_reminder("Buy milk", notes="2% milk")
reminder.complete()

# Iterate calendars and their events
from datetime import datetime, timedelta
for cal in client.calendars:
    print(f"{cal.title}: {cal.event_count} events")
    start = datetime.now()
    end = start + timedelta(days=7)
    for event in cal.get_events(start, end):
        print(f"  {event.start_date}: {event.title}")

# Create and manage events
cal = next(client.calendars)
event = cal.create_event(
    title="Team Lunch",
    start_date=datetime(2026, 1, 20, 12, 0),
    end_date=datetime(2026, 1, 20, 13, 0),
    location="Cafe Roma"
)
event.title = "Team Dinner"
event.save()
```

### Remote Connections

For remote access, enable "Allow remote connections" in Settings and create an API token:

```python
client = iCloudBridge(host="192.168.1.100", token="your-token-here")

for album in client.albums:
    print(album.title)
```

## API Overview

### Reminders

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/api/v1/lists` | GET | List all selected reminder lists |
| `/api/v1/lists/{id}` | GET | Get a specific list |
| `/api/v1/lists/{id}/reminders` | GET | Get reminders in a list |
| `/api/v1/lists/{id}/reminders` | POST | Create a new reminder |
| `/api/v1/reminders/{id}` | GET | Get a specific reminder |
| `/api/v1/reminders/{id}` | PUT | Update a reminder |
| `/api/v1/reminders/{id}` | DELETE | Delete a reminder |

### Calendars

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/api/v1/calendars` | GET | List all selected calendars |
| `/api/v1/calendars/{id}` | GET | Get calendar details |
| `/api/v1/calendars/{id}/events` | GET | Get events in date range (requires `start` and `end` params) |
| `/api/v1/calendars/{id}/events` | POST | Create a new event |
| `/api/v1/events/{id}` | GET | Get a specific event |
| `/api/v1/events/{id}` | PUT | Update an event |
| `/api/v1/events/{id}` | DELETE | Delete an event |

For recurring events, PUT and DELETE accept an optional `span` query parameter:
- `thisEvent` (default) - Only this occurrence
- `futureEvents` - This and all future occurrences

### Photos

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/api/v1/albums` | GET | List all selected albums |
| `/api/v1/albums/{id}` | GET | Get album details |
| `/api/v1/albums/{id}/photos` | GET | Get photos in an album (paginated) |
| `/api/v1/photos/{id}` | GET | Get photo metadata |
| `/api/v1/photos/{id}/thumbnail` | GET | Get photo thumbnail |
| `/api/v1/photos/{id}/image` | GET | Get full-resolution image |
| `/api/v1/photos/{id}/video` | GET | Get video file |
| `/api/v1/photos/{id}/live-video` | GET | Get Live Photo video component |

## Building from Source

### Prerequisites

- Xcode 15+ with Command Line Tools
- Swift 5.9+

### Build

```bash
git clone https://github.com/cleverdevil/icloudbridge.git
cd icloudbridge

swift build -c release

# The binary is at .build/release/iCloudBridge
```

### Run

```bash
.build/release/iCloudBridge

# Or use the app bundle
open iCloudBridge.app
```

## Configuration

Settings are stored in `~/Library/Preferences` via UserDefaults:

- **Server Port** - Default: 31337
- **Allow Remote Connections** - Enable to bind to all interfaces and require authentication
- **API Tokens** - Manage bearer tokens for remote access
- **Selected Lists** - Which reminder lists to expose
- **Selected Calendars** - Which calendars to expose
- **Selected Albums** - Which photo albums to expose

API tokens are stored as SHA-256 hashes in `~/Library/Application Support/iCloudBridge/tokens.json`.

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│                    iCloud Bridge                        │
├─────────────────────────────────────────────────────────┤
│  Menu Bar UI (SwiftUI)                                  │
│    └── Settings Window                                  │
│         ├── Onboarding (permissions)                    │
│         ├── List/Calendar/Album Selection               │
│         └── Token Management                            │
├─────────────────────────────────────────────────────────┤
│  REST API Server (Vapor)                                │
│    ├── AuthMiddleware (bearer tokens)                   │
│    ├── /api/v1/lists/*      → ListsController           │
│    ├── /api/v1/reminders/*  → RemindersController       │
│    ├── /api/v1/calendars/*  → CalendarsController       │
│    ├── /api/v1/events/*     → EventsController          │
│    ├── /api/v1/albums/*     → AlbumsController          │
│    └── /api/v1/photos/*     → PhotosController          │
├─────────────────────────────────────────────────────────┤
│  Services                                               │
│    ├── RemindersService (EventKit)                      │
│    ├── CalendarsService (EventKit)                      │
│    ├── PhotosService (Photos.framework)                 │
│    └── TokenManager (authentication)                    │
├─────────────────────────────────────────────────────────┤
│  iCloud (via system frameworks)                         │
└─────────────────────────────────────────────────────────┘
```

## Security

- **Localhost exempt** - Requests from localhost require no authentication
- **Remote authentication** - Remote connections require a valid bearer token
- **Token storage** - Only SHA-256 hashes are stored, never plaintext tokens
- **Minimal permissions** - The app requests only the minimum required permissions
- **Local data** - All data remains on your Mac; nothing is sent to external servers

## Roadmap

Future enhancements under consideration:

- [x] Calendar integration
- [ ] Contacts integration
- [ ] Notes integration
- [ ] Webhook notifications for changes

## License

MIT License - see [LICENSE](LICENSE) for details.

## Contributing

Contributions are welcome! Please open an issue to discuss proposed changes before submitting a pull request.
