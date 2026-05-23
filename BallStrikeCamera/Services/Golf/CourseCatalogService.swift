import Foundation
import CoreLocation
import Compression

// MARK: - Course Catalog (Supabase)
//
// The app's course database lives in Supabase:
//   • `courses` table  — 40k+ course catalog, searched via the `search_courses` RPC
//     (trigram name match + proximity ranking).
//   • Storage bucket `course-geometry/<course_uuid>.json.gz` — the full GolfCourse geometry,
//     gzipped, fetched on demand when a course is opened.
//
// Flow: search_courses(name, lat, lon, only_geometry) → best row's `id` → fetch + gunzip its
// geometry file → decode GolfCourse. No paid data; OSM-derived, attribution required.

enum CourseCatalog {
    private static let bucket = "course-geometry"

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    /// A lightweight catalog match returned by the search RPC.
    struct Match: Decodable {
        let id: String
        let name: String
        let latitude: Double?
        let longitude: Double?
        let dataTier: String?
    }

    /// Find a course in the catalog and load its geometry from Storage. Returns nil when there's
    /// no geometry-bearing match (caller falls back to live OSM).
    static func findGeometry(name: String, coordinate: CLLocationCoordinate2D?) async -> GolfCourse? {
        guard let config = SupabaseConfig.load() else { return nil }
        guard let match = await searchBest(name: name, coordinate: coordinate, config: config) else { return nil }
        return await loadGeometry(courseId: match.id, config: config)
    }

    // MARK: - Search RPC

    private static func searchBest(name: String,
                                   coordinate: CLLocationCoordinate2D?,
                                   config: SupabaseConfig) async -> Match? {
        let url = config.rpcBaseURL.appendingPathComponent("search_courses")
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue(config.anonKey, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(config.anonKey)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 12
        var body: [String: Any] = ["q": name, "only_geometry": true, "lim": 1]
        if let c = coordinate { body["lat"] = c.latitude; body["lon"] = c.longitude }
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)

        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
            let rows = (try? decoder.decode([Match].self, from: data)) ?? []
            return rows.first
        } catch {
            #if DEBUG
            print("[CourseCatalog] search failed: \(error.localizedDescription)")
            #endif
            return nil
        }
    }

    // MARK: - Geometry fetch from Storage

    private static func loadGeometry(courseId: String, config: SupabaseConfig) async -> GolfCourse? {
        let url = config.storageBaseURL
            .appendingPathComponent("object/public")
            .appendingPathComponent(bucket)
            .appendingPathComponent("\(courseId).json.gz")
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
            // Storage serves raw gzip bytes (no Content-Encoding header), so gunzip ourselves.
            let json = data.isGzip ? (data.gunzipped() ?? data) : data
            var course = try decoder.decode(GolfCourse.self, from: json)
            course.cachedAt = Date()
            return course.hasRealGeometry ? course : nil
        } catch {
            #if DEBUG
            print("[CourseCatalog] geometry fetch failed (\(courseId)): \(error.localizedDescription)")
            #endif
            return nil
        }
    }
}

// MARK: - Gzip inflate (Apple Compression framework)

extension Data {
    var isGzip: Bool { count >= 2 && self[startIndex] == 0x1f && self[startIndex + 1] == 0x8b }

    /// Inflate standard gzip data. Strips the 10-byte gzip header and raw-inflates the DEFLATE
    /// stream with COMPRESSION_ZLIB. Returns nil on failure.
    func gunzipped() -> Data? {
        guard count > 18 else { return nil }                    // header(10) + trailer(8)
        let deflate = subdata(in: (startIndex + 10)..<endIndex) // skip gzip header

        let bufferSize = 1 << 16
        var output = Data()
        let streamPtr = UnsafeMutablePointer<compression_stream>.allocate(capacity: 1)
        defer { streamPtr.deallocate() }
        guard compression_stream_init(streamPtr, COMPRESSION_STREAM_DECODE, COMPRESSION_ZLIB) == COMPRESSION_STATUS_OK else { return nil }
        defer { compression_stream_destroy(streamPtr) }

        let dst = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { dst.deallocate() }

        return deflate.withUnsafeBytes { (src: UnsafeRawBufferPointer) -> Data? in
            guard let srcBase = src.bindMemory(to: UInt8.self).baseAddress else { return nil }
            streamPtr.pointee.src_ptr = srcBase
            streamPtr.pointee.src_size = deflate.count
            streamPtr.pointee.dst_ptr = dst
            streamPtr.pointee.dst_size = bufferSize
            while true {
                let status = compression_stream_process(streamPtr, Int32(COMPRESSION_STREAM_FINALIZE.rawValue))
                switch status {
                case COMPRESSION_STATUS_OK, COMPRESSION_STATUS_END:
                    let produced = bufferSize - streamPtr.pointee.dst_size
                    if produced > 0 { output.append(dst, count: produced) }
                    streamPtr.pointee.dst_ptr = dst
                    streamPtr.pointee.dst_size = bufferSize
                    if status == COMPRESSION_STATUS_END { return output }
                default:
                    return nil
                }
            }
        }
    }
}
