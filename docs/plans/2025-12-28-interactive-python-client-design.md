# Interactive Python Client Design

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Make Python client domain objects interactive, allowing API calls directly from objects rather than always going through the client.

**Architecture:** Objects store a back-reference to the client that created them. Properties provide lazy-loading iterators for collections. Methods handle mutations and explicit control.

**Tech Stack:** Python standard library only (no dependencies)

---

## Core Pattern

Each domain object stores a `_client` reference (private, excluded from repr/compare):

```python
@dataclass
class Album:
    id: str
    title: str
    # ... other fields
    _client: Optional[iCloudBridge] = field(default=None, repr=False, compare=False)
```

The client injects itself when creating objects:

```python
def get_albums(self) -> list[Album]:
    data = self._request("GET", "/albums")
    return [Album.from_dict(item, self) for item in data]
```

## Design Principles

1. **Properties for reads** (even with network I/O)
2. **Methods for mutations** (save, complete, delete)
3. **Methods for explicit control** (pagination options, download options)
4. **Lazy iteration** for collections (auto-paginating, memory efficient)
5. **Backward compatible** (existing client API unchanged)

---

## Album

**New properties:**
- `photos` - Iterator of all photos (auto-paginates)
- `videos` - Iterator of videos only
- `live_photos` - Iterator of Live Photos only

**New methods:**
- `get_photos(limit, offset, sort, media_type)` - Explicit pagination control

**Usage:**
```python
album = client.get_album("ABC123")

# Iterate all (lazy, auto-paginates)
for photo in album.photos:
    print(photo.filename)

# Early exit is efficient
for photo in album.photos:
    if photo.is_favorite:
        break

# Explicit pagination
batch, total = album.get_photos(limit=50, offset=100)

# Materialize when needed
all_photos = list(album.photos)
```

---

## Photo

**New properties:**
- `thumbnail_small` - Small (200px) thumbnail bytes
- `thumbnail_medium` - Medium (800px) thumbnail bytes
- `image` - Full-resolution image bytes (auto-retries)
- `video` - Video bytes (works for videos and Live Photos)
- `is_video` - Boolean type check
- `is_live_photo` - Boolean type check

**New methods:**
- `get_thumbnail(size)` - Explicit size control
- `get_image(wait, max_retries)` - Explicit download control

**Usage:**
```python
for photo in album.photos:
    # Simple access via properties
    thumb = photo.thumbnail_medium

    if photo.is_video:
        data = photo.video
    else:
        data = photo.image

    # Explicit control when needed
    small = photo.get_thumbnail(size="small")
    img = photo.get_image(wait=True, max_retries=20)
```

---

## ReminderList

**New properties:**
- `reminders` - Iterator of incomplete reminders
- `all_reminders` - Iterator including completed

**New methods:**
- `get_reminders(include_completed)` - Explicit fetch
- `create_reminder(title, notes, priority, due_date)` - Create in this list

**Usage:**
```python
lst = client.get_list("ABC123")

# Iterate incomplete
for r in lst.reminders:
    print(r.title)

# Iterate all
for r in lst.all_reminders:
    print(r.title, r.is_completed)

# Create
reminder = lst.create_reminder("Buy milk", priority=1)
```

---

## Reminder

**New methods (mutations):**
- `save()` - Save changes to title, notes, priority, due_date
- `complete()` - Mark as completed
- `uncomplete()` - Mark as not completed
- `delete()` - Permanently delete

**Usage:**
```python
reminder = next(lst.reminders)

# Modify and save
reminder.title = "Updated title"
reminder.priority = 1
reminder.save()

# Complete
reminder.complete()

# Delete
reminder.delete()
```

---

## Client Changes

The `iCloudBridge` class needs:

1. Updated `from_dict` calls to pass `self`
2. Internal `_iter_photos()` method for auto-pagination
3. Internal `_iter_reminders()` method for reminder iteration

Existing public methods remain unchanged for backward compatibility.

---

## Not In Scope

- Caching/memoization (conflicts with lazy iteration)
- Async support
- Connection pooling
