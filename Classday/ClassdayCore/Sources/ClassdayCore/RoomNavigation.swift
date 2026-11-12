import Foundation

public enum RoomDirections: Equatable, Sendable {
    case coordinate(latitude: Double, longitude: Double, name: String)
    case search(query: String)
    case missing
}

public enum RoomNavigation {
    /// A saved pin with both coordinates is a real destination. Otherwise search
    /// by the room or building name. Never invent a coordinate.
    public static func directions(location: String, pin: RoomPin?) -> RoomDirections {
        let trimmedLocation = location.trimmingCharacters(in: .whitespacesAndNewlines)
        let pinQuery = pin?.query.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let name = pinQuery.isEmpty ? trimmedLocation : pinQuery
        if let pin,
           let latitude = pin.latitude,
           let longitude = pin.longitude,
           (-90.0...90.0).contains(latitude),
           (-180.0...180.0).contains(longitude) {
            return .coordinate(latitude: latitude, longitude: longitude, name: name.isEmpty ? pin.name : name)
        }
        let query = trimmedLocation.isEmpty ? pinQuery : trimmedLocation
        if query.isEmpty { return .missing }
        return .search(query: query)
    }
}
