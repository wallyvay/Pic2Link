# Pic2Link Mac App Store 发布

## 当前目标

**2026-09-11 15:51 最新回读：MAS 1.0.1 (2) 已重新提审，WAITING_FOR_REVIEW，选中构建 VALID，AFTER_APPROVAL，无分阶段发布，唯一审核项正确。** 审核专用配置与拒审修复说明均已回读。详见 [构建 2 提审记录](mas-build2-20260911.md)。以下拒审/私钥阻塞状态为历史记录。

2026-09-11 14:47：用户授权 MAS 新构建提审，本地已完成 Distribution `1.0.1 (2)` 导出及 73 项单测、2 项设置 UI 检查。上传私钥旧路径失效，未上传或重提审，ASC 仍选中拒审构建 1；详见 [build 2 记录](mas-build2-20260911.md)。

2026-09-11 14:33 更新：审核专用 RAM 凭据已通过真实连接、上传和公开读取验证；完整 OSS 配置已写入 ASC 审核 notes 并回读一致。其他审核字段及构建关系未变，仍为 1.0.1 (1) / REJECTED / AFTER_APPROVAL。仅审核配置阻塞已解除；新构建上传、App 沙盒流程验收与重新提审未完成。以下较早的“RAM 阻塞/未填审核配置”描述已被本条更新取代。

最新状态（2026-09-11 实时回读）：`1.0.1 (1)` 为 **REJECTED**，发布方式仍为 `AFTER_APPROVAL`。本地已修复 Finder 临时例外问题；审核专用 Bucket 已创建，但 RAM 凭据创建被现有 `codex` 身份权限阻止。尚未上传新构建、审核配置或重新提审。详情见 [本次修复记录](review-fix-20260911.md)。下文 9 月 6 日状态为历史记录。

- 产品与 App 内名称：Pic2Link。
- 用户确认的商店名：`Pic2Link: Image Uploader`；Apple App ID：`6809069103`。
- Bundle ID / SKU：`Amanoya.Pic2Link`；平台：`MAC_OS`。
- Developer Team：`W7XZ85M98K`；项目与 Scheme：`Pic2Link.xcodeproj` / `Pic2Link`。
- 版本与构建的唯一来源：工程 `MARKETING_VERSION` / `CURRENT_PROJECT_VERSION`，本次为 `1.0.1 (1)`，未递增。
- 原生资源 13 语言，对应 ASC：en-US、zh-Hans、zh-Hant、ko、ja、ru、es-ES、pt-BR、th、hi、fr-FR、ar-SA、de-DE。
- 定价目标：美国 USD 1.99、中国大陆 CNY 15；其他地区按美国基础价格的 Apple 等价价格，默认所有可用地区上架。
- 用户授权：完整上架，补齐资料并提审；审核通过后自动发布 `AFTER_APPROVAL`，关闭分阶段发布。

## 2026-09-06 发布状态

- 2026-09-06 08:13 创建商店记录；08:15 独立回读确认 Apple ID、Bundle ID、SKU、名称和主语言一致。
- 已为现有原始 Bundle ID 注册 Developer 标识 `7NA2C7PNB5`，回读 seedId 为 `W7XZ85M98K`，平台 `UNIVERSAL`。
- API 密钥不能执行 `apps CREATE`。已有 Apple ID fastlane 登录可用，选中 Li Wei 团队后，创建被 Apple 拒绝：**Pic2Link 名称已被其他账号使用**。
- 用户确认 `Pic2Link: Image Uploader` 后，通过现有 Apple ID 会话成功创建，原名失败不影响 App 内名称。Apple 初始版本为 1.0，已将可编辑版本对齐为 1.0.1，版本 ID `432a412d-0de5-4c5c-8a03-9114847ac44b`；发布方式已回读 `AFTER_APPROVAL`，无分阶段发布。
- 13 语言 metadata 已逐字段回读；39 张截图已全部 COMPLETE，并核对 2560×1600 尺寸、每语言 3 张、顺序、文件名及 MD5。分类为 PRODUCTIVITY。
- 隐私声明已发布，DATA_NOT_COLLECTED 已回读；年龄分级问卷按实际功能填写，包含 socialMedia/socialMediaAgeRestricted 新字段，无内容限制覆盖、不属于儿童专用 App。内容权利为 DOES_NOT_USE_THIRD_PARTY_CONTENT。
- 已按 Apple 当前价格点设置美国 USD 1.99、中国大陆 CNY 15；美国为基础地区，其他地区自动等价。175 个地区均 available=true，availableInNewTerritories=true，无预购。
- 08:26 安装包上传成功，Delivery UUID / Build ID `b8661459-72cd-44c5-910a-49e9d1302075`。08:29 回读精确 `1.0.1 (1)` 为 VALID，usesNonExemptEncryption=false；随后绑定到待审版本并独立回读成功。
- 09:52 使用用户提供的真实姓名、国际格式电话号码和已确认邮箱填写审核联系资料，连同审核说明逐字段回读成功；私人联系信息仅保存在忽略目录中，不写入源码。
- 09:53 提交后独立回读：版本与审核提交均为 **WAITING_FOR_REVIEW**；Submission ID `91bfa1ba-ec2e-4072-bab1-767635cdb192`。仅 1 个审核项且对应精确版本 ID，选中构建保持 VALID；`releaseType=AFTER_APPROVAL`，无分阶段发布。metadata、39 张截图、价格、175 地区及加密声明再次验证通过。
- 本次详细日志与基线在忽略目录 `dist/mas-20260905/`，无证书私钥或认证内容。

## 商店沙盒与审核说明

商店构建使用 `StoreBuild.xcconfig`、`Pic2Link/Store.entitlements`；普通本地构建保持原配置。商店版仅开启出站网络、用户选择文件只读、应用范围只读书签、照片图库访问和明确目标的 Apple Events。

- Photos 使用官方 `com.apple.Photos.library.read` scripting access group。
- Finder selection 和 URL 属性没有公开可用的对应 scripting access group，因此申请仅针对 `com.apple.finder` 的 Apple Events 临时例外；需在 Review Notes 说明固定快捷键触发、仅读取用户当前选择、不查询其他应用、不模拟复制。此例外是否获准由 Apple 审核决定。
- Finder 返回文件路径不会给沙盒读取权限。所选文件不可读时，使用系统 NSOpenPanel 让用户授权其所在文件夹，保存只读 security-scoped bookmark，后续按键复用；取消授权不会上传。
- 开机启动仅使用 SMAppService，商店构建不编译 LaunchAgents/launchctl 备用路径。
- 不替换用户本机的非沙盒安装，不修改其原配置、历史或 Keychain。两种分发方式之间的偏好迁移未作为已验证行为。

## 合规审计

- 数据路径：照片、文案及文件在本机合成/压缩，按用户选择直接发送到用户配置的图床；没有开发者中转、分析/广告 SDK、账号系统或追踪标识。凭据保存在 Keychain，公开图床配置、历史缩略图、文案与书签保存在本机。
- 云服务将收到上传内容、文件名、必要认证和网络连接信息；服务商按其政策处理。照片中的原始元数据在原样上传时可能保留，公开 URL 的可见性取决于图床配置。
- 仅链接兄弟仓库 `WMMarkCore` / `WMMarkRenderer`，未链接 WMMarkUI 的远程字体功能，没有第三方加密 SDK。
- 加密：URLSession 使用系统 HTTPS/TLS，Keychain 使用系统安全存储，OSS/S3/七牛/UPYUN/Flickr 等请求认证使用 Apple CryptoKit HMAC-SHA1、HMAC-SHA256、SHA256、MD5。没有自行实现加密算法。商店构建声明 `ITSAppUsesNonExemptEncryption = NO`，Archive、最终 PKG 和 ASC 构建均已回读为 false。
- `PrivacyInfo.xcprivacy` 申明本地偏好及所选文件稳定性检查所需 API 用途。ASC 隐私声明已通过会话接口发布并独立回读，证据为 `privacy-verification.json`。
- 无聊天、浏览器、公开内容社区、广告、博彩、健康建议或 IAP；一次付费购买 App，第三方存储费用由服务商决定。

## 已完成的本地检查与资料

- 普通单测及启用 `DEBUG APP_STORE` 的最终单测分别通过 71 项、零失败；后者结果位于 `/private/tmp/codex-apple-tests/Pic2Link/mas-20260905/FinalUnitTests.xcresult`，日志为 `dist/mas-20260905/final-unit-tests.log`。这不代表实际沙盒授权、Finder/Photos 交互或图床上传已验收。
- 13 种语言的 233 个 Localizable keys、2 个 InfoPlist keys 通过键集合、重复键及占位符检查；plist、Python 语法、Fastfile Ruby 语法及 `git diff --check` 通过。
- `fastlane/store-copy.json` 经 `scripts/prepare_store_metadata.py` 生成 13 语言 metadata，并通过 subtitle、description、keywords 长度限制检查；`name.txt` 使用已确认的商店名。翻译未经人工母语审校。
- DEBUG 专用真实视图渲染生成 78 张截图（13 语言、3 页面、深浅色），逐组查看全部 contact sheets。最终 `fastlane/screenshots/<locale>/` 每语言选 3 张，共 39 张 2560×1600 PNG；顺序为主页浅色、文案深色、设置浅色。生成器使用示例数据，不读取用户屏幕或图床凭据，不编入 Release。源图校验和见 `dist/mas-20260905/screenshot-manifest.json`。
- 截图时取得本任务 macOS UI 租约，输入源 ABC 已回读和恢复，完成后释放租约。截图仅作为真实视图与视觉检查证据，不等同于 UI XCTest。
- [隐私政策](https://github.com/wallyvay/Pic2Link/blob/store-legal/PRIVACY.md) 和 [支持页面](https://github.com/wallyvay/Pic2Link/issues) 均返回 HTTP 200。仅隐私文档发布至 GitHub `store-legal` 分支，commit `82efedad3cfe6881c4b1c4d8b36ca367212cd6e0`；没有提交本地源码改动。

## 签名产物与上传证据

- 已创建并安装 profile `Pic2Link Mac App Store`，UUID `4e14173e-8542-4864-973b-8483a825c8f4`，2027-07-25 到期；不要重复创建。
- Installer 证书 `3rd Party Mac Developer Installer: Li Wei (W7XZ85M98K)` 已创建并导入，Apple certificate ID `37858MWSQV`，2027-09-05 到期。签名资产保存在仓库外；fastlane 最终 WWDR 检查报错，但系统已验证实际 identity 有效，不要重建证书。
- Archive：`dist/mas-20260905/Pic2Link.xcarchive`。已验证 `Amanoya.Pic2Link 1.0.1 (1)`、arm64+x86_64、Apple Distribution/W7XZ85M98K、hardened runtime、App Sandbox、所需 Store entitlements、无 get-task-allow/入站网络、深度严格签名检查及加密字段 false。证据为 `archive-verification.json`。
- PKG 于 08:12 成功导出至 `dist/mas-20260905/export/Pic2Link.pkg`。`pkgutil --check-signature` 验证 Installer 签名，解包后再次核对 App 身份、双架构、Distribution 签名、profile、沙盒权限及 Boolean encryption=false。SHA256：`6e668728bc9afa37262254b8d34f6e6418dfc1c383d6736b6af3c37a7e03f237`。
- 同一 PKG 通过 Apple `altool --validate-app`（VERIFY SUCCEEDED with no errors），上传前重新核对 SHA256，随后 `altool --upload-package` 返回 UPLOAD SUCCEEDED with no errors。
- 证据文件位于 `dist/mas-20260905/`：`pkg-verification.json`、`apple-validation.log`、`binary-upload-identity.json`、`upload-binary.log`、`build-verification.json`、`metadata-verification.json`、`screenshots-verification.json`、`ratings-verification.json`、`privacy-verification.json`、`commerce-verification.json`。

## 已提审与剩余事项

1. 已按用户“请提审”的明确要求提交；接下来等待 Apple 审核，通过后自动公开发布。当前等待审核不等同于已上架。
2. 审核说明为 `docs/release/review-notes.txt`，包含图床配置步骤、菜单栏入口和 Finder 临时 Apple Events 权限解释。Finder 权限例外是否获准由 Apple 审核决定。
3. 实际沙盒 Finder/Photos 选择、文件夹授权和真实图床上传交互验收仍未完成；此前已向用户说明，不能以截图、单测或服务端包验证代替。
4. 最终证据：`review-preparation.json`、`review-submission-attempt.json`、`submission-verification.json`、`submit-review.log`；隐私声明通过会话接口在提审前后独立回读。后续只读检查现有提交，不重复创建、上传或提交。

原工作区改动保留；仅项目内发布工具和资料新增/更新，本机既有安装未被商店构建替换。已提交审核，尚未公开上架。

2026-09-06 12:00 后续本地修复：实况照片选择窗口尺寸已修复并更新本机非商店安装，见 `docs/live-photo-picker-size-validation.md`。本次未更改 ASC 或待审安装包；当前源码/本机安装包含该修复，已提交的 1.0.1 (1) 不包含。
