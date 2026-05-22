import SwiftUI
import WidgetKit
import PeepholeShared

/// Small Peephole layout: big eye icon at the top that goes red when
/// anything's active, "all clear" or "in use" headline, camera/mic
/// indicator chips below.
struct SmallView: View {
    let entry: PeepholeEntry

    // Peephole green — accent resolves to white on widget surface.
    private let peepholeGreen = Color(red: 0.36, green: 0.78, blue: 0.55)
    private let warningRed    = Color(red: 0.95, green: 0.35, blue: 0.35)

    var body: some View {
        VStack(spacing: 6) {
            Spacer(minLength: 0)
            Text("PEEPHOLE")
                .font(.system(size: 9, weight: .semibold))
                .tracking(1.5)
                .foregroundStyle(.secondary)

            Image(systemName: entry.state.anyActive
                  ? "eye.fill" : "eye.slash.fill")
                .font(.system(size: 30, weight: .bold))
                .foregroundStyle(entry.state.anyActive
                                 ? warningRed : peepholeGreen)

            Text(entry.state.anyActive ? "in use" : "all clear")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(entry.state.anyActive
                                 ? warningRed : Color.primary)

            HStack(spacing: 8) {
                indicator("video.fill",
                          on: entry.state.cameraActive)
                indicator("mic.fill",
                          on: entry.state.micActive)
            }
            .font(.system(size: 10))

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .multilineTextAlignment(.center)
        .padding(12)
    }

    private func indicator(_ symbol: String, on: Bool) -> some View {
        HStack(spacing: 3) {
            Image(systemName: symbol)
            Circle()
                .fill(on ? warningRed : Color.gray.opacity(0.4))
                .frame(width: 6, height: 6)
        }
        .foregroundStyle(on ? Color.primary.opacity(1) : Color.secondary.opacity(0.5))
    }
}
