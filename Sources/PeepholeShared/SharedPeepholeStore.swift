import Foundation
import WidgetKit

public enum SharedPeepholeStore {
    private static let filename = "shared-peephole.json"

    public static var fileURL: URL? {
        AppGroup.containerURL?.appendingPathComponent(filename)
    }

    public static func write(_ state: SharedPeephole) {
        guard let url = fileURL,
              let data = try? JSONEncoder().encode(state) else { return }
        _ = try? data.write(to: url, options: [.atomic])
        WidgetCenter.shared.reloadAllTimelines()
    }

    public static func read() -> SharedPeephole {
        guard let url = fileURL,
              let data = try? Data(contentsOf: url),
              let s = try? JSONDecoder().decode(
                  SharedPeephole.self, from: data)
        else { return SharedPeephole() }
        return s
    }
}
