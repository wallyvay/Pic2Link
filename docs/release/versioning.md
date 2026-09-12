# 版本与分发

- `Pic2Link.xcodeproj/project.pbxproj` 是版本号唯一来源；当前为 `1.0.1 (2)`。2026-09-11 用户授权新构建提审，ASC 确认只有构建 1 后递增；15:51 已上传并重新提审，WAITING_FOR_REVIEW，见 [记录](mas-build2-20260911.md)。下文构建 1 是历史发布记录。
- 未获明确授权不得递增正式版本或构建号；ASC build 冲突时先回读并报告。
- 普通 Debug/Release 是既有本地分发配置。
- Mac App Store 构建显式传入 `-xcconfig StoreBuild.xcconfig`，保持 Bundle ID/Team，使用商店沙盒配置；不能直接上传此前安装到 Applications 的非沙盒二进制。
- 所有上传以最终 archive/export 中的 Bundle ID、版本、构建、签名、架构、权限及加密字段为准。
- 2026-09-06：Distribution Archive 与最终 PKG `1.0.1 (1)` 已检查并通过 Apple 服务端验证，08:26 上传成功，09:53 提审并回读 WAITING_FOR_REVIEW。ASC App 为 `6809069103` / `Pic2Link: Image Uploader`；Apple 创建时的 1.0 商店版本已对齐为 1.0.1。未变更工程版本或构建号，默认审核通过后自动发布。最新证据以 [app-store-connect.md](app-store-connect.md) 为准。
