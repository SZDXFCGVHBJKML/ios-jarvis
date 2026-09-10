import SwiftUI

struct Msg: Identifiable {
    enum Kind { case you, jarvis, error, image }
    let id = UUID()
    let kind: Kind
    let who: String
    var text: String
    var imageData: Data? = nil
}

@MainActor
final class ChatVM: ObservableObject {
    @AppStorage("serverURL") var serverURL =
        "https://iliyazas-b650-aorus-elite-ax.tail61b14a.ts.net"
    @Published var msgs: [Msg] = []
    @Published var models: [String] = []
    @Published var currentModel: String?
    @Published var busy = false
    @Published var status = "tap the core to speak"
    @Published var needsPassword: String? = nil     // model awaiting a password
    var modelKeys: [String: String] = [:]

    var api: JarvisAPI { JarvisAPI(base: serverURL) }
    let speech = SpeechManager()
    let player = WavPlayer()

    init() {
        speech.onFinal = { [weak self] text in
            Task { await self?.send(text) }
        }
        player.onDone = { [weak self] in self?.status = "tap the core to speak" }
        Task { await loadModels() }
    }

    func loadModels() async {
        do {
            models = try await api.models()
            if currentModel == nil {
                currentModel = models.first(where: { $0.lowercased().hasPrefix("earl") })
                    ?? models.first
            }
        } catch { /* offline: chips stay empty, retry on settings change */ }
    }

    func normKey(_ m: String?) -> String {
        (m ?? "").lowercased().replacingOccurrences(of: ":latest", with: "")
    }

    func send(_ text: String) async {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, !busy else { return }
        msgs.append(Msg(kind: .you, who: "you", text: t))

        // image intent, same shapes the web app understands
        if let prompt = Self.imagePrompt(t) {
            busy = true; status = "painting\u{2026} (can take a minute)"
            defer { busy = false }
            do {
                let r = try await api.image(prompt: prompt)
                if let err = r.error { throw JarvisError.server(err) }
                if let b64 = r.image, let data = Data(base64Encoded: b64) {
                    msgs.append(Msg(kind: .image, who: "comfyui", text: "", imageData: data))
                }
                status = "tap the core to speak"
            } catch {
                fail(error)
            }
            return
        }

        busy = true; status = "thinking\u{2026}"
        defer { busy = false }
        do {
            let r = try await api.chat(text: t, model: currentModel,
                                       voice: "earl", speed: 1.0,
                                       key: modelKeys[normKey(currentModel)] ?? "")
            if let err = r.error {
                if err.lowercased().contains("locked") {
                    needsPassword = currentModel
                    status = "tap the core to speak"
                    return
                }
                throw JarvisError.server(err)
            }
            let name = (currentModel ?? "jarvis")
                .replacingOccurrences(of: ":latest", with: "")
            msgs.append(Msg(kind: .jarvis, who: name, text: r.reply ?? ""))
            if let audio = r.audio, !audio.isEmpty {
                status = "speaking\u{2026}"
                player.play(base64: audio)
            } else {
                status = "tap the core to speak"
            }
        } catch {
            fail(error)
        }
    }

    func fail(_ error: Error) {
        let text = (error as? JarvisError)?.text ?? error.localizedDescription
        msgs.append(Msg(kind: .error, who: "system", text: text))
        status = "tap the core to speak"
    }

    func orbTapped() {
        if player.speaking { player.stop() }
        if speech.listening {
            speech.finish()
        } else if !busy {
            status = "listening\u{2026}"
            speech.start()
        }
    }

    static func imagePrompt(_ t: String) -> String? {
        let pattern = #"^(?:/image\s+|(?:make|generate|create|draw|paint)\s+(?:me\s+)?(?:an?\s+)?(?:image|picture|photo|painting|art)\s+(?:of\s+)?)(.+)"#
        guard let re = try? NSRegularExpression(pattern: pattern,
                                                options: [.caseInsensitive, .dotMatchesLineSeparators]),
              let m = re.firstMatch(in: t, range: NSRange(t.startIndex..., in: t)),
              let r = Range(m.range(at: 1), in: t) else { return nil }
        return String(t[r])
    }
}

enum JarvisError: Error { case server(String)
    var text: String { if case .server(let s) = self { return s }; return "error" } }

struct ContentView: View {
    @StateObject var vm = ChatVM()
    @State private var typed = ""
    @State private var showSettings = false
    @State private var passwordInput = ""

    var body: some View {
        VStack(spacing: 10) {
            header
            chips
            log
            deck
        }
        .padding(.horizontal, 14)
        .background(Hud.bg.ignoresSafeArea())
        .onAppear { vm.speech.requestPermissions() }
        .sheet(isPresented: $showSettings) { settings }
        .alert("password for \(vm.needsPassword?.replacingOccurrences(of: ":latest", with: "") ?? "")",
               isPresented: Binding(get: { vm.needsPassword != nil },
                                    set: { if !$0 { vm.needsPassword = nil } })) {
            SecureField("password", text: $passwordInput)
            Button("unlock") {
                if let m = vm.needsPassword {
                    vm.modelKeys[vm.normKey(m)] = passwordInput
                }
                passwordInput = ""
                vm.needsPassword = nil
            }
            Button("cancel", role: .cancel) { passwordInput = "" }
        }
    }

    var header: some View {
        HStack(spacing: 10) {
            Text("J.A.R.V.I.S.")
                .font(Hud.mono(17, weight: .semibold))
                .kerning(6)
                .foregroundColor(Hud.acc)
                .shadow(color: Hud.acc.opacity(0.5), radius: 7)
            Rectangle().fill(
                LinearGradient(colors: [Hud.acc.opacity(0.6), Hud.acc.opacity(0.06)],
                               startPoint: .leading, endPoint: .trailing))
                .frame(height: 1)
            Button { showSettings = true } label: {
                Image(systemName: "gearshape")
                    .foregroundColor(Hud.acc.opacity(0.7))
            }
        }
        .padding(.top, 6)
    }

    var chips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 7) {
                ForEach(vm.models, id: \.self) { m in
                    let name = m.replacingOccurrences(of: ":latest", with: "")
                    let on = m == vm.currentModel
                    Button {
                        vm.currentModel = m
                    } label: {
                        Text(name.uppercased())
                            .font(Hud.mono(10))
                            .kerning(1.2)
                            .padding(.horizontal, 9).padding(.vertical, 6)
                            .foregroundColor(on ? Hud.bg : Hud.acc.opacity(0.7))
                            .background(on ? Hud.acc : .clear)
                            .overlay(Rectangle().stroke(Hud.acc.opacity(0.35), lineWidth: 1))
                    }
                }
            }
        }
    }

    var log: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 13) {
                    ForEach(vm.msgs) { m in msgView(m).id(m.id) }
                }
                .padding(10)
            }
            .overlay(Corners())
            .onChange(of: vm.msgs.count) { _ in
                if let last = vm.msgs.last { withAnimation { proxy.scrollTo(last.id, anchor: .bottom) } }
            }
        }
    }

    @ViewBuilder
    func msgView(_ m: Msg) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(m.who.uppercased())
                .font(Hud.mono(9)).kerning(2.5)
                .foregroundColor(m.kind == .you ? Hud.dim : Hud.acc)
            switch m.kind {
            case .you:
                Text("\u{203A} " + m.text).font(Hud.mono(13)).foregroundColor(Hud.dim)
            case .jarvis:
                Text(m.text).font(Hud.mono(13.5)).foregroundColor(Hud.ink)
                    .padding(.leading, 10)
                    .overlay(alignment: .leading) { Rectangle().fill(Hud.line).frame(width: 1) }
            case .error:
                Text(m.text).font(Hud.mono(12)).foregroundColor(Hud.bad)
            case .image:
                if let d = m.imageData, let ui = UIImage(data: d) {
                    Image(uiImage: ui).resizable().scaledToFit()
                        .frame(maxWidth: 320)
                        .border(Hud.line, width: 1)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    var deck: some View {
        VStack(spacing: 10) {
            Text(vm.status)
                .font(Hud.mono(10)).kerning(2)
                .foregroundColor(Hud.dim)
                .textCase(.uppercase)
            Orb(state: vm.speech.listening ? .listening
                     : vm.busy ? .thinking
                     : vm.player.speaking ? .speaking : .idle)
                .frame(width: 92, height: 92)
                .onTapGesture { vm.orbTapped() }
            HStack(spacing: 8) {
                TextField("or type here\u{2026}", text: $typed)
                    .font(Hud.mono(14))
                    .foregroundColor(Hud.ink)
                    .padding(.vertical, 8).padding(.horizontal, 6)
                    .overlay(alignment: .bottom) {
                        Rectangle().fill(Hud.acc.opacity(0.35)).frame(height: 1)
                    }
                    .submitLabel(.send)
                    .onSubmit(sendTyped)
                Button("SEND", action: sendTyped)
                    .font(Hud.mono(11)).kerning(1.5)
                    .foregroundColor(Hud.acc)
                    .padding(.horizontal, 12).padding(.vertical, 9)
                    .overlay(Rectangle().stroke(Hud.acc.opacity(0.5), lineWidth: 1))
            }
        }
        .padding(.bottom, 8)
    }

    func sendTyped() {
        let t = typed
        typed = ""
        Task { await vm.send(t) }
    }

    var settings: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("SETTINGS").font(Hud.mono(12, weight: .semibold)).kerning(3)
                .foregroundColor(Hud.acc)
            Text("server url").font(Hud.mono(9)).kerning(2)
                .foregroundColor(Hud.dim).textCase(.uppercase)
            TextField("https://\u{2026}", text: vm.$serverURL)
                .font(Hud.mono(12))
                .foregroundColor(Hud.ink)
                .autocapitalization(.none)
                .disableAutocorrection(true)
                .padding(8)
                .overlay(Rectangle().stroke(Hud.acc.opacity(0.35), lineWidth: 1))
            Button("reload models") { Task { await vm.loadModels() } }
                .font(Hud.mono(11)).kerning(1.5)
                .foregroundColor(Hud.acc)
            Spacer()
        }
        .padding(20)
        .presentationDetents([.medium])
        .background(Hud.bg)
    }
}

enum OrbState { case idle, listening, thinking, speaking }

struct Orb: View {
    let state: OrbState
    @State private var spin = false
    @State private var pulse = false

    var body: some View {
        ZStack {
            Circle().fill(
                RadialGradient(colors: [Hud.acc.opacity(0.28), .clear],
                               center: .center, startRadius: 4, endRadius: 62))
                .blur(radius: 8)
            Circle().stroke(Hud.acc.opacity(0.2), lineWidth: 1)
                .overlay(Circle().trim(from: 0, to: 0.25)
                    .stroke(Hud.acc, lineWidth: 1)
                    .rotationEffect(.degrees(spin ? 360 : 0))
                    .animation(.linear(duration: 14).repeatForever(autoreverses: false),
                               value: spin))
            Circle()
                .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [2, 5]))
                .foregroundColor(Hud.acc.opacity(0.35))
                .padding(10)
                .rotationEffect(.degrees(spin ? -360 : 0))
                .animation(.linear(duration: 22).repeatForever(autoreverses: false),
                           value: spin)
            Circle().fill(
                RadialGradient(colors: [.white, Hud.hot, Hud.acc, .clear],
                               center: .center, startRadius: 1, endRadius: 24))
                .frame(width: 44, height: 44)
                .scaleEffect(coreScale)
                .animation(coreAnimation, value: pulse)
        }
        .onAppear { spin = true; pulse = true }
    }

    var coreScale: CGFloat {
        switch state {
        case .idle: return 1.0
        case .listening: return 1.25
        case .thinking: return pulse ? 1.15 : 0.66
        case .speaking: return pulse ? 1.2 : 0.85
        }
    }

    var coreAnimation: Animation? {
        switch state {
        case .thinking: return .easeInOut(duration: 0.8).repeatForever(autoreverses: true)
        case .speaking: return .easeInOut(duration: 0.45).repeatForever(autoreverses: true)
        default: return .easeOut(duration: 0.3)
        }
    }
}

struct Corners: View {
    var body: some View {
        GeometryReader { g in
            let s: CGFloat = 22
            Path { p in
                p.move(to: .init(x: 0, y: s)); p.addLine(to: .zero)
                p.addLine(to: .init(x: s, y: 0))
                p.move(to: .init(x: g.size.width - s, y: 0))
                p.addLine(to: .init(x: g.size.width, y: 0))
                p.addLine(to: .init(x: g.size.width, y: s))
                p.move(to: .init(x: g.size.width, y: g.size.height - s))
                p.addLine(to: .init(x: g.size.width, y: g.size.height))
                p.addLine(to: .init(x: g.size.width - s, y: g.size.height))
                p.move(to: .init(x: s, y: g.size.height))
                p.addLine(to: .init(x: 0, y: g.size.height))
                p.addLine(to: .init(x: 0, y: g.size.height - s))
            }
            .stroke(Hud.acc, lineWidth: 1)
        }
        .allowsHitTesting(false)
    }
}
