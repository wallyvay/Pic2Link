# 项目内 fastlane

目标身份、实时阻塞与提审配置见 [app-store-connect.md](app-store-connect.md)，版本规则见 [versioning.md](versioning.md)。

当前入口：仓库根目录执行 `fastlane mac <lane>`。本机 Homebrew fastlane 自带 Ruby/gems，勿依赖系统 Ruby 加载 Spaceship。

2026-09-11 构建 2 重提审使用独立 `resubmission stage:<inspect|wait|metadata|prepare|submit|verify>`，由 `resubmission_support.rb` 实现。目标校验为 `CONFIRM_PIC2LINK_BUILD2=6809069103|Amanoya.Pic2Link|MAC_OS|1.0.1|2|AFTER_APPROVAL`，使用既有 ASC_API 环境变量传入密钥路径，正文日志关闭。`metadata` 只改 Description 并校验 QA 哈希；`prepare` 选择 VALID 构建 2、保留 OSS 凭据及联系人并更新修复说明；`submit` 仅操作原提交唯一版本项，使用 Apple 官方 `reviewSubmissionItems` 的 `resolved=true` 解决拒审后提交；`verify` 独立回读最终状态。结果在 `dist/mas-build2-20260911`，不使用旧 build 1 提审入口。上传 altool 必须显式使用用户提供的 `--p8-file-path`，不能依赖失效的 Downloads 符号链接。

2026-09-11 14:33：`fastlane mac update_reviewer_configuration` 已成功填入并回读审核 OSS 配置。该入口仅更新 notes，保留其他审核字段及版本/构建关系，绝不提审。使用 `FASTLANE_USER`、既有精确目标 `CONFIRM_PIC2LINK_RELEASE` 及 `PIC2LINK_REVIEW_CREDENTIAL_PATH`（仓库外 Markdown，含 AccessKey ID/Secret 标签），从 `docs/release/reviewer-configuration.txt` 运行时注入，不将密钥写入模板或日志。固定要求版本 1.0.1、选中构建 1、REJECTED；后续状态变化先检查再调整 guard。回读证据为 `dist/review-fix-20260911/reviewer-configuration-verification.json`。下文 RAM 阻塞描述为早期记录。

2026-09-11：新增 `inspect_review_with_session`，使用已有授权 Apple ID 会话只读检查精确拒审版本；只输出/保存脱敏状态，不保存审核正文。API 私钥的旧 Downloads 路径当前缺失，但授权会话已恢复并验证可用。`prepare_review` 现有目标仍为旧构建 1，且遇到尚未补齐配置的审核模板会在任何外部写入前拒绝运行；新构建和安全凭据上传需在 RAM 阻塞解除后单独更新、验证，不能直接重跑旧发布链。`release_support.rb` 关闭底层 API 正文日志，避免未来审核凭据进入 Spaceship 的 `/tmp` 日志。

认证环境：`APP_STORE_CONNECT_API_KEY_PATH` 指向外部 JSON，或 `ASC_API_KEY_ID`、`ASC_API_ISSUER_ID`、`ASC_API_PRIVATE_KEY_PATH`；App 创建还需要现有授权的 `FASTLANE_USER` 登录。不得把真实密钥、登录态或密码存入仓库。

| Lane | 作用 |
|---|---|
| inspect_asc | 只读查询精确 Bundle ID 对应 App、平台版本与构建 |
| inspect_registration | 只读 Bundle ID 与同名 App 检查 |
| inspect_session | 验证现有 fastlane Apple ID 登录和团队列表 |
| create_asc_app | 原始创建尝试，API 已证实禁止 apps CREATE，不应再次使用此路径创建 App |
| create_asc_app_with_session | 有目标确认串时使用授权会话创建 App；本次已创建 6809069103，禁止重复创建 |
| prepare_signing | 创建/安装商店 profile；本次已完成，不要重复创建 |
| prepare_installer_signing | 获取 Installer 证书；本次实际证书已导入，不能因末尾 WWDR 检查失败而重复创建 |
| build_release | 使用 StoreBuild.xcconfig、固定版本与签名身份生成 Distribution Archive，不上传 |
| export_release | 从已检查 Archive 导出 PKG；本次已完成 |
| inspect_details / inspect_commerce | 只读检查本产品 metadata、分级、价格点和可售区域 |
| upload_metadata | 仅写 13 语言资料、分类及版本设置，逐字段回读 |
| upload_screenshots | 仅上传现有截图，保留远端图片；检查 COMPLETE、尺寸、顺序和 MD5 |
| prepare_ratings | 填写年龄问卷及内容权利并回读 |
| prepare_privacy | 使用已有 Apple ID 会话发布已审计的隐私声明并回读 |
| verify_privacy | 使用授权会话只读核对隐私声明及发布状态，提审前后使用 |
| prepare_commerce | 按实时价格点设置 USA/CHN 价格及所有可售地区并回读；已存在配置不会盲目重建 |
| upload_binary | 固定 SHA256、已有 Apple 服务端验证、独立资料回读后仅上传 PKG；发现精确构建已存在时拒绝重传 |
| select_build | 绑定精确 VALID 构建，校验服务端加密声明 false，并回读；本次已完成 |
| prepare_review | 从仓库外/忽略目录中的真实联系人 JSON 填写审核资料，并绑定 VALID 构建；已执行并回读 |
| submit_review / verify_submission | 单独提交唯一版本项并严格回读；已执行，WAITING_FOR_REVIEW |

创建 guard：`CONFIRM_PIC2LINK_CREATE=NEW|Amanoya.Pic2Link|MAC_OS|1.0.1|1|AFTER_APPROVAL`。该值只是命令的目标校验，不能替代用户授权。已存在 App 时拒绝重复创建。

签名 guard：`CONFIRM_PIC2LINK_SIGNING=Amanoya.Pic2Link|MAC_OS|W7XZ85M98K`。Archive/export guard：`CONFIRM_PIC2LINK_ARCHIVE=Amanoya.Pic2Link|MAC_OS|1.0.1|1|W7XZ85M98K`。`export_release` 当前仅校验 Archive 检查报告存在，执行前仍需核实 Archive 未改变；不能把旧报告当作最终安装包验证。

本地资料生成：`python3 scripts/prepare_store_metadata.py`。用户确定可用商店名后，通过 `PIC2LINK_STORE_NAME` 设置名称并再次生成。`scripts/render_store_screenshots.py` 为 DEBUG 专用截图入口，调用前必须遵守 macOS UI 租约与 ABC 输入源规则；本次素材已完成，无需无故重拍。

所有日志和基线保存在被 git 忽略的 `dist/mas-20260905/`。`fastlane/README.md`、`report.xml` 为临时输出，不能作为远端状态证据。截图、metadata、构建上传、审核提交必须使用各自独立入口和回读，不让创建 lane 触发这些后续动作。

所有后续写入都必须先检查精确 App ID 及本产品状态，不执行猜测身份的价格、构建选择或提审操作。

上述远端写入入口通过 `release_support.rb` 固定 Apple ID、Bundle ID、SKU、主语言和版本 ID，guard 为 `CONFIRM_PIC2LINK_RELEASE=6809069103|Amanoya.Pic2Link|MAC_OS|1.0.1|1|AFTER_APPROVAL`。审核联系人通过 `PIC2LINK_REVIEW_CONTACT_PATH` 指向 JSON，键为 `contactFirstName`、`contactLastName`、`contactEmail`、`contactPhone`；不要将私密联系信息提交源码。

本次接口兼容记录：Build.all 使用 `app_id:`；fastlane 2.233.1 的 App Info localization 创建关系字段有误，项目直接使用正确的 `appInfo` 关系。创建 App Info locale 可能自动创建同语言 version locale，创建后须回读更新。可售地区由 `apps/<id>/appAvailabilityV2` 关系取得；新产品尚无价格或可售配置时，其子资源可能返回明确的不存在错误。只对确认不存在的资源进行首次创建，不把其他 API 错误当空数据。
