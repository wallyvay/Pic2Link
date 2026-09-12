# 同名上传覆盖修复与验证

日期：2026-09-07。目标：原生 macOS Pic2Link，`Amanoya.Pic2Link 1.0.1 (1)`，仅本机更新。

## 原因与改动

没有源文件名的剪贴板截图经 `PhotoCaptionRenderer` 加字后一律使用 `image-caption.png`。此前 `ImageHostingService.uploadFile` 将该文件名直接拼入日期目录作为 object key，三张不同截图因此写入同一对象；并非仅复制了错误链接。同名 Finder 文件或其他处理结果也存在相同风险。

在统一对象路径生成入口为每次上传分配完整随机 UUID，例：`uploads/wmblog/2026/09/07/image-caption-<UUID>.png`。UUID 在签名/发请求前仅生成一次，所有对象存储及 WebDAV 上传请求、七牛 key 字段和返回的公开链接共用该路径。保持原目录设置、文件名主体和扩展名；本地文件、上传字节、MIME 类型、历史显示名均不改变。重复上传同一内容也生成新路径。Imgur/Flickr 保留既有服务端资源 ID 机制。

本轮文件：

- `Pic2Link/Services/OSSService.swift`：唯一远端文件名，以及可注入测试 URLSession 的入口；生产默认网络配置不变。
- `Pic2LinkTests/UploadObjectKeyTests.swift`：3 项请求级回归测试。
- `README.md`、`项目需求与开发文档.md`：区分源/显示文件名和远端对象名。
- 本验证记录。

## 验证

项目 `Pic2Link.xcodeproj`、scheme `Pic2Link`；独立目录 `/private/tmp/codex-apple-tests/Pic2Link/unique-uploads-20260907/`。

- `UnitTests.xcresult` / `unit-tests.log`：macOS arm64 非 UI XCTest，74/74 通过、0 失败、0 跳过，关闭套件内部并行。测试宿主不启动正常菜单栏业务；使用隔离的内存 URLProtocol，没有访问真实图床或读取用户凭据。
- 三张实际生成的不同 PNG 经真实文案渲染后，虽然显示文件名均为 `image-caption.png`，请求路径及返回 URL 互不相同，三份上传字节各自正确，MIME/扩展名匹配。
- OSS、S3、R2、七牛、又拍云、WebDAV 的两种路径模式覆盖同名、同内容重复上传；请求对象路径/七牛 key 与公开链接一致。
- 中文空格文件名、大写 GIF 扩展名、SVG、复合扩展名、无扩展名文件，以及无文件名的 GIF 自动识别上传均保留内容和类型。
- `release-build.log`：签名 Release arm64/x86_64 通用构建成功；仅有既有系统 AppIntents 元数据提示，无源代码编译警告。
- 本次只改上传对象命名，没有 UI 改动；未运行 macOS UI Tests、深浅色 UI 自动化或真实图床上传验收。没有使用 Mac UI 会话租约、键盘鼠标或输入法切换。
- 保留已有未提交改动，不改工程配置、Bundle ID、版本号、entitlements 或签名团队，不触及 App Store Connect；商店已有构建不包含本次修复。

## 本机安装

- 已安装并重新启动 `/Applications/Amano Design/Pic2Link.app`。
- 原版备份：`/Users/amano/Library/Application Support/Codex/AppBackups/Pic2Link/20260907-unique-uploads/Pic2Link.app`。
- 使用现有 `Apple Development: Li Wei (QWW3QX37XE)` / `W7XZ85M98K` 签名；安装前后身份、版本及 entitlements 一致。安装包 deep/strict 签名与双架构通过，原版备份签名通过。
- 安装与构建产物可执行文件 SHA-256 一致：`a15065397ee79fedf7821266d2efbaaf635ef03b087257fb8fc6dfed76acfe64`。旧进程正常退出，安装位置的新进程已运行；配置、历史、Keychain 和原图不修改。

## 边界

新链接会比旧链接多一段 UUID，这是避免同名覆盖的预期变化。旧 URL 和旧历史不迁移；已覆盖对象不能由此修复自动恢复，需要重新上传原图，或另行检查服务端是否曾启用版本保留。未执行任何远端恢复、删除或覆盖操作。
