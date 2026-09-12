# 实况照片选择窗口尺寸修复

日期：2026-09-06。

`LivePhotoLibraryPicker.swift` 原先在创建 NSPanel 时传入 900×650，但赋值 `contentViewController = PHPickerViewController` 会采用系统选择器初始视图的小尺寸。之后设置 `minSize` 不会放大现有窗口，且该值包含标题栏。

修复为装入选择器后设置 `contentMinSize = 640×460`，然后 `setContentSize(900×650)`，最后居中和显示。选择、取消、过滤实况照片和上传流程保持原有实现；属于局部窗口 bug，无需变更 PRD。

使用原始实现与修复后的生产文件分别编译 AppKit/PhotosUI 运行探针，测量真实 NSPanel 内容区域（未选择或上传照片）：

| 时机 | 修复前 | 修复后 |
| --- | --- | --- |
| 首次打开 | 157×96 | 900×650 |
| 等待加载 2 秒 | 157×96 | 900×650 |
| 关闭后重新打开 | 157×96 | 900×650 |
| 重新打开后等待加载 | 157×96 | 900×650 |

修复后最小内容尺寸为 640×460。运行时持有 `macos-ui-session` 租约；原输入源 `com.tencent.inputmethod.wetype.pinyin`，测试切换并回读 ABC，结束后恢复原输入源并释放租约。没有启动 XCTest runner，未出现输入法授权错误；未验证真实照片选择或上传。

Release arm64+x86_64 构建通过，签名验证和 `git diff --check` 通过。产物和运行日志在 `dist/picker-size-20260906/`；隔离 DerivedData 在 `/private/tmp/codex-apple-tests/Pic2Link/picker-size-20260906/`。

已更新 `/Applications/Amano Design/Pic2Link.app`，校验签名、版本、entitlements 与可执行文件 SHA256，旧版备份记录见 `installation.json`。保留现有运行进程，退出并重新打开后生效。

本次未改变版本号、签名配置或 ASC 状态。此前提交审核的 1.0.1 (1) 安装包不包含这项修复；重新上传/替换待审构建需要独立发布操作，不能把本地安装视作已更新商店包。
