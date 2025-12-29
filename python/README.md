# iCloud Bridge Python Client

A Python client library for the iCloud Bridge REST API. Access your iCloud Reminders and Photos programmatically.

## Installation

```bash
# From the iCloud Bridge repository
pip install ./python

# Or install in development mode
pip install -e ./python
```

## Quick Start

```python
from icloudbridge import iCloudBridge

# Connect to the local iCloud Bridge server
client = iCloudBridge()

# Check server health
print(client.health())  # {'status': 'ok'}
```

## Working with Reminders

```python
from icloudbridge import iCloudBridge

client = iCloudBridge()

# Get all reminder lists
lists = client.get_lists()
for lst in lists:
    print(f"{lst.title}: {lst.reminder_count} reminders")

# Get reminders from a list (incomplete only by default)
reminders = client.get_reminders(lists[0].id)

# Include completed reminders
all_reminders = client.get_reminders(lists[0].id, include_completed=True)

# Create a new reminder
from datetime import datetime, timedelta

reminder = client.create_reminder(
    list_id=lists[0].id,
    title="Call dentist",
    notes="Schedule cleaning appointment",
    priority=1,  # High priority
    due_date=datetime.now() + timedelta(days=7)
)
print(f"Created: {reminder.title} (ID: {reminder.id})")

# Update a reminder
updated = client.update_reminder(
    reminder.id,
    title="Call dentist office",
    notes="Ask about Saturday appointments"
)

# Mark as complete
client.complete_reminder(reminder.id)

# Or mark as incomplete
client.uncomplete_reminder(reminder.id)

# Delete a reminder
client.delete_reminder(reminder.id)
```

## Working with Photos

```python
from icloudbridge import iCloudBridge

client = iCloudBridge()

# Get all albums
albums = client.get_albums()
for album in albums:
    print(f"{album.title}: {album.photo_count} photos, {album.video_count} videos")

# Get photos from an album (paginated)
photos, total = client.get_photos(
    albums[0].id,
    limit=50,
    offset=0,
    sort="date-desc"  # or "date-asc", "album"
)
print(f"Got {len(photos)} of {total} photos")

# Filter by media type
videos, total = client.get_photos(
    albums[0].id,
    media_type="video"  # or "photo", "live"
)

# Get photo metadata
photo = client.get_photo(photos[0].id)
print(f"Filename: {photo.filename}")
print(f"Size: {photo.width}x{photo.height}")
print(f"Type: {photo.media_type}")

# Download thumbnail
thumbnail = client.get_thumbnail(photo.id, size="medium")  # or "small"
with open("thumb.jpg", "wb") as f:
    f.write(thumbnail)

# Download full-resolution image
# Note: May need to download from iCloud first
image = client.get_image(photo.id, wait=True)
with open("photo.jpg", "wb") as f:
    f.write(image)

# Download video
if photo.media_type == "video":
    video = client.get_video(photo.id)
    with open("video.mov", "wb") as f:
        f.write(video)

# Get Live Photo motion video
if photo.media_type == "livePhoto":
    live_video = client.get_live_video(photo.id)
    with open("live.mov", "wb") as f:
        f.write(live_video)
```

## Data Classes

### ReminderList

| Attribute | Type | Description |
|-----------|------|-------------|
| `id` | str | Unique identifier |
| `title` | str | List name |
| `color` | str \| None | Hex color code |
| `reminder_count` | int | Number of incomplete reminders |

### Reminder

| Attribute | Type | Description |
|-----------|------|-------------|
| `id` | str | Unique identifier |
| `title` | str | Reminder title |
| `notes` | str \| None | Additional notes |
| `is_completed` | bool | Completion status |
| `priority` | int | 0=none, 1=high, 5=medium, 9=low |
| `due_date` | datetime \| None | Due date |
| `completion_date` | datetime \| None | When completed |
| `list_id` | str | Parent list ID |

### Album

| Attribute | Type | Description |
|-----------|------|-------------|
| `id` | str | Unique identifier |
| `title` | str | Album name |
| `album_type` | str | "user", "smart", or "shared" |
| `photo_count` | int | Number of photos |
| `video_count` | int | Number of videos |
| `start_date` | datetime \| None | Earliest photo date |
| `end_date` | datetime \| None | Latest photo date |

### Photo

| Attribute | Type | Description |
|-----------|------|-------------|
| `id` | str | Unique identifier |
| `album_id` | str | Parent album ID |
| `media_type` | str | "photo", "video", or "livePhoto" |
| `creation_date` | datetime | When taken |
| `modification_date` | datetime \| None | When modified |
| `width` | int | Width in pixels |
| `height` | int | Height in pixels |
| `is_favorite` | bool | Favorite status |
| `is_hidden` | bool | Hidden status |
| `filename` | str \| None | Original filename |
| `file_size` | int \| None | Size in bytes |

## Error Handling

```python
from icloudbridge import iCloudBridge, NotFoundError, APIError, iCloudBridgeError

client = iCloudBridge()

try:
    reminder = client.get_reminder("invalid-id")
except NotFoundError:
    print("Reminder not found")
except APIError as e:
    print(f"API error {e.status_code}: {e.reason}")
except iCloudBridgeError as e:
    print(f"Connection error: {e}")
```

## Configuration

```python
# Connect to a different host/port
client = iCloudBridge(host="192.168.1.100", port=8080)

# Or use the convenience function
from icloudbridge import connect
client = connect(port=8080)
```

## Requirements

- Python 3.9+
- No external dependencies (uses only the standard library)
- iCloud Bridge server running on macOS

## Documentation

Full API documentation is available in the [docs](docs/) directory. To build locally:

```bash
pip install -e ".[dev]"
cd docs
make html
open _build/html/index.html
```

## License

MIT License - see the main project [LICENSE](../LICENSE) for details.
