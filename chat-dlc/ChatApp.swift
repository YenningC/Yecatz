import AppKit
import CoreText
import SwiftUI

@MainActor
private final class Chat: ObservableObject {
    @Published var history: [ChatMessage] = []
    @Published var partial = ""
    @Published var draft = ""
    @Published var keyDraft = ""
    @Published var error: String?
    @Published var busy = false
    @Published var configured = false
    @Published var showingSettings = false

    private var key: String?
    private var task: Task<Void, Never>?
    private var generation = UUID()
    private var pendingUser: ChatMessage?

    func refresh() {
        key = ChatKeychain.read()
        configured = key != nil
        showingSettings = !configured
    }

    func saveKey() {
        let value = keyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, !value.contains(where: { $0.isWhitespace }) else {
            error = "请输入完整的 OpenRouter API 密钥。"
            return
        }
        guard ChatKeychain.save(value) else {
            error = "macOS 钥匙串未能保存密钥，请重试。"
            return
        }
        key = value
        configured = true
        showingSettings = false
        keyDraft = ""
        error = nil
    }

    func removeKey() {
        guard ChatKeychain.remove() else {
            error = "macOS 钥匙串未能移除密钥，请重试。"
            return
        }
        stop()
        key = nil
        configured = false
        showingSettings = true
        keyDraft = ""
        error = nil
    }

    func send() {
        let text = String(draft.trimmingCharacters(in: .whitespacesAndNewlines).prefix(1000))
        guard let key, !showingSettings, !busy, !text.isEmpty else { return }
        let user = ChatMessage(role: "user", content: text)
        let messages = [ChatMessage(role: "system", content: persona())] + history.suffix(12) + [user]
        pendingUser = user
        partial = ""
        error = nil
        draft = ""
        busy = true
        let token = UUID()
        generation = token
        task = Task { [weak self] in
            do {
                try await ChatAPI.stream(key: key, messages: messages) { chunk in
                    guard let self, self.generation == token else { return }
                    self.partial += chunk
                }
                guard let self, self.generation == token else { return }
                self.history.append(user)
                self.history.append(ChatMessage(role: "assistant", content: self.partial.trimmingCharacters(in: .whitespacesAndNewlines)))
                self.history = Array(self.history.suffix(80))
                self.finish()
            } catch {
                guard let self, self.generation == token else { return }
                self.error = (error as? ChatAPI.Failure)?.errorDescription
                    ?? "连接 OpenRouter 失败，请检查网络后重试。"
                self.draft = user.content
                self.finish()
            }
        }
    }

    func stop() {
        generation = UUID()
        task?.cancel()
        if let pendingUser { draft = pendingUser.content }
        finish()
    }

    func clear() {
        stop()
        history.removeAll()
        draft = ""
        error = nil
    }

    var visibleUser: String? { pendingUser?.content }

    private func finish() {
        pendingUser = nil
        partial = ""
        busy = false
        task = nil
    }

    private func persona() -> String {
        let source = Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent("chat-dlc/persona.txt")
        for url in [source, Bundle.main.url(forResource: "persona", withExtension: "txt")].compactMap({ $0 }) {
            if let text = try? String(contentsOf: url, encoding: .utf8), !text.isEmpty {
                return text
            }
        }
        return "你是 Yecatz，一只高冷但不刻薄的西装橘猫桌宠。用简体中文和用户简短聊天。"
    }
}

private enum ChatType {
    static let portrait = Bundle.main.url(forResource: "cat", withExtension: "png").flatMap(NSImage.init(contentsOf:))
    static let name: String = {
        guard let url = Bundle.main.url(forResource: "pixel-zh-hans", withExtension: "ttf"),
              let descriptors = CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor],
              let descriptor = descriptors.first,
              let name = CTFontDescriptorCopyAttribute(descriptor, kCTFontNameAttribute) as? String
        else { return "Menlo" }
        CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        return name
    }()

    static func pixel(_ size: CGFloat) -> Font { .custom(name, size: size) }
}

private struct ChatView: View {
    @ObservedObject var chat: Chat
    @FocusState private var inputFocused: Bool
    private let ink = Color(red: 0.18, green: 0.14, blue: 0.16)
    private let paper = Color(red: 0.98, green: 0.95, blue: 0.89)
    private let peach = Color(red: 0.97, green: 0.83, blue: 0.70)

    var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle().fill(ink).frame(height: 2)
            transcript
            if let error = chat.error {
                Text(error)
                    .padding(.horizontal, 16).padding(.vertical, 8)
                    .foregroundStyle(Color(red: 0.55, green: 0.14, blue: 0.15))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Rectangle().fill(ink).frame(height: 2)
            composer
        }
        .font(ChatType.pixel(14))
        .foregroundStyle(ink)
        .background(paper)
        .frame(minWidth: 410, minHeight: 420)
        .onAppear {
            chat.refresh()
            inputFocused = chat.configured
        }
        .onDisappear { chat.stop() }
    }

    private var header: some View {
        HStack(spacing: 12) {
            if let cat = ChatType.portrait {
                Image(nsImage: cat).interpolation(.none).resizable().scaledToFit()
                    .frame(width: 38, height: 48).accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("Yecatz").font(ChatType.pixel(24))
                Text("OpenRouter · 免费模型").font(ChatType.pixel(12))
            }
            Spacer()
            Button("设置") { chat.showingSettings.toggle(); chat.error = nil }
                .disabled(!chat.configured || chat.busy)
            Button("清空对话") { chat.clear(); inputFocused = true }
                .disabled(chat.history.isEmpty && !chat.busy)
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .background(peach)
    }

    private var transcript: some View {
        ScrollViewReader { scroll in
            ScrollView {
                VStack(spacing: 13) {
                    if chat.showingSettings {
                        configuration
                    } else {
                        if chat.history.isEmpty && chat.visibleUser == nil {
                            message("Hi，I'm Yecatz。坐吧，今天怎么样？", user: false)
                        }
                        ForEach(chat.history) { item in
                            message(item.content, user: item.role == "user")
                        }
                        if let user = chat.visibleUser {
                            message(user, user: true)
                            message(chat.partial.isEmpty ? "…" : chat.partial, user: false)
                        }
                    }
                    Color.clear.frame(height: 1).id("bottom")
                }
                .padding(16)
            }
            .onChange(of: chat.history.count) { _, _ in scroll.scrollTo("bottom", anchor: .bottom) }
            .onChange(of: chat.partial) { _, _ in scroll.scrollTo("bottom", anchor: .bottom) }
            .onChange(of: chat.busy) { _, _ in scroll.scrollTo("bottom", anchor: .bottom) }
        }
    }

    private var configuration: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("配置聊天 API").font(ChatType.pixel(18))
            Text("创建一个 OpenRouter 密钥并粘贴到这里。聊天会发送给 OpenRouter 及其模型供应商，密钥保存在 macOS 钥匙串。")
            SecureField("OpenRouter API 密钥", text: $chat.keyDraft)
                .textFieldStyle(.roundedBorder)
                .onSubmit { chat.saveKey() }
            HStack {
                Link("获取密钥", destination: ChatAPI.keysPage)
                Button("保存") { chat.saveKey(); inputFocused = chat.configured }
                if chat.configured {
                    Button("移除密钥") { chat.removeKey() }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(peach.opacity(0.62))
    }

    private func message(_ text: String, user: Bool) -> some View {
        VStack(alignment: user ? .trailing : .leading, spacing: 5) {
            Text(user ? "你" : "Yecatz").font(ChatType.pixel(12))
            Text(text).lineSpacing(3).textSelection(.enabled)
                .padding(.horizontal, 12).padding(.vertical, 9)
                .background(user ? peach : Color.white)
                .overlay(Rectangle().strokeBorder(ink, lineWidth: 1))
        }
        .frame(maxWidth: .infinity, alignment: user ? .trailing : .leading)
    }

    private var composer: some View {
        HStack(spacing: 10) {
            TextField("跟 Yecatz 说点什么…", text: $chat.draft)
                .focused($inputFocused)
                .textFieldStyle(.roundedBorder)
                .disabled(!chat.configured || chat.busy || chat.showingSettings)
                .onSubmit { chat.send() }
                .onChange(of: chat.busy) { _, busy in
                    if !busy && chat.configured { inputFocused = true }
                }
            if chat.busy {
                Button("停止") { chat.stop() }
            } else {
                Button("发送") { chat.send() }
                    .disabled(!chat.configured || chat.showingSettings || chat.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(14)
    }
}

@main
struct YecatzChatApp: App {
    @StateObject private var chat = Chat()

    var body: some Scene {
        Window("和 Yecatz 聊天", id: "chat") { ChatView(chat: chat) }
            .defaultSize(width: 480, height: 500)
    }
}
