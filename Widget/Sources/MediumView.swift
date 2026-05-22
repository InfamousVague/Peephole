import SwiftUI
import WidgetKit
import PeepholeShared

struct MediumView: View {
    let entry: PeepholeEntry

    private let peepholeGreen = Color(red: 0.36, green: 0.78, blue: 0.55)
    private let warningRed    = Color(red: 0.95, green: 0.35, blue: 0.35)

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
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
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(entry.state.anyActive
                                     ? warningRed : Color.primary)

                Spacer(minLength: 0)
            }

            VStack(alignment: .leading, spacing: 6) {
                deviceList(symbol: "video.fill",
                           label: "Camera",
                           on: entry.state.cameraActive,
                           devices: entry.state.activeCameras)
                deviceList(symbol: "mic.fill",
                           label: "Microphone",
                           on: entry.state.micActive,
                           devices: entry.state.activeMics)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
    }

    private func deviceList(symbol: String,
                            label: String,
                            on: Bool,
                            devices: [String]) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: symbol)
                Text(label)
                    .font(.system(size: 10, weight: .medium))
                Spacer()
                Circle()
                    .fill(on ? warningRed : Color.gray.opacity(0.4))
                    .frame(width: 6, height: 6)
            }
            .foregroundStyle(on ? Color.primary.opacity(1) : Color.secondary.opacity(0.5))
            .font(.system(size: 10))

            if on, !devices.isEmpty {
                ForEach(devices.prefix(2), id: \.self) { name in
                    Text(name)
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .padding(.leading, 18)
                }
            } else if !on {
                Text("idle")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
                    .padding(.leading, 18)
            }
        }
    }
}
