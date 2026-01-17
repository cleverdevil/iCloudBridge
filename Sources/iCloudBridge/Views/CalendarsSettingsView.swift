import SwiftUI
import EventKit

struct CalendarsSettingsView: View {
    @ObservedObject var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            calendarsSection
            Spacer()
        }
        .padding(20)
        .onAppear {
            appState.calendarsService.loadCalendars()
        }
    }

    private var calendarsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Select Calendars")
                .font(.headline)

            Text("Choose which calendars to expose via the API:")
                .font(.caption)
                .foregroundColor(.secondary)

            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(appState.calendarsService.allCalendars, id: \.calendarIdentifier) { calendar in
                        Toggle(isOn: Binding(
                            get: { appState.isCalendarSelected(calendar.calendarIdentifier) },
                            set: { _ in appState.toggleCalendar(calendar.calendarIdentifier) }
                        )) {
                            HStack {
                                Circle()
                                    .fill(Color(cgColor: calendar.cgColor ?? CGColor(gray: 0.5, alpha: 1)))
                                    .frame(width: 12, height: 12)
                                Text(calendar.title)
                                if calendar.isImmutable {
                                    Text("(read-only)")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
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
