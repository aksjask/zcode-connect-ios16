import SwiftUI
import AVFoundation
import Combine
enum AccentTheme: String, CaseIterable, Identifiable {
    case violet, blue, teal, green, orange, rose
    var id: String { rawValue }
    var label: String {
        switch self {
        case .violet: "紫色"
        case .blue: "蓝色"
        case .teal: "青色"
        case .green: "绿色"
        case .orange: "橙色"
        case .rose: "玫瑰色"
        }
    }
    var rgb: (Double, Double, Double) {
        switch self {
        case .violet: (172, 120, 249)
        case .blue: (66, 139, 245)
        case .teal: (35, 155, 163)
        case .green: (65, 157, 95)
        case .orange: (223, 134, 48)
        case .rose: (219, 100, 151)
        }
    }
    var color: Color { Color(red: rgb.0 / 255, green: rgb.1 / 255, blue: rgb.2 / 255) }
}

@MainActor final class ThemePreferences: ObservableObject {
    static let shared = ThemePreferences()
    @Published var selection: AccentTheme {
        didSet { UserDefaults.standard.set(selection.rawValue, forKey: "accentTheme") }
    }
    private init() {
        selection = AccentTheme(rawValue: UserDefaults.standard.string(forKey: "accentTheme") ?? "") ?? .violet
    }
}

@MainActor enum ZTheme {
    @available(iOS 26.0, *) static var controlGlass: Glass {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--clear-tinted-glass") { return .clear.tint(.white.opacity(0.6)) }
        if ProcessInfo.processInfo.arguments.contains("--clear-glass") { return .clear }
        #endif
        return .regular
    }
    static var accent: Color { ThemePreferences.shared.selection.color }
    static let agentColors = [(42.0, 132.0, 79.0), (140.0, 83.0, 209.0), (46.0, 106.0, 219.0), (219.0, 61.0, 79.0)]
        .map { Color(red: $0.0 / 255, green: $0.1 / 255, blue: $0.2 / 255) }
    static var userText: Color {
        if ThemePreferences.shared.selection == .violet { return Color(red: 0.50, green: 0.27, blue: 0.89) }
        let rgb = ThemePreferences.shared.selection.rgb
        return Color(light: UIColor(red: rgb.0 / 340, green: rgb.1 / 340, blue: rgb.2 / 340, alpha: 1),
                     dark: UIColor(red: 0.4 + rgb.0 / 425, green: 0.4 + rgb.1 / 425, blue: 0.4 + rgb.2 / 425, alpha: 1))
    }
    static var userBubble: Color {
        if ThemePreferences.shared.selection == .violet {
            return Color(light: UIColor(red: 0.936, green: 0.897, blue: 0.996, alpha: 1),
                         dark: UIColor(red: 0.22, green: 0.15, blue: 0.33, alpha: 1))
        }
        let rgb = ThemePreferences.shared.selection.rgb
        return Color(light: UIColor(red: 0.88 + rgb.0 / 2125, green: 0.88 + rgb.1 / 2125, blue: 0.88 + rgb.2 / 2125, alpha: 1),
                     dark: UIColor(red: 0.06 + rgb.0 / 850, green: 0.06 + rgb.1 / 850, blue: 0.06 + rgb.2 / 850, alpha: 1))
    }
    static let background = Color(uiColor: .systemBackground)
    static let secondary = Color(uiColor: .secondaryLabel)
    static let listSecondary = Color(light: UIColor(white: 0.42, alpha: 1), dark: UIColor(white: 0.66, alpha: 1))
    static let searchPlaceholder = Color(light: UIColor(white: 151.0 / 255, alpha: 1), dark: UIColor(white: 0.66, alpha: 1))
    static let grouped = Color(uiColor: .secondarySystemGroupedBackground)
    static let separator = Color(uiColor: .separator).opacity(0.5)
    static let pageInset: CGFloat = 16
}

struct NativeGlassButtonStyle: PrimitiveButtonStyle {
    @ViewBuilder
    func makeBody(configuration: Configuration) -> some View {
        Button(configuration).compatGlassButton()
    }
}

extension Color {
    init(light: UIColor, dark: UIColor) {
        self.init(uiColor: UIColor { $0.userInterfaceStyle == .dark ? dark : light })
    }
}

struct SymbolButton: View {
    let symbol: String
    let label: String
    var size: CGFloat = 22
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: size, weight: .medium))
                .frame(width: 44, height: 44).contentShape(Circle())
        }
        .accessibilityLabel(label)
    }
}

struct GlassSearchField: View {
    @Binding var text: String
    var placeholder: String
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").font(.system(size: 17))
            TextField(placeholder, text: $text, prompt: Text(placeholder).foregroundColor(ZTheme.searchPlaceholder))
                .font(.system(size: 17))
                .submitLabel(.search)
                .autocorrectionDisabled()
                .accessibilityIdentifier("searchField")
            if !text.isEmpty {
                Button { text = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }.accessibilityLabel("清除搜索")
            }
        }
        .padding(.horizontal, 12).frame(height: 48)
        .compatGlassEffect(.control, in: Capsule())
        .measureLayout("search.\(placeholder)")
    }
}

struct StatusDot: View {
    var status: SessionStatus
    var body: some View {
        Group {
            if status == .running {
                ProgressView().controlSize(.mini).tint(ZTheme.accent)
                    .frame(width: 12, height: 12)
            } else {
                Circle().fill(color).frame(width: 7, height: 7)
            }
        }.accessibilityElement(children: .ignore).accessibilityLabel(status.label)
    }
    private var color: Color {
        switch status {
        case .running: ZTheme.accent
        case .waiting: .orange
        case .failed: .red
        case .completed: ZTheme.accent
        case .idle: .gray
        }
    }
}

struct ChangeCount: View {
    let additions: Int
    let deletions: Int
    var body: some View {
        HStack(spacing: 4) {
            Text("+\(additions)").foregroundStyle(.green)
            Text("−\(deletions)").foregroundStyle(.red)
        }.font(.system(size: 13, design: .monospaced))
    }
}

struct InlineNotice: View {
    var symbol = "info.circle"
    let text: String
    var body: some View {
        Label(text, systemImage: symbol)
            .font(.footnote).foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 16))
    }
}

// MARK: ============================================================
// MARK: - iOS 16 兼容层（Compat26）
// iOS 26+ 走真实 Liquid Glass / 新 API；更低版本用 Material 等系统组件近似替代。
// 所有 #available 分支内保持与原实现完全一致的调用形式。

/// 玻璃风格标记：26+ 映射到真实 Glass，低版本忽略。
enum ZGlassStyle {
    case regular
    case clear
    case control
    case regularTint(Color)
    case controlTintInteractive(Color)
}

/// .circle 边框形状是 iOS 17+，低版本退化为胶囊。
enum CompatButtonBorder { case circle, capsule }

extension View {
    @ViewBuilder
    func compatButtonBorderShape(_ shape: CompatButtonBorder) -> some View {
        if #available(iOS 17.0, *) {
            switch shape {
            case .circle: self.buttonBorderShape(.circle)
            case .capsule: self.buttonBorderShape(.capsule)
            }
        } else {
            self.buttonBorderShape(.capsule)
        }
    }
}

/// .presentationCompactAdaptation 是 iOS 16.4+。
enum CompatCompactAdaptation { case popover, sheet }

extension View {
    @ViewBuilder
    func compatPresentationCompactAdaptation(_ adaptation: CompatCompactAdaptation) -> some View {
        if #available(iOS 16.4, *) {
            switch adaptation {
            case .popover: self.presentationCompactAdaptation(.popover)
            case .sheet: self.presentationCompactAdaptation(.sheet)
            }
        } else {
            self
        }
    }
}

/// navigationDestination(item:) 是 iOS 17+；低版本用 isPresented 形式。
extension View {
    @ViewBuilder
    func compatNavigationDestination<V: Hashable, D: View>(item: Binding<V?>,
                                                           @ViewBuilder destination: @escaping (V) -> D) -> some View {
        if #available(iOS 17.0, *) {
            self.navigationDestination(item: item, destination: destination)
        } else {
            self.navigationDestination(isPresented: Binding(
                get: { item.wrappedValue != nil },
                set: { if !$0 { item.wrappedValue = nil } })) {
                if let item = item.wrappedValue { destination(item) }
            }
        }
    }
}

/// onScrollPhaseChange 是 iOS 18+；低版本无操作（仅性能探针使用）。
extension View {
    @ViewBuilder
    func compatScrollPhaseChange(_ handler: @escaping (String) -> Void) -> some View {
        if #available(iOS 18.0, *) {
            self.onScrollPhaseChange { _, phase in
                switch phase {
                case .idle: handler("idle")
                case .tracking: handler("tracking")
                case .interacting: handler("interacting")
                case .decelerating: handler("decelerating")
                case .animating: handler("animating")
                @unknown default: handler("other")
                }
            }
        } else {
            self
        }
    }
}

/// iOS 17+ 键帧渐隐动画；低版本无动画。
extension View {
    @ViewBuilder
    func compatKeyframeOpacityReveal(trigger: some Equatable, reduced: Bool) -> some View {
        if #available(iOS 17.0, *) {
            self.keyframeAnimator(initialValue: 0.0, trigger: trigger) { content, progress in
                content.opacity(1 - progress).offset(y: reduced ? 0 : 7 * progress)
            } keyframes: { _ in
                MoveKeyframe(0.65)
                CubicKeyframe(0, duration: 0.28)
            }
        } else {
            self
        }
    }
}

// MARK: - Liquid Glass（iOS 26+）

extension View {
    /// iOS 26+ 真实 Liquid Glass；低版本退化为 Material 背景近似。
    @ViewBuilder
    func compatGlassEffect(_ style: ZGlassStyle, in shape: some InsettableShape) -> some View {
        if #available(iOS 26.0, *) {
            switch style {
            case .regular: self.glassEffect(.regular, in: shape)
            case .clear: self.glassEffect(.clear, in: shape)
            case .control: self.glassEffect(ZTheme.controlGlass, in: shape)
            case .regularTint(let color): self.glassEffect(.regular.tint(color), in: shape)
            case .controlTintInteractive(let color): self.glassEffect(ZTheme.controlGlass.tint(color).interactive(), in: shape)
            }
        } else {
            switch style {
            case .clear:
                self.compatGlassSurface(shape, material: .ultraThinMaterial, shadow: false)
            case .regularTint(let color):
                self.background(color.opacity(0.14), in: shape)
                    .overlay(shape.strokeBorder(color.opacity(0.28), lineWidth: 0.5))
            case .controlTintInteractive(let color):
                // 选中态（传入 .black tint）：accent 浅底 + accent 描边，模拟原版选中玻璃。
                let selected = color == .black
                if selected {
                    self.background(ZTheme.accent.opacity(0.14), in: shape)
                        .overlay(shape.strokeBorder(ZTheme.accent.opacity(0.55), lineWidth: 1))
                } else {
                    self.compatGlassSurface(shape, material: .regularMaterial, shadow: false)
                }
            default:
                self.compatGlassSurface(shape, material: .regularMaterial)
            }
        }
    }

    /// iOS 16 上的玻璃近似：毛玻璃 + 发丝描边 + 顶部高光渐变 + 柔投影。
    func compatGlassSurface<S: InsettableShape>(_ shape: S, material: Material, shadow: Bool = true) -> some View {
        self
            .background(material, in: shape)
            .overlay(
                shape.strokeBorder(
                    LinearGradient(colors: [.white.opacity(0.45), .white.opacity(0.06)],
                                   startPoint: .top, endPoint: .bottom),
                    lineWidth: 0.8)
                    .allowsHitTesting(false)
            )
            .overlay(shape.strokeBorder(Color.black.opacity(0.06), lineWidth: 0.5).allowsHitTesting(false))
            .shadow(color: .black.opacity(shadow ? 0.10 : 0), radius: 9, x: 0, y: 2)
    }

    @ViewBuilder
    func compatGlassEffectID(_ id: some Hashable & Sendable, in namespace: Namespace.ID) -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffectID(id, in: namespace)
        } else {
            self
        }
    }

    @ViewBuilder
    func compatGlassEffectTransitionIdentity() -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffectTransition(.identity)
        } else {
            self
        }
    }

    /// 对应 `.buttonStyle(.glass)` / `.buttonStyle(.glass(.clear))`。
    @ViewBuilder
    func compatGlassButton(clear: Bool = false) -> some View {
        if #available(iOS 26.0, *) {
            if clear {
                self.buttonStyle(.glass(.clear))
            } else {
                self.buttonStyle(.glass)
            }
        } else {
            self.buttonStyle(CompatGlassButtonStyle(fallback: clear ? .clear : .regular))
        }
    }

    /// 对应 `.buttonStyle(.glassProminent)`。
    @ViewBuilder
    func compatGlassButtonProminent() -> some View {
        if #available(iOS 26.0, *) {
            self.buttonStyle(.glassProminent)
        } else {
            self.buttonStyle(CompatGlassButtonStyle(fallback: .prominent))
        }
    }
}

/// 低版本上的玻璃按钮替代样式：紧贴原标签（原系统玻璃自带内边距的视觉由外围 frame 承担），
/// 毛玻璃胶囊 + 发丝高光描边，prominent 用主题色实底。
struct CompatGlassButtonStyle: ButtonStyle {
    enum Fallback { case regular, clear, prominent }
    var fallback: Fallback = .regular

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(background, in: Capsule())
            .overlay(Capsule().strokeBorder(hairline, lineWidth: 0.8).allowsHitTesting(false))
            .foregroundStyle(foreground)
            .opacity(configuration.isPressed ? 0.72 : 1)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
    }

    private var hairline: LinearGradient {
        LinearGradient(colors: [.white.opacity(0.45), .white.opacity(0.06)],
                       startPoint: .top, endPoint: .bottom)
    }

    private var background: AnyShapeStyle {
        switch fallback {
        case .prominent: return AnyShapeStyle(ZTheme.accent)
        case .clear: return AnyShapeStyle(.ultraThinMaterial)
        case .regular: return AnyShapeStyle(.regularMaterial)
        }
    }

    private var foreground: Color {
        fallback == .prominent ? .white : .primary
    }
}

/// 对应 `GlassEffectContainer(spacing:)`；低版本直接渲染内容。
struct CompatGlassEffectContainer<Content: View>: View {
    var spacing: CGFloat = 0
    @ViewBuilder var content: () -> Content

    var body: some View {
        if #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: spacing, content: content)
        } else {
            content()
        }
    }
}

// MARK: - onChange（iOS 17 双参形式）

extension View {
    /// 替代 iOS 17 的 `onChange(of:initial:) { old, new in }` 双参形式。
    @ViewBuilder
    func compatChange<V: Equatable>(of value: V, initial: Bool = false,
                                    perform action: @escaping (V) -> Void) -> some View {
        if #available(iOS 17.0, *) {
            self.onChange(of: value, initial: initial) { _, newValue in action(newValue) }
        } else {
            self.modifier(CompatChangeSensor(value: value, initial: initial, action: action))
        }
    }
}

private struct CompatChangeSensor<V: Equatable>: ViewModifier {
    let value: V
    let initial: Bool
    let action: (V) -> Void

    func body(content: Content) -> some View {
        content
            .onAppear { if initial { action(value) } }
            .onChange(of: value) { newValue in action(newValue) }
    }
}

// MARK: - defaultScrollAnchor（iOS 17+）

enum CompatScrollAnchorKind { case alignment }


extension View {
    @ViewBuilder
    func compatScrollAnchor(_ anchor: UnitPoint) -> some View {
        if #available(iOS 17.0, *) {
            self.defaultScrollAnchor(anchor)
        } else {
            self
        }
    }

    @ViewBuilder
    func compatScrollAnchor(_ anchor: UnitPoint, for kind: CompatScrollAnchorKind) -> some View {
        if #available(iOS 18.0, *) {
            switch kind {
            case .alignment: self.defaultScrollAnchor(anchor, for: .alignment)
            }
        } else if #available(iOS 17.0, *) {
            // iOS 17 的单参版本即为对齐锚点语义
            self.defaultScrollAnchor(anchor)
        } else {
            self
        }
    }
}

// MARK: - ContentUnavailableView（iOS 17+）

/// 低版本上的空状态占位视图，布局仿系统 `ContentUnavailableView`。
struct CompatUnavailableView: View {
    var title: String
    var systemImage: String
    var description: Text

    init(_ title: String, systemImage: String, description: Text = Text("")) {
        self.title = title
        self.systemImage = systemImage
        self.description = description
    }

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(.secondary)
            Text(title).font(.title3.weight(.semibold))
            description.font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - 麦克风权限（AVAudioApplication 为 iOS 17+）

enum CompatAudio {
    static func requestRecordPermission() async -> Bool {
        await withCheckedContinuation { continuation in
            AVAudioSession.sharedInstance().requestRecordPermission { @Sendable granted in
                continuation.resume(returning: granted)
            }
        }
    }
}
