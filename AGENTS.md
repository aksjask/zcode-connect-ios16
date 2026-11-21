# Zcode Connect iOS16

## 开发规范（必须遵守）
1. 每次改动之后，必须创建一个对应的 Git commit，以便后续追踪和回滚。
2. 每次改动之后，必须编写或更新相关的测试，并在交付给用户前，确保所有测试和验收全部通过（CI 的 `build` 与 `screenshots` 两个 job 必须全绿）。

## 项目背景备注
- 本仓库是 `PacoZhou1/zcode-connect` 的 iOS 16 兼容构建分支（`compat*`/`ZTheme` 兼容层负责降级 iOS 26 专属 API），新代码禁止直接使用 iOS 17+ 专属 API，一律走兼容层。
- 工程由 `ios/project.yml` 经 xcodegen 生成；改版本号只改 `project.yml`，并同步 `ZCodeMobileUITests/VerificationFlow.swift` 里的版本号断言。
