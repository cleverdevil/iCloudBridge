"""
iCloud Bridge Python Client Library

A Python client for interacting with the iCloud Bridge REST API.
"""

from .icloudbridge import (
    iCloudBridge,
    connect,
    Album,
    Photo,
    Reminder,
    ReminderList,
    iCloudBridgeError,
    NotFoundError,
    APIError,
)

__all__ = [
    "iCloudBridge",
    "connect",
    "Album",
    "Photo",
    "Reminder",
    "ReminderList",
    "iCloudBridgeError",
    "NotFoundError",
    "APIError",
]

__version__ = "1.0.0"
