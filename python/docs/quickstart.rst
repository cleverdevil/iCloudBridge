Quick Start
===========

This guide will help you get started with the iCloud Bridge Python client.

Prerequisites
-------------

Before using the Python client, ensure that:

1. **iCloud Bridge is running** - The macOS app must be running with the server started
2. **Permissions are granted** - The app needs access to Reminders and/or Photos
3. **Lists/Albums are selected** - Configure which data to expose in the app settings

Installation
------------

Install the client from the iCloud Bridge repository:

.. code-block:: bash

   pip install ./python

Or install in development mode:

.. code-block:: bash

   pip install -e ./python

Connecting
----------

By default, the client connects to ``localhost:31337``:

.. code-block:: python

   from icloudbridge import iCloudBridge

   client = iCloudBridge()

To connect to a different host or port:

.. code-block:: python

   client = iCloudBridge(host="192.168.1.100", port=8080)

Or use the convenience function:

.. code-block:: python

   from icloudbridge import connect

   client = connect(port=8080)

Health Check
------------

Verify the server is running:

.. code-block:: python

   status = client.health()
   print(status)  # {'status': 'ok'}

Error Handling
--------------

The client raises specific exceptions for different error conditions:

.. code-block:: python

   from icloudbridge import (
       iCloudBridge,
       iCloudBridgeError,  # Base exception
       NotFoundError,      # 404 responses
       APIError,           # Other HTTP errors
   )

   client = iCloudBridge()

   try:
       reminder = client.get_reminder("invalid-id")
   except NotFoundError:
       print("Reminder not found")
   except APIError as e:
       print(f"API error {e.status_code}: {e.reason}")
   except iCloudBridgeError as e:
       print(f"Connection error: {e}")

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

Next Steps
----------

- :doc:`reminders` - Learn how to work with Reminders
- :doc:`photos` - Learn how to work with Photos
- :doc:`api` - Full API reference
