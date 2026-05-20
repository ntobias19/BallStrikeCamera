import Foundation

// MARK: - Overpass JSON Response

/// Raw decode targets for the Overpass API.
/// Docs: https://wiki.openstreetmap.org/wiki/Overpass_API/Overpass_QL
struct OSMResponse: Codable {
    let elements: [OSMElement]
}

enum OSMElementType: String, Codable {
    case node, way, relation
}

/// Sum-type decoder: Overpass mixes nodes/ways/relations in one `elements` array.
struct OSMElement: Codable {
    let type: OSMElementType
    let id: Int64
    let lat: Double?
    let lon: Double?
    let nodes: [Int64]?
    let tags: [String: String]?
    let members: [OSMRelationMember]?
}

struct OSMRelationMember: Codable {
    let type: OSMElementType
    let ref: Int64
    let role: String?
}

// MARK: - Classified Geometry

/// A way after node-ref resolution into coordinates.
struct OSMWayGeometry {
    let id: Int64
    let coordinates: [Coordinate]
    let tags: [String: String]

    var ring: PolygonRing {
        guard let first = coordinates.first,
              let last = coordinates.last,
              first != last else {
            return PolygonRing(coordinates: coordinates)
        }
        return PolygonRing(coordinates: coordinates + [first])
    }
    var centroid: Coordinate? { ring.centroid }

    func tag(_ key: String) -> String? { tags[key] }
    func intTag(_ key: String) -> Int? { tags[key].flatMap(Int.init) }
}

struct OSMPointGeometry {
    let id: Int64
    let coordinate: Coordinate
    let tags: [String: String]

    func tag(_ key: String) -> String? { tags[key] }
}

/// Output of the classifier: ways grouped by golf feature kind.
struct OSMClassified {
    var greens:    [OSMWayGeometry] = []
    var fairways:  [OSMWayGeometry] = []
    var tees:      [OSMWayGeometry] = []
    var bunkers:   [OSMWayGeometry] = []
    var water:     [OSMWayGeometry] = []
    var pins:      [OSMPointGeometry] = []
    var holeWays:  [OSMWayGeometry] = []   // golf=hole linestrings (typically tee→green centerline)
    var courseBoundaries: [OSMWayGeometry] = []
}
