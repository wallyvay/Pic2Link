#!/bin/bash
set -euo pipefail
cd /Users/amano/Desktop/VibeCoding/Pic2Link
uiLease=/private/tmp/codex-apple-test-locks/macos-ui-session.lock
testRoot=/private/tmp/codex-apple-tests/Pic2Link/review-fix-20260911
inputTool="$testRoot/input-source"
clang scripts/test_input_source.c -framework Carbon -o "$inputTool"
testProcess=""
originalInput=""
mkdir "$uiLease"
mkdir "$uiLease/owner-$$-Pic2Link-review-fix-20260911"
cleanup() {
    local restoreStatus=0
    if [[ -n "$testProcess" ]] && kill -0 "$testProcess" 2>/dev/null; then
        kill -TERM "$testProcess"
        wait "$testProcess" || true
    fi
    if [[ -n "$originalInput" ]]; then
        "$inputTool" "$originalInput" || restoreStatus=1
        [[ "$("$inputTool")" == "$originalInput" ]] || restoreStatus=1
    fi
    rmdir "$uiLease/owner-$$-Pic2Link-review-fix-20260911"
    rmdir "$uiLease"
    return "$restoreStatus"
}
trap cleanup EXIT
trap 'exit 130' INT TERM
originalInput="$("$inputTool")"
echo "Original input: $originalInput"
"$inputTool" com.apple.keylayout.ABC
[[ "$("$inputTool")" == com.apple.keylayout.ABC ]]
xcodebuild -project Pic2Link.xcodeproj -scheme Pic2Link \
    -destination 'platform=macOS,arch=arm64' \
    -derivedDataPath "$testRoot/UIDerivedData" \
    -resultBundlePath "$testRoot/${PIC2LINK_UI_RESULT_NAME:-UITests}.xcresult" \
    -parallel-testing-enabled NO \
    -only-testing:Pic2LinkUITests/Pic2LinkUITests/testEnglishSettingsInLightAppearance \
    -only-testing:Pic2LinkUITests/Pic2LinkUITests/testEnglishSettingsInDarkAppearance \
    'SWIFT_ACTIVE_COMPILATION_CONDITIONS=DEBUG APP_STORE' \
    test > "$testRoot/ui-tests.log" 2>&1 &
testProcess=$!
wait "$testProcess"
testProcess=""
