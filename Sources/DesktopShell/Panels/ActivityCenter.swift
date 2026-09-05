import Foundation
import SwiftUI
import AIOSCore
import ProjectKernel

/// Activity Center (docs 06): the global process monitor. Every row is a
/// real running attempt from the projection — owner, state, and a
/// deterministic stop. No rows, no panel: absence is honest.
struct ActivityCenterPanel: View {
    @ObservedObject var model: AppModel
    let rendered: ProjectState

    var body: some View {
        let running = rendered.attempts.values.filter { $0.phase == .running }
        if !running.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "chart.bar.doc.horizontal")
                    Text("Activity Center").font(.headline)
                    Spacer()
                    Text("\(running.count) live").font(.caption).foregroundStyle(.secondary)
                }
                ForEach(Array(running), id: \.attemptID) { attempt in
                    row(for: attempt)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AIOSDesign.token(.surfacePanel), in: RoundedRectangle(cornerRadius: 8))
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Activity Center: \(running.count) running attempts")
        }
    }

    private func row(for attempt: AttemptRecord) -> some View {
        HStack(spacing: 12) {
            Circle().fill(Color.green).frame(width: 6, height: 6)
            VStack(alignment: .leading, spacing: 2) {
                Text(ownerLine(attempt)).font(.caption.weight(.medium))
                if let task = rendered.tasks[attempt.taskID] {
                    Text(task.objective).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer()
            Button("Stop") {
                let id = attempt.attemptID
                Task { await model.cancelAttempt(attemptID: id, reason: "activity center stop") }
            }
            .buttonStyle(.bordered)
            .font(.caption)
            .accessibilityLabel(stopLabel(attempt))
        }
        .padding(6)
        .background(AIOSDesign.token(.surfacePanel), in: RoundedRectangle(cornerRadius: 6))
    }

    private func ownerLine(_ attempt: AttemptRecord) -> String {
        let worker = attempt.worker?.workerID ?? "worker"
        let brain = attempt.worker?.model ?? attempt.worker?.runtime.rawValue ?? "?"
        return "\(worker) · \(brain)"
    }

    private func stopLabel(_ attempt: AttemptRecord) -> String {
        "Stop activity " + (attempt.worker?.workerID ?? "unknown")
    }
}
