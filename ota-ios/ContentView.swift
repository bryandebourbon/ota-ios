import SwiftUI



struct ContentView: View {
    @StateObject private var viewModel = TripUpdateViewModel()

    var body: some View {
        TabView {
            NavigationView {
                VStack {
                    // The “favorite stop bar” if any
                    if let favorite = viewModel.favoriteStop {
                        FavoriteStopBar(viewModel: viewModel, stopID: favorite)
                            .padding()
                    }

                    // The main trip list
                    List(viewModel.tripUpdates, id: \.id) { trip in
                        VStack(alignment: .leading) {
                            Text("Trip ID: \(trip.tripId)").font(.headline)
                            Text("Route: \(trip.routeId)")
                            Text("Delay: \(trip.delay ?? 0)")
                        }
                    }
                    .navigationTitle("All Trips")
                }
                .onAppear {
                    viewModel.fetchTripUpdates()
                }
            }
            .tabItem {
                Label("All Trips", systemImage: "list.bullet")
            }

            NavigationView {
                StopIDsListView(viewModel: viewModel)
                    .navigationTitle("Stops")
            }
            .tabItem {
                Label("Stops", systemImage: "magnifyingglass")
            }
        }
    }
}


class TripUpdateViewModel: ObservableObject {
    @Published var tripUpdates: [TripUpdate] = []
    @Published var favoriteStop: String? = nil
    
    var allStopIDs: [String] {
        let stops = tripUpdates
            .flatMap { $0.stopTimeUpdates }
            .compactMap { $0.stopId }
            // Filter out any stop IDs that contain digits
            .filter { stopID in
                stopID.rangeOfCharacter(from: .decimalDigits) == nil
            }
        
        return Array(Set(stops)).sorted()
    }
    
    private let endpointURL = URL(string: "https://api.openmetrolinx.com/OpenDataAPI/api/V1/Gtfs/Feed/TripUpdates?key=30023952")!

    func fetchTripUpdates() {
        print("** Debug: Attempting to fetch from \(endpointURL.absoluteString) **")

        let task = URLSession.shared.dataTask(with: endpointURL) { data, response, error in
            // 1. Log any network error
            if let error = error {
                print("** Error fetching data: \(error.localizedDescription) **")
                return
            }

            // 2. Log the HTTP status code (if available)
            if let httpResp = response as? HTTPURLResponse {
                print("** HTTP Status Code: \(httpResp.statusCode) **")
            }

            // 3. Check for nil data
            guard let data = data else {
                print("** Data is nil **")
                return
            }

            // 4. Convert data to a string for logging the raw JSON
            let rawJson = String(data: data, encoding: .utf8) ?? "No valid UTF-8 data"
            print("** Raw JSON data: **\n\(rawJson)")

            // 5. Decode
            do {
                let feed = try JSONDecoder().decode(GtfsRealtimeFeed.self, from: data)
                DispatchQueue.main.async {
                    self.tripUpdates = feed.entity.compactMap { entity -> TripUpdate? in
                        guard let tu = entity.tripUpdate else { return nil }
                        
                        return TripUpdate(
                            id: entity.id,
                            tripId: tu.trip?.tripId ?? "Unknown",
                            routeId: tu.trip?.routeId ?? "Unknown",
                            delay: tu.delay,
                            stopTimeUpdates: tu.stopTimeUpdate ?? [],
                            
                            // new fields
                            directionId: tu.trip?.directionId,
                            vehicleLabel: tu.vehicle?.label,
                            scheduleRelationship: tu.trip?.scheduleRelationship, // if you decode it as an enum, or as a string
                            startTime: tu.trip?.startTime,
                            startDate: tu.trip?.startDate
                        )
                    }
                }

            } catch {
                print("** Decoding error: \(error) **")
            }
        }
        task.resume()
    }
    
    var favoriteStopUpcomingTrips: [(trip: TripUpdate, stopTime: StopTimeUpdate)] {
        guard let stopID = favoriteStop else { return [] }
        
        // Filter each trip to see if it has the stop ID
        return tripUpdates
            .compactMap { trip -> (TripUpdate, StopTimeUpdate)? in
                guard let stopTime = trip.stopTimeUpdates
                    .first(where: { $0.stopId == stopID })
                else {
                    return nil
                }
                return (trip, stopTime)
            }
            // Sort by earliest departure time
            .sorted { lhs, rhs in
                let lhsTime = lhs.stopTime.departure?.time ?? 0
                let rhsTime = rhs.stopTime.departure?.time ?? 0
                return lhsTime < rhsTime
            }
    }
}


// ---------------------------------------
// MARK: - Supporting Views

struct StopIDsListView: View {
    @ObservedObject var viewModel: TripUpdateViewModel

    var body: some View {
        List(viewModel.allStopIDs, id: \.self) { stopID in
            NavigationLink(destination: StopDetailView(viewModel: viewModel, stopID: stopID)) {
                Text(stopID)
            }
        }
        .navigationTitle("All Stop IDs")
    }
}

struct StopDetailView: View {
    @ObservedObject var viewModel: TripUpdateViewModel
    let stopID: String

    enum DirectionFilter: String, CaseIterable, Identifiable {
        case all = "All"
        case inbound = "Inbound"
        case outbound = "Outbound"
        
        var id: String { self.rawValue }
    }

    @State private var selectedFilter: DirectionFilter = .all
    
    private var upcomingTripsAtStop: [(trip: TripUpdate, stopTime: StopTimeUpdate)] {
        viewModel.tripUpdates
            .compactMap { trip -> (TripUpdate, StopTimeUpdate)? in
                guard let stopTime = trip.stopTimeUpdates.first(where: { $0.stopId == stopID }) else {
                    return nil
                }
                return (trip, stopTime)
            }
            .sorted { lhs, rhs in
                let lhsTime = lhs.stopTime.departure?.time ?? 0
                let rhsTime = rhs.stopTime.departure?.time ?? 0
                return lhsTime < rhsTime
            }
    }
    
    // Filter the list based on the selected direction
    private var filteredTrips: [(trip: TripUpdate, stopTime: StopTimeUpdate)] {
        upcomingTripsAtStop.filter { item in
            switch selectedFilter {
            case .all:
                return true
            case .inbound:
                // directionId == 0 => inbound
                return item.trip.directionId == 0
            case .outbound:
                // directionId == 1 => outbound
                return item.trip.directionId == 1
            }
        }
    }

    var body: some View {
        VStack {
            // 1) A segmented picker to filter by direction
            Picker("Direction", selection: $selectedFilter) {
                ForEach(DirectionFilter.allCases) { direction in
                    Text(direction.rawValue).tag(direction)
                }
            }
            .pickerStyle(.segmented)
            .padding()

            // 2) The filtered list of trips
            List(filteredTrips, id: \.trip.id) { item in
                // Wrap the row in a NavigationLink
                NavigationLink(destination: TripDetailsView(trip: item.trip, stopTime: item.stopTime)) {
                    tripRow(item)
                }
            }
        }
        .navigationTitle("Stop: \(stopID)")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: {
                    viewModel.favoriteStop = stopID
                }) {
                    Image(systemName: "star")
                }
            }
        }
    }
    
    // MARK: - A subview for each trip row
    @ViewBuilder
    private func tripRow(_ item: (trip: TripUpdate, stopTime: StopTimeUpdate)) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // Vehicle label or Trip ID
            HStack {
                if let vehicleLabel = item.trip.vehicleLabel {
                    Text(vehicleLabel)  // e.g. "LW - Aldershot GO"
                        .font(.headline)
                } else {
                    Text("Trip: \(item.trip.tripId)")
                        .font(.headline)
                }
                
                Spacer()
                
                // Show direction (if known)
                if let direction = item.trip.directionId {
                    Text(direction == 0 ? "Inbound" : "Outbound")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            // Departure & Arrival times
            let depSec = item.stopTime.departure?.time ?? 0
            let arrSec = item.stopTime.arrival?.time ?? 0
            HStack {
                Text("Departure: \(formattedTime(depSec))")
                Spacer()
                Text("Arrival: \(formattedTime(arrSec))")
            }
            .font(.subheadline)
            
            // Delay
            let delay = item.trip.delay ?? 0
            if delay > 0 {
                Text("Delayed by \(delay) min")
                    .foregroundColor(.red)
            }
            
            // schedule_relationship
            if let relationship = item.stopTime.scheduleRelationship {
                switch relationship {
                case "SKIPPED":
                    Text("Skipping this stop")
                        .foregroundColor(.orange)
                        .bold()
                case "SCHEDULED":
                    Text("Scheduled stop")
                        .foregroundColor(.green)
                default:
                    Text("\(relationship.capitalized) stop")
                        .foregroundColor(.blue)
                }
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Helper to format Unix timestamp -> time string
    private func formattedTime(_ seconds: Int) -> String {
        guard seconds > 0 else { return "--" }
        let date = Date(timeIntervalSince1970: TimeInterval(seconds))
        let formatter = DateFormatter()
        formatter.timeStyle = .short  // "h:mm a"
        return formatter.string(from: date)
    }
}




private func formattedTime(_ seconds: Int) -> String {
    let date = Date(timeIntervalSince1970: TimeInterval(seconds))
    let formatter = DateFormatter()
    formatter.timeStyle = .short  // or .medium, or custom like "h:mm a"
    return formatter.string(from: date)
}


struct FavoriteStopBar: View {
    @ObservedObject var viewModel: TripUpdateViewModel
    let stopID: String

    var body: some View {
        VStack(alignment: .leading) {
            Text("Favorite Stop: \(stopID)")
                .font(.title3)
                .bold()

            if viewModel.favoriteStopUpcomingTrips.isEmpty {
                Text("No upcoming trips for \(stopID)")
                    .foregroundColor(.secondary)
            } else {
                // Show the next 1 or 2 trains
                ForEach(viewModel.favoriteStopUpcomingTrips.prefix(2), id: \.trip.id) { item in
                    let delay = item.trip.delay ?? 0
                    HStack {
                        Text("Trip: \(item.trip.tripId)")
                        Spacer()
                        if delay > 0 {
                            Text("Delay: \(delay) min")
                                .foregroundColor(.red)
                        }
                    }
                }
            }
        }
        .padding()
        .background(Color(UIColor.secondarySystemBackground))
        .cornerRadius(8)
    }
}

struct FullTripStopsView: View {
    let trip: TripUpdate
    
    var body: some View {
        List(trip.stopTimeUpdates, id: \.stopId) { stu in
            VStack(alignment: .leading, spacing: 4) {
                Text("Stop: \(stu.stopId ?? "Unknown")")
                    .font(.headline)
                
                // Show if SKIPPED or SCHEDULED
                if let relationship = stu.scheduleRelationship {
                    if relationship == "SKIPPED" {
                        Text("Skipped").foregroundColor(.red)
                    } else {
                        Text(relationship.capitalized)
                    }
                }
                
                // Show arrival & departure times
                HStack {
                    Text("Arrival: \(formattedTime(stu.arrival?.time))")
                    Spacer()
                    Text("Departure: \(formattedTime(stu.departure?.time))")
                }
                .font(.caption)
            }
            .padding(.vertical, 4)
        }
        .navigationTitle("Full Trip: \(trip.tripId)")
    }

    private func formattedTime(_ time: Int?) -> String {
        guard let t = time, t > 0 else { return "--" }
        let date = Date(timeIntervalSince1970: TimeInterval(t))
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}
struct TripDetailsView: View {
    let trip: TripUpdate
    let stopTime: StopTimeUpdate
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Trip ID: \(trip.tripId)")
                .font(.title2)
            
            if let vehicleLabel = trip.vehicleLabel {
                Text("Vehicle: \(vehicleLabel)")
            }

            Text("Route ID: \(trip.routeId)")
            
            if let direction = trip.directionId {
                Text("Direction: \(direction == 0 ? "Inbound" : "Outbound")")
            }
            
            // More fields from TripUpdate:
            if let startTime = trip.startTime {
                Text("Start Time: \(startTime)")
            }
            if let startDate = trip.startDate {
                Text("Start Date: \(startDate)")
            }
            if let scheduleRel = trip.scheduleRelationship {
                Text("Schedule Relationship: \(scheduleRel)")
            }
            
            Divider()

            // Show the departure time or arrival time for this specific stop
            let depSec = stopTime.departure?.time ?? 0
            let arrSec = stopTime.arrival?.time ?? 0
            Text("Stop departure: \(formattedTime(depSec))")
            Text("Stop arrival: \(formattedTime(arrSec))")
            
            // If you want all the stops in this trip:
            NavigationLink("View All Stops for This Trip") {
                FullTripStopsView(trip: trip)
            }
            
            Spacer()
        }
        .padding()
        .navigationTitle("Trip Details")
    }

    // Format time helper:
    private func formattedTime(_ seconds: Int) -> String {
        guard seconds > 0 else { return "--" }
        let date = Date(timeIntervalSince1970: TimeInterval(seconds))
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}
