# 直接上传选中照片快捷键验证

日期：2026-09-05；原生 macOS Pic2Link，`Amanoya.Pic2Link 1.0.1 (1)`。

## 行为

- 固定全局 ⌘⇧U 从前台 Finder 或“照片”读取当前选择，支持多选；保留原可配置剪贴板快捷键（默认 ⌘U）。
- Finder 使用 selection（`sele`）和 URL（`pURL`）；Photos 使用 selection（`selc`）与 id（`ID  `）。Photos 本机脚本字典将 id 明确映射为 PhotoKit 的 `localIdentifier`。单张浏览仍依赖 Photos 公开接口提供的 selection，没有额外的当前查看器 API。
- 触发时固定前台 bundle ID / PID 和图床、文案、压缩设置。只读 Apple Events 在线程池中执行，单次请求超时 30 秒；不读取或模拟复制剪贴板。
- Finder 图片继续稳定性检测和大文件确认。PhotoKit 只查询指定资源 ID，读取 `.current` 图像数据、支持 iCloud 下载，并按实际数据类型保持 MIME 和扩展名一致；Live Photo 继续使用现有 GIF 开关。
- 所有成功读取的照片进入现有文案、空白跳过合成、压缩、上传和 Markdown 复制流程。非图片文件、视频、空选中、不支持的前台应用或读取失败都不会回退上传剪贴板。
- 菜单增加对应入口，设置说明新快捷键且禁止重叠保存；已有剪贴板快捷键若为 ⌘⇧U，新键优先并提示修改旧设置。

## 涉及文件

- `Pic2Link/Services/SelectedPhotoReader.swift`：原生 Apple Event 构造、目标固定、选中来源解析和错误映射。
- `Pic2Link/Services/PhotoLibraryImageSource.swift`：PhotoKit 授权及当前图像读取。
- `Pic2Link/Models/ImageModels.swift`：独立快捷键定义。
- `Pic2Link/Pic2LinkApp.swift`：第二个 Carbon 热键注册、菜单与前台应用捕获。
- `Pic2Link/ViewModels/MainViewModel.swift`：取图与现有上传队列衔接。
- `Pic2Link/Views/SettingsView.swift`：快捷键说明和冲突提示。
- `Pic2Link.xcodeproj/project.pbxproj`、13 语言 `InfoPlist.strings`：补自动化权限说明，更新图库读取用途；未改 entitlements、签名或版本配置。
- 13 语言 `Localizable.strings`：菜单、说明与错误。
- `Pic2LinkTests/SelectedPhotoReaderTests.swift`：8 项边界和解析测试。
- `README.md`、`项目需求与开发文档.md`：功能与使用边界同步。

## 验证

隔离工作目录：`/private/tmp/codex-apple-tests/Pic2Link/selection-shortcut-20260905/`。

- `UnitTests3.xcresult` / `unit-tests3.log`：70/70 单测通过，0 失败。新测试覆盖独立组合键、限定来源、目标 PID、Unicode/换行文件名、多选去重顺序、Finder 引用解析、Photos 稳定 ID、空选择、自动化拒绝、非文件 URL、超时，以及当前图像数据与扩展名一致。
- 初次测试修正了两个问题：PID 地址描述符要按原始数据读取，不能强制转成普通整数；`fileURLValue` 会将任意字符串强制转为文件路径，因此生产代码只对真正的文件描述符使用该转换，对对象引用显式读取 URL 属性。
- 所有 Apple Event 单测使用注入回包；没有跨 App 读取真实选择、没有请求图库权限、没有上传真实图片。原有测试继续使用隔离状态。
- `release-build.log`：Release arm64/x86_64 通用签名构建通过。新代码无编译警告；仅有未链接 AppIntents 的系统元数据提取提示。
- `static-checks.json`：13 语言各 231 个 Localizable 键、2 个 InfoPlist 键全部一致、无重复，通过 `plutil -lint`；`git diff --check` 通过。
- 最终 App 的 Bundle ID、版本/构建为 `Amanoya.Pic2Link 1.0.1 (1)`，两项 usage description 已写入，沿用 Apple Development / W7XZ85M98K。工程签名配置与 entitlements 保持原样。

构建和测试入口：

```sh
xcodebuild -project Pic2Link.xcodeproj -scheme Pic2Link \
  -configuration Debug -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath /private/tmp/codex-apple-tests/Pic2Link/selection-shortcut-20260905/DerivedData \
  -resultBundlePath /private/tmp/codex-apple-tests/Pic2Link/selection-shortcut-20260905/UnitTests3.xcresult \
  -only-testing:Pic2LinkTests -parallel-testing-enabled NO CODE_SIGN_IDENTITY=- test

xcodebuild -project Pic2Link.xcodeproj -scheme Pic2Link \
  -configuration Release -destination 'platform=macOS' \
  -derivedDataPath /private/tmp/codex-apple-tests/Pic2Link/selection-shortcut-20260905/ReleaseDerivedData \
  ARCHS='arm64 x86_64' ONLY_ACTIVE_ARCH=NO CODE_SIGN_IDENTITY='Apple Development' build
```

复跑测试时另选尚不存在的 resultBundlePath。

## 界面验收边界

- 已取得 `macos-ui-session` 租约，用 TIS API 记录原输入源 `com.tencent.inputmethod.wetype.pinyin`，切为 `com.apple.keylayout.ABC` 并回读确认。
- CUA 尝试获取已安装 Pic2Link 界面时，返回 ScreenCaptureKit `-3811` 音频/视频捕捉失败，未继续界面操作、未操作系统授权弹窗。不能据此判断有无输入法弹窗；没有启动 UI Test runner。
- 检查结束后恢复 `com.tencent.inputmethod.wetype.pinyin` 并回读，释放自身租约，见 `input-source.json` / `ui-lease.log`。
- Finder 实际多选、Photos 网格/单张浏览、新快捷键注册和菜单点击、首次授权、iCloud-only 图片与真实上传仍待开发者验收。PhotoKit 需要选中资源属于可访问的系统照片图库；不支持时明确提示，不会搜索其他库。
- 建议退出重开后，先开启文案开关，用测试照片在 Finder 和“照片”分别按 ⌘⇧U，核对弹出的照片后留空提交；再分别检查有文案、压缩、Live Photo GIF 和原 ⌘U。首次按系统提示手动允许自动化和照片读取。

## 安装

- 已更新 `/Applications/Amano Design/Pic2Link.app`。
- 旧版备份：`/Users/amano/Library/Application Support/Codex/AppBackups/Pic2Link/20260905-230952/Pic2Link.app`。
- staged 安装前后校验 deep/strict 签名、双架构、可执行文件 SHA-256；签名要求及 entitlements 与旧版一致。记录见 `installation.json`。
- 未修改用户配置、历史或 Keychain，未提交或发布到应用商店。
- 安装保留旧版运行进程；需要退出并重新打开 Pic2Link 后使用新快捷键。
