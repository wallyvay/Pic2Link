<p align="center">
  <img src="Pic2Link/Resources/icon.png" width="160" alt="Pic2Link app icon">
</p>

# Pic2Link

Pic2Link is a native macOS menu bar utility that uploads a clipboard image or a dragged file to your own storage and immediately copies the resulting public link.

It stays out of the Dock, shows byte-accurate upload progress in the menu bar and popover, and confirms successful uploads with a notification and a subtle sound.

## Features

- Upload the current clipboard image with one click or a global keyboard shortcut.
- Drag images and general files directly onto the menu bar icon.
- Choose a file manually from the menu.
- See progress based on bytes actually sent, including transferred and total size.
- Copy the public link automatically after a successful upload.
- Receive foreground and background completion notifications with a success sound.
- Keep a local history with image previews and file-type placeholders.
- Manage multiple storage profiles and switch the active host from the menu.
- Optionally launch Pic2Link when you sign in to macOS.

### Storage providers

Pic2Link currently supports:

- Alibaba Cloud OSS
- Synology C2 Object Storage
- JD Cloud Object Storage
- Baidu Cloud BOS
- Tencent Cloud COS
- Qiniu Cloud
- UPYUN
- Amazon S3
- Google Cloud Storage through S3 interoperability
- Cloudflare R2
- Backblaze B2
- Generic S3-compatible services such as MinIO, Wasabi, DigitalOcean Spaces, and IDrive E2
- WebDAV
- Flickr
- Imgur

Flickr and Imgur accept images only. The object-storage and WebDAV providers accept images and general files.

## Languages

The app supports English, Simplified Chinese, Traditional Chinese, Korean, Japanese, Russian, Spanish, Portuguese, Thai, Hindi, French, Arabic, and German.

On first launch, Pic2Link follows the primary macOS language when it is supported and falls back to English otherwise. A language selected in Settings takes effect immediately and is used for future launches. Arabic also switches the interface to right-to-left layout.

## Requirements

- macOS 14.0 or later
- Xcode 26.4 or later for development

The project has no third-party package dependencies.

## Build

1. Clone the repository.
2. Open `Pic2Link.xcodeproj` in Xcode.
3. Select the `Pic2Link` scheme and your Mac as the run destination.
4. Choose your own development team if you want to sign the local build.
5. Build and run.

You can also perform an unsigned command-line build:

```sh
xcodebuild \
  -project Pic2Link.xcodeproj \
  -scheme Pic2Link \
  -configuration Debug \
  -derivedDataPath /tmp/Pic2LinkBuild \
  CODE_SIGNING_ALLOWED=NO \
build
```

Run the unsigned unit test suite with:

```sh
xcodebuild \
  -project Pic2Link.xcodeproj \
  -scheme Pic2Link \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath /tmp/Pic2LinkTests \
  -only-testing:Pic2LinkTests \
  CODE_SIGNING_ALLOWED=NO \
  test
```

The UI regression suite launches the signed macOS test runner and therefore requires a local development team plus macOS automation permission for Xcode or the invoking terminal:

```sh
xcodebuild \
  -project Pic2Link.xcodeproj \
  -scheme Pic2Link \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath /tmp/Pic2LinkUITests \
  -only-testing:Pic2LinkUITests \
  DEVELOPMENT_TEAM=YOUR_TEAM_ID \
  test
```

After launch, use the menu bar icon to open Settings and add a storage profile. Pic2Link does not include any bundled cloud credentials.

## Security notes

- Use least-privilege credentials limited to the intended bucket or directory.
- Do not commit credentials, signing files, or exported configuration data.
- Provider credentials are stored in the current user's macOS Keychain. Non-sensitive profile metadata and upload history remain in `UserDefaults`.
- Existing installations migrate plaintext credentials from `UserDefaults` only after the corresponding Keychain write succeeds, preventing credential loss if migration fails.
- Public URL prefixes must point to content that your provider is configured to expose. Pic2Link does not change bucket access policies.

## Project structure

```text
Pic2Link/
├── Pic2Link.xcodeproj/
├── Pic2Link/
│   ├── Assets.xcassets/
│   ├── Models/
│   ├── Services/
│   ├── ViewModels/
│   ├── Views/
│   ├── *.lproj/                 # 13 Localizable.strings files
│   └── Pic2LinkApp.swift
├── Pic2LinkTests/               # Language, Keychain, progress, and error tests
├── Pic2LinkUITests/             # Appearance, RTL, and long-label UI regressions
├── Design/                      # App icon source and design notes
└── 项目需求与开发文档.md
```

## Distribution

Release archives in `dist/` are local artifacts and are intentionally excluded from source control. If a binary is published through GitHub Releases, build it for both Apple Silicon and Intel, then sign and notarize that exact artifact.

## License

Pic2Link is source-available but not open source. See [LICENSE](LICENSE): all rights are reserved and no permission to copy, modify, or redistribute is granted without prior written permission.
