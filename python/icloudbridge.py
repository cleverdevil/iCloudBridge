"""
iCloud Bridge Python Client

A Python client library for interacting with the iCloud Bridge REST API.
Uses only the standard library - no external dependencies required.

Usage:
    from icloudbridge import iCloudBridge

    client = iCloudBridge()  # defaults to localhost:31337

    # List all available reminder lists
    lists = client.get_lists()

    # Get reminders from a specific list
    reminders = client.get_reminders(lists[0].id)

    # Create a new reminder
    reminder = client.create_reminder(
        list_id=lists[0].id,
        title="Buy milk",
        notes="2% preferred"
    )

    # Update a reminder
    client.update_reminder(reminder.id, is_completed=True)

    # Delete a reminder
    client.delete_reminder(reminder.id)
"""

from __future__ import annotations

import json
import urllib.request
import urllib.error
import urllib.parse
from dataclasses import dataclass
from datetime import datetime
from typing import Optional


@dataclass
class ReminderList:
    """Represents a Reminders list."""
    id: str
    title: str
    color: Optional[str]
    reminder_count: int

    @classmethod
    def from_dict(cls, data: dict) -> ReminderList:
        return cls(
            id=data["id"],
            title=data["title"],
            color=data.get("color"),
            reminder_count=data["reminderCount"],
        )


@dataclass
class Reminder:
    """Represents a single reminder."""
    id: str
    title: str
    notes: Optional[str]
    is_completed: bool
    priority: int
    due_date: Optional[datetime]
    completion_date: Optional[datetime]
    list_id: str

    @classmethod
    def from_dict(cls, data: dict) -> Reminder:
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
        )


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
    """

    def __init__(self, host: str = "localhost", port: int = 31337):
        self.base_url = f"http://{host}:{port}/api/v1"
        self._health_url = f"http://{host}:{port}/health"

    def _request(
        self,
        method: str,
        path: str,
        data: Optional[dict] = None,
    ) -> Optional[dict | list]:
        """Make an HTTP request to the API."""
        url = f"{self.base_url}{path}"

        headers = {"Content-Type": "application/json"}
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

    # List operations

    def get_lists(self) -> list[ReminderList]:
        """
        Get all available reminder lists.

        Returns:
            list[ReminderList]: All reminder lists configured in iCloud Bridge
        """
        data = self._request("GET", "/lists")
        return [ReminderList.from_dict(item) for item in data]

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
        return ReminderList.from_dict(data)

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
        return [Reminder.from_dict(item) for item in data]

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
        return Reminder.from_dict(data)

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
        return Reminder.from_dict(data)

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
        return Reminder.from_dict(data)

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

        lists = client.get_lists()
        print(f"\nFound {len(lists)} reminder lists:")
        for lst in lists:
            print(f"  - {lst.title} ({lst.reminder_count} reminders)")

        if lists:
            # Get incomplete reminders (default)
            reminders = client.get_reminders(lists[0].id)
            print(f"\nIncomplete reminders in '{lists[0].title}':")
            for r in reminders:
                status = "[x]" if r.is_completed else "[ ]"
                print(f"  {status} {r.title}")

            # Get all reminders including completed
            all_reminders = client.get_reminders(lists[0].id, include_completed=True)
            print(f"\nAll reminders (including completed): {len(all_reminders)} total")

    except iCloudBridgeError as e:
        print(f"Error: {e}")
