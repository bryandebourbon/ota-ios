//
//  FavoriteStopWidget.swift
//  YourWidgetExtension
//
//  Created by YourName on YYYY-MM-DD.
//

import SwiftUI
import WidgetKit
import AppIntents

// Make sure this import or module reference matches how your project is set up.
// If "GtfsModels.swift" is in the same module, you might only need "import Foundation."
// But if it's a separate target or Swift package, adjust accordingly.
import Foundation

// MARK: - 1) An AppEnum for directions (Inbound, Outbound, All)
enum GOTransitDirection: String, AppEnum {
    case inbound  = "Inbound"
    case outbound = "Outbound"
    case all      = "All"

    static var typeDisplayRepresentation: TypeDisplayRepresentation {
        "GO Transit Direction"
    }

    static var caseDisplayRepresentations: [GOTransitDirection: DisplayRepresentation] {
        [
            .inbound:  "Inbound",
            .outbound: "Outbound",
            .all:      "All"
        ]
    }
}

// MARK: - 2) Your widget’s configuration intent
struct SelectStopIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Select Stop"
    static var description = IntentDescription("Choose a GO Transit stop and direction for this widget.")

    @Parameter(title: "Stop ID", default: "UN")
    var stopID: String

    @Parameter(title: "Direction", default: .all)
    var direction: GOTransitDirection
}

// MARK: - 3) A struct to hold the widget’s trip details
struct WidgetTripData {
    let tripId: String
    let vehicleLabel: String
    let directionText: String
    let routeId: String
    let departureTime: Int
    let arrivalTime: Int
    let delay: Int
}

// MARK: - 4) The TimelineEntry
struct FavoriteStopEntry: TimelineEntry {
    let date: Date
    let stopID: String
    let upcomingTrips: [WidgetTripData]
    let direction: GOTransitDirection
}

// MARK: - 5) The main Timeline Provider
struct FavoriteStopProvider: AppIntentTimelineProvider {
    typealias Intent = SelectStopIntent
    typealias Entry  = FavoriteStopEntry

    func placeholder(in context: Context) -> FavoriteStopEntry {
        FavoriteStopEntry(
            date: Date(),
            stopID: "Loading...",
            upcomingTrips: [],
            direction: .all
        )
    }

    func snapshot(for configuration: SelectStopIntent, in context: Context) async -> FavoriteStopEntry {
        FavoriteStopEntry(
            date: Date(),
            stopID: configuration.stopID,
            upcomingTrips: [],
            direction: configuration.direction
        )
    }

    // MARK: - Minute-by-minute timeline approach
    // We only fetch once, then create multiple entries (one per minute).
    func timeline(for configuration: SelectStopIntent, in context: Context) async -> Timeline<FavoriteStopEntry> {
        let chosenStop = configuration.stopID
        let selectedDirection = configuration.direction

        // 1) Build the GTFS endpoint
        guard let url = URL(string: "https://api.openmetrolinx.com/OpenDataAPI/api/V1/Gtfs/Feed/TripUpdates?key=30023952") else {
            let fallback = FavoriteStopEntry(
                date: Date(),
                stopID: chosenStop,
                upcomingTrips: [],
                direction: selectedDirection
            )
            return Timeline(entries: [fallback], policy: .after(Date().addingTimeInterval(3600)))
        }

        // We'll store the final list of matching trips here
        let matching: [WidgetTripData]

        do {
            // 2) Fetch data once
            let (data, _) = try await URLSession.shared.data(from: url)

            // 3) Decode the feed (GtfsRealtimeFeed is defined in GtfsModels.swift)
            let feed = try JSONDecoder().decode(GtfsRealtimeFeed.self, from: data)

            // 4) Convert to [TripUpdate] (the domain model at bottom of GtfsModels)
            let allTrips: [TripUpdate] = feed.entity.compactMap { entity in
                guard let tu = entity.tripUpdate else {
                    return nil
                }

                // Build our domain TripUpdate struct
                return TripUpdate(
                    id: entity.id,
                    tripId: tu.trip?.tripId ?? "Unknown",
                    routeId: tu.trip?.routeId ?? "Unknown",
                    delay: tu.delay,
                    stopTimeUpdates: tu.stopTimeUpdate ?? [],
                    directionId: tu.trip?.directionId,
                    vehicleLabel: tu.vehicle?.label,
                    scheduleRelationship: tu.trip?.scheduleRelationship,
                    startTime: tu.trip?.startTime,
                    startDate: tu.trip?.startDate
                )
            }

            // 5) Filter for trips that include `chosenStop`
            let filtered = allTrips.compactMap { trip -> WidgetTripData? in
                guard let stopTime = trip.stopTimeUpdates.first(where: { $0.stopId == chosenStop }) else {
                    return nil
                }

                // Filter direction if needed
                if selectedDirection != .all {
                    switch selectedDirection {
                    case .inbound:
                        guard trip.directionId == 0 else { return nil }
                    case .outbound:
                        guard trip.directionId == 1 else { return nil }
                    case .all:
                        break
                    }
                }

                let directionText: String
                if let d = trip.directionId {
                    directionText = (d == 0) ? "Inbound" : "Outbound"
                } else {
                    directionText = "Unknown"
                }

                let depTime = stopTime.departure?.time ?? 0
                let arrTime = stopTime.arrival?.time ?? 0

                return WidgetTripData(
                    tripId: trip.tripId,
                    vehicleLabel: trip.vehicleLabel ?? "N/A",
                    directionText: directionText,
                    routeId: trip.routeId,
                    departureTime: depTime,
                    arrivalTime: arrTime,
                    delay: trip.delay ?? 0
                )
            }

            // Sort by earliest departure time
            matching = filtered.sorted { $0.departureTime < $1.departureTime }

        } catch {
            // If fetching or decoding fails, return a fallback entry
            let fallback = FavoriteStopEntry(
                date: Date(),
                stopID: chosenStop,
                upcomingTrips: [],
                direction: selectedDirection
            )
            return Timeline(entries: [fallback], policy: .after(Date().addingTimeInterval(3600)))
        }

        // 6) Build multiple timeline entries (one for each minute, for up to N minutes)
        let now = Date()
        // For example, show minute-by-minute countdown for the next 30 minutes:
        let maxMinutes = 30

        var entries: [FavoriteStopEntry] = []

        for minuteOffset in 0..<maxMinutes {
            let entryDate = now.addingTimeInterval(Double(minuteOffset * 60))

            let entry = FavoriteStopEntry(
                date: entryDate,
                stopID: chosenStop,
                upcomingTrips: matching,
                direction: selectedDirection
            )
            entries.append(entry)
        }

        // 7) Return all entries. The system will display them at the correct time.
        //    You can choose .never if you want no auto-refresh, or .after(...) for a fallback refresh.
        return Timeline(entries: entries, policy: .never)
    }
}

// MARK: - 6) An AppIntent to trigger a refresh
//     iOS 17 interactive widgets allow a button to call this intent.
struct RefreshStopWidgetIntent: AppIntent {
    static var title: LocalizedStringResource = "Refresh Favorite Stop"

    // This runs when the user taps the button in the widget
    func perform() async throws -> some IntentResult {
        // Request the system to reload our widget’s timelines
        WidgetCenter.shared.reloadTimelines(ofKind: "FavoriteStopWidget")
        return .result()
    }
}

// MARK: - 7) The Widget definition
@main
struct FavoriteStopWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: "FavoriteStopWidget",
            intent: SelectStopIntent.self,
            provider: FavoriteStopProvider()
        ) { entry in
            FavoriteStopWidgetEntryView(entry: entry)
                .containerBackground(.black, for:.widget)
        }
        .configurationDisplayName("Favorite Stop Widget")
        .description("Shows upcoming trips for your chosen stop and direction.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .accessoryRectangular, .accessoryInline, .accessoryCircular])
    }
}

// MARK: - 8) The Widget UI, now with a "Refresh" Button + countdown
struct FavoriteStopWidgetEntryView: View {
    let entry: FavoriteStopEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Title row
            HStack {
                Text("Stop: \(entry.stopID)")
                    .font(.headline)
                Spacer()
                // Our new Refresh button:
                Button(intent: RefreshStopWidgetIntent()) {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
            }

            // Direction
            Text(directionLabel(entry.direction))
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            // Upcoming trips or placeholder
            if entry.upcomingTrips.isEmpty {
                Text("No upcoming trips")
                    .foregroundColor(.secondary)
                    .font(.subheadline)
            } else {
                // Show up to 3 upcoming trips
                ForEach(entry.upcomingTrips.prefix(3), id: \.tripId) { item in
                    tripRow(item, currentTime: entry.date)
                }
            }
        }
        .padding()
    }
    
    // Helper: direction label
    private func directionLabel(_ direction: GOTransitDirection) -> String {
        switch direction {
        case .all:      return "All Directions"
        case .inbound:  return "Inbound Only"
        case .outbound: return "Outbound Only"
        }
    }

    // Helper: row for each trip
    @ViewBuilder
    private func tripRow(_ item: WidgetTripData, currentTime: Date) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            // Vehicle label & direction
            HStack {
                Text(item.vehicleLabel)
                    .font(.subheadline)
                Spacer()
                Text(item.directionText)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            // "Departs in X min"
            let minutesLeft = minutesUntilDeparture(item.departureTime, from: currentTime)

            HStack {
                Text("Departure: \(formattedTime(item.departureTime))")
                Spacer()
                Text("\(minutesLeft) min left")
                    .foregroundColor(.blue)
            }
            .font(.caption)
            
            if item.delay > 0 {
                Text("Delay: \(item.delay) min")
                    .foregroundColor(.red)
                    .font(.caption)
            }
        }
        .padding(.vertical, 4)
    }

    // Converts departureTime to "minutes from currentTime"
    private func minutesUntilDeparture(_ departureUnix: Int, from currentTime: Date) -> Int {
        let departureDate = Date(timeIntervalSince1970: TimeInterval(departureUnix))
        let diff = departureDate.timeIntervalSince(currentTime)
        return max(0, Int(diff / 60))
    }

    // Formats a Unix timestamp into a short local time string
    private func formattedTime(_ seconds: Int) -> String {
        guard seconds > 0 else { return "--" }
        let date = Date(timeIntervalSince1970: TimeInterval(seconds))
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}
