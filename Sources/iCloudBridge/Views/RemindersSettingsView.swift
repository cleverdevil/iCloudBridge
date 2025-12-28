import SwiftUI
import EventKit

struct RemindersSettingsView: View {
    @ObservedObject var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            listsSection
            Spacer()
        }
        .padding(20)
        .onAppear {
            appState.remindersService.loadLists()
        }
    }

    private var listsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Select Reminders Lists")
                .font(.headline)

            Text("Choose which lists to expose via the API:")
                .font(.caption)
                .foregroundColor(.secondary)

            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(appState.remindersService.allLists, id: \.calendarIdentifier) { list in
                        Toggle(isOn: Binding(
                            get: { appState.isListSelected(list.calendarIdentifier) },
                            set: { _ in appState.toggleList(list.calendarIdentifier) }
                        )) {
                            HStack {
                                Circle()
                                    .fill(Color(cgColor: list.cgColor ?? CGColor(gray: 0.5, alpha: 1)))
                                    .frame(width: 12, height: 12)
                                Text(list.title)
                            }
                        }
                        .toggleStyle(.checkbox)
                    }
                }
                .padding(8)
            }
            .frame(maxHeight: 200)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(6)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color(NSColor.separatorColor), lineWidth: 1)
            )
        }
    }
}
