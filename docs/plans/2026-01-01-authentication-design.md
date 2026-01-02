# Authentication Design

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add bearer token authentication for remote API access while keeping localhost access seamless.

**Architecture:** Toggle between localhost-only and public binding. When public, require bearer tokens for remote requests. Tokens stored as SHA-256 hashes in Keychain.

**Tech Stack:** Swift, Vapor middleware, macOS Keychain, SwiftUI

---

## Settings UI - Server Tab

The Server tab will be reorganized with these elements:

**Port Configuration** (existing)
- Text field for port number (1024-65535)
- Same validation as current implementation

**Network Binding** (new)
- Toggle: "Allow remote connections"
- When OFF: Server binds to `127.0.0.1` (localhost only, safe default)
- When ON: Server binds to `0.0.0.0` (all interfaces) and reveals token management

**Token Management** (shown only when remote connections enabled)
- Section header: "Access Tokens"
- List of existing tokens showing:
  - Description (user-provided)
  - Created date
  - "Revoke" button (with confirmation)
- "Add Token" button at bottom
- Clicking "Add Token" prompts for description, creates token, shows modal

**Token Creation Modal**
- Displays the generated token (43-character random string)
- Prominent "Copy to Clipboard" button
- Clear warning: "This token will only be shown once"
- User must dismiss before continuing

**Save Behavior**
- "Save & Restart Server" button applies all changes
- Disabling remote access keeps tokens stored for re-enabling later

---

## Token Storage & Data Model

**Token Structure**
- `id`: UUID for internal reference and revocation
- `tokenHash`: SHA-256 hash of the actual token
- `description`: User-provided label (e.g., "Home Assistant")
- `createdAt`: ISO8601 timestamp

**Security Model**
Store SHA-256 hash of token, not plaintext:
1. On creation: generate token, show to user, store hash
2. On request: hash provided Bearer token, compare against stored hashes
3. Match = authenticated

Even if Keychain is compromised, actual tokens aren't exposed.

**Keychain Organization**
- Service name: `com.icloudbridge.api-tokens`
- Each token as separate Keychain item
- Account field: token ID (UUID)
- Password field: JSON with hash, description, createdAt

**AppState Changes**
- `@Published var allowRemoteConnections: Bool` (persisted to UserDefaults)
- `@Published var apiTokens: [APIToken]` (metadata only: id, description, createdAt)
- New `TokenManager` service handles Keychain operations and hash lookups

---

## Authentication Middleware

**Request Flow**
1. Request arrives at Vapor server
2. Check if from localhost (127.0.0.1 or ::1)
   - Localhost: allow through, no token needed
3. For remote requests, check `Authorization` header
   - Expected: `Bearer <token>`
   - Missing/invalid format: 401 Unauthorized
4. Hash provided token, compare against stored hashes
   - No match: 401 Unauthorized
   - Match: allow through

**Error Response**
```json
{
  "error": true,
  "reason": "Invalid or missing authentication token"
}
```

**Exempt Endpoints**
- `GET /health` - Always accessible for monitoring
- All other endpoints require auth when remote

**Python Client Update**
```python
client = iCloudBridge(host="remote.server", port=31337, token="abc123...")
```
When token provided, adds `Authorization: Bearer <token>` to all requests.

---

## Edge Cases

**Binding Changes**
- Changing localhost ↔ all interfaces requires server restart
- "Save & Restart Server" button handles this
- Sub-second restart is acceptable

**Token Revocation**
- Immediate effect on next request
- Confirmation: "Revoke token '[description]'? Clients using this token will stop working."

**No Tokens + Remote Enabled**
- Show warning: "Remote connections enabled but no tokens exist. Remote clients won't authenticate."
- Allow saving anyway

**Startup**
- Load `allowRemoteConnections` from UserDefaults
- Bind to appropriate interface
- Load token hashes from Keychain immediately

**Logging**
- Log auth failures with source IP (not token values)
- Example: "Auth failed from 192.168.1.50 - invalid token"

---

## Token Generation

**Format**
- 32 bytes cryptographically random data
- Base64url encoded (43 characters)
- Example: `iBx7Kp9mQ2vL8nRt3wYz6aFc5dHj0eGi4oNs1uXb`

**Swift Implementation**
```swift
func generateToken() -> String {
    var bytes = [UInt8](repeating: 0, count: 32)
    _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
    return Data(bytes).base64EncodedString()
        .replacingOccurrences(of: "+", with: "-")
        .replacingOccurrences(of: "/", with: "_")
        .replacingOccurrences(of: "=", with: "")
}
```
