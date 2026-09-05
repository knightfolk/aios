import Foundation
import SwiftUI
import AIOSCore
import VoiceRuntime

/// Voice surface (docs 01/06): mic button routing through VoiceSession with
/// explicit target selection. The echo ASR double is the declared offline
/// brain; the mic input field is text until real capture lands with the
/// app-shell audio pipeline. Nothing here fakes hearing you.
struct VoicePanel: View {
    @ObservedObject var model: AppModel
    @State private var transcript: [String] = []
    @State private var input = ""
    @State private var target: VoiceTarget = .concierge
    @State private var session: VoiceSession?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "mic")
                Text("Voice").font(.headline)
                Spacer()
                Picker("Target", selection: $target) {
                    Text("Concierge").tag(VoiceTarget.concierge)
                    Text("This Project").tag(VoiceTarget.project("current"))
                }
                .pickerStyle(.segmented)
                .frame(width: 180)
            }
            HStack {
                TextField("speak (text input until the audio pipeline lands)", text: $input)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(send)
                Button("Send", action: send)
                .buttonStyle(.borderedProminent)
                .disabled(input.isEmpty)
                .accessibilityLabel("Send spoken input to \(targetLabel)")
            }
            ForEach(transcript.suffix(4), id: \.self) { line in
                Text(line)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(4)
                    .background(AIOSDesign.token(.surfacePanel), in: RoundedRectangle(cornerRadius: 4))
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AIOSDesign.token(.surfacePanel), in: RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .contain)
    }

    private var targetLabel: String {
        switch target {
        case .concierge: "Concierge"
        case .project: "this project"
        }
    }

    private func send() {
        let text = input
        guard !text.isEmpty else { return }
        input = ""
        transcript.append("you: \(text)")
        if session == nil {
            session = VoiceSession(asr: EchoASRAdapter(), tts: EchoTTSAdapter())
        }
        let currentSession = session!
        let currentTarget = target
        Task {
            let routed = try? await currentSession.utterance(
                fromBuffers: [VoiceBuffer(samples: [0.1], at: 0)], target: currentTarget
            )
            if let routed {
                transcript.append("heard (echo double): \(routed.transcript) → \(targetLabel)")
            }
            // Text input routes through the Concierge for real effects.
            await model.submitConcierge(text)
        }
    }
}
