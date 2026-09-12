<p align="center">
  <img src="Pic2Link/Resources/icon.png" width="160" alt="Pic2Link app icon">
</p>

# Pic2Link

Pic2Link is a native macOS menu bar utility that uploads a clipboard image or a dragged file to your own storage and immediately copies the resulting public link.

It stays out of the Dock, shows byte-accurate progress in the menu bar and popover—including linked compression and upload gauges when resizing is enabled—and confirms successful uploads with a notification and a subtle sound.

## Features

- Upload the current clipboard image with one click or a global keyboard shortcut.
- Press **⌘⇧U** in Photos to upload the current selection, including a photo in single-photo view. Direct local builds also support selected Finder photo files; Mac App Store builds do not read Finder selections or request a temporary Apple Events exception. For Finder files in the store build, use drag-and-drop, clipboard upload, or the system file picker. Multiple photos follow the existing upload queue, text prompts, and compression settings. The clipboard shortcut (default **⌘U**) remains separate.
- Direct selection upload uses macOS Automation; Photos also requires photo-library access. Grant these permissions on first use. No selection or an unsupported foreground app produces a message without reading the clipboard. Photos supplies its current edited image through PhotoKit, downloading from iCloud when needed; Live Photos follow the existing GIF switch. PhotoKit must be able to access the selected asset in the system photo library.
- Drag one or multiple images and general files directly from Finder or Photos onto the menu bar icon. Photos file promises are accepted without asking you to save an intermediate copy first.
- Preserve original bytes, display names, and formats for dragged or copied image files, including animated GIFs, WebP, HEIC, and SVG. Object-storage and WebDAV uploads add a fresh UUID before the remote filename extension on every upload, preventing same-name files or captioned screenshots from overwriting earlier links; local files and existing history are unchanged.
- Enable **Add Text Before Upload** in the menu or Settings to open a focused text panel beneath the menu-bar icon. Multiple drafts can stack independently. **⌘Return** copies nonblank text, closes that draft, and confirms its upload; Return inserts a newline. Cancel, Escape, or closing the panel skips only that image. Leave the text blank to upload without composition while keeping the configured compression.
- Text uses the embedded Fluffmark (WMMark) engine for automatic placement, then follows the existing compression and upload pipeline. Fluffmark does not need to be installed or running. Static images produce an in-memory PNG; GIFs retain their frames and timing, with one stable layout chosen from the first frame.
- Optionally resize images in memory before upload by width, height, percentage, free dimensions, or maximum bounds; the original is never modified and no compressed copy is saved.
- Optionally turn a clipboard Live Photo into an in-memory 480p animated GIF before upload. It activates only when the clipboard supplies its matching still image and paired video; ordinary static images are never converted.
- Choose a Live Photo directly from the system Photos picker when a Photos copy contains only its static cover image. Pic2Link reads the selected asset's paired video into a temporary working folder, creates the GIF in memory, and removes the temporary source as soon as the upload finishes.
- Before reading a dragged or selected file, wait for two unchanged file observations. This prevents newly captured screenshots from being signed and uploaded while their source application is still writing them.
- Turn “Compress Before Upload” and “Convert Live Photos to GIF” on or off directly from the menu-bar menu; the same saved switches remain available in Settings.
- Queue consecutive clipboard, drag-and-drop, and manual uploads serially. With text prompts enabled, confirmed drafts enter the upload queue in submission order; unsubmitted drafts do not block uploads.
- Choose a file manually from the menu.
- See the active dragged or clipboard image, queue state, compression progress, and byte-accurate upload progress together in the upload area and as two linked menu-bar gauges.
- Copy the public link automatically after a successful upload. Enable **Markdown Links** in the menu to copy `![](URL)` or `![caption](URL)` instead; newly uploaded captions are saved with history for later copying.
- Click an uploaded item or its **Copy Link** action to copy in the currently selected format and play a success sound.
- Receive foreground and background completion notifications with a success sound.
- Keep a local history with image previews and file-type placeholders; **More Files** opens a separate window with the complete list.
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

The project links the first-party `WMMarkCore` and `WMMarkRenderer` Swift Package products from the sibling `../毛标标` source checkout. The built app runs independently of that checkout and of the Fluffmark app. Keep the two source repositories side by side when building. No third-party package dependency is added.

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
│   ├── *.lproj/                 # 13 Localizable.strings and InfoPlist.strings files
│   └── Pic2LinkApp.swift
├── Pic2LinkTests/               # Language, Keychain, resize, compression, progress, and error tests
├── Pic2LinkUITests/             # Appearance, compression settings, RTL, and long-label UI regressions
├── Design/                      # App icon source and design notes
└── 项目需求与开发文档.md
```

## Distribution

Release archives in `dist/` are local artifacts and are intentionally excluded from source control. If a binary is published through GitHub Releases, build it for both Apple Silicon and Intel, then sign and notarize that exact artifact.

Mac App Store builds explicitly use `StoreBuild.xcconfig` and `Pic2Link/Store.entitlements`. They enable App Sandbox, use read-only folder grants for inaccessible Finder selections, and use SMAppService for launch at login. Local builds retain their existing distribution configuration. Project-owned release lanes, verified artifacts, and pending App Store steps are documented in [the release record](docs/release/app-store-connect.md) and [fastlane guide](docs/release/fastlane.md).

## License

Pic2Link is source-available but not open source. See [LICENSE](LICENSE): all rights are reserved and no permission to copy, modify, or redistribute is granted without prior written permission.
