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

    # Iterate albums and their photos
    for album in client.albums:
        print(album.title)
        for photo in album.photos:  # auto-paginates
            print(photo.filename)
            thumb = photo.thumbnail_medium  # download thumbnail

    # Iterate reminder lists and manage reminders
    for lst in client.reminder_lists:
        print(lst.title)
        for reminder in lst.reminders:
            print(reminder.title)

    # Create and manage reminders
    lst = next(client.reminder_lists)
    reminder = lst.create_reminder("Buy milk")
    reminder.complete()
    reminder.delete()
"""

from __future__ import annotations

import json
import urllib.request
import urllib.error
import urllib.parse
from dataclasses import dataclass, field
from datetime import datetime
from typing import Iterator, Optional


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

    @property
    def videos(self) -> Iterator[Photo]:
        """
        Iterate only videos in the album, auto-paginating.

        Yields:
            Photo: Each video in the album

        Raises:
            RuntimeError: If album was not created by a client
        """
        if self._client is None:
            raise RuntimeError("Album not associated with a client")
        yield from self._client._iter_photos(self.id, media_type="video")

    @property
    def live_photos(self) -> Iterator[Photo]:
        """
        Iterate only Live Photos in the album, auto-paginating.

        Yields:
            Photo: Each Live Photo in the album

        Raises:
            RuntimeError: If album was not created by a client
        """
        if self._client is None:
            raise RuntimeError("Album not associated with a client")
        yield from self._client._iter_photos(self.id, media_type="live")

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

    @property
    def is_video(self) -> bool:
        """Check if this is a video."""
        return self.media_type == "video"

    @property
    def is_live_photo(self) -> bool:
        """Check if this is a Live Photo."""
        return self.media_type == "livePhoto"

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

    @property
    def video(self) -> bytes:
        """
        Get video data. Works for videos and Live Photos.

        For Live Photos, returns the motion video component.

        Returns:
            bytes: Video data

        Raises:
            RuntimeError: If photo was not created by a client
            ValueError: If this is not a video or Live Photo
        """
        if self._client is None:
            raise RuntimeError("Photo not associated with a client")
        if self.media_type == "video":
            return self._client.get_video(self.id)
        elif self.media_type == "livePhoto":
            return self._client.get_live_video(self.id)
        else:
            raise ValueError(
                f"Cannot get video for media type '{self.media_type}'. "
                "Only videos and Live Photos have video data."
            )

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


class iCloudBridgeError(Exception):
    """Base exception for iCloud Bridge errors."""
    pass


class NotFoundError(iCloudBridgeError):
    """Raised when a resource is not found."""
    pass


class APIError(iCloudBridgeError):
    """Raised when the API returns an error."""
    def __init__(self, status_code: int, reason: str):
        self.status_code = status_code
        self.reason = reason
        super().__init__(f"API error {status_code}: {reason}")


def _parse_iso_date(date_str: str) -> datetime:
    """Parse an ISO 8601 date string."""
    # Handle various ISO formats
    date_str = date_str.replace("Z", "+00:00")
    try:
        return datetime.fromisoformat(date_str)
    except ValueError:
        # Fallback for formats without timezone
        if "." in date_str:
            return datetime.strptime(date_str.split(".")[0], "%Y-%m-%dT%H:%M:%S")
        return datetime.strptime(date_str, "%Y-%m-%dT%H:%M:%S")


def _format_iso_date(dt: datetime) -> str:
    """Format a datetime as ISO 8601."""
    return dt.strftime("%Y-%m-%dT%H:%M:%SZ")


class iCloudBridge:
    """
    Client for the iCloud Bridge REST API.

    Args:
        host: The hostname of the iCloud Bridge server (default: localhost)
        port: The port number (default: 31337)
        token: Bearer token for authentication (required for remote connections)
    """

    def __init__(self, host: str = "localhost", port: int = 31337, token: Optional[str] = None):
        self.base_url = f"http://{host}:{port}/api/v1"
        self._health_url = f"http://{host}:{port}/health"
        self._token = token

    def _request(
        self,
        method: str,
        path: str,
        data: Optional[dict] = None,
    ) -> Optional[dict | list]:
        """Make an HTTP request to the API."""
        url = f"{self.base_url}{path}"

        headers = {"Content-Type": "application/json"}
        if self._token:
            headers["Authorization"] = f"Bearer {self._token}"
        body = None
        if data is not None:
            body = json.dumps(data).encode("utf-8")

        request = urllib.request.Request(url, data=body, headers=headers, method=method)

        try:
            with urllib.request.urlopen(request) as response:
                if response.status == 204:
                    return None
                return json.loads(response.read().decode("utf-8"))
        except urllib.error.HTTPError as e:
            if e.code == 404:
                raise NotFoundError(f"Resource not found: {path}")
            try:
                error_body = json.loads(e.read().decode("utf-8"))
                reason = error_body.get("reason", str(e))
            except (json.JSONDecodeError, UnicodeDecodeError):
                reason = str(e)
            raise APIError(e.code, reason)
        except urllib.error.URLError as e:
            raise iCloudBridgeError(f"Connection failed: {e.reason}")

    # Health check

    def health(self) -> dict:
        """
        Check if the server is running.

        Returns:
            dict: Health status (e.g., {"status": "ok"})
        """
        request = urllib.request.Request(self._health_url)
        try:
            with urllib.request.urlopen(request) as response:
                return json.loads(response.read().decode("utf-8"))
        except urllib.error.URLError as e:
            raise iCloudBridgeError(f"Health check failed: {e}")

    # Collection properties

    @property
    def albums(self) -> Iterator[Album]:
        """
        Iterate all available photo albums.

        Yields:
            Album: Each album configured in iCloud Bridge

        Example:
            for album in client.albums:
                print(album.title)
        """
        yield from self.get_albums()

    @property
    def reminder_lists(self) -> Iterator[ReminderList]:
        """
        Iterate all available reminder lists.

        Yields:
            ReminderList: Each reminder list configured in iCloud Bridge

        Example:
            for lst in client.reminder_lists:
                print(lst.title)
        """
        yield from self.get_lists()

    # List operations

    def get_lists(self) -> list[ReminderList]:
        """
        Get all available reminder lists.

        Returns:
            list[ReminderList]: All reminder lists configured in iCloud Bridge
        """
        data = self._request("GET", "/lists")
        return [ReminderList.from_dict(item, self) for item in data]

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

    # Reminder operations

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

    def delete_reminder(self, reminder_id: str) -> None:
        """
        Delete a reminder.

        Args:
            reminder_id: The reminder to delete

        Raises:
            NotFoundError: If the reminder is not found
        """
        self._request("DELETE", f"/reminders/{urllib.parse.quote(reminder_id)}")

    def complete_reminder(self, reminder_id: str) -> Reminder:
        """
        Mark a reminder as completed.

        This is a convenience method that calls update_reminder with is_completed=True.

        Args:
            reminder_id: The reminder to complete

        Returns:
            Reminder: The updated reminder
        """
        return self.update_reminder(reminder_id, is_completed=True)

    def uncomplete_reminder(self, reminder_id: str) -> Reminder:
        """
        Mark a reminder as not completed.

        This is a convenience method that calls update_reminder with is_completed=False.

        Args:
            reminder_id: The reminder to uncomplete

        Returns:
            Reminder: The updated reminder
        """
        return self.update_reminder(reminder_id, is_completed=False)

    # Album operations

    def get_albums(self) -> list[Album]:
        """
        Get all available photo albums.

        Returns:
            list[Album]: All albums configured in iCloud Bridge
        """
        data = self._request("GET", "/albums")
        return [Album.from_dict(item, self) for item in data]

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

    def get_thumbnail(self, photo_id: str, size: str = "medium") -> bytes:
        """
        Get a thumbnail image.

        Args:
            photo_id: The photo identifier
            size: Thumbnail size - "small" (200px) or "medium" (800px)

        Returns:
            bytes: JPEG image data

        Raises:
            NotFoundError: If the photo is not found
        """
        path = f"/photos/{urllib.parse.quote(photo_id)}/thumbnail"
        if size != "medium":
            path += f"?size={size}"

        url = f"{self.base_url}{path}"
        request = urllib.request.Request(url)

        try:
            with urllib.request.urlopen(request) as response:
                return response.read()
        except urllib.error.HTTPError as e:
            if e.code == 404:
                raise NotFoundError(f"Photo not found: {photo_id}")
            raise APIError(e.code, str(e))
        except urllib.error.URLError as e:
            raise iCloudBridgeError(f"Connection failed: {e.reason}")

    def get_image(self, photo_id: str, wait: bool = False, max_retries: int = 10) -> bytes:
        """
        Get full-resolution image.

        Args:
            photo_id: The photo identifier
            wait: If True, block until download completes; if False, poll with retries
            max_retries: Maximum retry attempts for non-blocking mode (default: 10)

        Returns:
            bytes: Image data

        Raises:
            NotFoundError: If the photo is not found
            iCloudBridgeError: If download fails or times out
        """
        import time

        path = f"/photos/{urllib.parse.quote(photo_id)}/image"
        if wait:
            path += "?wait=true"

        url = f"{self.base_url}{path}"

        for attempt in range(max_retries if not wait else 1):
            request = urllib.request.Request(url)

            try:
                with urllib.request.urlopen(request) as response:
                    return response.read()
            except urllib.error.HTTPError as e:
                if e.code == 404:
                    raise NotFoundError(f"Photo not found: {photo_id}")
                elif e.code == 202:
                    # Download pending, retry
                    if wait:
                        raise iCloudBridgeError("Image download pending despite wait=true")

                    # Parse retry-after header
                    retry_after = int(e.headers.get("Retry-After", "5"))

                    if attempt < max_retries - 1:
                        time.sleep(retry_after)
                        continue
                    else:
                        raise iCloudBridgeError(f"Image download timed out after {max_retries} retries")
                else:
                    raise APIError(e.code, str(e))
            except urllib.error.URLError as e:
                raise iCloudBridgeError(f"Connection failed: {e.reason}")

        raise iCloudBridgeError("Image download failed")

    def get_video(self, photo_id: str) -> bytes:
        """
        Get video file for a video or Live Photo.

        Args:
            photo_id: The photo identifier

        Returns:
            bytes: Video data

        Raises:
            NotFoundError: If the photo is not found
            APIError: If the photo is not a video
        """
        path = f"/photos/{urllib.parse.quote(photo_id)}/video"
        url = f"{self.base_url}{path}"
        request = urllib.request.Request(url)

        try:
            with urllib.request.urlopen(request) as response:
                return response.read()
        except urllib.error.HTTPError as e:
            if e.code == 404:
                raise NotFoundError(f"Photo not found: {photo_id}")
            raise APIError(e.code, str(e))
        except urllib.error.URLError as e:
            raise iCloudBridgeError(f"Connection failed: {e.reason}")

    def get_live_video(self, photo_id: str) -> bytes:
        """
        Get motion video component for a Live Photo.

        Args:
            photo_id: The photo identifier (must be a Live Photo)

        Returns:
            bytes: Video data

        Raises:
            NotFoundError: If the photo is not found
            APIError: If the photo is not a Live Photo
        """
        path = f"/photos/{urllib.parse.quote(photo_id)}/live-video"
        url = f"{self.base_url}{path}"
        request = urllib.request.Request(url)

        try:
            with urllib.request.urlopen(request) as response:
                return response.read()
        except urllib.error.HTTPError as e:
            if e.code == 404:
                raise NotFoundError(f"Photo not found: {photo_id}")
            raise APIError(e.code, str(e))
        except urllib.error.URLError as e:
            raise iCloudBridgeError(f"Connection failed: {e.reason}")


# Convenience function for quick access
def connect(host: str = "localhost", port: int = 31337) -> iCloudBridge:
    """
    Create a new iCloud Bridge client connection.

    Args:
        host: The hostname (default: localhost)
        port: The port number (default: 31337)

    Returns:
        iCloudBridge: A connected client instance
    """
    return iCloudBridge(host=host, port=port)


if __name__ == "__main__":
    # Simple demo/test
    client = iCloudBridge()

    try:
        health = client.health()
        print(f"Server status: {health}")

        # Test Reminders
        lists = client.get_lists()
        print(f"\nFound {len(lists)} reminder lists:")
        for lst in lists:
            print(f"  - {lst.title} ({lst.reminder_count} reminders)")

        if lists:
            reminders = client.get_reminders(lists[0].id)
            print(f"\nIncomplete reminders in '{lists[0].title}':")
            for r in reminders:
                status = "[x]" if r.is_completed else "[ ]"
                print(f"  {status} {r.title}")

        # Test Photos
        albums = client.get_albums()
        print(f"\nFound {len(albums)} photo albums:")
        for album in albums:
            print(f"  - {album.title} ({album.photo_count} photos, {album.video_count} videos)")

        if albums:
            photos, total = client.get_photos(albums[0].id, limit=5)
            print(f"\nFirst 5 photos in '{albums[0].title}' (total: {total}):")
            for photo in photos:
                print(f"  - {photo.filename or photo.id} ({photo.width}x{photo.height}, {photo.media_type})")

    except iCloudBridgeError as e:
        print(f"Error: {e}")
