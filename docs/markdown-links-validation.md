# Markdown 链接与复制音效验证

日期：2026-09-05；原生 macOS Pic2Link，`Amanoya.Pic2Link 1.0.1 (1)`。

## 改动

- 菜单新增本地化“Markdown格式链接”勾选项，默认关闭，跨启动保存。
- 上传成功自动复制与历史记录点击/右键复制共用 `LinkClipboard`：开启时输出 `![](URL)` 或 `![文案](URL)`，关闭时保留原始 URL。
- 新上传的文案保存在对应 `UploadedImage.caption`；旧历史缺失该可选字段仍正常读取，使用空替代文本。即使上传时 Markdown 开关关闭，文案仍保留，之后可按当前选择复制。
- Markdown 中换行转为空格，语法字符转义，URL 空白编码；存储的原文案和原 URL 不改写。
- 手动复制成功写入剪贴板后播放现有 Glass 提示音；自动上传复制不另播一次，沿用上传完成通知的音效。没有新增复制横幅通知。
- Markdown 开关仅由菜单修改，保存其他设置会保留最近的菜单选择。

## 文件

- `Pic2Link/Services/LinkClipboard.swift`：统一格式与剪贴板写入、成功反馈边界。
- `Pic2Link/Models/ImageModels.swift`：可选历史文案及兼容旧配置的格式开关。
- `Pic2Link/ViewModels/MainViewModel.swift`：保存上传文案，接入两种复制入口，保留菜单设置。
- `Pic2Link/Pic2LinkApp.swift`：菜单勾选项及操作。
- `Pic2Link/Services/NotificationManager.swift`：复用 Glass 成功音效。
- `Pic2Link/*.lproj/Localizable.strings`：13 语言菜单名称。
- `Pic2LinkTests/LinkClipboardTests.swift`：7 项格式、持久化兼容及反馈顺序测试。
- `README.md`、`项目需求与开发文档.md`：同步功能约定。

## 验证

独立目录：`/private/tmp/codex-apple-tests/Pic2Link/markdown-links-20260905/`。

- `UnitTestsFinal.xcresult` / `unit-tests-final.log`：62/62 单元测试通过，0 失败、0 跳过。本功能 7 项验证旧配置与旧历史兼容、各条记录的文案独立保留、空文案、特殊字符与多行、签名 URL 保留、格式即时切换、写入完成后才触发反馈，以及自动复制不重复播放音效。
- 测试使用独立命名剪贴板和音效回调计数，不改用户剪贴板，不读取图床凭据，不上传真实图片。
- `release-build.log`：Release 的 arm64/x86_64 通用构建通过；沿用 Apple Development / W7XZ85M98K 签名，未改工程签名配置、entitlements、Bundle ID 或版本号。新增代码无编译警告，仅系统 AppIntents 元数据提示。
- 13 语言 221 个本地化键一致、无重复，全部通过 `plutil -lint`；`git diff --check` 通过。
- 原生 UI 检查尝试取得 `macos-ui-session` 后，被 ScreenCaptureKit `-3811`（音频/视频捕捉失败）阻止；没有继续操作界面。因此新菜单的深浅色显示与真实听感尚未验收，音效结果仅为成功后调用路径的测试证据。
- TIS API 记录原输入源 `com.tencent.inputmethod.wetype.pinyin`，自动检查前切为 `com.apple.keylayout.ABC` 并回读；结束后恢复原输入源并回读、释放租约。记录见 `input-source.json` / `ui-lease.log`。未操作系统权限弹窗。

## 安装

- 已更新 `/Applications/Amano Design/Pic2Link.app`。
- 旧版备份：`/Users/amano/Library/Application Support/Codex/AppBackups/Pic2Link/20260905-223555/Pic2Link.app`。
- 安装后 deep/strict 签名、双架构、可执行文件 SHA-256 均通过；签名要求和 entitlements 与旧版完全一致，配置、历史及 Keychain 未修改。
- 保留安装前正在运行的 Pic2Link 进程，需要退出并重新打开后使用新功能。证据见 `installation.json`。
