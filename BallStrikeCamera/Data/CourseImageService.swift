import Foundation
import MapKit
import UIKit
import SwiftUI

// MARK: - Course Image Service
// Provides course thumbnail images: MapKit satellite snapshot → disk cache → SwiftUI fallback.

@MainActor
final class CourseImageService: ObservableObject {
    static let shared = CourseImageService()

    private var memCache: [String: UIImage] = [:]
    private let fm = FileManager.default

    private var cacheDir: URL {
        fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("TrueCarry/courseImages", isDirectory: true)
    }

    private init() {
        try? fm.createDirectory(at: cacheDir, withIntermediateDirectories: true)
    }

    // Returns a UIImage for the course — from memory, disk, MapKit, or nil (use SwiftUI fallback).
    func thumbnail(for course: GolfCourse) async -> UIImage? {
        let key = course.id

        // 1. Memory cache
        if let img = memCache[key] { return img }

        // 2. Disk cache
        let diskURL = cacheDir.appendingPathComponent("\(key).png")
        if let data = try? Data(contentsOf: diskURL), let img = UIImage(data: data) {
            memCache[key] = img
            return img
        }

        // 3. MapKit satellite snapshot (requires coordinates)
        if let coord = course.coordinate, let img = await mapKitSnapshot(coord: coord) {
            memCache[key] = img
            try? img.pngData()?.write(to: diskURL)
            return img
        }

        return nil  // Caller renders TCCourseAerialThumbnail as fallback
    }

    // Clears cached image for a specific course (call when course data updates)
    func clearCache(for courseId: String) {
        memCache.removeValue(forKey: courseId)
        let url = cacheDir.appendingPathComponent("\(courseId).png")
        try? fm.removeItem(at: url)
    }

    // MARK: - MapKit snapshot

    private func mapKitSnapshot(coord: CLLocationCoordinate2D) async -> UIImage? {
        let opts = MKMapSnapshotter.Options()
        opts.region = MKCoordinateRegion(
            center: coord,
            latitudinalMeters: 1100,
            longitudinalMeters: 1100
        )
        opts.mapType = .satellite
        opts.size = CGSize(width: 320, height: 220)
        opts.scale = UIScreen.main.scale

        return await withCheckedContinuation { cont in
            MKMapSnapshotter(options: opts).start(with: .global(qos: .userInitiated)) { snap, _ in
                cont.resume(returning: snap?.image)
            }
        }
    }
}

// MARK: - CourseImageView
// SwiftUI view wrapper: shows MapKit snapshot when available, TCCourseAerialThumbnail as fallback.

struct CourseImageView: View {
    let course: GolfCourse
    var seed: Int = 0
    var cornerRadius: CGFloat = 10

    @State private var image: UIImage? = nil
    @State private var loading = false

    var body: some View {
        ZStack {
            if let img = image {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
            } else {
                TCCourseAerialThumbnail(seed: seed)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .task(id: course.id) {
            guard !loading else { return }
            loading = true
            image = await CourseImageService.shared.thumbnail(for: course)
            loading = false
        }
    }
}
