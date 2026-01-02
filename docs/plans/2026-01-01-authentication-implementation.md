# Authentication Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add bearer token authentication for remote API access while keeping localhost access seamless.

**Architecture:** TokenManager handles Keychain storage of SHA-256 hashed tokens. Vapor middleware checks Authorization header for remote requests. Settings UI provides token management when remote access is enabled.

**Tech Stack:** Swift, Vapor middleware, macOS Keychain (Security framework), SwiftUI, CryptoKit

---

## Task 1: Create APIToken Model

**Files:**
- Create: `Sources/iCloudBridge/Models/APIToken.swift`

**Step 1: Create the model file**

```swift
import Foundation

/// Represents an API access token (metadata only - hash stored separately in Keychain)
struct APIToken: Identifiable, Codable, Equatable {
    let id: UUID
    let description: String
    let createdAt: Date

    init(id: UUID = UUID(), description: String, createdAt: Date = Date()) {
        self.id = id
        self.description = description
        self.createdAt = createdAt
    }
}
```

**Step 2: Verify it compiles**

Run: `swift build 2>&1 | tail -5`
Expected: "Build complete!"

**Step 3: Commit**

```bash
git add Sources/iCloudBridge/Models/APIToken.swift
git commit -m "feat: add APIToken model"
```

---

## Task 2: Create TokenManager Service

**Files:**
- Create: `Sources/iCloudBridge/Services/TokenManager.swift`

**Step 1: Create TokenManager with Keychain operations**

```swift
import Foundation
import Security
import CryptoKit

actor TokenManager {
    private let serviceName = "com.icloudbridge.api-tokens"

    /// Generate a cryptographically secure token
    func generateToken() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    /// Hash a token using SHA-256
    private func hashToken(_ token: String) -> String {
        let data = Data(token.utf8)
        let hash = SHA256.hash(data: data)
        return hash.compactMap { String(format: "%02x", $0) }.joined()
    }

    /// Store a new token in Keychain, returns the token metadata
    func createToken(description: String) throws -> (token: String, metadata: APIToken) {
        let token = generateToken()
        let tokenHash = hashToken(token)
        let metadata = APIToken(description: description)

        let tokenData = TokenData(hash: tokenHash, description: description, createdAt: metadata.createdAt)
        let jsonData = try JSONEncoder().encode(tokenData)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: metadata.id.uuidString,
            kSecValueData as String: jsonData
        ]

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw TokenError.keychainError(status)
        }

        return (token, metadata)
    }

    /// Load all token metadata from Keychain
    func loadTokens() throws -> [APIToken] {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecMatchLimit as String: kSecMatchLimitAll,
            kSecReturnAttributes as String: true,
            kSecReturnData as String: true
        ]

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        if status == errSecItemNotFound {
            return []
        }

        guard status == errSecSuccess,
              let items = result as? [[String: Any]] else {
            throw TokenError.keychainError(status)
        }

        return items.compactMap { item -> APIToken? in
            guard let accountString = item[kSecAttrAccount as String] as? String,
                  let id = UUID(uuidString: accountString),
                  let data = item[kSecValueData as String] as? Data,
                  let tokenData = try? JSONDecoder().decode(TokenData.self, from: data) else {
                return nil
            }
            return APIToken(id: id, description: tokenData.description, createdAt: tokenData.createdAt)
        }
    }

    /// Validate a token against stored hashes
    func validateToken(_ token: String) throws -> Bool {
        let providedHash = hashToken(token)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecMatchLimit as String: kSecMatchLimitAll,
            kSecReturnData as String: true
        ]

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        if status == errSecItemNotFound {
            return false
        }

        guard status == errSecSuccess,
              let items = result as? [Data] else {
            throw TokenError.keychainError(status)
        }

        for data in items {
            if let tokenData = try? JSONDecoder().decode(TokenData.self, from: data),
               tokenData.hash == providedHash {
                return true
            }
        }

        return false
    }

    /// Revoke (delete) a token by ID
    func revokeToken(id: UUID) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: id.uuidString
        ]

        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw TokenError.keychainError(status)
        }
    }
}

/// Internal structure for Keychain storage
private struct TokenData: Codable {
    let hash: String
    let description: String
    let createdAt: Date
}

enum TokenError: Error, LocalizedError {
    case keychainError(OSStatus)

    var errorDescription: String? {
        switch self {
        case .keychainError(let status):
            return "Keychain error: \(status)"
        }
    }
}
```

**Step 2: Verify it compiles**

Run: `swift build 2>&1 | tail -5`
Expected: "Build complete!"

**Step 3: Commit**

```bash
git add Sources/iCloudBridge/Services/TokenManager.swift
git commit -m "feat: add TokenManager for Keychain token storage"
```

---

## Task 3: Update AppState with Authentication Settings

**Files:**
- Modify: `Sources/iCloudBridge/AppState.swift`

**Step 1: Add new properties and persistence**

Add after line 68 (`@Published var showingSettings: Bool = false`):

```swift
    @Published var allowRemoteConnections: Bool = false
    @Published var apiTokens: [APIToken] = []
```

Add new key after line 75 (`private let serverPortKey = "serverPort"`):

```swift
    private let allowRemoteConnectionsKey = "allowRemoteConnections"
```

**Step 2: Update loadSettings()**

Add at the end of `loadSettings()` function (before closing brace on line 113):

```swift
        allowRemoteConnections = UserDefaults.standard.bool(forKey: allowRemoteConnectionsKey)
```

**Step 3: Update saveSettings()**

Add at the end of `saveSettings()` function (before closing brace on line 119):

```swift
        UserDefaults.standard.set(allowRemoteConnections, forKey: allowRemoteConnectionsKey)
```

**Step 4: Verify it compiles**

Run: `swift build 2>&1 | tail -5`
Expected: "Build complete!"

**Step 5: Commit**

```bash
git add Sources/iCloudBridge/AppState.swift
git commit -m "feat: add allowRemoteConnections setting to AppState"
```

---

## Task 4: Create Authentication Middleware

**Files:**
- Create: `Sources/iCloudBridge/API/AuthMiddleware.swift`

**Step 1: Create the middleware**

```swift
import Vapor

/// Middleware that requires Bearer token authentication for remote requests
struct AuthMiddleware: AsyncMiddleware {
    let tokenManager: TokenManager
    let isAuthEnabled: () -> Bool

    func respond(to request: Request, chainingTo next: AsyncResponder) async throws -> Response {
        // Skip auth if disabled
        guard isAuthEnabled() else {
            return try await next.respond(to: request)
        }

        // Allow localhost requests without auth
        if isLocalhost(request) {
            return try await next.respond(to: request)
        }

        // Require Bearer token for remote requests
        guard let authHeader = request.headers.bearerAuthorization else {
            throw Abort(.unauthorized, reason: "Invalid or missing authentication token")
        }

        let token = authHeader.token

        do {
            let isValid = try await tokenManager.validateToken(token)
            guard isValid else {
                throw Abort(.unauthorized, reason: "Invalid or missing authentication token")
            }
        } catch {
            request.logger.warning("Auth validation error: \(error)")
            throw Abort(.unauthorized, reason: "Invalid or missing authentication token")
        }

        return try await next.respond(to: request)
    }

    private func isLocalhost(_ request: Request) -> Bool {
        guard let peerAddress = request.peerAddress else {
            return false
        }

        let hostname = peerAddress.hostname ?? ""

        // Check for IPv4 localhost
        if hostname == "127.0.0.1" {
            return true
        }

        // Check for IPv6 localhost
        if hostname == "::1" || hostname == "0:0:0:0:0:0:0:1" {
            return true
        }

        return false
    }
}
```

**Step 2: Verify it compiles**

Run: `swift build 2>&1 | tail -5`
Expected: "Build complete!"

**Step 3: Commit**

```bash
git add Sources/iCloudBridge/API/AuthMiddleware.swift
git commit -m "feat: add AuthMiddleware for bearer token authentication"
```

---

## Task 5: Update ServerManager for Dynamic Binding

**Files:**
- Modify: `Sources/iCloudBridge/Services/ServerManager.swift`

**Step 1: Add tokenManager and binding flag to init**

Replace the entire `ServerManager` actor with:

```swift
import Vapor
import Foundation

actor ServerManager {
    private var app: Application?
    private let remindersService: RemindersService
    private let photosService: PhotosService
    private let selectedListIds: () -> [String]
    private let selectedAlbumIds: () -> [String]
    let tokenManager: TokenManager
    private let allowRemoteConnections: () -> Bool

    init(
        remindersService: RemindersService,
        photosService: PhotosService,
        selectedListIds: @escaping () -> [String],
        selectedAlbumIds: @escaping () -> [String],
        tokenManager: TokenManager,
        allowRemoteConnections: @escaping () -> Bool
    ) {
        self.remindersService = remindersService
        self.photosService = photosService
        self.selectedListIds = selectedListIds
        self.selectedAlbumIds = selectedAlbumIds
        self.tokenManager = tokenManager
        self.allowRemoteConnections = allowRemoteConnections
    }

    var isRunning: Bool {
        return app != nil
    }

    func start(port: Int) async throws {
        if app != nil {
            await stop()
        }

        var env = Environment.production
        env.arguments = ["serve"]

        let newApp = try await Application.make(env)

        // Bind to all interfaces if remote connections allowed, otherwise localhost only
        newApp.http.server.configuration.hostname = allowRemoteConnections() ? "0.0.0.0" : "127.0.0.1"
        newApp.http.server.configuration.port = port

        // Configure JSON encoder for dates
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        ContentConfiguration.global.use(encoder: encoder, for: .json)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        ContentConfiguration.global.use(decoder: decoder, for: .json)

        try configureRoutes(
            newApp,
            remindersService: remindersService,
            photosService: photosService,
            selectedListIds: selectedListIds,
            selectedAlbumIds: selectedAlbumIds,
            tokenManager: tokenManager,
            isAuthEnabled: allowRemoteConnections
        )

        self.app = newApp

        try await newApp.startup()
    }

    func stop() async {
        if let app = app {
            try? await app.asyncShutdown()
            self.app = nil
        }
    }
}
```

**Step 2: Verify it compiles (will fail - Routes.swift not updated yet)**

Run: `swift build 2>&1 | grep -i error | head -5`
Expected: Error about configureRoutes signature mismatch

**Step 3: Commit partial progress**

```bash
git add Sources/iCloudBridge/Services/ServerManager.swift
git commit -m "feat: update ServerManager for dynamic binding and auth"
```

---

## Task 6: Update Routes to Apply Middleware

**Files:**
- Modify: `Sources/iCloudBridge/API/Routes.swift`

**Step 1: Update configureRoutes to add middleware**

Replace entire file with:

```swift
import Vapor

func configureRoutes(
    _ app: Application,
    remindersService: RemindersService,
    photosService: PhotosService,
    selectedListIds: @escaping () -> [String],
    selectedAlbumIds: @escaping () -> [String],
    tokenManager: TokenManager,
    isAuthEnabled: @escaping () -> Bool
) throws {
    // Health check endpoint - always accessible (no auth)
    app.get("health") { req in
        return ["status": "ok"]
    }

    // API routes with authentication middleware
    let authMiddleware = AuthMiddleware(tokenManager: tokenManager, isAuthEnabled: isAuthEnabled)
    let api = app.grouped("api", "v1").grouped(authMiddleware)

    try api.register(collection: ListsController(
        remindersService: remindersService,
        selectedListIds: selectedListIds
    ))

    try api.register(collection: RemindersController(
        remindersService: remindersService,
        selectedListIds: selectedListIds
    ))

    try api.register(collection: AlbumsController(
        photosService: photosService,
        selectedAlbumIds: selectedAlbumIds
    ))

    try api.register(collection: PhotosController(
        photosService: photosService,
        selectedAlbumIds: selectedAlbumIds
    ))
}
```

**Step 2: Verify it compiles (will fail - iCloudBridgeApp not updated)**

Run: `swift build 2>&1 | grep -i error | head -5`
Expected: Error about ServerManager init in iCloudBridgeApp

**Step 3: Commit**

```bash
git add Sources/iCloudBridge/API/Routes.swift
git commit -m "feat: apply auth middleware to API routes"
```

---

## Task 7: Update iCloudBridgeApp with TokenManager

**Files:**
- Modify: `Sources/iCloudBridge/iCloudBridgeApp.swift`

**Step 1: Find ServerManager instantiation**

Search for where `ServerManager` is created and update to include new parameters.

Run: `grep -n "ServerManager(" Sources/iCloudBridge/iCloudBridgeApp.swift`

**Step 2: Add tokenManager property and update ServerManager init**

Add property near other state:
```swift
    private let tokenManager = TokenManager()
```

Update ServerManager initialization to include new parameters:
```swift
            serverManager = ServerManager(
                remindersService: appState.remindersService,
                photosService: appState.photosService,
                selectedListIds: { [weak appState] in appState?.selectedLists ?? [] },
                selectedAlbumIds: { [weak appState] in appState?.selectedAlbums ?? [] },
                tokenManager: tokenManager,
                allowRemoteConnections: { [weak appState] in appState?.allowRemoteConnections ?? false }
            )
```

**Step 3: Verify it compiles**

Run: `swift build 2>&1 | tail -5`
Expected: "Build complete!"

**Step 4: Commit**

```bash
git add Sources/iCloudBridge/iCloudBridgeApp.swift
git commit -m "feat: wire TokenManager into app startup"
```

---

## Task 8: Create Token Creation Modal

**Files:**
- Create: `Sources/iCloudBridge/Views/TokenCreatedModal.swift`

**Step 1: Create the modal view**

```swift
import SwiftUI

struct TokenCreatedModal: View {
    let token: String
    let onDismiss: () -> Void

    @State private var copied = false

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "key.fill")
                .font(.system(size: 48))
                .foregroundColor(.green)

            Text("Token Created")
                .font(.headline)

            Text("Copy this token now. It will only be shown once.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            GroupBox {
                HStack {
                    Text(token)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)

                    Spacer()

                    Button(action: copyToken) {
                        Image(systemName: copied ? "checkmark" : "doc.on.doc")
                    }
                    .buttonStyle(.borderless)
                }
            }
            .frame(maxWidth: .infinity)

            if copied {
                Text("Copied to clipboard!")
                    .font(.caption)
                    .foregroundColor(.green)
            }

            Button("Done") {
                onDismiss()
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(24)
        .frame(width: 400)
    }

    private func copyToken() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(token, forType: .string)
        copied = true
    }
}
```

**Step 2: Verify it compiles**

Run: `swift build 2>&1 | tail -5`
Expected: "Build complete!"

**Step 3: Commit**

```bash
git add Sources/iCloudBridge/Views/TokenCreatedModal.swift
git commit -m "feat: add TokenCreatedModal for displaying new tokens"
```

---

## Task 9: Update SettingsView with Token Management

**Files:**
- Modify: `Sources/iCloudBridge/Views/SettingsView.swift`

**Step 1: Add new state and properties**

Add after line 10 (`@State private var showingPortError: Bool = false`):

```swift
    @State private var showingAddToken: Bool = false
    @State private var newTokenDescription: String = ""
    @State private var showingTokenCreated: Bool = false
    @State private var createdToken: String = ""
    @State private var showingRevokeConfirmation: Bool = false
    @State private var tokenToRevoke: APIToken?

    let tokenManager: TokenManager
```

**Step 2: Update init to accept tokenManager**

The view needs tokenManager passed in. Update the struct to have an init or pass it through.

**Step 3: Update contentHeight for server tab**

Change line 25 to accommodate larger server settings:
```swift
            return 400
```

**Step 4: Replace serverSettingsView**

Replace the `serverSettingsView` computed property with:

```swift
    private var serverSettingsView: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Port configuration
            VStack(alignment: .leading, spacing: 8) {
                Text("Server Port")
                    .font(.headline)

                HStack {
                    TextField("Port", text: $portString)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 100)
                        .onChange(of: portString) { _, _ in
                            validatePort()
                        }

                    if showingPortError {
                        Text("Invalid port (1024-65535)")
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                }

                Text("Default: 31337")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Divider()

            // Remote access toggle
            VStack(alignment: .leading, spacing: 8) {
                Toggle("Allow remote connections", isOn: $appState.allowRemoteConnections)

                Text("When enabled, the server binds to all network interfaces. Remote access requires a valid token.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            // Token management (shown when remote enabled)
            if appState.allowRemoteConnections {
                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    Text("Access Tokens")
                        .font(.headline)

                    if appState.apiTokens.isEmpty {
                        Text("No tokens configured. Remote clients won't be able to authenticate.")
                            .font(.caption)
                            .foregroundColor(.orange)
                    } else {
                        ForEach(appState.apiTokens) { token in
                            tokenRow(token)
                        }
                    }

                    Button("Add Token") {
                        showingAddToken = true
                    }
                }
            }

            Spacer()
        }
        .padding(20)
        .sheet(isPresented: $showingAddToken) {
            addTokenSheet
        }
        .sheet(isPresented: $showingTokenCreated) {
            TokenCreatedModal(token: createdToken) {
                showingTokenCreated = false
                createdToken = ""
            }
        }
        .alert("Revoke Token", isPresented: $showingRevokeConfirmation, presenting: tokenToRevoke) { token in
            Button("Cancel", role: .cancel) {}
            Button("Revoke", role: .destructive) {
                Task {
                    await revokeToken(token)
                }
            }
        } message: { token in
            Text("Revoke token '\(token.description)'? Any clients using this token will stop working.")
        }
    }

    private func tokenRow(_ token: APIToken) -> some View {
        HStack {
            VStack(alignment: .leading) {
                Text(token.description)
                    .font(.body)
                Text("Created \(token.createdAt.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Button("Revoke") {
                tokenToRevoke = token
                showingRevokeConfirmation = true
            }
            .foregroundColor(.red)
        }
        .padding(.vertical, 4)
    }

    private var addTokenSheet: some View {
        VStack(spacing: 16) {
            Text("Add Access Token")
                .font(.headline)

            TextField("Description (e.g., Home Assistant)", text: $newTokenDescription)
                .textFieldStyle(.roundedBorder)
                .frame(width: 300)

            HStack {
                Button("Cancel") {
                    newTokenDescription = ""
                    showingAddToken = false
                }

                Button("Create Token") {
                    Task {
                        await createToken()
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(newTokenDescription.isEmpty)
            }
        }
        .padding(24)
    }

    private func createToken() async {
        do {
            let (token, metadata) = try await tokenManager.createToken(description: newTokenDescription)
            await MainActor.run {
                appState.apiTokens.append(metadata)
                createdToken = token
                newTokenDescription = ""
                showingAddToken = false
                showingTokenCreated = true
            }
        } catch {
            print("Failed to create token: \(error)")
        }
    }

    private func revokeToken(_ token: APIToken) async {
        do {
            try await tokenManager.revokeToken(id: token.id)
            await MainActor.run {
                appState.apiTokens.removeAll { $0.id == token.id }
            }
        } catch {
            print("Failed to revoke token: \(error)")
        }
    }
```

**Step 5: Verify it compiles**

Run: `swift build 2>&1 | tail -10`

**Step 6: Commit**

```bash
git add Sources/iCloudBridge/Views/SettingsView.swift
git commit -m "feat: add token management UI to Settings Server tab"
```

---

## Task 10: Load Tokens on App Startup

**Files:**
- Modify: `Sources/iCloudBridge/iCloudBridgeApp.swift`

**Step 1: Load tokens into AppState on startup**

Add a function to load tokens and call it during initialization:

```swift
    private func loadTokens() {
        Task {
            do {
                let tokens = try await tokenManager.loadTokens()
                await MainActor.run {
                    appState.apiTokens = tokens
                }
            } catch {
                print("Failed to load tokens: \(error)")
            }
        }
    }
```

Call this in the appropriate lifecycle method (onAppear or init).

**Step 2: Pass tokenManager to SettingsView**

Update where SettingsView is created to pass tokenManager.

**Step 3: Verify it compiles**

Run: `swift build 2>&1 | tail -5`
Expected: "Build complete!"

**Step 4: Commit**

```bash
git add Sources/iCloudBridge/iCloudBridgeApp.swift
git commit -m "feat: load tokens from Keychain on app startup"
```

---

## Task 11: Update Python Client with Token Support

**Files:**
- Modify: `python/icloudbridge.py`

**Step 1: Update iCloudBridge.__init__ to accept token**

Find the `__init__` method (around line 610) and update:

```python
    def __init__(self, host: str = "localhost", port: int = 31337, token: Optional[str] = None):
        self.base_url = f"http://{host}:{port}/api/v1"
        self._health_url = f"http://{host}:{port}/health"
        self._token = token
```

**Step 2: Update _request to add Authorization header**

In the `_request` method, update the headers section:

```python
        headers = {"Content-Type": "application/json"}
        if self._token:
            headers["Authorization"] = f"Bearer {self._token}"
```

**Step 3: Update docstring**

Update the class docstring to document the token parameter:

```python
    """
    Client for the iCloud Bridge REST API.

    Args:
        host: The hostname of the iCloud Bridge server (default: localhost)
        port: The port number (default: 31337)
        token: Bearer token for authentication (required for remote connections)
    """
```

**Step 4: Verify syntax**

Run: `python3 -c "from python.icloudbridge import iCloudBridge; print('OK')"`
Expected: "OK"

**Step 5: Commit**

```bash
git add python/icloudbridge.py
git commit -m "feat(python): add token parameter for bearer auth"
```

---

## Task 12: Update Module Docstring

**Files:**
- Modify: `python/icloudbridge.py`

**Step 1: Update the module docstring at the top**

Add remote connection example to the Interactive Objects section:

```python
Remote Connections:
    For remote servers, provide an authentication token:

    client = iCloudBridge(host="192.168.1.100", token="your-token-here")
    for album in client.albums:
        print(album.title)
```

**Step 2: Commit**

```bash
git add python/icloudbridge.py
git commit -m "docs(python): add remote connection example to module docstring"
```

---

## Task 13: Final Build Verification

**Step 1: Clean build**

Run: `swift build 2>&1 | tail -10`
Expected: "Build complete!"

**Step 2: Verify Python client**

Run: `cd python && source .venv/bin/activate && python3 -c "from icloudbridge import iCloudBridge; c = iCloudBridge(token='test'); print('Token support OK')"`
Expected: "Token support OK"

**Step 3: Final commit if any uncommitted changes**

```bash
git status
# If changes exist:
git add -A && git commit -m "chore: final cleanup"
```
