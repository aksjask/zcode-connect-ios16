# Zcode Connect — iOS 16 适配版构建说明

本分支在开源快照（`codex/native-remote`，commit eebaab4）基础上，把最低系统要求从 **iOS 26.0 降到 iOS 16.0**，用于在旧系统（例如 iOS 16.3 + 巨魔 TrollStore）上安装使用。

## 环境要求（Mac）

- macOS + **Xcode 26.x**（必须：工程里引用了 `Glass` / `GlassEffectTransition` 等 iOS 26 SDK 类型，旧 Xcode 无法编译；运行期由 `#available` 分支保护）
- Swift 6 工具链（随 Xcode 26）
- [XcodeGen](https://github.com/yonaskolb/XcodeGen)：`brew install xcodegen`

## 构建步骤

```sh
cd ios
xcodegen generate        # 重新生成工程（纳入改动文件、刷新部署目标）
open ZCodeMobile.xcodeproj
```

1. 选 `ZCodeMobile` scheme，目标设备选你的 iPhone（iOS 16+）。
2. Signing & Capabilities 里选择你自己的团队：
   - 免费 Apple ID 也可以（Xcode → Settings → Accounts 添加），7 天有效期——但配合巨魔安装则**无签名要求**，见下。
   - 如提示 Bundle ID 冲突，把 `PRODUCT_BUNDLE_IDENTIFIER`（当前 `dev.paco.zcode.mobile`）改成自己的唯一值。
3. 直接连真机 Cmd+R 运行调试；或继续下一步导出 IPA。

### 导出给巨魔（TrollStore）安装的 IPA

巨魔**不校验签名**，任何方式导出的 IPA 都能装，且永不过期：

1. Xcode 菜单 Product → Archive（目标选 "Any iOS Device (arm64)"）。
2. Window → Organizer → Distribute App → Custom → Development（或任意选项）导出 `.ipa`。
3. 把 `.ipa` 通过 AirDrop / 微信文件传到 iPhone。
4. iPhone 上打开 **TrollStore → Apps → 右上角 +** → 选择该 IPA → 安装。

> 偷懒做法：直接 Build 一次真机版本，把 `DerivedData/.../Debug-iphoneos/ZCodeMobile.app` 打包成 `Payload/ZCodeMobile.app` 结构 zip，改后缀 `.ipa` 也可以。

## 本次改动清单

| 文件 | 改动 |
|---|---|
| `ios/project.yml` | `deploymentTarget` 26.0 → 16.0 |
| `ios/ZCodeMobile.xcodeproj/project.pbxproj` | `IPHONEOS_DEPLOYMENT_TARGET` 同步改 16.0（跑过 xcodegen 后会被重新生成，无影响） |
| `ios/ZCodeMobile/Design/Theme.swift` | ① `ThemePreferences` 迁移为 `ObservableObject + @Published`；② `NativeGlassButtonStyle` 内部走兼容层；③ 文件尾部新增 **iOS 16 兼容层**（原独立文件 Compat26.swift 的内容，避免重新生成工程时漏编） |
| `ios/ZCodeMobile/Core/AppStore.swift` | `@Observable` → `ObservableObject`；全部存储属性加 `@Published`（计算属性除外）；`import Observation` → `import Combine` |
| `ios/ZCodeMobile/Core/SpeechCapture.swift` | 同上；`AVAudioApplication.requestRecordPermission()`（iOS 17+）→ `AVAudioSession.requestRecordPermission` 兼容封装 |
| `ios/ZCodeMobile/Core/Mirror/MirrorSession.swift` | 同上；补 `import Combine` |
| `ios/ZCodeMobile/Features/MessageView.swift` | `StreamingMessageTextState` 迁移；`renderer` 改 `@StateObject` |
| `ios/ZCodeMobile/App/ZCodeMobileApp.swift` | `@State` → `@StateObject`；`.environment(store)` → `.environmentObject(store)` |
| `ios/ZCodeMobile/App/AppShell.swift` | `@Environment(AppStore.self)` → `@EnvironmentObject`；删除局部 `@Bindable`；根部订阅 `ThemePreferences` 驱动全局主题色刷新 |
| 全部 Feature/Design 视图（16 个文件） | `@Environment(AppStore.self)` → `@EnvironmentObject`（16 处）；局部 `@Bindable var store = store` 删除（5 处，`@EnvironmentObject` 自带 `$store` 投影）；双参 `onChange` → `compatChange`（约 30 处）；`ContentUnavailableView` → `CompatUnavailableView`（8 处）；`glassEffect` / `GlassEffectContainer` / `glassEffectID` / `buttonStyle(.glass*)` → 兼容版本（约 20 处）；`defaultScrollAnchor` → `compatScrollAnchor`（6 处） |
| `ios/ZCodeMobile/Features/SettingsViews.swift` | 主题选择器显式订阅 `ThemePreferences`，选中态与预览实时刷新 |
| `ios/ZCodeMobile/Design/InlineVoiceControls.swift` | `let capture` → `@ObservedObject var capture` |

### 兼容层行为（Theme.swift 尾部）

| API | iOS 26+ | iOS 16 |
|---|---|---|
| `compatGlassEffect` | 真实 Liquid Glass | `.regularMaterial` 背景 |
| `compatGlassButton(.glass/.glassProminent)` | 系统玻璃按钮样式 | Material/Accent 胶囊按钮 + 按压缩放 |
| `CompatGlassEffectContainer` | 真实容器 | 直接渲染内容 |
| `compatChange(of:initial:)` | 系统 `onChange(of:initial:)` | `onAppear` + 旧版 `onChange(of:perform:)` |
| `compatScrollAnchor` | 系统 `defaultScrollAnchor` | 无操作 |
| `CompatUnavailableView` | —（16 直接用它） | 仿系统空状态布局 |
| `CompatAudio.requestRecordPermission` | — | `AVAudioSession` 旧接口 |

## 已知差异与注意事项

1. **未做编译验证**：本改动在 Windows 环境完成（无 Xcode）。转换均按"原调用形式包进 `#available` 分支"的原则机械替换，但 Swift 6 严格并发下不排除个别小错（大概率是几行 warning 级别），在 Xcode 里按报错微调即可。
2. **视觉**：iOS 16 上没有 Liquid Glass，按钮和浮层用 Material 近似，观感偏"扁平毛玻璃"。
3. **主题色**：根视图已订阅主题单例，全局 accent 实时刷新；个别直接读 `ZTheme.accent` 静态色的小组件（如状态点）可能到下一次自然刷新才变色。
4. **聊天滚动**：主聊天区的初始定位与滚动由自研 `StableTranscriptList` 驱动，iOS 16 行为一致；仅"新任务预览"的底部锚点在 iOS 17 以下不生效（打开时停在顶部，无功能影响）。
5. **性能**：AppStore 的部分私有簿记属性也加了 `@Published`（多一次无效视图刷新，无正确性影响）；如需极致性能可把纯内部状态上的 `@Published` 摘掉。
6. 构建时会出现旧版 `onChange(of:perform:)` 的 deprecation 警告，属预期，不影响运行。
7. 语音识别、扫码（DataScanner）、图片选择、通知等能力均为 iOS 16 可用 API，功能不受影响。

## 源项目

- 上游仓库：https://github.com/PacoZhou1/zcode-connect （MIT License）
- 本说明仅覆盖 iOS 16 适配差异；功能、连接方式、自建中转部署见原 `README.md` 与 `docs/DEVELOPMENT.md`。
