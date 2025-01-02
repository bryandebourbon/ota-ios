// GtfsModels.swift

import Foundation

// -------------------------------------------------
// MARK: - Shared GTFS Models
// -------------------------------------------------

public struct GtfsRealtimeFeed: Codable {
    public let header: Header
    public let entity: [GtfsEntity]
}

public struct Header: Codable {
    public let gtfsRealtimeVersion: String?
    public let incrementality: String?
    public let timestamp: Int?
}

public struct GtfsEntity: Codable {
    public let id: String
    public let isDeleted: Bool?
    public let tripUpdate: TripUpdateData?

    enum CodingKeys: String, CodingKey {
        case id
        case isDeleted    = "is_deleted"
        case tripUpdate   = "trip_update"
    }
}

public struct TripUpdateData: Codable {
    public let trip: Trip?
    public let vehicle: Vehicle?
    public let stopTimeUpdate: [StopTimeUpdate]?
    public let timestamp: Int?
    public let delay: Int?

    enum CodingKeys: String, CodingKey {
        case trip
        case vehicle
        case stopTimeUpdate = "stop_time_update"
        case timestamp
        case delay
    }
}

public struct Trip: Codable {
    public let tripId: String?
    public let routeId: String?
    public let directionId: Int?
    public let startTime: String?
    public let startDate: String?
    public let scheduleRelationship: String?

    enum CodingKeys: String, CodingKey {
        case tripId               = "trip_id"
        case routeId              = "route_id"
        case directionId          = "direction_id"
        case startTime            = "start_time"
        case startDate            = "start_date"
        case scheduleRelationship = "schedule_relationship"
    }
}

public struct Vehicle: Codable {
    public let id: String?
    public let label: String?
    public let licensePlate: String?

    enum CodingKeys: String, CodingKey {
        case id
        case label
        case licensePlate = "license_plate"
    }
}

public struct StopTimeUpdate: Codable {
    public let stopId: String?
    public let arrival: StopTimeEvent?
    public let departure: StopTimeEvent?
    public let scheduleRelationship: String?

    enum CodingKeys: String, CodingKey {
        case stopId              = "stop_id"
        case arrival
        case departure
        case scheduleRelationship = "schedule_relationship"
    }
}

public struct StopTimeEvent: Codable {
    public let delay: Int?
    public let time: Int?
    public let uncertainty: Int?
}

// An Identifiable wrapper for the “decoded” trip info
// that your SwiftUI views rely on
struct TripUpdate {
    let id: String
    let tripId: String
    let routeId: String
    let delay: Int?
    let stopTimeUpdates: [StopTimeUpdate]
    
    // New fields
    let directionId: Int?         // 0 or 1
    let vehicleLabel: String?     // e.g. "LW - Aldershot GO"
    let scheduleRelationship: String?  // e.g. "SCHEDULED" at the trip level, if available
    let startTime: String?        // e.g. "20:14:00"
    let startDate: String?        // e.g. "20250101"
}

