Working with Reminders
======================

This guide covers how to use the Python client to manage iCloud Reminders.

Listing Reminder Lists
----------------------

Get all available reminder lists:

.. code-block:: python

   from icloudbridge import iCloudBridge

   client = iCloudBridge()

   lists = client.get_lists()
   for lst in lists:
       print(f"{lst.title}")
       print(f"  ID: {lst.id}")
       print(f"  Color: {lst.color}")
       print(f"  Reminders: {lst.reminder_count}")

Get a specific list by ID:

.. code-block:: python

   lst = client.get_list("ABC123-DEF456")
   print(f"{lst.title}: {lst.reminder_count} reminders")

Getting Reminders
-----------------

By default, only incomplete reminders are returned:

.. code-block:: python

   reminders = client.get_reminders(lst.id)
   for r in reminders:
       print(f"[ ] {r.title}")
       if r.due_date:
           print(f"    Due: {r.due_date}")

Include completed reminders:

.. code-block:: python

   all_reminders = client.get_reminders(lst.id, include_completed=True)
   for r in all_reminders:
       status = "[x]" if r.is_completed else "[ ]"
       print(f"{status} {r.title}")

Get a specific reminder:

.. code-block:: python

   reminder = client.get_reminder("REM123-456")
   print(f"Title: {reminder.title}")
   print(f"Notes: {reminder.notes}")
   print(f"Completed: {reminder.is_completed}")

Creating Reminders
------------------

Create a simple reminder:

.. code-block:: python

   reminder = client.create_reminder(
       list_id=lst.id,
       title="Buy groceries"
   )
   print(f"Created: {reminder.id}")

Create a reminder with all options:

.. code-block:: python

   from datetime import datetime, timedelta

   reminder = client.create_reminder(
       list_id=lst.id,
       title="Call dentist",
       notes="Schedule cleaning appointment",
       priority=1,  # High priority (1=high, 5=medium, 9=low, 0=none)
       due_date=datetime.now() + timedelta(days=7)
   )

Updating Reminders
------------------

Update any fields (only provided fields are changed):

.. code-block:: python

   updated = client.update_reminder(
       reminder.id,
       title="Call dentist office",
       notes="Ask about Saturday appointments",
       priority=5  # Change to medium priority
   )

Mark as complete or incomplete:

.. code-block:: python

   # Mark complete
   client.complete_reminder(reminder.id)

   # Mark incomplete
   client.uncomplete_reminder(reminder.id)

   # Or use update_reminder directly
   client.update_reminder(reminder.id, is_completed=True)

Deleting Reminders
------------------

Permanently delete a reminder:

.. code-block:: python

   client.delete_reminder(reminder.id)

.. warning::

   Deletion is permanent and cannot be undone.

Priority Levels
---------------

The priority field uses these values:

=========  ===========
Value      Meaning
=========  ===========
0          None
1          High (!)
5          Medium (!!)
9          Low (!!!)
=========  ===========

Example: Bulk Operations
------------------------

Complete all reminders in a list:

.. code-block:: python

   reminders = client.get_reminders(lst.id)
   for r in reminders:
       client.complete_reminder(r.id)
       print(f"Completed: {r.title}")

Find overdue reminders:

.. code-block:: python

   from datetime import datetime

   now = datetime.now()
   reminders = client.get_reminders(lst.id)

   overdue = [r for r in reminders if r.due_date and r.due_date < now]
   print(f"Found {len(overdue)} overdue reminders:")
   for r in overdue:
       print(f"  - {r.title} (due {r.due_date})")
