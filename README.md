# iCloud Bridge

A macOS menu bar application that exposes your iCloud Reminders and Photos via a local REST API.

## Features

- **Reminders API** - Full CRUD access to your reminder lists and items
- **Photos API** - Browse albums, fetch metadata, thumbnails, and full-resolution images
- **Native macOS App** - Runs quietly in your menu bar
- **Python Client** - Ready-to-use Python library for easy integration
- **Privacy-First** - All data stays local; the API only binds to localhost
- **Selective Sync** - Choose which lists and albums to expose

## Requirements

- macOS 14.0 (Sonoma) or later
- Reminders and/or Photos permissions granted to the app

## Quick Start

### 1. Download and Run

Download the latest release and move `iCloud Bridge.app` to your Applications folder. Launch the app - it will appear in your menu bar.

### 2. Grant Permissions

On first launch, you'll be guided through granting access to Reminders and Photos. Both permissions are required for full functionality.

### 3. Configure

Select which reminder lists and photo albums you want to expose via the API, then click "Save & Start Server".

### 4. Use the API

The API runs on `http://localhost:31337` by default. Test it:

```bash
curl http://localhost:31337/api/v1/health
# {"status":"ok"}

curl http://localhost:31337/api/v1/lists
# Returns your selected reminder lists
```

## Documentation

- **[REST API Reference](docs/api/)** - Complete API documentation with interactive Swagger UI
- **[Python Client](python/)** - Python library documentation and examples

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

## Python Client

Install the client library:

```bash
pip install ./python
```

Quick example:

```python
from icloudbridge import iCloudBridge

# Connect to the local API
client = iCloudBridge()

# Get all reminder lists
lists = client.get_lists()
for lst in lists:
    print(f"{lst.title}: {lst.reminder_count} reminders")

# Create a reminder
reminder = client.create_reminder(
    list_id=lists[0].id,
    title="Buy groceries",
    notes="Milk, eggs, bread"
)

# Mark it complete
client.complete_reminder(reminder.id)

# Browse photo albums
albums = client.get_albums()
for album in albums:
    print(f"{album.title}: {album.photo_count} photos")

# Download a photo
photos, total = client.get_photos(albums[0].id, limit=10)
image_data = client.get_image(photos[0].id)
with open("photo.jpg", "wb") as f:
    f.write(image_data)
```

## Building from Source

### Prerequisites

- Xcode 15+ with Command Line Tools
- Swift 5.9+

### Build

```bash
# Clone the repository
git clone https://github.com/cleverdevil/icloudbridge.git
cd icloudbridge

# Build release version
swift build -c release

# The binary is at .build/release/iCloudBridge
```

### Run

```bash
# Run directly
.build/release/iCloudBridge

# Or use the app bundle
open iCloudBridge.app
```

## Configuration

Settings are stored in `~/Library/Preferences` via UserDefaults:

- **Server Port** - Default: 31337 (configurable in Settings)
- **Selected Lists** - Which reminder lists to expose
- **Selected Albums** - Which photo albums to expose

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│                    iCloud Bridge                         │
├─────────────────────────────────────────────────────────┤
│  Menu Bar UI (SwiftUI)                                  │
│    └── Settings Window                                  │
│         ├── Onboarding (permissions)                    │
│         └── List/Album Selection                        │
├─────────────────────────────────────────────────────────┤
│  REST API Server (Vapor)                                │
│    ├── /api/v1/lists/*      → ListsController           │
│    ├── /api/v1/reminders/*  → RemindersController       │
│    ├── /api/v1/albums/*     → AlbumsController          │
│    └── /api/v1/photos/*     → PhotosController          │
├─────────────────────────────────────────────────────────┤
│  Services                                               │
│    ├── RemindersService (EventKit)                      │
│    └── PhotosService (Photos.framework)                 │
├─────────────────────────────────────────────────────────┤
│  iCloud (via system frameworks)                         │
└─────────────────────────────────────────────────────────┘
```

## Security Considerations

- The API binds only to `localhost` - it is not accessible from other machines
- No authentication is currently implemented (planned for future releases)
- The app requests only the minimum required permissions
- All data remains on your Mac; nothing is sent to external servers

## Roadmap

Future enhancements under consideration:

- [ ] API authentication (API keys, tokens)
- [ ] Calendar integration
- [ ] Contacts integration
- [ ] Notes integration
- [ ] Network binding options (for LAN access)
- [ ] Webhook notifications for changes

## License

MIT License - see [LICENSE](LICENSE) for details.

## Contributing

Contributions are welcome! Please open an issue to discuss proposed changes before submitting a pull request.
