import Foundation
import ARKit

// MARK: - Persisted Vector Types
struct PersistedVector3: Codable {
    var x: Float
    var y: Float
    var z: Float
    
    init(_ v: simd_float3) {
        self.x = v.x
        self.y = v.y
        self.z = v.z
    }
    
    var simd: simd_float3 { simd_float3(x, y, z) }
}

struct PersistedVector2: Codable {
    var x: Float
    var y: Float
    
    init(_ v: simd_float2) {
        self.x = v.x
        self.y = v.y
    }
    
    var simd: simd_float2 { simd_float2(x, y) }
}

// MARK: - Persisted Models
struct PersistedWiFiMeasurement: Codable {
    var location: PersistedVector3
    var timestamp: Date
    var signalStrength: Int
    var networkName: String
    var speed: Double
    var frequency: String
    var roomType: RoomType?
}

struct PersistedRoom: Codable {
    var type: RoomType
    var wallPoints: [PersistedVector2]
    var center: PersistedVector3
    var area: Float
}

struct SavedSession: Codable {
    var id: UUID
    var name: String
    var createdAt: Date
    var updatedAt: Date
    var rooms: [PersistedRoom]
    var measurements: [PersistedWiFiMeasurement]
}

struct SavedSessionIndexItem: Codable {
    var id: UUID
    var name: String
    var createdAt: Date
    var updatedAt: Date
}

// MARK: - Session Manager
class SessionManager {
    static let shared = SessionManager()
    private init() {}
    
    private let sessionsDirectoryName = "Sessions"
    
    private var sessionsDirectoryURL: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let dir = docs.appendingPathComponent(sessionsDirectoryName, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
    
    private func sessionJSONURL(for id: UUID) -> URL {
        sessionsDirectoryURL.appendingPathComponent("\(id.uuidString).json")
    }
    
    private func worldMapURL(for id: UUID) -> URL {
        sessionsDirectoryURL.appendingPathComponent("\(id.uuidString).worldmap")
    }
    
    // MARK: - Save
    func saveSession(name: String,
                     rooms: [RoomAnalyzer.IdentifiedRoom],
                     measurements: [WiFiMeasurement],
                     worldMap: ARWorldMap?) throws -> SavedSession {
        let now = Date()
        let id = UUID()
        let persistedRooms: [PersistedRoom] = rooms.map { room in
            PersistedRoom(
                type: room.type,
                wallPoints: room.wallPoints.map { PersistedVector2($0) },
                center: PersistedVector3(room.center),
                area: room.area
            )
        }
        let persistedMeasurements: [PersistedWiFiMeasurement] = measurements.map { m in
            PersistedWiFiMeasurement(
                location: PersistedVector3(m.location),
                timestamp: m.timestamp,
                signalStrength: m.signalStrength,
                networkName: m.networkName,
                speed: m.speed,
                frequency: m.frequency,
                roomType: m.roomType
            )
        }
        let session = SavedSession(
            id: id,
            name: name,
            createdAt: now,
            updatedAt: now,
            rooms: persistedRooms,
            measurements: persistedMeasurements
        )
        try write(session)
        if let map = worldMap {
            try saveWorldMap(map, for: id)
        }
        return session
    }
    
    func updateSession(_ session: SavedSession) throws {
        try write(session)
    }
    
    private func write(_ session: SavedSession) throws {
        let url = sessionJSONURL(for: session.id)
        let data = try JSONEncoder().encode(session)
        try data.write(to: url, options: .atomic)
    }
    
    // MARK: - Load
    func listSessions() -> [SavedSessionIndexItem] {
        let dir = sessionsDirectoryURL
        guard let contents = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { return [] }
        let jsonFiles = contents.filter { $0.pathExtension.lowercased() == "json" }
        var items: [SavedSessionIndexItem] = []
        for file in jsonFiles {
            if let data = try? Data(contentsOf: file),
               let session = try? JSONDecoder().decode(SavedSession.self, from: data) {
                items.append(SavedSessionIndexItem(id: session.id, name: session.name, createdAt: session.createdAt, updatedAt: session.updatedAt))
            }
        }
        return items.sorted { $0.updatedAt > $1.updatedAt }
    }
    
    func loadSession(id: UUID) -> SavedSession? {
        let url = sessionJSONURL(for: id)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(SavedSession.self, from: data)
    }
    
    // MARK: - World Map
    func saveWorldMap(_ map: ARWorldMap, for id: UUID) throws {
        let data = try NSKeyedArchiver.archivedData(withRootObject: map, requiringSecureCoding: true)
        try data.write(to: worldMapURL(for: id), options: .atomic)
    }
    
    func worldMapData(for id: UUID) -> Data? {
        let url = worldMapURL(for: id)
        return try? Data(contentsOf: url)
    }
    
    // MARK: - Conversion Helpers
    func runtimeMeasurements(from persisted: [PersistedWiFiMeasurement]) -> [WiFiMeasurement] {
        return persisted.map { p in
            WiFiMeasurement(
                location: p.location.simd,
                timestamp: p.timestamp,
                signalStrength: p.signalStrength,
                networkName: p.networkName,
                speed: p.speed,
                frequency: p.frequency,
                roomType: p.roomType
            )
        }
    }
    
    struct SimpleRoom {
        let type: RoomType
        let wallPoints: [simd_float2]
        let center: simd_float3
        let area: Float
    }
    
    func simpleRooms(from persisted: [PersistedRoom]) -> [SimpleRoom] {
        persisted.map { p in
            SimpleRoom(type: p.type, wallPoints: p.wallPoints.map { $0.simd }, center: p.center.simd, area: p.area)
        }
    }
}