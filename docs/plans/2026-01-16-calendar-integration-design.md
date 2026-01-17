# Calendar Integration Design

## Overview

Add iCloud Calendar support to iCloud Bridge, following the existing patterns established by Reminders and Photos. The implementation leverages Apple's EventKit framework for all calendar operations including recurrence handling.

## Scope

**In scope:**
- Calendar listing and selection
- Event CRUD operations
- Date range queries (EventKit expands recurring events automatically)
- Recurrence rules (daily, weekly, monthly, yearly)
- All-day and timed events
- Location, URL, notes
- Alarms/alerts
- Availability (busy/free/tentative)
- Travel time

**Out of scope:**
- Attendees (requires CalDAV server integration)
- Attachments (file handling complexity)

## API Endpoints

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/api/v1/calendars` | GET | List selected calendars |
| `/api/v1/calendars/{id}` | GET | Get a specific calendar |
| `/api/v1/calendars/{id}/events` | GET | Get events in date range (required: `start`, `end` params) |
| `/api/v1/calendars/{id}/events` | POST | Create a new event |
| `/api/v1/events/{id}` | GET | Get a specific event |
| `/api/v1/events/{id}` | PUT | Update an event |
| `/api/v1/events/{id}` | DELETE | Delete an event |

### Recurring Event Operations

For PUT and DELETE on recurring events, an optional `span` query parameter controls scope:
- `thisEvent` (default) - Only this occurrence
- `futureEvents` - This and all future occurrences
- `allEvents` - The entire series

Example: `DELETE /api/v1/events/{id}?span=futureEvents`

### Date Range Queries

Events must be queried with a date range:

```
GET /api/v1/calendars/{id}/events?start=2026-01-01T00:00:00Z&end=2026-01-31T23:59:59Z
```

EventKit automatically expands recurring events into individual occurrences within the range.

## Data Models

### CalendarDTO

```json
{
  "id": "string",
  "title": "string",
  "color": "#FF6B6B",
  "isReadOnly": false,
  "eventCount": 42
}
```

- `isReadOnly`: True for subscribed calendars, holidays, etc.
- `eventCount`: Number of events in next 30 days (for quick reference)

### EventDTO

```json
{
  "id": "string",
  "calendarId": "string",
  "title": "string",
  "notes": "string or null",
  "location": "string or null",
  "url": "string or null",
  "startDate": "2026-01-16T10:00:00Z",
  "endDate": "2026-01-16T11:00:00Z",
  "isAllDay": false,
  "availability": "busy",
  "travelTime": 15,
  "alarms": [
    {"offsetMinutes": -15},
    {"offsetMinutes": -60}
  ],
  "isRecurring": true,
  "recurrenceRule": {
    "frequency": "weekly",
    "interval": 1,
    "daysOfWeek": ["monday", "wednesday", "friday"],
    "dayOfMonth": null,
    "endDate": "2026-12-31T00:00:00Z",
    "occurrenceCount": null
  },
  "seriesId": "master-event-id"
}
```

- `availability`: One of "busy", "free", "tentative", "unavailable"
- `travelTime`: Minutes before event (null if not set)
- `alarms`: Array of alarm offsets in minutes (negative = before event)
- `isRecurring`: True if this event is part of a recurring series
- `recurrenceRule`: Present on master events or when creating recurring events
- `seriesId`: ID of master event (for occurrences of recurring events)

### RecurrenceRuleDTO

```json
{
  "frequency": "weekly",
  "interval": 2,
  "daysOfWeek": ["tuesday", "thursday"],
  "dayOfMonth": null,
  "endDate": null,
  "occurrenceCount": 10
}
```

- `frequency`: "daily", "weekly", "monthly", "yearly"
- `interval`: Every N periods (1 = every week, 2 = every other week)
- `daysOfWeek`: For weekly recurrence (null for other frequencies)
- `dayOfMonth`: For monthly recurrence on specific day (1-31)
- `endDate`: When recurrence stops (null = forever)
- `occurrenceCount`: Alternative to endDate - stop after N occurrences

### CreateEventDTO

```json
{
  "title": "Team Meeting",
  "notes": "Weekly sync",
  "location": "Conference Room A",
  "url": "https://meet.example.com/team",
  "startDate": "2026-01-20T10:00:00Z",
  "endDate": "2026-01-20T11:00:00Z",
  "isAllDay": false,
  "availability": "busy",
  "travelTime": 15,
  "alarms": [{"offsetMinutes": -15}],
  "recurrenceRule": {
    "frequency": "weekly",
    "interval": 1,
    "daysOfWeek": ["monday"]
  }
}
```

### UpdateEventDTO

Same as CreateEventDTO - all fields optional.

## Swift Implementation

### CalendarsService

```
Sources/iCloudBridge/Services/CalendarsService.swift
```

Uses the same `EKEventStore` pattern as RemindersService:

```swift
@MainActor
class CalendarsService: ObservableObject {
    private var eventStore = EKEventStore()

    @Published var authorizationStatus: EKAuthorizationStatus = .notDetermined
    @Published var allCalendars: [EKCalendar] = []

    func requestAccess() async -> Bool
    func loadCalendars()

    // Calendar operations
    func getCalendars(ids: [String]) -> [EKCalendar]
    func getCalendar(id: String) -> EKCalendar?

    // Event operations
    func getEvents(in calendar: EKCalendar, from: Date, to: Date) -> [EKEvent]
    func getEvent(id: String) -> EKEvent?
    func createEvent(in calendar: EKCalendar, title: String, ...) throws -> EKEvent
    func updateEvent(_ event: EKEvent, span: EKSpan, ...) throws -> EKEvent
    func deleteEvent(_ event: EKEvent, span: EKSpan) throws

    // DTO conversions
    func toDTO(_ calendar: EKCalendar, eventCount: Int) -> CalendarDTO
    func toDTO(_ event: EKEvent) -> EventDTO
}
```

### Controllers

```
Sources/iCloudBridge/API/CalendarsController.swift
```

Handles: `GET /calendars`, `GET /calendars/{id}`, `GET /calendars/{id}/events`, `POST /calendars/{id}/events`

```
Sources/iCloudBridge/API/EventsController.swift
```

Handles: `GET /events/{id}`, `PUT /events/{id}`, `DELETE /events/{id}`

### DTOs

```
Sources/iCloudBridge/Models/CalendarDTO.swift
Sources/iCloudBridge/Models/EventDTO.swift
```

### Route Registration

Update `ServerManager.swift` to register calendar routes:

```swift
try app.register(collection: CalendarsController(
    calendarsService: calendarsService,
    selectedCalendarIds: { UserDefaults.standard.stringArray(forKey: "selectedCalendarIds") ?? [] }
))

try app.register(collection: EventsController(
    calendarsService: calendarsService,
    selectedCalendarIds: { UserDefaults.standard.stringArray(forKey: "selectedCalendarIds") ?? [] }
))
```

### UI Updates

1. **Onboarding**: Add calendar permission request step
2. **Settings**: Add calendar selection view (similar to reminder list selection)
3. **UserDefaults**: Store `selectedCalendarIds` array

## Python Client

### New Classes

```python
@dataclass
class Calendar:
    id: str
    title: str
    color: Optional[str]
    is_read_only: bool
    event_count: int
    _client: Optional["iCloudBridge"]

    @property
    def events(self) -> Iterator[Event]:
        """Iterate events in next 30 days."""

    def get_events(self, start: datetime, end: datetime) -> list[Event]:
        """Get events in date range."""

    def create_event(self, title: str, start: datetime, end: datetime, ...) -> Event:
        """Create a new event."""


@dataclass
class Event:
    id: str
    calendar_id: str
    title: str
    notes: Optional[str]
    location: Optional[str]
    url: Optional[str]
    start_date: datetime
    end_date: datetime
    is_all_day: bool
    availability: str
    travel_time: Optional[int]
    alarms: list[Alarm]
    is_recurring: bool
    recurrence_rule: Optional[RecurrenceRule]
    series_id: Optional[str]
    _client: Optional["iCloudBridge"]

    def save(self, span: str = "thisEvent") -> Event:
        """Save changes to this event."""

    def delete(self, span: str = "thisEvent") -> None:
        """Delete this event."""


@dataclass
class RecurrenceRule:
    frequency: str
    interval: int
    days_of_week: Optional[list[str]]
    day_of_month: Optional[int]
    end_date: Optional[datetime]
    occurrence_count: Optional[int]


@dataclass
class Alarm:
    offset_minutes: int
```

### Client Methods

```python
class iCloudBridge:
    @property
    def calendars(self) -> Iterator[Calendar]:
        """Iterate all available calendars."""

    def get_calendars(self) -> list[Calendar]
    def get_calendar(self, calendar_id: str) -> Calendar
    def get_events(self, calendar_id: str, start: datetime, end: datetime) -> list[Event]
    def get_event(self, event_id: str) -> Event
    def create_event(self, calendar_id: str, title: str, start: datetime, end: datetime, ...) -> Event
    def update_event(self, event_id: str, span: str = "thisEvent", ...) -> Event
    def delete_event(self, event_id: str, span: str = "thisEvent") -> None
```

### Usage Examples

```python
from icloudbridge import iCloudBridge
from datetime import datetime, timedelta

client = iCloudBridge()

# List calendars
for cal in client.calendars:
    print(f"{cal.title}: {cal.event_count} upcoming events")

# Get events for next week
cal = next(client.calendars)
start = datetime.now()
end = start + timedelta(days=7)
for event in cal.get_events(start, end):
    print(f"{event.start_date}: {event.title}")

# Create an event
event = cal.create_event(
    title="Team Lunch",
    start=datetime(2026, 1, 20, 12, 0),
    end=datetime(2026, 1, 20, 13, 0),
    location="Cafe Roma"
)

# Create a recurring event
event = cal.create_event(
    title="Weekly Standup",
    start=datetime(2026, 1, 20, 9, 0),
    end=datetime(2026, 1, 20, 9, 30),
    recurrence_rule=RecurrenceRule(
        frequency="weekly",
        interval=1,
        days_of_week=["monday"]
    )
)

# Update just this occurrence
event.title = "Standup (Moved)"
event.save(span="thisEvent")

# Delete all future occurrences
event.delete(span="futureEvents")
```

## Implementation Tasks

### Swift Backend
1. Create `CalendarsService.swift` - EventKit integration
2. Create `CalendarDTO.swift` - Calendar model
3. Create `EventDTO.swift` - Event, RecurrenceRule, Alarm models
4. Create `CalendarsController.swift` - Calendar and event listing
5. Create `EventsController.swift` - Event CRUD
6. Register routes in `ServerManager.swift`
7. Add calendar permission to onboarding
8. Add calendar selection UI to settings
9. Store selected calendar IDs in UserDefaults

### Python Client
10. Add `Calendar`, `Event`, `RecurrenceRule`, `Alarm` dataclasses
11. Add calendar/event methods to `iCloudBridge` class
12. Update module docstring with calendar examples

### Documentation
13. Update README with calendar API endpoints
14. Update architecture diagram
