# 更多文件窗口与格式切换重新复制验证

日期：2026-09-12；项目 Pic2Link（macOS），基于工作区未提交改动，未改版本号与签名配置。

## 改动

- 弹出面板的「更多文件」按钮此前是空闭包，点击没有任何反应。现在通过 `.openHistoryRequested` 通知交给 `AppDelegate` 打开独立历史窗口，关闭菜单跟踪后创建或复用一个非 Released 窗口并置前。
- 历史窗口展示全部上传记录（弹出面板仍只显示最近 10 张），支持点击/右键复制链接、右键删除单条与清空全部；数据来自同一个 `MainViewModel`，上传、删除、清空后立即刷新。
- 语言切换时窗口标题与内容一起重建，窗口内容跟随 `locale` 与 `layoutDirection`，阿拉伯语下为 RTL。
- 勾选或取消「Markdown格式链接」时，先保存开关，再用新格式把最近一次上传的链接重新复制到剪切板、播放成功提示音、更新弹出面板状态并推送系统通知；历史为空时完全不写入剪切板。
- 复制通知复用 `NotificationManager`，但不再叠加系统提示音，避免与剪贴板写入的 Glass 音效重复播放。
- 历史单元格宽度固定为 104 pt；历史窗口用固定列宽网格，列数由 `HistoryGridLayout.columnCount(fitting:)` 按容器宽度算出，单元格不会超出列宽。

## 文件

- `Pic2Link/Pic2LinkApp.swift`：新增 `.openHistoryRequested` 通知、`historyWindow` 窗口管理、`showHistoryWindow()`、`refreshHistoryWindow()`，并接线 `onViewMore`。
- `Pic2Link/Views/HistoryWindowView.swift`：新增，历史窗口视图与 `HistoryGridLayout` 列计算，复用 `UploadedImageCell`。
- `Pic2Link/Views/UploadedImageSection.swift`：`UploadedImageCell` 增加显式 `cellWidth`（默认 104），缩略图与占位图都用它，不再使用自适应宽度。
- `Pic2Link/ViewModels/MainViewModel.swift`：剪贴板依赖可注入，`setCopyLinksAsMarkdown` 切换后调用 `recopyLatestUploadedLink()`。
- `Pic2Link/Services/NotificationManager.swift`：新增 `sendLinkCopiedNotification(link:)`。
- `Pic2Link/*.lproj/Localizable.strings`：13 语言新增 `notification.linkCopied`。
- `Pic2LinkTests/LinkClipboardTests.swift`：新增 2 项复制行为测试。
- `Pic2LinkTests/HistoryGridLayoutTests.swift`：新增 2 项网格列宽不变式测试。
- `README.md`、`项目需求与开发文档.md`：同步行为说明。

## 验证

独立目录：`/private/tmp/codex-apple-tests/Pic2Link/history-window-20260912/`。

- `DerivedData/`：Debug 构建（`CODE_SIGNING_ALLOWED=NO`，未经签名，不替换本机安装）。
- `Results/UnitTests-4.xcresult`：78/78 单元测试通过，0 失败、0 跳过（改动前基线 74 项）。
- `HistoryGridLayoutTests` 在 104–1600 pt 之间按 7 pt 步长校验「列数 × 104 + 间距 ≤ 容器宽度」，并固定 1 / 3 / 6 列三个常见窗口宽度的取值。新增两项分别是：`testLinkFormatTogglesRecopyLatestUploadInTheNewFormat`（开启时写入 `![最新](…)` 并播放一次提示音，关闭时写回纯 URL 并再播放一次）与 `testRecopyWithoutHistoryLeavesClipboardUntouched`（空历史时剪贴板保持 `keep` 且不播放提示音）。测试使用独立命名剪贴板与音效回调计数，不读写用户剪贴板、配置或图床凭据。
- 首次编译暴露并修复：`LinkClipboard()` 是 main actor 隔离的初始化器，不能作为默认参数求值，改为 `convenience init()` 显式传入。

## 回归修复（2026-09-12 晚）

用户回图反馈：弹出面板「已上传文件」和「更多文件」窗口的缩略图都超出宽度并互相叠加。

- 原因：首次实现把缩略图从固定 104 pt 改成 `.frame(maxWidth: .infinity)`。`Image.resizable()` 的固有宽度是原图宽度（手机截图可达数千 pt），网格测量单元格时按固有宽度计算，单元格被撑出列宽后互相重叠；弹出面板与历史窗口共用同一个单元格，因此两个界面同时出问题。
- 修复：`UploadedImageCell` 恢复 `frame(width:height:)` 并改为显式 `cellWidth` 参数；`HistoryWindowView` 改用固定列宽网格并按容器宽度计算列数，同时新增列宽不变式测试。
- 已重新构建签名 Release `1.0.1 (2)` 并替换本机安装，替换前备份为 `/Applications/Amano Design/Pic2Link Backups/Pic2Link-1.0.1-2-pre-grid-width-fix-20260912-2326.app`。
- 弹出面板与历史窗口的实际显示效果已由用户回图确认恢复正常；未运行 UI Tests。

## 未完成与风险

- 未运行 UI Tests：列宽不变式测试只覆盖列数计算，SwiftUI 实际渲染未自动校验（本次异常由用户发现，修复后由用户确认恢复正常）。窗口深浅色外观、阿拉伯语 RTL、长文件名截断和「更多文件」点击后的窗口置前仍未系统验收。
- Markdown 开关重新复制取的是历史第一条（最近一次上传）。若用户复制的是更早的记录，切换开关不会重放该条内容。
- 未验证首次点击「更多文件」时菜单跟踪是否在所有 macOS 版本下都干净退出。
