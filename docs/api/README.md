# iCloud Bridge REST API Documentation

This directory contains the OpenAPI specification for the iCloud Bridge REST API.

## Interactive Documentation

To view the interactive API documentation locally:

```bash
# From the project root
./scripts/serve-docs.sh
```

Then open http://localhost:8080 in your browser to access the Swagger UI.

## API Specification

The complete API is defined in [openapi.yaml](openapi.yaml) using the OpenAPI 3.0 specification.

## Quick Reference

### Base URL

```
http://localhost:31337/api/v1
```

The port (31337) is configurable in the app settings.

### Endpoints Overview

#### Health
- `GET /health` - Server health check

#### Reminders

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/lists` | Get all reminder lists |
| GET | `/lists/{id}` | Get a specific list |
| GET | `/lists/{id}/reminders` | Get reminders in a list |
| POST | `/lists/{id}/reminders` | Create a reminder |
| GET | `/reminders/{id}` | Get a reminder |
| PUT | `/reminders/{id}` | Update a reminder |
| DELETE | `/reminders/{id}` | Delete a reminder |

#### Photos

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/albums` | Get all photo albums |
| GET | `/albums/{id}` | Get album details |
| GET | `/albums/{id}/photos` | Get photos (paginated) |
| GET | `/photos/{id}` | Get photo metadata |
| GET | `/photos/{id}/thumbnail` | Get thumbnail |
| GET | `/photos/{id}/image` | Get full image |
| GET | `/photos/{id}/video` | Get video file |
| GET | `/photos/{id}/live-video` | Get Live Photo video |

## Examples

### Get all lists

```bash
curl http://localhost:31337/api/v1/lists
```

### Create a reminder

```bash
curl -X POST http://localhost:31337/api/v1/lists/{listId}/reminders \
  -H "Content-Type: application/json" \
  -d '{"title": "Buy groceries", "notes": "Milk, eggs, bread"}'
```

### Get photos with pagination

```bash
curl "http://localhost:31337/api/v1/albums/{albumId}/photos?limit=50&offset=0&sort=date-desc"
```

### Download a photo

```bash
curl http://localhost:31337/api/v1/photos/{photoId}/image -o photo.jpg
```

## Error Responses

All errors return a JSON object with `error` and `reason` fields:

```json
{
  "error": true,
  "reason": "List not found"
}
```

Common HTTP status codes:
- `200` - Success
- `201` - Created (for POST requests)
- `204` - No Content (for DELETE requests)
- `202` - Accepted (image is downloading from iCloud)
- `400` - Bad Request
- `404` - Not Found
- `500` - Internal Server Error
