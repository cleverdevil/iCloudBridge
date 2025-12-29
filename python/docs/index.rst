iCloud Bridge Python Client
===========================

A Python client library for the iCloud Bridge REST API. Access your iCloud
Reminders and Photos programmatically from Python.

.. note::

   This library requires the iCloud Bridge macOS application to be running.
   The API binds to localhost by default on port 31337.

Features
--------

- **Zero dependencies** - Uses only the Python standard library
- **Full API coverage** - Access all Reminders and Photos endpoints
- **Type hints** - Full type annotations for IDE support
- **Dataclasses** - Clean, typed data models

Installation
------------

.. code-block:: bash

   # From the iCloud Bridge repository
   pip install ./python

   # Or install in development mode
   pip install -e ./python

Quick Start
-----------

.. code-block:: python

   from icloudbridge import iCloudBridge

   # Connect to the local server
   client = iCloudBridge()

   # List reminder lists
   lists = client.get_lists()
   for lst in lists:
       print(f"{lst.title}: {lst.reminder_count} reminders")

   # Browse photo albums
   albums = client.get_albums()
   for album in albums:
       print(f"{album.title}: {album.photo_count} photos")

Contents
--------

.. toctree::
   :maxdepth: 2
   :caption: User Guide

   quickstart
   reminders
   photos

.. toctree::
   :maxdepth: 2
   :caption: API Reference

   api

Indices and tables
==================

* :ref:`genindex`
* :ref:`modindex`
* :ref:`search`
