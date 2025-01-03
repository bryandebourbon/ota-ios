//
//  FavoriteStopWidget.swift
//  YourWidgetExtension
//
//  Created by YourName on YYYY-MM-DD.
//

import SwiftUI
import WidgetKit
import AppIntents

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
/// This is a simplified model *just* for the widget UI.
struct WidgetTripData {
    let tripId: String
    let vehicleLabel: String
    let directionText: String
    let routeId: String
    let departureTime: Int
    let arrivalTime: Int
    let delay: Int
}

// MARK: - 4) The TimelineEntry, including “lastFetchTime”
struct FavoriteStopEntry: TimelineEntry {
    let date: Date
    let stopID: String
    let upcomingTrips: [WidgetTripData]
    let direction: GOTransitDirection

    // Store the time we last fetched data from the server
    let lastFetchTime: Date
}

// MARK: - 5) The main Timeline Provider
struct FavoriteStopProvider: AppIntentTimelineProvider {
    typealias Intent = SelectStopIntent
    typealias Entry  = FavoriteStopEntry

    func placeholder(in context: Context) -> FavoriteStopEntry {
        FavoriteStopEntry(
            date: Date(),
            stopID: "Loading…",
            upcomingTrips: [],
            direction: .all,
            lastFetchTime: Date()
        )
    }

    func snapshot(for configuration: SelectStopIntent, in context: Context) async -> FavoriteStopEntry {
        FavoriteStopEntry(
            date: Date(),
            stopID: configuration.stopID,
            upcomingTrips: [],
            direction: configuration.direction,
            lastFetchTime: Date()
        )
    }

    func timeline(for configuration: SelectStopIntent, in context: Context) async -> Timeline<FavoriteStopEntry> {
        let chosenStop        = configuration.stopID
        let selectedDirection = configuration.direction

        // Build the GTFS endpoint
        guard let url = URL(string: "https://api.openmetrolinx.com/OpenDataAPI/api/V1/Gtfs/Feed/TripUpdates?key=30023952") else {
            // If invalid URL, create a fallback entry
            let fallback = FavoriteStopEntry(
                date: Date(),
                stopID: chosenStop,
                upcomingTrips: [],
                direction: selectedDirection,
                lastFetchTime: Date()
            )
            return Timeline(entries: [fallback], policy: .after(Date().addingTimeInterval(3600)))
        }

        // Prepare for success or fallback
        let matchingTrips: [WidgetTripData]
        let fetchTime: Date

        do {
            // 1) Fetch data
            let (data, _) = try await URLSession.shared.data(from: url)
            fetchTime = Date()

            // 2) Decode as per your GtfsModels
            let feed = try JSONDecoder().decode(GtfsRealtimeFeed.self, from: data)

            // 3) Convert each GtfsEntity -> domain TripUpdate
            let allTrips = feed.entity.compactMap { entity -> TripUpdate? in
                guard let tuData = entity.tripUpdate else { return nil }
                return TripUpdate(
                    id: entity.id,
                    tripId: tuData.trip?.tripId ?? "Unknown",
                    routeId: tuData.trip?.routeId ?? "Unknown",
                    delay: tuData.delay,
                    stopTimeUpdates: tuData.stopTimeUpdate ?? [],
                    directionId: tuData.trip?.directionId,
                    vehicleLabel: tuData.vehicle?.label,
                    scheduleRelationship: tuData.trip?.scheduleRelationship,
                    startTime: tuData.trip?.startTime,
                    startDate: tuData.trip?.startDate
                )
            }

            // 4) Filter to only trips that include the chosenStop
            let filtered = allTrips.compactMap { trip -> WidgetTripData? in
                // Must have a matching StopTimeUpdate for this stop
                guard let stopTime = trip.stopTimeUpdates.first(where: { $0.stopId == chosenStop }) else {
                    return nil
                }

                // Also filter direction if not “.all”
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

                // Build text for direction
                let directionText: String
                if let d = trip.directionId {
                    directionText = (d == 0) ? "Inbound" : "Outbound"
                } else {
                    directionText = "Unknown"
                }

                let depTime = stopTime.departure?.time ?? 0
                let arrTime = stopTime.arrival?.time   ?? 0

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

            // Sort by earliest departure
            matchingTrips = filtered.sorted { $0.departureTime < $1.departureTime }

        } catch {
            // If network or decoding fails, fallback
            let fallback = FavoriteStopEntry(
                date: Date(),
                stopID: chosenStop,
                upcomingTrips: [],
                direction: selectedDirection,
                lastFetchTime: Date()
            )
            return Timeline(entries: [fallback], policy: .after(Date().addingTimeInterval(3600)))
        }

        // 6) Build a series of timeline entries for the next N minutes
        let now        = Date()
        let maxMinutes = 30
        var entries: [FavoriteStopEntry] = []

        for minuteOffset in 0..<maxMinutes {
            let entryDate = now.addingTimeInterval(Double(minuteOffset * 60))
            
            // Filter out any trips that have departed before this entry’s time
            let upcomingTripsForThisEntry = matchingTrips.filter { trip in
                let depTimeDate = Date(timeIntervalSince1970: TimeInterval(trip.departureTime))
                return depTimeDate >= entryDate
            }

            let entry = FavoriteStopEntry(
                date: entryDate,
                stopID: chosenStop,
                upcomingTrips: upcomingTripsForThisEntry,
                direction: selectedDirection,
                lastFetchTime: fetchTime
            )
            entries.append(entry)
        }

        // 7) Return all entries
        return Timeline(entries: entries, policy: .never)
    }
}

// MARK: - 6) An AppIntent to trigger a refresh (iOS 17 interactive widgets)
//     Restrict re-calls if less than 60s from last refresh.
struct RefreshStopWidgetIntent: AppIntent {
    static var title: LocalizedStringResource = "Refresh Favorite Stop"
    
    // Keep track of the last time we triggered a refresh
    private static var lastRefresh: Date?

    func perform() async throws -> some IntentResult {
        let now = Date()
        if let last = Self.lastRefresh, now.timeIntervalSince(last) < 60 {
            // If it's been less than 60 seconds, ignore the request
            print("** Refresh requested too soon (\(Int(now.timeIntervalSince(last)))s), ignoring. **")
            return .result()
        }

        // Otherwise, do a full refresh
        Self.lastRefresh = now
        WidgetCenter.shared.reloadTimelines(ofKind: "FavoriteStopWidget")
        return .result()
    }
}

// MARK: - 7) The widget definition
@main
struct FavoriteStopWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: "FavoriteStopWidget",
            intent: SelectStopIntent.self,
            provider: FavoriteStopProvider()
        ) { entry in
            FavoriteStopWidgetEntryView(entry: entry)
                // For iOS 17 “widget stacks” background styling.
                // Below we choose dark vs. light container color.
                .modifier(DynamicWidgetContainerBackground())
        }
        .configurationDisplayName("Favorite Stop Widget")
        .description("Shows upcoming trips for your chosen stop and direction.")
        .supportedFamilies([
            .systemSmall, .systemMedium, .systemLarge,
            .accessoryRectangular, .accessoryInline, .accessoryCircular
        ])
    }
}

// A helper view modifier to handle dynamic backgrounds
fileprivate struct DynamicWidgetContainerBackground: ViewModifier {
    @Environment(\.colorScheme) var colorScheme

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 17.0, *) {
            // If you want a dynamic color (black for Dark Mode, white for Light Mode):
            content
                .containerBackground(
                    colorScheme == .dark ? .black : .white,
                    for: .widget
                )
        } else {
            // On iOS 16 or earlier (non-interactive widgets), you won't use containerBackground
            content
        }
    }
}

// MARK: - 8) The Widget UI, including “N minutes ago”
struct FavoriteStopWidgetEntryView: View {
    let entry: FavoriteStopEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Top row: Title + Refresh button
            HStack {
                Text("Stop: \(entry.stopID)")
                    .font(.headline)

                Spacer()

                // The refresh button (iOS 17+)
                Button(intent: RefreshStopWidgetIntent()) {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
            }

            // Show direction
            Text(directionLabel(entry.direction))
                .font(.subheadline)
                .foregroundColor(.secondary)

            // Upcoming trips or placeholder
            if entry.upcomingTrips.isEmpty {
                Text("No upcoming trips")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            } else {
                // Show up to 3 upcoming trips
                ForEach(entry.upcomingTrips.prefix(3), id: \.tripId) { item in
                    tripRow(item, currentTime: entry.date)
                }
            }
            
            Spacer()
            // Show how long ago we fetched data
            let minutesAgo = minutesSince(entry.lastFetchTime, to: entry.date)
            Text("Updated \(minutesAgo) min ago")
                .font(.caption2)
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .trailing)
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

            // “Departs in X min”
            let minutesLeft = minutesUntilDeparture(item.departureTime, from: currentTime)
            HStack {
                Text("Departure: \(formattedTime(item.departureTime))")
                Spacer()
                Text("\(minutesLeft) min left")
                    .foregroundColor(.blue)
            }
            .font(.caption)

            // Delay, if any
            if item.delay > 0 {
                Text("Delay: \(item.delay) min")
                    .foregroundColor(.red)
                    .font(.caption)
            }
        }
        .padding(.vertical, 4)
    }

    // Converts departureTime -> “minutes from currentTime”
    private func minutesUntilDeparture(_ departureUnix: Int, from currentTime: Date) -> Int {
        let departureDate = Date(timeIntervalSince1970: TimeInterval(departureUnix))
        let diff = departureDate.timeIntervalSince(currentTime)
        return max(0, Int(diff / 60))
    }

    // Helper to format a Unix timestamp into local time
    private func formattedTime(_ seconds: Int) -> String {
        guard seconds > 0 else { return "--" }
        let date = Date(timeIntervalSince1970: TimeInterval(seconds))
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    // Helper to compute “N minutes since last fetch”
    private func minutesSince(_ from: Date, to: Date) -> Int {
        let diff = to.timeIntervalSince(from)
        return max(0, Int(diff / 60))
    }
}
