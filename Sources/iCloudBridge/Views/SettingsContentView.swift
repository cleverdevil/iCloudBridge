import SwiftUI

struct SettingsContentView: View {
    @ObservedObject var appState: AppState
    @ObservedObject var remindersService: RemindersService
    @ObservedObject var photosService: PhotosService
    let onSave: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        if appState.hasAllPermissions {
            SettingsView(appState: appState, onSave: onSave)
        } else {
            OnboardingView(
                appState: appState,
                remindersService: appState.remindersService,
                photosService: appState.photosService,
                onComplete: handleOnboardingComplete
            )
        }
    }

    private func handleOnboardingComplete() {
        // Reload data now that we have permissions
        appState.remindersService.loadLists()
        appState.photosService.loadAlbums()

        if appState.hasSavedSettings {
            // Has saved settings - start server and close window
            onSave()
            dismiss()
        }
        // Otherwise, stay open to show SettingsView (view will re-render)
    }
}
