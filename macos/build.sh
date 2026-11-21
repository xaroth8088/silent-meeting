#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."
repo="$PWD"
build="${SILENT_BUILD_DIR:-$repo/.build/macos}"
mkdir -p "$build"
build="$(cd "$build" && pwd)"
deps="${SILENT_DEPS_DIR:-$build/dependencies}"
mkdir -p "$deps"
deps="$(cd "$deps" && pwd)"
stage="$(mktemp -d "$build/stage.XXXXXX")"
trap 'rm -rf "$stage"' EXIT
root="$stage/root"

mode="${1:---unsigned}"
bundle="${SILENT_BUNDLE_ID:-io.github.xaroth8088.silent-meeting}"
team="${SILENT_TEAM_ID:-UNSIGNED00}"
app_identity="${SILENT_APP_IDENTITY:-}"
installer_identity="${SILENT_INSTALLER_IDENTITY:-}"
profile="${SILENT_NOTARY_PROFILE:-}"
app_profile="${SILENT_APP_PROFILE:-}"
if [[ ! "$bundle" =~ ^[A-Za-z0-9][A-Za-z0-9.-]+$ ]]; then
    echo "SILENT_BUNDLE_ID must be a reverse-DNS bundle identifier." >&2
    exit 2
fi
case "$mode" in
    --launcher)
        bundle="${SILENT_BUNDLE_ID:-$bundle.launcher}"
        team=UNSIGNED00
        ;;
    --unsigned)
        team=UNSIGNED00
        ;;
    --release)
        if [[ ! "$team" =~ ^[A-Z0-9]{10}$ || "$team" == UNSIGNED00 ||
              -z "$app_identity" || -z "$installer_identity" || -z "$profile" ]]; then
            echo "Set SILENT_TEAM_ID, SILENT_APP_IDENTITY, SILENT_INSTALLER_IDENTITY, and SILENT_NOTARY_PROFILE." >&2
            exit 2
        fi
        if [[ ! -f "$app_profile" || ! -r "$app_profile" ]]; then
            echo "Set SILENT_APP_PROFILE to the host app's Developer ID provisioning profile with System Extension enabled." >&2
            exit 2
        fi
        ;;
    *)
        echo "Usage: macos/build.sh [--launcher | --unsigned | --release]" >&2
        exit 2
        ;;
esac

for tool in python3 cmake; do
    command -v "$tool" >/dev/null || { echo "Building requires $tool on PATH." >&2; exit 2; }
done
if [[ -z "${DEVELOPER_DIR:-}" && -d /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk ]]; then
    export DEVELOPER_DIR=/Library/Developer/CommandLineTools
fi
sdk="$(xcrun --sdk macosx --show-sdk-path)"
swift="$(xcrun --find swiftc)"
clang="$(xcrun --find clang)"
clangxx="$(xcrun --find clang++)"
minimum=14.0
architectures=(arm64 x86_64)

download() {
    local destination="$deps/$1" url="$2" hash="$3"
    if ! [[ -f "$destination" ]] || ! printf '%s  %s\n' "$hash" "$destination" | shasum -a 256 -c -s; then
        /usr/bin/curl -fsSL --retry 2 --max-time 150 -o "$destination.part" "$url"
        if ! printf '%s  %s\n' "$hash" "$destination.part" | shasum -a 256 -c -s; then
            rm -f "$destination.part"
            echo "Checksum mismatch for $url" >&2
            exit 1
        fi
        mv "$destination.part" "$destination"
    fi
}

if [[ "$mode" != --launcher ]]; then
    download apple-audio.zip 'https://docs-assets.developer.apple.com/published/430ad6501f6f/CreatingAnAudioServerDriverPlugIn.zip' \
        860334dfa9e83f2afb749a890ca5a79fc7d3d572d4e116ff9242bec458be4cb0
    unzip -p "$deps/apple-audio.zip" NullAudio.c > "$stage/NullAudio.c"
    unzip -p "$deps/apple-audio.zip" LICENSE.txt > "$stage/Apple-NullAudio.txt"
fi
download whisper.tar.gz 'https://codeload.github.com/ggml-org/whisper.cpp/tar.gz/refs/tags/v1.9.5' \
    ff1a9053feb509ff9d7729703355541ae9690073a6b1c40eb692c962e0dc1720
download libfvad.tar.gz 'https://codeload.github.com/dpirch/libfvad/tar.gz/refs/tags/v1.0' \
    8c8a1e4911a454b1a8e3ed062abbce4865eea3fc794417e2c96373309174215c
download ggml-tiny-q5_1.bin 'https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-tiny-q5_1.bin' \
    818710568da3ca15689e31a743197b520007872ff9576237bda97bd1b469c3d7
download openai-whisper-LICENSE 'https://raw.githubusercontent.com/openai/whisper/v20250625/LICENSE' \
    b5d65a59060e68c4ff940e1eddfa6f94b2d68fdf58ed7f4dd57721c997e35e9d
tar -xzf "$deps/whisper.tar.gz" -C "$stage"
tar -xzf "$deps/libfvad.tar.gz" -C "$stage"
whisper="$stage/whisper.cpp-1.9.5"
fvad="$stage/libfvad-1.0"
cmake -S "$whisper" -B "$stage/whisper-build" -DCMAKE_BUILD_TYPE=Release \
    "-DCMAKE_OSX_SYSROOT=$sdk" "-DCMAKE_OSX_DEPLOYMENT_TARGET=$minimum" \
    '-DCMAKE_OSX_ARCHITECTURES=arm64;x86_64' "-DCMAKE_C_COMPILER=$clang" "-DCMAKE_CXX_COMPILER=$clangxx" \
    -DBUILD_SHARED_LIBS=OFF -DWHISPER_BUILD_TESTS=OFF -DWHISPER_BUILD_EXAMPLES=OFF -DWHISPER_BUILD_SERVER=OFF \
    -DGGML_METAL=OFF -DGGML_BLAS=ON -DGGML_OPENMP=OFF -DGGML_NATIVE=OFF -DGGML_AVX=OFF -DGGML_AVX2=OFF -DGGML_FMA=OFF -DGGML_F16C=OFF
cmake --build "$stage/whisper-build" --parallel 8 --target whisper

app="$root/Applications/Silent Meeting.app/Contents"
ext_id="$bundle.camera"
camera="$app/Library/SystemExtensions/$ext_id.systemextension/Contents"
audio="$root/Library/Audio/Plug-Ins/HAL/SilentMeetingPiano.driver/Contents"
mkdir -p "$app/MacOS" "$app/Resources/Licenses"
metadata_args=("$root" "$team" "$bundle")
if [[ "$mode" == --launcher ]]; then
    metadata_args+=(--launcher)
    cp assets/{maple-leaf-rag,the-entertainer,burglar-music}.mp3 "$app/Resources/"
else
    mkdir -p "$camera/MacOS" "$audio/MacOS" "$audio/Resources"
    if [[ "$mode" == --unsigned ]]; then metadata_args+=(--unsigned); fi
fi
python3 macos/Installer/bundle_metadata.py "${metadata_args[@]}"
cp "$deps/ggml-tiny-q5_1.bin" "$app/Resources/"
cp LICENSE "$app/Resources/Licenses/Silent-Meeting.txt"
cp "$whisper/LICENSE" "$app/Resources/Licenses/whisper.cpp.txt"
cp "$deps/openai-whisper-LICENSE" "$app/Resources/Licenses/Whisper-model.txt"
cp "$fvad/LICENSE" "$app/Resources/Licenses/libfvad.txt"
cp "$fvad/PATENTS" "$app/Resources/Licenses/libfvad-PATENTS.txt"
cp assets/AGENTS.md "$app/Resources/Licenses/Soundtrack.md"
if [[ "$mode" == --launcher ]]; then
    ui=(macos/Launcher/*.swift)
else
    ui=(macos/App/SilentMeetingApp.swift)
    cp "$stage/Apple-NullAudio.txt" "$audio/Resources/Apple-NullAudio.txt"
    cp assets/AGENTS.md "$audio/Resources/Soundtrack.md"
    # The driver uses an uncompressed mono buffer so its real-time callback never decodes audio.
    afconvert -f WAVE -d LEF32@48000 -c 1 assets/maple-leaf-rag.mp3 "$stage/track.wav"
    python3 macos/Installer/wave_to_pcm.py "$stage/track.wav" "$audio/Resources/maple-leaf-rag.f32"
    patch -s -o "$stage/Driver.c" "$stage/NullAudio.c" macos/Microphone/null-audio.patch
    "$clang" -arch arm64 -arch x86_64 "-mmacosx-version-min=$minimum" -isysroot "$sdk" -O2 -fblocks \
        -bundle -I macos/Microphone -framework CoreFoundation -framework CoreAudio \
        "$stage/Driver.c" macos/Microphone/Soundtrack.c -o "$audio/MacOS/SilentMeetingPiano"
fi

for arch in "${architectures[@]}"; do
    target="$arch-apple-macos$minimum"
    objects=()
    for source in "$fvad"/src/*.c "$fvad"/src/*/*.c; do
        object="$stage/$arch-$(basename "$source" .c).o"
        "$clang" -target "$target" -isysroot "$sdk" -O2 -I "$fvad/include" -c "$source" -o "$object"
        objects+=("$object")
    done
    "$swift" -swift-version 5 -O -target "$target" -sdk "$sdk" \
        -module-cache-path "$build/swift-cache-$arch" -import-objc-header macos/App/NativeSpeech.h \
        -Xcc "-I$fvad/include" -Xcc "-I$whisper/include" -Xcc "-I$whisper/ggml/include" \
        macos/Shared/*.swift macos/App/{CameraSink,CapturePipeline,DialogueCards,FilmRenderer,SoundtrackSentiment,SpeechPipeline}.swift \
        "${ui[@]}" "${objects[@]}" \
        "$stage/whisper-build/src/libwhisper.a" "$stage"/whisper-build/ggml/src/libggml*.a \
        "$stage/whisper-build/ggml/src/ggml-blas/libggml-blas.a" -lc++ -framework Accelerate -o "$stage/app-$arch"
    if [[ "$mode" != --launcher ]]; then
        "$swift" -swift-version 5 -O -target "$target" -sdk "$sdk" \
            -module-cache-path "$build/swift-cache-$arch" \
            macos/Shared/*.swift macos/Camera/*.swift -o "$stage/camera-$arch"
    fi

    if [[ "$arch" == "$(uname -m)" && "${SILENT_RUN_TESTS:-0}" == 1 ]]; then
        tests=(macos/Tests/Smoke.swift)
        if [[ "$mode" == --launcher ]]; then
            tests+=(-DSILENT_MEETING_LAUNCHER macos/Tests/LauncherSmoke.swift
                    macos/Launcher/{Setup,BlackHolePiano}.swift)
        fi
        "$swift" -parse-as-library -swift-version 5 -O -target "$target" -sdk "$sdk" \
            -module-cache-path "$build/swift-cache-$arch" -import-objc-header macos/App/NativeSpeech.h \
            -Xcc "-I$fvad/include" -Xcc "-I$whisper/include" -Xcc "-I$whisper/ggml/include" \
            macos/Shared/*.swift macos/App/{CameraSink,CapturePipeline,DialogueCards,FilmRenderer,SoundtrackSentiment,SpeechPipeline}.swift "${tests[@]}" \
            "${objects[@]}" "$stage/whisper-build/src/libwhisper.a" "$stage"/whisper-build/ggml/src/libggml*.a \
            "$stage/whisper-build/ggml/src/ggml-blas/libggml-blas.a" -lc++ -framework Accelerate -o "$stage/smoke"
        "$stage/smoke" "$app/Resources/ggml-tiny-q5_1.bin" \
            "${SILENT_TEST_PCM:?Set SILENT_TEST_PCM to a short 16 kHz mono s16le speech fixture.}" \
            "$app/Resources"
        if [[ "$mode" != --launcher ]]; then
            "$clang" -target "$target" -isysroot "$sdk" -framework CoreAudio -framework CoreFoundation \
                macos/Tests/DriverSmoke.c -o "$stage/driver-smoke"
            "$stage/driver-smoke" "$audio/MacOS/SilentMeetingPiano"
        fi
    fi
done
lipo -create "$stage/app-arm64" "$stage/app-x86_64" -output "$app/MacOS/SilentMeeting"
if [[ "$mode" == --launcher ]]; then
    product="$build/Silent Meeting.app"
    codesign --force --sign - "$app/.."
    codesign --verify --strict "$app/.."
    if [[ -e "$product" ]]; then
        existing_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$product/Contents/Info.plist" 2>/dev/null || true)"
        [[ "$existing_id" == "$bundle" ]] || { echo "An unrelated app already exists at $product" >&2; exit 1; }
        mv "$product" "$stage/previous.app"
    fi
    if ! mv "$root/Applications/Silent Meeting.app" "$product"; then
        if [[ -d "$stage/previous.app" ]]; then mv "$stage/previous.app" "$product"; fi
        exit 1
    fi
    echo "$product"
    exit 0
fi
lipo -create "$stage/camera-arm64" "$stage/camera-x86_64" -output "$camera/MacOS/$ext_id"

if [[ "$mode" == --release ]]; then
    cp "$app_profile" "$app/embedded.provisionprofile"
    if [[ -n "${SILENT_CAMERA_PROFILE:-}" ]]; then cp "$SILENT_CAMERA_PROFILE" "$camera/embedded.provisionprofile"; fi
    codesign --force --sign "$app_identity" --options runtime --timestamp "$audio/.."
    codesign --force --sign "$app_identity" --options runtime --timestamp --entitlements "$stage/camera.entitlements" "$camera/.."
    codesign --force --sign "$app_identity" --options runtime --timestamp --entitlements "$stage/app.entitlements" "$app/.."
    codesign --verify --deep --strict "$app/.."
    codesign --verify --strict "$audio/.."
else
    codesign --force --sign - "$audio/.."
    codesign --force --sign - "$camera/.."
    codesign --force --sign - "$app/.."
fi

pkgbuild --analyze --root "$root" "$stage/components.plist"
python3 - "$stage/components.plist" <<'PY'
import plistlib
from pathlib import Path
import sys

path = Path(sys.argv[1])
items = plistlib.loads(path.read_bytes())
for item in items:
    item["BundleIsRelocatable"] = False
path.write_bytes(plistlib.dumps(items))
PY
version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Info.plist")"
pkgbuild --root "$root" --identifier "$bundle.installer" --version "$version" \
    --install-location / --component-plist "$stage/components.plist" "$stage/payload.pkg"
if [[ "$mode" == --release ]]; then
    pkg="$build/Silent-Meeting-$version.pkg"
    productbuild --distribution "$stage/Distribution.xml" --package-path "$stage" --sign "$installer_identity" "$pkg"
    if [[ -n "${SILENT_NOTARY_DEVELOPER_DIR:-}" ]]; then
        export DEVELOPER_DIR="$SILENT_NOTARY_DEVELOPER_DIR"
    fi
    xcrun notarytool submit "$pkg" --keychain-profile "$profile" --wait
    xcrun stapler staple "$pkg"
    spctl --assess --type install "$pkg"
else
    pkg="$build/Silent-Meeting-$version-unsigned.pkg"
    productbuild --distribution "$stage/Distribution.xml" --package-path "$stage" "$pkg"
    echo "Unsigned development package. Its embedded camera cannot be activated."
fi
echo "$pkg"
