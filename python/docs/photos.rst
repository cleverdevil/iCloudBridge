Working with Photos
===================

This guide covers how to use the Python client to access iCloud Photos.

Listing Albums
--------------

Get all available albums:

.. code-block:: python

   from icloudbridge import iCloudBridge

   client = iCloudBridge()

   albums = client.get_albums()
   for album in albums:
       print(f"{album.title}")
       print(f"  Type: {album.album_type}")
       print(f"  Photos: {album.photo_count}")
       print(f"  Videos: {album.video_count}")
       if album.start_date:
           print(f"  Date range: {album.start_date} to {album.end_date}")

Get a specific album:

.. code-block:: python

   album = client.get_album("ALB123-456")
   print(f"{album.title}: {album.photo_count} photos")

Album Types
~~~~~~~~~~~

The ``album_type`` field indicates the type of album:

==========  ===========
Type        Description
==========  ===========
user        User-created album
smart       Smart album (e.g., "Favorites", "Videos")
shared      Shared album
==========  ===========

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

Browsing Photos
---------------

Get photos with pagination:

.. code-block:: python

   # Get first 50 photos
   photos, total = client.get_photos(album.id, limit=50)
   print(f"Got {len(photos)} of {total} total photos")

   # Get next page
   photos, total = client.get_photos(album.id, limit=50, offset=50)

Sort options:

.. code-block:: python

   # Sort by date (newest first)
   photos, _ = client.get_photos(album.id, sort="date-desc")

   # Sort by date (oldest first)
   photos, _ = client.get_photos(album.id, sort="date-asc")

   # Album order (default)
   photos, _ = client.get_photos(album.id, sort="album")

Filter by media type:

.. code-block:: python

   # Only photos
   photos, _ = client.get_photos(album.id, media_type="photo")

   # Only videos
   videos, _ = client.get_photos(album.id, media_type="video")

   # Only Live Photos
   live_photos, _ = client.get_photos(album.id, media_type="live")

Photo Metadata
--------------

Get detailed metadata for a photo:

.. code-block:: python

   photo = client.get_photo(photos[0].id)

   print(f"Filename: {photo.filename}")
   print(f"Size: {photo.width}x{photo.height}")
   print(f"Type: {photo.media_type}")  # photo, video, or livePhoto
   print(f"Date: {photo.creation_date}")
   print(f"Favorite: {photo.is_favorite}")
   print(f"File size: {photo.file_size} bytes")

Downloading Images
------------------

Download a thumbnail:

.. code-block:: python

   # Medium size (800px) - default
   thumbnail = client.get_thumbnail(photo.id)

   # Small size (200px)
   thumbnail = client.get_thumbnail(photo.id, size="small")

   # Save to file
   with open("thumb.jpg", "wb") as f:
       f.write(thumbnail)

Download full-resolution image:

.. code-block:: python

   # May need to download from iCloud first
   image = client.get_image(photo.id, wait=True)

   with open("photo.jpg", "wb") as f:
       f.write(image)

.. note::

   If the photo is stored in iCloud and not locally available, the API may
   return a 202 status while downloading. Use ``wait=True`` to block until
   the download completes.

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

Handling iCloud Downloads
~~~~~~~~~~~~~~~~~~~~~~~~~

When ``wait=False`` (default), the client will automatically retry if the
image is being downloaded from iCloud:

.. code-block:: python

   # Retry up to 10 times (default)
   image = client.get_image(photo.id)

   # Custom retry count
   image = client.get_image(photo.id, max_retries=20)

Working with Videos
-------------------

Download a video file:

.. code-block:: python

   if photo.media_type == "video":
       video = client.get_video(photo.id)
       with open("video.mov", "wb") as f:
           f.write(video)

Working with Live Photos
------------------------

Live Photos have both a still image and a motion video component:

.. code-block:: python

   if photo.media_type == "livePhoto":
       # Get the still image
       image = client.get_image(photo.id)
       with open("photo.jpg", "wb") as f:
           f.write(image)

       # Get the motion video
       video = client.get_live_video(photo.id)
       with open("live.mov", "wb") as f:
           f.write(video)

Example: Download All Photos
----------------------------

Download all photos from an album:

.. code-block:: python

   import os

   album = client.get_albums()[0]
   output_dir = f"downloads/{album.title}"
   os.makedirs(output_dir, exist_ok=True)

   offset = 0
   limit = 100

   while True:
       photos, total = client.get_photos(album.id, limit=limit, offset=offset)

       if not photos:
           break

       for photo in photos:
           filename = photo.filename or f"{photo.id}.jpg"
           filepath = os.path.join(output_dir, filename)

           print(f"Downloading {filename}...")

           try:
               if photo.media_type == "video":
                   data = client.get_video(photo.id)
               else:
                   data = client.get_image(photo.id, wait=True)

               with open(filepath, "wb") as f:
                   f.write(data)
           except Exception as e:
               print(f"Failed to download {filename}: {e}")

       offset += limit
       print(f"Progress: {min(offset, total)}/{total}")

   print(f"Downloaded {total} photos to {output_dir}")

Example: Find Large Photos
--------------------------

Find photos larger than a certain size:

.. code-block:: python

   large_photos = []
   offset = 0
   limit = 100
   min_size = 10 * 1024 * 1024  # 10 MB

   while True:
       photos, total = client.get_photos(album.id, limit=limit, offset=offset)
       if not photos:
           break

       for photo in photos:
           if photo.file_size and photo.file_size > min_size:
               large_photos.append(photo)

       offset += limit

   print(f"Found {len(large_photos)} photos larger than 10 MB:")
   for photo in large_photos:
       size_mb = photo.file_size / (1024 * 1024)
       print(f"  {photo.filename}: {size_mb:.1f} MB")
