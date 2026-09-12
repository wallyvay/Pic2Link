# 2026-09-11 拒审修复：Finder 沙盒与审核配置

目标：Pic2Link: Image Uploader / `6809069103` / `Amanoya.Pic2Link` / macOS。

## 14:33 后续完成：审核凭据与备注

- 控制台创建 `pic2link-app-review`（仅 API 访问）及自定义策略 `Pic2LinkAppReviewOSS`。用户手动将策略绑定到审核用户和 `codex`，明确要求两者均保留。
- 从用户提供的仓库外凭据文件在进程内读取密钥，不打印、不存入源码。该文件位于用户 iCloud Drive，已提醒其可能同步。
- 审核身份真实网络验证：Bucket GET 200、合成 PNG PUT 200、匿名 GET 字节一致。样本为 `review/reviewer-verification-f69f2539-14e1-454e-b8d3-14630ba4bf47.png`，由 30 天生命周期清理。未执行真实 App 沙盒 UI 验收，也未实测所有越权拒绝路径。
- `update_reviewer_configuration` 仅 PATCH 审核 notes；配置与步骤来自无密钥模板 `reviewer-configuration.txt`，凭据运行时注入。禁用 API 正文日志，错误细节不输出。
- 14:33:39 ASC 回读 notes 完全一致，其他审核字段、版本及选中构建完全未变：仍为 `1.0.1 (1)` / `REJECTED` / `AFTER_APPROVAL`。证据为 `dist/review-fix-20260911/reviewer-configuration-verification.json`。
- Ruby 语法和 diff 检查通过。本轮仅发布工具/审核资料，无 App 源码变化，未运行 XCTest 或安装。
- 下文 RAM 阻塞和未填凭据描述为较早阶段记录，已由本节解除。新商店构建、UI 验收及重新提审仍未完成。

## 状态与授权范围

用户要求按诊断方案修复，并创建独立阿里云测试 Bucket、生成审核凭据及填入审核信息。

ASC 已使用现有授权 Apple ID 会话实时回读：`1.0.1 (1)` 为 `REJECTED`，仍为 `AFTER_APPROVAL`，已选构建 1，审核资料存在。此次未修改任何远端商店字段、构建关系或审核状态，未重新提审。旧 API 私钥路径已不存在；授权会话在获得系统文件访问许可后恢复并成功使用，不应把该问题误报为必须重新提供 ASC 密钥。

正式版本号、构建号、Bundle ID、签名团队、证书和 profile 未变更。本轮产物是 `1.0.1 (1)` 的本地验证包，不可重传为新构建；下一轮上传前须确认新的构建号并更新旧发布 lane 中的固定目标和产物路径，不能复用 `dist/mas-20260905` 的旧包或旧验证报告。

## 代码与文案

- `Pic2Link/Store.entitlements` 删除整个 `com.apple.security.temporary-exception.apple-events`。保留 Photos 的公开 scripting access group 和 PhotoKit 权限。
- `SelectedPhotoReader` 在 `APP_STORE` 下发送任何事件前拒绝 Finder，`MainViewModel` 同样提前拒绝。非商店版保留 Finder 功能。
- Finder 用户改走既有拖放、剪贴板或 NSOpenPanel；不以 UI scripting、模拟复制或扩大权限绕过审核限制。
- 13 语言新增 4 个商店版专用提示键。设置说明、空选择、自动化权限提示仅指向 Photos；Finder 路径给出替代方式。13 语言权限用途文案改为通用的“来源应用中的所选照片”，对两种分发均真实。
- 13 语言商店 Description 及 `store-copy.json` 删除 Finder 选中项快捷上传/首次文件夹授权承诺，其余名称、关键词、价格、截图和公开政策 URL 保持原样。仅本地修改，未上传。
- 审核说明模板移除临时权限申请，并加入替代操作说明。`prepare_review` 在缺少真实审核配置时阻止写入；`release_support.rb` 禁用底层 Spaceship JSON 正文日志，防止未来配置密钥进入 `/tmp` 日志。

## 已创建的独立 OSS 资源

| 配置项 | 值 |
|---|---|
| Bucket | `pic2link-review-20260911-92a7` |
| Region | `ap-southeast-1`（新加坡） |
| Endpoint | `oss-ap-southeast-1.aliyuncs.com` |
| Public URL | `https://pic2link-review-20260911-92a7.oss-ap-southeast-1.aliyuncs.com` |
| Base path | `review` |
| ACL | private |
| 匿名访问 | 仅 `review/*` 的 GetObject，不能列举或写入 |
| 生命周期 | `review/` 对象 30 天到期，未完成分片 1 天清理 |
| 计费 | 标准存储按量计费；未购买资源包，无费用硬上限 |

最初新 Bucket 默认启用 bucket-level BlockPublicAccess，导致公开策略返回 403。回读后仅关闭这个新 Bucket 的该开关，再应用精确到 `review/*` 的公开读取策略；没有修改账号级设置或任何生产 Bucket（包括 wmblog）。策略、ACL、生命周期、账号归属均回读确认。

`scripts/prepare_review_bucket.py` 固定唯一目标并验证 owner，凭据只从现有 `codex` CLI 配置读入内存，不输出密钥。初次创建后若失败，必须先回读，不盲目重建。配置写入只允许本任务新建且空的 Bucket；现在已有合成样本，不能直接重复 `--apply`。

使用现有运维身份上传一张合成 PNG：PUT 200，匿名 GET 200，返回字节和 MIME 一致，匿名列举 403。样本位于 `review/`，由 30 天生命周期清理。这证明 Bucket 可用，不代表尚未创建的审核身份已验收，也不是 App 沙盒端到端上传测试。

## 当前唯一凭据阻塞与所需管理员步骤

现有 CLI profile 为 `codex`，RAM 用户属于账号 `1945014481925631`。阿里云明确拒绝 `ram:GetUser`、`ram:ListPoliciesForUser` 和 `ram:CreateUser`；最后一项请求 ID 为 `01A08EB8-D3D1-5724-AFC0-0DA94F12CA52`。这不是本机 sandbox 或网络错误，提权运行本机命令不能解决云端 RAM 权限。

需要管理员创建编程访问专用 RAM 用户 `pic2link-app-review`，不启用控制台登录、不附加系统全权限策略。绑定 [review-oss-policy.json](review-oss-policy.json)：仅本测试 Bucket 下 `review/*` 的 PutObject/GetObject，以及该 Bucket 的 ListObjects（App 的连接测试需要）。不允许其他 Bucket、删除对象、改 ACL/策略或 RAM 管理。

可由用户在控制台完成上述一步，或配置一个已授权、能管理该 RAM 用户/策略/AccessKey 的临时 CLI profile 后让 Codex继续。不要把生产主密钥或 `codex` 运维密钥提供给审核员，也不要将新 Secret 粘贴到聊天/源码中；生成结果应直接存入受保护的本机凭据文件或安全存储。

RAM 阻塞解除后：生成专用 AccessKey → 验证只对指定 Bucket/前缀生效 → 用真实沙盒 App 验证连接、上传、压缩、GIF、链接 → 在关闭请求正文日志的情况下将完整配置安全写入 ASC Review Information 并逐字段回读。审核说明需提示仅使用测试图片，链接公开且 30 天自动清理。当前没有生成或提交任何审核专用 AccessKey；不能声称 2.1(a) 已解决。

## 验证与未完成项

独立工作目录：`/private/tmp/codex-apple-tests/Pic2Link/review-fix-20260911/`。

- `StoreUnitTestsRetry.xcresult`：商店条件编译的单元测试 73/73 通过，包括 Finder 零事件回归；没有传商店沙盒 xcconfig，因此不是实际沙盒 UI/网络验收。
- `LocalUnitTests.xcresult`：非商店版单元测试 74/74 通过，保留 Finder 解析、Photos 和之前防覆盖回归。
- 初次 sandbox 内构建无法写入 SwiftPM 系统缓存；获得工具权限后重跑成功，不归为产品失败。
- 签名 Release 验证包使用 `StoreBuild.xcconfig`、arm64/x86_64，实际 entitlements 有 App Sandbox、Photos scripting target，没有任何临时 Apple Events 例外；Development 签名/deep strict 验证通过。该包不是 Distribution Archive/提交包，保留 get-task-allow 用于本地验证。未替换用户本机的非商店安装。
- `UITests.xcresult`：英文深/浅色均失败在首个“设置窗口存在”检查，没有执行到新文案断言；界面验收未完成，不用单元测试或编译成功替代。原输入源 `com.tencent.inputmethod.wetype.pinyin`，测试时通过 TIS 切至 `com.apple.keylayout.ABC`，结束恢复并回读；租约已释放。日志未显示输入法授权弹窗，未批准任何第三方输入法请求。
- `scripts/test_review_ui.sh` 为隔离重跑入口，使用 `test_input_source.c` 构建 TIS 工具，并在退出时恢复输入源。首轮使用内容相同的既有 TIS 工具，脚本现已改为项目内源码自包含。
- 13 语言各 237 个键，键集合/重复键一致，全部 InfoPlist.strings lint 通过；Ruby 语法、Python 编译及 diff 检查通过。13 语言 Description 静态检查通过；本轮为功能事实修正，不做 ASO 重写。

脱敏云端/商店证据：`dist/review-fix-20260911/{bucket-verification,network-verification,asc-review-inspection,metadata-lint}.json`。

受影响文件覆盖上传选择服务/ViewModel、商店 entitlements、设置帮助、13 语言资源、对应 XCTest/UI Tests、说明文档、13 语言 Description 与源文案、发布日志保护及本任务脚本。保护原有未提交改动，没有 commit/push。还需管理员 RAM 操作、审核身份与沙盒完整流程验收、UI 测试启动问题定位、新构建打包上传及审核资料回读；当前未完成提审准备。
