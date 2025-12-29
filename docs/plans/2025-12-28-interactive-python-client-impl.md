# Interactive Python Client Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Make Python client domain objects interactive with lazy-loading properties and mutation methods.

**Architecture:** Each dataclass gets a `_client` back-reference. Properties use internal iterator methods for auto-pagination. Methods handle mutations and explicit control. Backward compatible with existing API.

**Tech Stack:** Python 3.9+, standard library only, dataclasses

---

## Task 1: Add _client Field to Album Dataclass

**Files:**
- Modify: `python/icloudbridge.py:115-156` (Album class)

**Step 1: Import field from dataclasses**

The file already imports `dataclass` but needs `field` for customizing the _client attribute.

Update the import at line 38:
```python
from dataclasses import dataclass, field
```

**Step 2: Add _client field to Album**

Add the `_client` field with proper defaults to exclude from repr/compare:

```python
@dataclass
class Album:
    """
    Represents a photo album from the Photos library.

    Attributes:
        id: Unique identifier for the album.
        title: Display name of the album.
        album_type: Type of album ("user", "smart", or "shared").
        photo_count: Number of photos in the album.
        video_count: Number of videos in the album.
        start_date: Date of the earliest photo, or None.
        end_date: Date of the latest photo, or None.
    """
    id: str
    title: str
    album_type: str
    photo_count: int
    video_count: int
    start_date: Optional[datetime]
    end_date: Optional[datetime]
    _client: Optional["iCloudBridge"] = field(default=None, repr=False, compare=False)
```

**Step 3: Update Album.from_dict to accept client**

```python
@classmethod
def from_dict(cls, data: dict, client: "iCloudBridge" = None) -> Album:
    start_date = None
    if data.get("startDate"):
        start_date = _parse_iso_date(data["startDate"])

    end_date = None
    if data.get("endDate"):
        end_date = _parse_iso_date(data["endDate"])

    return cls(
        id=data["id"],
        title=data["title"],
        album_type=data["albumType"],
        photo_count=data["photoCount"],
        video_count=data["videoCount"],
        start_date=start_date,
        end_date=end_date,
        _client=client,
    )
```

**Step 4: Commit**

```bash
git add python/icloudbridge.py
git commit -m "feat(python): add _client field to Album dataclass"
```

---

## Task 2: Add _client Field to Photo Dataclass

**Files:**
- Modify: `python/icloudbridge.py:158-209` (Photo class)

**Step 1: Add _client field to Photo**

```python
@dataclass
class Photo:
    """
    Represents a single photo or video from the Photos library.

    Attributes:
        id: Unique identifier for the photo.
        album_id: ID of the album containing this photo.
        media_type: Type of media ("photo", "video", or "livePhoto").
        creation_date: When the photo was taken.
        modification_date: When the photo was last modified, or None.
        width: Image width in pixels.
        height: Image height in pixels.
        is_favorite: Whether the photo is marked as a favorite.
        is_hidden: Whether the photo is hidden.
        filename: Original filename, or None.
        file_size: File size in bytes, or None.
    """
    id: str
    album_id: str
    media_type: str
    creation_date: datetime
    modification_date: Optional[datetime]
    width: int
    height: int
    is_favorite: bool
    is_hidden: bool
    filename: Optional[str]
    file_size: Optional[int]
    _client: Optional["iCloudBridge"] = field(default=None, repr=False, compare=False)
```

**Step 2: Update Photo.from_dict to accept client**

```python
@classmethod
def from_dict(cls, data: dict, client: "iCloudBridge" = None) -> Photo:
    creation_date = _parse_iso_date(data["creationDate"])

    modification_date = None
    if data.get("modificationDate"):
        modification_date = _parse_iso_date(data["modificationDate"])

    return cls(
        id=data["id"],
        album_id=data["albumId"],
        media_type=data["mediaType"],
        creation_date=creation_date,
        modification_date=modification_date,
        width=data["width"],
        height=data["height"],
        is_favorite=data["isFavorite"],
        is_hidden=data["isHidden"],
        filename=data.get("filename"),
        file_size=data.get("fileSize"),
        _client=client,
    )
```

**Step 3: Commit**

```bash
git add python/icloudbridge.py
git commit -m "feat(python): add _client field to Photo dataclass"
```

---

## Task 3: Add _client Field to ReminderList Dataclass

**Files:**
- Modify: `python/icloudbridge.py:43-67` (ReminderList class)

**Step 1: Add _client field to ReminderList**

```python
@dataclass
class ReminderList:
    """
    Represents a Reminders list from iCloud.

    Attributes:
        id: Unique identifier for the list.
        title: Display name of the list.
        color: Hex color code (e.g., "#FF6B6B"), or None if not set.
        reminder_count: Number of incomplete reminders in the list.
    """
    id: str
    title: str
    color: Optional[str]
    reminder_count: int
    _client: Optional["iCloudBridge"] = field(default=None, repr=False, compare=False)

    @classmethod
    def from_dict(cls, data: dict, client: "iCloudBridge" = None) -> ReminderList:
        return cls(
            id=data["id"],
            title=data["title"],
            color=data.get("color"),
            reminder_count=data["reminderCount"],
            _client=client,
        )
```

**Step 2: Commit**

```bash
git add python/icloudbridge.py
git commit -m "feat(python): add _client field to ReminderList dataclass"
```

---

## Task 4: Add _client Field to Reminder Dataclass

**Files:**
- Modify: `python/icloudbridge.py:69-113` (Reminder class)

**Step 1: Add _client field to Reminder**

```python
@dataclass
class Reminder:
    """
    Represents a single reminder item.

    Attributes:
        id: Unique identifier for the reminder.
        title: Title/name of the reminder.
        notes: Additional notes or description, or None.
        is_completed: Whether the reminder has been completed.
        priority: Priority level (0=none, 1=high, 5=medium, 9=low).
        due_date: Due date and time, or None if not set.
        completion_date: When the reminder was completed, or None.
        list_id: ID of the list this reminder belongs to.
    """
    id: str
    title: str
    notes: Optional[str]
    is_completed: bool
    priority: int
    due_date: Optional[datetime]
    completion_date: Optional[datetime]
    list_id: str
    _client: Optional["iCloudBridge"] = field(default=None, repr=False, compare=False)

    @classmethod
    def from_dict(cls, data: dict, client: "iCloudBridge" = None) -> Reminder:
        due_date = None
        if data.get("dueDate"):
            due_date = _parse_iso_date(data["dueDate"])

        completion_date = None
        if data.get("completionDate"):
            completion_date = _parse_iso_date(data["completionDate"])

        return cls(
            id=data["id"],
            title=data["title"],
            notes=data.get("notes"),
            is_completed=data["isCompleted"],
            priority=data["priority"],
            due_date=due_date,
            completion_date=completion_date,
            list_id=data["listId"],
            _client=client,
        )
```

**Step 2: Commit**

```bash
git add python/icloudbridge.py
git commit -m "feat(python): add _client field to Reminder dataclass"
```

---

## Task 5: Update Client Methods to Inject Self

**Files:**
- Modify: `python/icloudbridge.py` (iCloudBridge class methods)

**Step 1: Update get_lists to pass self**

```python
def get_lists(self) -> list[ReminderList]:
    """
    Get all available reminder lists.

    Returns:
        list[ReminderList]: All reminder lists configured in iCloud Bridge
    """
    data = self._request("GET", "/lists")
    return [ReminderList.from_dict(item, self) for item in data]
```

**Step 2: Update get_list to pass self**

```python
def get_list(self, list_id: str) -> ReminderList:
    """
    Get a specific reminder list by ID.

    Args:
        list_id: The list identifier

    Returns:
        ReminderList: The requested list

    Raises:
        NotFoundError: If the list is not found
    """
    data = self._request("GET", f"/lists/{urllib.parse.quote(list_id)}")
    return ReminderList.from_dict(data, self)
```

**Step 3: Update get_reminders to pass self**

```python
def get_reminders(self, list_id: str, include_completed: bool = False) -> list[Reminder]:
    """
    Get reminders in a specific list.

    By default, only incomplete reminders are returned. Set include_completed=True
    to include completed reminders as well.

    Args:
        list_id: The list identifier
        include_completed: Whether to include completed reminders (default: False)

    Returns:
        list[Reminder]: Reminders in the list (incomplete only by default)

    Raises:
        NotFoundError: If the list is not found
    """
    path = f"/lists/{urllib.parse.quote(list_id)}/reminders"
    if include_completed:
        path += "?includeCompleted=true"
    data = self._request("GET", path)
    return [Reminder.from_dict(item, self) for item in data]
```

**Step 4: Update get_reminder to pass self**

```python
def get_reminder(self, reminder_id: str) -> Reminder:
    """
    Get a specific reminder by ID.

    Args:
        reminder_id: The reminder identifier

    Returns:
        Reminder: The requested reminder

    Raises:
        NotFoundError: If the reminder is not found
    """
    data = self._request("GET", f"/reminders/{urllib.parse.quote(reminder_id)}")
    return Reminder.from_dict(data, self)
```

**Step 5: Update create_reminder to pass self**

```python
def create_reminder(
    self,
    list_id: str,
    title: str,
    notes: Optional[str] = None,
    priority: Optional[int] = None,
    due_date: Optional[datetime] = None,
) -> Reminder:
    """
    Create a new reminder in a list.

    Args:
        list_id: The list to create the reminder in
        title: The reminder title
        notes: Optional notes/description
        priority: Priority level (0=none, 1=high, 5=medium, 9=low)
        due_date: Optional due date

    Returns:
        Reminder: The created reminder

    Raises:
        NotFoundError: If the list is not found
    """
    payload = {"title": title}
    if notes is not None:
        payload["notes"] = notes
    if priority is not None:
        payload["priority"] = priority
    if due_date is not None:
        payload["dueDate"] = _format_iso_date(due_date)

    data = self._request("POST", f"/lists/{urllib.parse.quote(list_id)}/reminders", payload)
    return Reminder.from_dict(data, self)
```

**Step 6: Update update_reminder to pass self**

```python
def update_reminder(
    self,
    reminder_id: str,
    title: Optional[str] = None,
    notes: Optional[str] = None,
    is_completed: Optional[bool] = None,
    priority: Optional[int] = None,
    due_date: Optional[datetime] = None,
) -> Reminder:
    """
    Update an existing reminder.

    Args:
        reminder_id: The reminder to update
        title: New title (if changing)
        notes: New notes (if changing)
        is_completed: New completion status (if changing)
        priority: New priority (if changing)
        due_date: New due date (if changing)

    Returns:
        Reminder: The updated reminder

    Raises:
        NotFoundError: If the reminder is not found
    """
    payload = {}
    if title is not None:
        payload["title"] = title
    if notes is not None:
        payload["notes"] = notes
    if is_completed is not None:
        payload["isCompleted"] = is_completed
    if priority is not None:
        payload["priority"] = priority
    if due_date is not None:
        payload["dueDate"] = _format_iso_date(due_date)

    data = self._request("PUT", f"/reminders/{urllib.parse.quote(reminder_id)}", payload)
    return Reminder.from_dict(data, self)
```

**Step 7: Update get_albums to pass self**

```python
def get_albums(self) -> list[Album]:
    """
    Get all available photo albums.

    Returns:
        list[Album]: All albums configured in iCloud Bridge
    """
    data = self._request("GET", "/albums")
    return [Album.from_dict(item, self) for item in data]
```

**Step 8: Update get_album to pass self**

```python
def get_album(self, album_id: str) -> Album:
    """
    Get a specific album by ID.

    Args:
        album_id: The album identifier

    Returns:
        Album: The requested album

    Raises:
        NotFoundError: If the album is not found
    """
    data = self._request("GET", f"/albums/{urllib.parse.quote(album_id)}")
    return Album.from_dict(data, self)
```

**Step 9: Update get_photos to pass self**

```python
def get_photos(
    self,
    album_id: str,
    limit: int = 100,
    offset: int = 0,
    sort: str = "album",
    media_type: Optional[str] = None
) -> tuple[list[Photo], int]:
    """
    Get photos in a specific album.

    Args:
        album_id: The album identifier
        limit: Number of photos per page (default: 100)
        offset: Number of photos to skip (default: 0)
        sort: Sort order - "album", "date-asc", or "date-desc" (default: "album")
        media_type: Filter by type - "photo", "video", "live", or "all" (default: None/all)

    Returns:
        tuple[list[Photo], int]: Photos and total count

    Raises:
        NotFoundError: If the album is not found
    """
    path = f"/albums/{urllib.parse.quote(album_id)}/photos"
    params = []
    if limit != 100:
        params.append(f"limit={limit}")
    if offset != 0:
        params.append(f"offset={offset}")
    if sort != "album":
        params.append(f"sort={sort}")
    if media_type is not None:
        params.append(f"type={media_type}")

    if params:
        path += "?" + "&".join(params)

    data = self._request("GET", path)
    photos = [Photo.from_dict(item, self) for item in data["photos"]]
    return photos, data["total"]
```

**Step 10: Update get_photo to pass self**

```python
def get_photo(self, photo_id: str) -> Photo:
    """
    Get a specific photo by ID.

    Args:
        photo_id: The photo identifier

    Returns:
        Photo: The requested photo

    Raises:
        NotFoundError: If the photo is not found
    """
    data = self._request("GET", f"/photos/{urllib.parse.quote(photo_id)}")
    return Photo.from_dict(data, self)
```

**Step 11: Commit**

```bash
git add python/icloudbridge.py
git commit -m "feat(python): inject client reference into all domain objects"
```

---

## Task 6: Add Internal Pagination Iterators to Client

**Files:**
- Modify: `python/icloudbridge.py` (iCloudBridge class)

**Step 1: Add Iterator import**

Update the typing import at line 40:
```python
from typing import Optional, Iterator
```

**Step 2: Add _iter_photos method**

Add this method to the iCloudBridge class (after get_photo method):

```python
def _iter_photos(
    self,
    album_id: str,
    sort: str = "album",
    media_type: Optional[str] = None
) -> Iterator[Photo]:
    """
    Internal iterator for auto-paginating through photos.

    Args:
        album_id: The album identifier
        sort: Sort order
        media_type: Filter by type

    Yields:
        Photo: Each photo in the album
    """
    offset = 0
    limit = 100
    while True:
        photos, total = self.get_photos(album_id, limit=limit, offset=offset, sort=sort, media_type=media_type)
        yield from photos
        offset += limit
        if offset >= total:
            break
```

**Step 3: Add _iter_reminders method**

Add this method to the iCloudBridge class (after get_reminder method):

```python
def _iter_reminders(self, list_id: str, include_completed: bool = False) -> Iterator[Reminder]:
    """
    Internal iterator for reminders.

    Note: Reminders API doesn't paginate, so this just wraps get_reminders.

    Args:
        list_id: The list identifier
        include_completed: Whether to include completed reminders

    Yields:
        Reminder: Each reminder in the list
    """
    yield from self.get_reminders(list_id, include_completed=include_completed)
```

**Step 4: Commit**

```bash
git add python/icloudbridge.py
git commit -m "feat(python): add internal pagination iterators"
```

---

## Task 7: Add Album Interactive Properties and Methods

**Files:**
- Modify: `python/icloudbridge.py` (Album class)

**Step 1: Add photos property**

Add to the Album class after from_dict:

```python
@property
def photos(self) -> Iterator[Photo]:
    """
    Iterate all photos in the album, auto-paginating.

    Yields:
        Photo: Each photo in the album

    Raises:
        RuntimeError: If album was not created by a client
    """
    if self._client is None:
        raise RuntimeError("Album not associated with a client")
    yield from self._client._iter_photos(self.id)
```

**Step 2: Add videos property**

```python
@property
def videos(self) -> Iterator[Photo]:
    """
    Iterate only videos in the album, auto-paginating.

    Yields:
        Photo: Each video in the album
    """
    if self._client is None:
        raise RuntimeError("Album not associated with a client")
    yield from self._client._iter_photos(self.id, media_type="video")
```

**Step 3: Add live_photos property**

```python
@property
def live_photos(self) -> Iterator[Photo]:
    """
    Iterate only Live Photos in the album, auto-paginating.

    Yields:
        Photo: Each Live Photo in the album
    """
    if self._client is None:
        raise RuntimeError("Album not associated with a client")
    yield from self._client._iter_photos(self.id, media_type="live")
```

**Step 4: Add get_photos method**

```python
def get_photos(
    self,
    limit: int = 100,
    offset: int = 0,
    sort: str = "album",
    media_type: Optional[str] = None
) -> tuple[list[Photo], int]:
    """
    Get photos with explicit pagination control.

    Args:
        limit: Number of photos per page (default: 100)
        offset: Number of photos to skip (default: 0)
        sort: Sort order - "album", "date-asc", or "date-desc"
        media_type: Filter by type - "photo", "video", "live", or "all"

    Returns:
        tuple[list[Photo], int]: Photos and total count

    Raises:
        RuntimeError: If album was not created by a client
    """
    if self._client is None:
        raise RuntimeError("Album not associated with a client")
    return self._client.get_photos(self.id, limit=limit, offset=offset, sort=sort, media_type=media_type)
```

**Step 5: Commit**

```bash
git add python/icloudbridge.py
git commit -m "feat(python): add Album interactive properties and methods"
```

---

## Task 8: Add Photo Interactive Properties and Methods

**Files:**
- Modify: `python/icloudbridge.py` (Photo class)

**Step 1: Add is_video property**

Add to the Photo class after from_dict:

```python
@property
def is_video(self) -> bool:
    """Check if this is a video."""
    return self.media_type == "video"
```

**Step 2: Add is_live_photo property**

```python
@property
def is_live_photo(self) -> bool:
    """Check if this is a Live Photo."""
    return self.media_type == "livePhoto"
```

**Step 3: Add thumbnail_small property**

```python
@property
def thumbnail_small(self) -> bytes:
    """
    Get small (200px) thumbnail.

    Returns:
        bytes: JPEG image data

    Raises:
        RuntimeError: If photo was not created by a client
    """
    if self._client is None:
        raise RuntimeError("Photo not associated with a client")
    return self._client.get_thumbnail(self.id, size="small")
```

**Step 4: Add thumbnail_medium property**

```python
@property
def thumbnail_medium(self) -> bytes:
    """
    Get medium (800px) thumbnail.

    Returns:
        bytes: JPEG image data

    Raises:
        RuntimeError: If photo was not created by a client
    """
    if self._client is None:
        raise RuntimeError("Photo not associated with a client")
    return self._client.get_thumbnail(self.id, size="medium")
```

**Step 5: Add image property**

```python
@property
def image(self) -> bytes:
    """
    Get full-resolution image (auto-retries if downloading from iCloud).

    Returns:
        bytes: Image data

    Raises:
        RuntimeError: If photo was not created by a client
    """
    if self._client is None:
        raise RuntimeError("Photo not associated with a client")
    return self._client.get_image(self.id)
```

**Step 6: Add video property**

```python
@property
def video(self) -> bytes:
    """
    Get video data. Works for videos and Live Photos.

    For Live Photos, returns the motion video component.

    Returns:
        bytes: Video data

    Raises:
        RuntimeError: If photo was not created by a client
        APIError: If this is not a video or Live Photo
    """
    if self._client is None:
        raise RuntimeError("Photo not associated with a client")
    if self.media_type == "video":
        return self._client.get_video(self.id)
    else:
        return self._client.get_live_video(self.id)
```

**Step 7: Add get_thumbnail method**

```python
def get_thumbnail(self, size: str = "medium") -> bytes:
    """
    Get thumbnail with explicit size control.

    Args:
        size: "small" (200px) or "medium" (800px)

    Returns:
        bytes: JPEG image data

    Raises:
        RuntimeError: If photo was not created by a client
    """
    if self._client is None:
        raise RuntimeError("Photo not associated with a client")
    return self._client.get_thumbnail(self.id, size=size)
```

**Step 8: Add get_image method**

```python
def get_image(self, wait: bool = False, max_retries: int = 10) -> bytes:
    """
    Get full-resolution image with explicit control.

    Args:
        wait: If True, block until download completes
        max_retries: Maximum retry attempts for non-blocking mode

    Returns:
        bytes: Image data

    Raises:
        RuntimeError: If photo was not created by a client
    """
    if self._client is None:
        raise RuntimeError("Photo not associated with a client")
    return self._client.get_image(self.id, wait=wait, max_retries=max_retries)
```

**Step 9: Commit**

```bash
git add python/icloudbridge.py
git commit -m "feat(python): add Photo interactive properties and methods"
```

---

## Task 9: Add ReminderList Interactive Properties and Methods

**Files:**
- Modify: `python/icloudbridge.py` (ReminderList class)

**Step 1: Add reminders property**

Add to the ReminderList class after from_dict:

```python
@property
def reminders(self) -> Iterator[Reminder]:
    """
    Iterate incomplete reminders in this list.

    Yields:
        Reminder: Each incomplete reminder

    Raises:
        RuntimeError: If list was not created by a client
    """
    if self._client is None:
        raise RuntimeError("ReminderList not associated with a client")
    yield from self._client._iter_reminders(self.id, include_completed=False)
```

**Step 2: Add all_reminders property**

```python
@property
def all_reminders(self) -> Iterator[Reminder]:
    """
    Iterate all reminders including completed.

    Yields:
        Reminder: Each reminder in the list

    Raises:
        RuntimeError: If list was not created by a client
    """
    if self._client is None:
        raise RuntimeError("ReminderList not associated with a client")
    yield from self._client._iter_reminders(self.id, include_completed=True)
```

**Step 3: Add get_reminders method**

```python
def get_reminders(self, include_completed: bool = False) -> list[Reminder]:
    """
    Get reminders with explicit control.

    Args:
        include_completed: Whether to include completed reminders

    Returns:
        list[Reminder]: Reminders in this list

    Raises:
        RuntimeError: If list was not created by a client
    """
    if self._client is None:
        raise RuntimeError("ReminderList not associated with a client")
    return self._client.get_reminders(self.id, include_completed=include_completed)
```

**Step 4: Add create_reminder method**

```python
def create_reminder(
    self,
    title: str,
    notes: Optional[str] = None,
    priority: Optional[int] = None,
    due_date: Optional[datetime] = None,
) -> Reminder:
    """
    Create a new reminder in this list.

    Args:
        title: The reminder title
        notes: Optional notes/description
        priority: Priority level (0=none, 1=high, 5=medium, 9=low)
        due_date: Optional due date

    Returns:
        Reminder: The created reminder

    Raises:
        RuntimeError: If list was not created by a client
    """
    if self._client is None:
        raise RuntimeError("ReminderList not associated with a client")
    return self._client.create_reminder(self.id, title, notes=notes, priority=priority, due_date=due_date)
```

**Step 5: Commit**

```bash
git add python/icloudbridge.py
git commit -m "feat(python): add ReminderList interactive properties and methods"
```

---

## Task 10: Add Reminder Mutation Methods

**Files:**
- Modify: `python/icloudbridge.py` (Reminder class)

**Step 1: Add save method**

Add to the Reminder class after from_dict:

```python
def save(self) -> "Reminder":
    """
    Save changes to this reminder.

    Sends current values of title, notes, priority, due_date to the API.

    Returns:
        Reminder: The updated reminder (self is also updated)

    Raises:
        RuntimeError: If reminder was not created by a client
    """
    if self._client is None:
        raise RuntimeError("Reminder not associated with a client")
    updated = self._client.update_reminder(
        self.id,
        title=self.title,
        notes=self.notes,
        priority=self.priority,
        due_date=self.due_date,
    )
    # Update self with response
    self.title = updated.title
    self.notes = updated.notes
    self.is_completed = updated.is_completed
    self.priority = updated.priority
    self.due_date = updated.due_date
    self.completion_date = updated.completion_date
    return self
```

**Step 2: Add complete method**

```python
def complete(self) -> "Reminder":
    """
    Mark this reminder as completed.

    Returns:
        Reminder: The updated reminder (self is also updated)

    Raises:
        RuntimeError: If reminder was not created by a client
    """
    if self._client is None:
        raise RuntimeError("Reminder not associated with a client")
    updated = self._client.complete_reminder(self.id)
    self.is_completed = updated.is_completed
    self.completion_date = updated.completion_date
    return self
```

**Step 3: Add uncomplete method**

```python
def uncomplete(self) -> "Reminder":
    """
    Mark this reminder as not completed.

    Returns:
        Reminder: The updated reminder (self is also updated)

    Raises:
        RuntimeError: If reminder was not created by a client
    """
    if self._client is None:
        raise RuntimeError("Reminder not associated with a client")
    updated = self._client.uncomplete_reminder(self.id)
    self.is_completed = updated.is_completed
    self.completion_date = updated.completion_date
    return self
```

**Step 4: Add delete method**

```python
def delete(self) -> None:
    """
    Permanently delete this reminder.

    After calling this method, the reminder object should not be used.

    Raises:
        RuntimeError: If reminder was not created by a client
    """
    if self._client is None:
        raise RuntimeError("Reminder not associated with a client")
    self._client.delete_reminder(self.id)
```

**Step 5: Commit**

```bash
git add python/icloudbridge.py
git commit -m "feat(python): add Reminder mutation methods"
```

---

## Task 11: Update Documentation

**Files:**
- Modify: `python/docs/quickstart.rst`
- Modify: `python/docs/photos.rst`
- Modify: `python/docs/reminders.rst`

**Step 1: Update quickstart.rst with interactive example**

Add a new section after "Error Handling":

```rst
Interactive Objects
-------------------

Domain objects returned by the client are interactive. You can access related
data directly from the object:

.. code-block:: python

   # Get an album and iterate its photos
   album = client.get_albums()[0]
   for photo in album.photos:
       print(photo.filename)

   # Get a reminder list and create a reminder
   lst = client.get_lists()[0]
   reminder = lst.create_reminder("Buy milk")

   # Complete and delete
   reminder.complete()
   reminder.delete()

See :doc:`photos` and :doc:`reminders` for complete examples.
```

**Step 2: Update photos.rst with interactive examples**

Add after "Listing Albums" section:

```rst
Interactive Album Access
~~~~~~~~~~~~~~~~~~~~~~~~

Albums provide direct access to their photos:

.. code-block:: python

   album = client.get_albums()[0]

   # Iterate all photos (lazy, auto-paginates)
   for photo in album.photos:
       print(photo.filename)

   # Iterate only videos
   for video in album.videos:
       print(video.filename)

   # Iterate only Live Photos
   for live in album.live_photos:
       print(live.filename)

   # Explicit pagination when needed
   batch, total = album.get_photos(limit=50, offset=100)
```

Add after "Downloading Images" section:

```rst
Interactive Photo Downloads
~~~~~~~~~~~~~~~~~~~~~~~~~~~

Photos provide direct download access:

.. code-block:: python

   photo = next(album.photos)

   # Simple property access
   small_thumb = photo.thumbnail_small
   medium_thumb = photo.thumbnail_medium
   full_image = photo.image

   # For videos and Live Photos
   if photo.is_video or photo.is_live_photo:
       video_data = photo.video

   # Explicit control when needed
   img = photo.get_image(wait=True, max_retries=20)
```

**Step 3: Update reminders.rst with interactive examples**

Add after "Getting Reminders" section:

```rst
Interactive List Access
~~~~~~~~~~~~~~~~~~~~~~~

Reminder lists provide direct access to their reminders:

.. code-block:: python

   lst = client.get_lists()[0]

   # Iterate incomplete reminders
   for r in lst.reminders:
       print(r.title)

   # Iterate all including completed
   for r in lst.all_reminders:
       print(r.title, r.is_completed)

   # Create a reminder directly
   reminder = lst.create_reminder("Buy groceries", priority=1)
```

Add after "Updating Reminders" section:

```rst
Interactive Reminder Updates
~~~~~~~~~~~~~~~~~~~~~~~~~~~~

Reminders support direct mutation:

.. code-block:: python

   reminder = next(lst.reminders)

   # Modify and save
   reminder.title = "Updated title"
   reminder.priority = 5
   reminder.save()

   # Complete/uncomplete
   reminder.complete()
   reminder.uncomplete()

   # Delete
   reminder.delete()
```

**Step 4: Commit**

```bash
git add python/docs/
git commit -m "docs(python): add interactive object usage examples"
```

---

## Task 12: Update Module Docstring

**Files:**
- Modify: `python/icloudbridge.py:1-30`

**Step 1: Update module docstring with interactive examples**

```python
"""
iCloud Bridge Python Client

A Python client library for interacting with the iCloud Bridge REST API.
Uses only the standard library - no external dependencies required.

Basic Usage:
    from icloudbridge import iCloudBridge

    client = iCloudBridge()  # defaults to localhost:31337

    # List all available reminder lists
    lists = client.get_lists()

    # Get reminders from a specific list
    reminders = client.get_reminders(lists[0].id)

Interactive Objects:
    Domain objects are interactive and can make API calls directly:

    # Albums provide access to photos
    album = client.get_albums()[0]
    for photo in album.photos:  # auto-paginates
        print(photo.filename)
        thumb = photo.thumbnail_medium  # download thumbnail

    # Reminder lists provide access to reminders
    lst = client.get_lists()[0]
    reminder = lst.create_reminder("Buy milk")
    reminder.complete()
    reminder.delete()
"""
```

**Step 2: Commit**

```bash
git add python/icloudbridge.py
git commit -m "docs(python): update module docstring with interactive examples"
```

---

## Task 13: Rebuild Sphinx Documentation

**Step 1: Build documentation**

```bash
cd /Volumes/Chonker/Development/icloudbridge/.worktrees/interactive-python-client
./scripts/serve-docs.sh build
```

**Step 2: Verify build succeeds with no new errors**

Expected: Build completes with only the existing duplicate object warnings.

**Step 3: Commit any generated changes (if applicable)**

No commit needed - built files are in .gitignore.

---

## Summary

After completing all tasks, the Python client will support:

| Object | New Properties | New Methods |
|--------|---------------|-------------|
| Album | photos, videos, live_photos | get_photos() |
| Photo | thumbnail_small, thumbnail_medium, image, video, is_video, is_live_photo | get_thumbnail(), get_image() |
| ReminderList | reminders, all_reminders | get_reminders(), create_reminder() |
| Reminder | — | save(), complete(), uncomplete(), delete() |

All existing client methods remain unchanged for backward compatibility.
