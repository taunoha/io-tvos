import SwiftUI

struct LiveChannelCard: View {
    let channel: LiveChannel
    @State private var schedules: [LiveSchedule] = []
    @State private var loaded = false

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let current = schedules.first { $0.contains(context.date) }
            VStack(alignment: .leading, spacing: 24) {
                Text(channel.title).font(.system(size: 48, weight: .bold))
                VStack(alignment: .leading, spacing: 8) {
                    Text(current?.title ?? (loaded ? "Saatekava pole saadaval" : "Saatekava laadimine…"))
                        .font(.system(size: 29, weight: .medium))
                        .lineLimit(2, reservesSpace: true)
                    Text(current?.timeRange ?? " ")
                        .font(IoDesign.metadata)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 370, alignment: .topLeading)
            .padding(32)
            .foregroundStyle(.white)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .task {
            while !Task.isCancelled {
                do {
                    schedules = try await LiveAPI.schedules(channel)
                } catch {
                    if Task.isCancelled { return }
                }
                loaded = true
                do { try await Task.sleep(for: .seconds(30)) }
                catch { return }
            }
        }
    }
}
