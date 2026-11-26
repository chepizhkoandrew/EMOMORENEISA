import SwiftUI
import PhotosUI

/// Entry for the Live Conversation mode: pick a topic and/or a photo, then
/// "call" the tutor. Hosts the call screen in place and the paywall on a 402.
struct LiveConversationView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var wallet = WalletManager.shared

    @State private var topic = ""
    @State private var photo: UIImage?
    @State private var pickerItem: PhotosPickerItem?
    @State private var showCamera = false
    @State private var activeCall: LiveCallConfig?

    private let quickPicks = [
        "Mi fin de semana", "Comida y restaurantes", "Viajes", "Mi trabajo o mis estudios",
        "Películas y series", "Música", "Planes para el futuro", "Vivir en Madrid"
    ]

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground()
                VStack(spacing: 0) {
                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 22) {
                            header
                            topicField
                            quickPicksSection
                            photoSection
                        }
                        .padding(24)
                    }
                    callButton
                }
            }
            .navigationTitle(L("Live Call"))
            .navigationBarTitleDisplayMode(.large)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbarBackground(AppColors.backgroundTop, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    BackButton { dismiss() }
                }
            }
        }
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self), let img = UIImage(data: data) {
                    photo = img
                }
                pickerItem = nil
            }
        }
        .fullScreenCover(isPresented: $showCamera) {
            CameraPickerView { photo = $0 }.ignoresSafeArea()
        }
        .fullScreenCover(item: $activeCall) { config in
            LiveCallView(config: config) { wantsPaywall in
                activeCall = nil
                if wantsPaywall {
                    // Present after the call cover is gone (two covers can't stack here).
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { wallet.showPaywall = true }
                }
            }
        }
        .fullScreenCover(isPresented: $wallet.showPaywall) {
            NavigationStack {
                PaywallView()
                    .toolbar {
                        ToolbarItem(placement: .navigationBarLeading) {
                            BackButton { wallet.showPaywall = false }
                        }
                    }
            }
        }
    }

    // MARK: - Sections

    private var header: some View {
        VStack(spacing: 10) {
            Image("professor_dog")
                .resizable()
                .scaledToFit()
                .frame(height: 120)
            Text(L("Talk Spanish in real time, like a phone call with a friendly tutor."))
                .font(.system(size: 17, weight: .medium, design: .rounded))
                .foregroundColor(AppColors.textSecondary)
                .multilineTextAlignment(.center)
        }
    }

    private var topicField: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L("What do you want to talk about?"))
                .font(.system(size: 19, weight: .semibold, design: .rounded))
                .foregroundColor(.white)
            ZStack(alignment: .topLeading) {
                if topic.isEmpty {
                    Text(L("e.g. \"my trip to Barcelona\" — or leave empty and just chat"))
                        .font(.system(size: 17, design: .rounded))
                        .foregroundColor(.white.opacity(0.45))
                        .padding(.horizontal, 18).padding(.vertical, 16)
                        .allowsHitTesting(false)
                }
                TextField("", text: $topic, axis: .vertical)
                    .font(.system(size: 17, design: .rounded))
                    .foregroundColor(AppColors.textPrimary)
                    .lineLimit(1...4)
                    .padding(.horizontal, 18).padding(.vertical, 16)
            }
            .background(AppColors.inputBackground)
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(AppColors.inputBorder, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
    }

    private var quickPicksSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L("Quick picks"))
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundColor(AppColors.textSecondary)
            FlowLayout(hSpacing: 10, vSpacing: 10) {
                ForEach(quickPicks, id: \.self) { pick in
                    let selected = topic == pick
                    Button { topic = selected ? "" : pick } label: {
                        Text(pick)
                            .font(.system(size: 15, weight: .medium, design: .rounded))
                            .foregroundColor(selected ? .black : AppColors.textPrimary)
                            .padding(.horizontal, 16).padding(.vertical, 10)
                            .background(selected ? Color.yellow : AppColors.inputBackground)
                            .overlay(RoundedRectangle(cornerRadius: 22).stroke(selected ? Color.yellow : AppColors.inputBorder, lineWidth: 1))
                            .clipShape(RoundedRectangle(cornerRadius: 22))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var photoSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L("Add a photo to talk about (optional)"))
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundColor(AppColors.textSecondary)

            if let photo {
                ZStack(alignment: .topTrailing) {
                    Image(uiImage: photo)
                        .resizable()
                        .scaledToFill()
                        .frame(maxWidth: .infinity)
                        .frame(height: 200)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                    Button { self.photo = nil } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 26))
                            .foregroundStyle(.white, .black.opacity(0.55))
                    }
                    .padding(10)
                }
            } else {
                HStack(spacing: 12) {
                    PhotosPicker(selection: $pickerItem, matching: .images) {
                        photoButtonLabel(icon: "photo.on.rectangle", title: L("Gallery"))
                    }
                    if UIImagePickerController.isSourceTypeAvailable(.camera) {
                        Button { showCamera = true } label: {
                            photoButtonLabel(icon: "camera.fill", title: L("Camera"))
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func photoButtonLabel(icon: String, title: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
            Text(title)
        }
        .font(.system(size: 16, weight: .semibold, design: .rounded))
        .foregroundColor(.white)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(AppColors.inputBackground)
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(AppColors.inputBorder, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private var callButton: some View {
        Button {
            activeCall = LiveCallConfig(topic: topic.trimmingCharacters(in: .whitespacesAndNewlines), photo: photo)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "phone.fill")
                Text(L("Start the call"))
            }
            .font(.system(size: 19, weight: .bold, design: .rounded))
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
            .background(GameColors.verde)
            .clipShape(RoundedRectangle(cornerRadius: 18))
            .shadow(color: GameColors.verde.opacity(0.4), radius: 12, y: 4)
        }
        .padding(.horizontal, 24)
        .padding(.top, 12)
        .padding(.bottom, 20)
        .background(AppColors.backgroundTop)
        .overlay(Rectangle().frame(height: 0.5).foregroundColor(AppColors.cardBorder), alignment: .top)
    }
}

// MARK: - Call screen

struct LiveCallView: View {
    /// `wantsPaywall`: the user tapped "Get more treats" after running out.
    let onClose: (_ wantsPaywall: Bool) -> Void
    @State private var model: LiveCallModel
    @State private var showCaptions = false
    @State private var pickerItem: PhotosPickerItem?
    @State private var showCamera = false
    @Environment(\.scenePhase) private var scenePhase

    init(config: LiveCallConfig, onClose: @escaping (_ wantsPaywall: Bool) -> Void) {
        self.onClose = onClose
        _model = State(initialValue: LiveCallModel(config: config))
    }

    var body: some View {
        ZStack {
            AppBackground()
            VStack(spacing: 0) {
                topBar
                Spacer(minLength: 12)
                avatar
                statusText.padding(.top, 18)
                Spacer(minLength: 12)
                if showCaptions && !model.isEnded {
                    captions.transition(.move(edge: .bottom).combined(with: .opacity))
                }
                if model.isEnded {
                    endedPanel
                } else {
                    controls
                }
            }
            .animation(.easeInOut(duration: 0.25), value: showCaptions)
        }
        .task { await model.begin() }
        .onChange(of: model.isEnded) { _, ended in
            // ProxyClient flips the global paywall flag on any 402; this cover
            // can't host it, so clear it and let "Get more treats" re-raise it.
            if ended { WalletManager.shared.showPaywall = false }
        }
        .onChange(of: scenePhase) { _, phase in
            // No background-audio mode: the call can't keep running hidden.
            if phase == .background { model.hangUp() }
        }
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self), let img = UIImage(data: data) {
                    model.sendPhoto(img)
                }
                pickerItem = nil
            }
        }
        .fullScreenCover(isPresented: $showCamera) {
            CameraPickerView { model.sendPhoto($0) }.ignoresSafeArea()
        }
        .onDisappear { model.hangUp() }
    }

    // MARK: Pieces

    private var topBar: some View {
        HStack {
            Text(timeString(model.elapsed))
                .font(.system(size: 17, weight: .semibold, design: .monospaced))
                .foregroundColor(AppColors.textSecondary)
            Spacer()
            if model.costPerMinute > 0 && !model.isEnded {
                Label(L("%d / min", model.costPerMinute), systemImage: "pawprint.fill")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundColor(AppColors.textSecondary)
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 16)
    }

    private var avatar: some View {
        let speaking = model.tutorSpeaking
        let ring = speaking ? 1.12 : 1.0 + CGFloat(model.micLevel) * 0.25
        return ZStack {
            Circle()
                .fill((speaking ? Color.yellow : GameColors.verde).opacity(0.18))
                .frame(width: 250, height: 250)
                .scaleEffect(model.phase == .live ? ring : 1)
                .animation(.easeOut(duration: 0.15), value: ring)
            Circle()
                .stroke((speaking ? Color.yellow : GameColors.verde).opacity(0.5), lineWidth: 3)
                .frame(width: 220, height: 220)
            Image("professor_dog")
                .resizable()
                .scaledToFit()
                .frame(height: 190)
                .offset(y: 14)
                .frame(width: 216, height: 216)
                .clipShape(Circle())
        }
        .frame(height: 260)
    }

    private var statusText: some View {
        Text(statusLine)
            .font(.system(size: 18, weight: .semibold, design: .rounded))
            .foregroundColor(.white)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 32)
            .contentTransition(.opacity)
    }

    private var statusLine: String {
        switch model.phase {
        case .preparing, .connecting: return L("Calling…")
        case .reconnecting: return L("Reconnecting…")
        case .live:
            if model.isMuted { return L("You're muted") }
            return model.tutorSpeaking ? L("Professor is talking — jump in anytime") : L("Your turn — just speak")
        case .ended(let reason):
            switch reason {
            case .hungUp: return L("Call ended")
            case .outOfTreats: return L("You're out of treats. Top up to keep talking.")
            case .maxDuration: return L("That's the longest call — take a break and call again!")
            case .connectionLost: return L("The connection dropped.")
            case .micDenied: return L("Allow microphone access in Settings to make calls.")
            case .interrupted: return L("The call was interrupted.")
            case .failed: return L("Couldn't connect. Please try again.")
            }
        }
    }

    private var captions: some View {
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 10) {
                    if model.lines.isEmpty {
                        Text(L("Captions will appear here."))
                            .font(.system(size: 15, design: .rounded))
                            .foregroundColor(AppColors.textTertiary)
                    }
                    ForEach(model.lines) { line in
                        captionRow(line).id(line.id)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
            }
            .frame(maxHeight: 260)
            .background(AppColors.cardBackground)
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(AppColors.cardBorder, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 18))
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
            .onChange(of: model.lines) { _, lines in
                if let last = lines.last { withAnimation { proxy.scrollTo(last.id, anchor: .bottom) } }
            }
        }
    }

    private func captionRow(_ line: LiveLine) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(line.role == .tutor ? L("Professor") : L("You"))
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundColor(line.role == .tutor ? .yellow : GameColors.verde)
            Text(line.text)
                .font(.system(size: 16, design: .rounded))
                .foregroundColor(line.isOpen ? AppColors.textSecondary : .white)
                .textSelection(.enabled)
        }
    }

    private var controls: some View {
        HStack(spacing: 22) {
            roundButton(icon: model.isMuted ? "mic.slash.fill" : "mic.fill",
                        active: model.isMuted, label: L("Mute")) { model.isMuted.toggle() }
            Menu {
                PhotosPicker(selection: $pickerItem, matching: .images) {
                    Label(L("Gallery"), systemImage: "photo.on.rectangle")
                }
                if UIImagePickerController.isSourceTypeAvailable(.camera) {
                    Button { showCamera = true } label: { Label(L("Camera"), systemImage: "camera.fill") }
                }
            } label: {
                roundButtonLabel(icon: "photo.fill", active: false, label: L("Photo"))
            }
            .disabled(model.phase != .live)
            roundButton(icon: "captions.bubble.fill", active: showCaptions, label: L("Captions")) {
                showCaptions.toggle()
            }
            Button { model.hangUp() } label: {
                VStack(spacing: 6) {
                    Image(systemName: "phone.down.fill")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(.white)
                        .frame(width: 64, height: 64)
                        .background(GameColors.rojo)
                        .clipShape(Circle())
                    Text(L("End"))
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundColor(AppColors.textSecondary)
                }
            }
            .buttonStyle(.plain)
        }
        .padding(.bottom, 28)
    }

    private func roundButton(icon: String, active: Bool, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { roundButtonLabel(icon: icon, active: active, label: label) }
            .buttonStyle(.plain)
    }

    private func roundButtonLabel(icon: String, active: Bool, label: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 22, weight: .semibold))
                .foregroundColor(active ? .black : .white)
                .frame(width: 58, height: 58)
                .background(active ? Color.white : Color.white.opacity(0.14))
                .clipShape(Circle())
            Text(label)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundColor(AppColors.textSecondary)
        }
    }

    private var endedPanel: some View {
        VStack(spacing: 14) {
            if case .ended(.outOfTreats) = model.phase {
                Button {
                    onClose(true)
                } label: {
                    panelButtonLabel(L("Get more treats"), color: .yellow, textColor: .black)
                }
            }
            Button { onClose(false) } label: {
                panelButtonLabel(L("Done"), color: Color.white.opacity(0.14), textColor: .white)
            }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 28)
    }

    private func panelButtonLabel(_ title: String, color: Color, textColor: Color) -> some View {
        Text(title)
            .font(.system(size: 18, weight: .bold, design: .rounded))
            .foregroundColor(textColor)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .background(color)
            .clipShape(RoundedRectangle(cornerRadius: 18))
    }

    private func timeString(_ s: Int) -> String {
        String(format: "%d:%02d", s / 60, s % 60)
    }
}
