import Foundation

struct ModelResourceLoader {

    static func url(forModelResource name: String, extension ext: String = "json") -> URL? {
        // 1. Bundle "Models" subdirectory (preferred — folder reference registered in Xcode)
        if let url = Bundle.main.url(forResource: name, withExtension: ext, subdirectory: "Models") {
            print("[ModelResourceLoader] Bundled (Models/): \(name).\(ext)")
            return url
        }

        // 2. Bundle root fallback
        if let url = Bundle.main.url(forResource: name, withExtension: ext) {
            print("[ModelResourceLoader] Bundled (root): \(name).\(ext)")
            return url
        }

        // 3. Documents/Models
        if let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            let candidate = docs.appendingPathComponent("Models").appendingPathComponent("\(name).\(ext)")
            if FileManager.default.fileExists(atPath: candidate.path) {
                print("[ModelResourceLoader] Documents/Models: \(name).\(ext)")
                return candidate
            }
        }

        // 4. DEBUG simulator Downloads fallback (never ships on device)
        #if DEBUG
        let fallback = URL(fileURLWithPath: "/Users/noahtobias/Downloads/\(name).\(ext)")
        if FileManager.default.fileExists(atPath: fallback.path) {
            print("[ModelResourceLoader] DEBUG Downloads fallback: \(name).\(ext)")
            return fallback
        }
        #endif

        print("[ModelResourceLoader] Not found: \(name).\(ext)")
        return nil
    }

    static func logBundleCheck() {
        let models = ["vla_model", "flight_model", "ground_ball_size_calibration"]
        print("[ModelResourceLoader] === Bundle model check ===")
        for name in models {
            let found = url(forModelResource: name) != nil
            print("[ModelResourceLoader]   \(name).json: \(found ? "FOUND" : "MISSING")")
        }
        print("[ModelResourceLoader] =========================")
    }
}
