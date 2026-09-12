# 上传前添加文案：实现与验证

日期：2026-09-05。目标：原生 macOS Pic2Link，`Amanoya.Pic2Link`；保留 `1.0.1 (1)`。

## 当前行为

- 菜单栏及设置页提供持久化“上传前添加文案”开关，默认关闭；旧配置安全兼容。
- 图片准备好后在菜单栏图标下方展开文案面板。每个草稿独立保存文字，可同时叠加；最新面板激活并聚焦输入框。失焦不取消；提交、取消或关闭前层后聚焦剩余面板。
- Return 换行，Command-Return 或提交按钮确认当前草稿。非空文案原样复制到剪贴板，再关闭该面板，按提交顺序进入既有串行上传队列。未提交草稿不阻塞已确认的图片。
- 空串或仅空白字符可直接提交：保留源数据、文件名和类型，跳过文字合成，继续配置的压缩与上传；空白提交不清空剪贴板。上传成功仍自动复制最终 URL。
- 取消、Escape 或关闭按钮只取消对应图片，不复制其文案，不影响其他草稿或上传。Live Photo 的既有 GIF 转换先于文案面板，图片网络上传始终晚于确认。
- 非空文案使用直接链接的毛标标 `WMMarkCore`、`WMMarkRenderer` 自动排版。Pic2Link 自行适配 macOS Vision，无需安装或运行毛标标，无远端排版服务或字体下载。
- 静态图合成内存 PNG；GIF 保留帧、时长和循环，按首帧固定布局。合成失败终止当前项，不自动改传原图。所有合成前校正图像方向，历史缩略图取自实际上传内容。
- 13 语言共有 18 个 `caption.*` 键；普通文件保持原上传流程。开关、压缩和图床配置在进入流程时固定。

## 本轮主要文件

- `Pic2Link/Views/CaptionPromptController.swift`：菜单栏定位、独立面板、级联布局、焦点及键盘操作。
- `Pic2Link/Services/CaptionDraftStore.swift`：草稿只完成一次，提交时先复制，取消隔离。
- `Pic2Link/Services/CaptionUploadGate.swift`：空白跳过合成，取消与提交边界。
- `Pic2Link/ViewModels/MainViewModel.swift`：分离图片准备与上传队列，已提交文案进入原压缩/上传流程。
- `Pic2Link/Pic2LinkApp.swift`：绑定菜单栏图标，不让新草稿重置正在上传的进度。
- `Pic2Link/*/Localizable.strings`：可选文案、直接上传及设置说明，共 13 语言。
- `Pic2LinkTests/CaptionDraftTests.swift`、`CaptionUploadTests.swift`：草稿、顺序、空白压缩及原有渲染回归。
- `Pic2Link/Views/CaptionUITestHarness.swift`、`Pic2LinkUITests/CaptionUITests.swift`：真实面板测试入口与七项 UI 回归。测试入口使用独立剪贴板，不读取图床账户、不发网络上传，且不进入 Release。
- `README.md`、`项目需求与开发文档.md`：同步菜单栏叠加、提交顺序及空白直传约定。

## 本轮验证

独立产物目录：`/private/tmp/codex-apple-tests/Pic2Link/caption-dropdown-20260905/`。旧验证产物保留于 `caption-20260905/`。

- `UnitTests.xcresult` / `unit-tests.log`：55/55 单元测试通过，0 跳过、0 失败。本功能包括 4 项草稿/定位测试与 12 项确认门/渲染测试。
- `final-test-build.log`：最后调整测试入口的外观和辅助功能值后，全部测试目标编译通过；使用额外的 `FinalDebugDerivedData`，未覆盖用户正在操作的测试应用。
- 新增覆盖：后打开草稿先提交；复制在上传入队前；取消不复制；一个草稿只完成一次；窗口位于图标下且适配负坐标外接屏；空串/纯空白跳过合成后仍实际压缩为 80×60。
- 原有覆盖保留：开关与配置兼容、普通文件直通、确认前无上传、渲染失败阻断、实际 PNG 像素变化、JPEG 方向、GIF 帧数/时长/循环、多语言完整排版、主体 mask 顶部行方向。
- 原生 UI 操作（CUA）已验证：不点击直接向最新 Photo-2 草稿输入；Return 换行；Command-Return 关闭 Photo-2，Photo-1 保持独立空白并自动获焦；Photo-1 空白提交。测试结果明确为 `waiting,Photo-2:submitted,Photo-1:blank`，私有剪贴板仍为 Photo-2 的两行原文。截图及辅助功能状态记录在本任务工具输出中。
- XCTest UI 套件未完整通过：第一轮空白快捷提交、关闭取消已执行，但测试断言误读 macOS 静态文本的 label；已改为明确的可访问性 value。后续出现键盘事件合成超时；进程采样显示应用主线程处于正常事件循环。没有把这些失败计为通过。中断的 `CaptionUI*.xcresult` 不完整，以 `ui-tests*.log` 为证。
- 浅色面板已目视检查。启动参数未可靠改变旧测试入口外观，当前 DEBUG 入口已改成显式设置 Aqua/darkAqua；深色最终外观、纯空白按钮和 Escape 的整套 UI 回归仍待复核。没有进行真实图床网络上传。
- `release-build.log` / `release-verification.json`：Release 通用构建 `arm64 x86_64` 通过，`codesign --verify --deep --strict` 通过。本地验证采用 ad-hoc 签名；工程配置与本轮基线一致，Bundle ID、正式版本号、签名团队及 sandbox 配置未改，未覆盖本机安装目录。
- 13 语言全部 `.strings` 通过 `plutil -lint`；220 个键一致、无重复；`git diff --check` 通过。

## Mac UI 环境与用户接管

- 每次自动操作前取得 `macos-ui-session` 独占租约；TIS API 读取原输入源 `com.tencent.inputmethod.wetype.pinyin`，切为 `com.apple.keylayout.ABC` 并回读后执行。
- XCTest 期间检测到系统自动切回原输入源；测试中止后均恢复原输入源并回读，释放租约。没有授予第三方输入法或钥匙串新权限，本轮未操作 SecurityAgent 界面。
- 原生 CUA 验证核心路径后，检测到用户开始输入测试文案，停止自动键盘操作。保留该测试窗口供用户继续操作，停止看护脚本，恢复原输入源并释放租约。该窗口只做本地测试，不会上传到图床。状态见 `native-input-source.json`、`native-dark-input-source.json`。

## 边界

- 未提交草稿保留在内存；大量同时打开的高分辨率图片会占用更多内存，未实现磁盘草稿或重启恢复。
- 非空合成限制为 4,000 UTF-16 单元、单边 16,384 px、单帧 4,000 万 px、600 帧且累计 2 亿 px；未实现超大媒体分块渲染或完整排版编辑器。空白提交跳过渲染器的限制，仍受既有压缩/上传能力约束。
- 构建需同级 `../毛标标` 源码；最终应用不依赖该 App 进程或源码目录。静态图使用 PNG 中间结果，动画避让基于首帧。
- 保留同工作区另一个任务已有的 Live Photo 选择与文件就绪检测改动；不修改毛标标共享源码、iOS 工程或发布配置，因此不适用 GreenShell/APhone 部署。

## 2026-09-05 本机安装

用户确认安装后，按当前源码重新构建 Release 通用版本，沿用现有 Apple Development 签名和 `W7XZ85M98K` 团队；版本保持 `1.0.1 (1)`。

- 安装路径：`/Applications/Amano Design/Pic2Link.app`。
- 旧版备份：`/Users/amano/Library/Application Support/Codex/AppBackups/Pic2Link/20260905-220507/Pic2Link.app`。
- 安装前后通过 deep/strict 签名检查、双架构检查和可执行文件 SHA-256 一致性检查；签名要求与 entitlements 均和旧版一致。
- 原应用安装时未运行；没有修改偏好设置、上传历史或 Keychain 数据。本次只安装，没有额外启动应用或执行真实上传。
- 构建及安装证据：`/private/tmp/codex-apple-tests/Pic2Link/caption-install-20260905/build-signed.log`、`installation.json`。
