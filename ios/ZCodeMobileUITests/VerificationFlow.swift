import XCTest

/// 手机模拟操作验证：按真实用户流程逐步操作并断言 + 截图存证。
/// 前置：全新安装（无连接记录）→ 首屏为「连接你的电脑」。
final class VerificationFlow: XCTestCase {

    @MainActor
    func launchAndEnterReference() -> XCUIApplication {
        let app = XCUIApplication()
        app.launch()
        let skip = app.buttons["pairing.skip"]
        XCTAssertTrue(skip.waitForExistence(timeout: 15), "首屏应为连接页且左上角有「跳过」")
        skip.tap()
        let menu = app.buttons["home.menu"]
        XCTAssertTrue(menu.waitForExistence(timeout: 10), "跳过后应进入首页")
        return app
    }

    @MainActor
    func anyExists(_ app: XCUIApplication, _ label: String) -> Bool {
        app.buttons[label].exists || app.staticTexts[label].exists || app.cells[label].exists
    }

    @MainActor
    func snap(_ name: String) {
        let a = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        a.name = name
        a.lifetime = .keepAlways
        add(a)
    }

    // 1. 首次连接页：标题、主按钮、返回出口
    @MainActor
    func test01OnboardingPage() {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.staticTexts["连接你的电脑"].waitForExistence(timeout: 15), "页标题")
        XCTAssertTrue(app.staticTexts["扫描连接二维码"].exists, "扫码入口")
        XCTAssertTrue(app.staticTexts["粘贴连接信息"].exists, "粘贴入口")
        XCTAssertTrue(app.buttons["pairing.skip"].exists, "顶部跳过（返回出口）")
        XCTAssertTrue(app.buttons["pairing.guide"].exists, "连接指南")
        snap("01-onboarding")
    }

    // 2. 跳过 → 参考体验首页：默认按项目分组 + 行元素齐全
    @MainActor
    func test02HomeList() {
        let app = launchAndEnterReference()
        XCTAssertTrue(app.staticTexts["Demo Workspace"].waitForExistence(timeout: 8), "按项目分组头（默认排序）")
        XCTAssertTrue(app.staticTexts["登录页深色模式"].exists, "任务标题")
        XCTAssertTrue(app.buttons["home.new"].exists, "新建任务按钮")
        XCTAssertTrue(app.textFields["搜索聊天"].waitForExistence(timeout: 5) || app.staticTexts["搜索聊天"].exists, "底部搜索栏")
        snap("02-home")
    }

    // 3. 排序菜单三模式切换
    @MainActor
    func test03SortModes() {
        let app = launchAndEnterReference()
        app.buttons["home.menu"].tap()
        XCTAssertTrue(app.buttons["按分组"].waitForExistence(timeout: 6), "排序菜单出现")
        snap("03-menu")
        app.buttons["按项目"].tap()
        XCTAssertTrue(app.staticTexts["Demo Workspace"].waitForExistence(timeout: 6), "按项目分组头")
        app.buttons["home.menu"].tap()
        app.buttons["最近更新"].tap()
        XCTAssertTrue(app.staticTexts["昨天"].waitForExistence(timeout: 6), "最近更新按天分组")
        app.buttons["home.menu"].tap()
        app.buttons["按分组"].tap()
        XCTAssertTrue(app.staticTexts["未分组"].waitForExistence(timeout: 6), "按分组显示未分组区块")
        snap("03-group-sort")
    }

    // 4. 设置页 + 版本号显示
    @MainActor
    func test04SettingsVersion() {
        let app = launchAndEnterReference()
        app.buttons["home.menu"].tap()
        XCTAssertTrue(app.buttons["设置"].waitForExistence(timeout: 6), "设置菜单项")
        app.buttons["设置"].tap()
        XCTAssertTrue(app.staticTexts["外观"].waitForExistence(timeout: 8), "设置页打开")
        // Form 懒加载：关于区块在屏幕外，先滑动让其物化
        for _ in 0..<4 where !app.staticTexts["ZCode Mobile"].exists {
            app.swipeUp(velocity: .fast)
        }
        XCTAssertTrue(app.staticTexts["ZCode Mobile"].exists, "关于行")
        let versionShown = app.staticTexts.matching(NSPredicate(format: "label CONTAINS '1.19'")).firstMatch.exists
        let aboutLabel = app.staticTexts["ZCode Mobile"].label
        XCTAssertTrue(versionShown, "版本号显示应为 1.19，关于行内容为：")
        _ = aboutLabel
        snap("04-settings")
        app.buttons["完成"].tap()
        XCTAssertTrue(app.buttons["home.menu"].waitForExistence(timeout: 6), "关闭设置回首页")
    }

    // 5. IPA 安装器：输入直链后安装按钮出现
    @MainActor
    func test05IPAInstaller() {
        let app = launchAndEnterReference()
        app.buttons["home.menu"].tap()
        app.buttons["IPA 安装器"].tap()
        let field = app.textFields["ipa.urlField"]
        XCTAssertTrue(field.waitForExistence(timeout: 8), "IPA 安装器打开")
        field.tap()
        field.typeText("http://192.168.1.110:8666/demo.ipa")
        XCTAssertTrue(anyExists(app, "用 TrollStore 直接安装"), "巨魔安装按钮")
        XCTAssertTrue(anyExists(app, "下载到手机"), "下载按钮")
        snap("05-ipa")
        // 收起键盘后再点工具栏「关闭」
        if app.keyboards.count > 0 {
            app.keyboards.buttons["return"].firstMatch.tap()
        }
        app.buttons["关闭"].tap()
        XCTAssertTrue(app.buttons["home.menu"].waitForExistence(timeout: 6), "关闭回首页")
    }

    // 6. 聊天页：打开会话 → 输入框输入 → 发送按钮 → 返回
    @MainActor
    func test06ChatCompose() {
        let app = launchAndEnterReference()
        let row = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'session.'")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 8), "存在会话行")
        row.tap()
        let composer = app.textViews["composer.text"].waitForExistence(timeout: 5)
            ? app.textViews["composer.text"] : app.textFields["composer.text"]
        XCTAssertTrue(composer.waitForExistence(timeout: 8), "聊天输入框")
        composer.tap()
        composer.typeText("手机模拟验证消息")
        XCTAssertTrue(app.buttons["composer.send"].waitForExistence(timeout: 5), "发送按钮")
        snap("06-chat")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.buttons["home.menu"].waitForExistence(timeout: 8), "返回首页")
    }

    // 7. 全部项目任务（参考模式无 relay：应优雅降级不崩溃）
    @MainActor
    func test07AllProjectsGraceful() {
        let app = launchAndEnterReference()
        app.buttons["home.menu"].tap()
        XCTAssertTrue(app.buttons["全部项目任务"].waitForExistence(timeout: 6), "菜单入口")
        app.buttons["全部项目任务"].tap()
        XCTAssertTrue(app.staticTexts["全部项目任务"].waitForExistence(timeout: 8), "总览页打开")
        snap("07-all-projects")
        app.buttons["关闭"].tap()
        XCTAssertTrue(app.buttons["home.menu"].waitForExistence(timeout: 6), "关闭回首页")
    }
}

// 8. 手机模拟操作演示：验证「只有一条 → 全部任务」修复的完整操作流程。
//    通过 --demo-foreign-tasks 预置其他项目的任务，逐步点按并截图。
@MainActor
final class ForeignTaskSwitchDemo: XCTestCase {
    @MainActor
    func snap(_ name: String) {
        let a = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        a.name = name
        a.lifetime = .keepAlways
        add(a)
    }

    @MainActor
    func test08ForeignTaskSwitchDemo() {
        let app = XCUIApplication()
        app.launchArguments += ["--demo-foreign-tasks"]
        app.launch()

        // 步骤 1：首屏连接页
        let skip = app.buttons["pairing.skip"]
        XCTAssertTrue(skip.waitForExistence(timeout: 15), "首屏连接页")
        skip.tap()
        snap("step1-home-with-foreign-tasks")

        // 步骤 2：首页出现多个分组与其他项目的任务
        let sshRow = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'session.demo-f1'")).firstMatch
        XCTAssertTrue(sshRow.waitForExistence(timeout: 10), "其他项目的任务应出现在首页")
        XCTAssertTrue(app.staticTexts["服务器ssh信息：ubuntu 24.04 地址：200.200.202.96"].exists, "外来任务标题")
        snap("step2-home-all-projects")

        // 步骤 3：点击其他项目的任务 → 提示需先在电脑端打开该项目窗口（演示环境无已保存连接）
        sshRow.tap()
        XCTAssertTrue(app.alerts.firstMatch.waitForExistence(timeout: 6), "切换提示弹窗")
        snap("step3-switch-hint")
        app.alerts.firstMatch.buttons["好"].tap()

        // 步骤 4：回到首页，多条任务仍在
        XCTAssertTrue(app.buttons["home.menu"].waitForExistence(timeout: 8), "回到首页")
        XCTAssertTrue(app.staticTexts["egolite 浏览器自动化测试执行与验证"].exists, "多条任务仍在")
        snap("step4-back-home")
    }
}
