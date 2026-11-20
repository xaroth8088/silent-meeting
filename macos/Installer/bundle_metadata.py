"""Generate fixed-location installer and bundle metadata."""

import argparse
from pathlib import Path
import plistlib
from xml.etree import ElementTree as ET

MIC_ID = "io.github.xaroth8088.silent-meeting.microphone"
FACTORY = "611E6109-7E0A-4E9A-A1A7-B2889482AB43"
HAL_TYPE = "443ABAB8-E7B3-491A-B985-BEB9187030DB"
# Changing the major/minor/patch version must also increment this monotonic build number.
VERSION = "0.2.0"
BUILD = "2"


def plist(path: Path, **values) -> None:
    with path.open("wb") as stream:
        plistlib.dump(values, stream)


def info(path: Path, identifier: str, executable: str, style: str, name: str, *,
         version: str = VERSION, build: str = BUILD, **extra) -> None:
    plist(
        path, CFBundleIdentifier=identifier, CFBundleExecutable=executable,
        CFBundleName=name, CFBundleDisplayName=name, CFBundlePackageType=style,
        CFBundleShortVersionString=version, CFBundleVersion=build,
        CFBundleInfoDictionaryVersion="6.0", CFBundleDevelopmentRegion="en",
        LSMinimumSystemVersion="14.0", CFBundleSupportedPlatforms=["MacOSX"], **extra,
    )


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("stage", type=Path)
    parser.add_argument("team")
    parser.add_argument("bundle")
    parser.add_argument("--unsigned", action="store_true")
    parser.add_argument("--launcher", action="store_true")
    args = parser.parse_args()

    app = args.stage / "Applications/Silent Meeting.app/Contents"
    capture_permissions = {
        "LSApplicationCategoryType": "public.app-category.video",
        "NSCameraUsageDescription": "Silent Meeting uses your camera to make the silent-film video.",
        "NSMicrophoneUsageDescription": "Silent Meeting uses your microphone to create dialogue cards on this Mac.",
        "NSHighResolutionCapable": True,
    }
    if args.launcher:
        info(app / "Info.plist", args.bundle, "SilentMeeting", "APPL", "Silent Meeting",
             version="0.3.0", build="3", **capture_permissions)
        return
    ext_id = args.bundle + ".camera"
    extension = app / f"Library/SystemExtensions/{ext_id}.systemextension/Contents"
    microphone = args.stage / "Library/Audio/Plug-Ins/HAL/SilentMeetingPiano.driver/Contents"
    mach_service = f"{args.team}.{ext_id}"

    info(
        app / "Info.plist", args.bundle, "SilentMeeting", "APPL", "Silent Meeting",
        SilentMeetingCameraExtension=ext_id,
        SilentMeetingSigned=not args.unsigned,
        **capture_permissions,
    )
    info(
        extension / "Info.plist", ext_id, ext_id, "SYSX", "Silent Meeting Camera",
        NSSystemExtensionUsageDescription="Makes Silent Meeting Camera available to macOS video apps.",
        CMIOExtension={"CMIOExtensionMachServiceName": mach_service},
        SilentMeetingHost=args.bundle,
        SilentMeetingTeam=args.team,
    )
    info(
        microphone / "Info.plist", MIC_ID, "SilentMeetingPiano", "BNDL", "Silent Meeting Piano",
        CFPlugInFactories={FACTORY: "NullAudio_Create"},
        CFPlugInTypes={HAL_TYPE: [FACTORY]},
    )
    sandbox = {
        "com.apple.security.app-sandbox": True,
        "com.apple.security.application-groups": [mach_service],
    }
    plist(args.stage.parent / "camera.entitlements", **sandbox)
    plist(
        args.stage.parent / "app.entitlements", **sandbox, **{
            "com.apple.security.device.camera": True,
            "com.apple.security.device.audio-input": True,
            "com.apple.developer.system-extension.install": True,
        },
    )

    root = ET.Element("installer-gui-script", minSpecVersion="2")
    ET.SubElement(root, "title").text = "Silent Meeting"
    ET.SubElement(root, "options", customize="never", hostArchitectures="arm64,x86_64")
    ET.SubElement(root, "domains", enable_anywhere="false", enable_currentUserHome="false", enable_localSystem="true")
    volume = ET.SubElement(root, "volume-check")
    os_version = ET.SubElement(volume, "allowed-os-versions")
    ET.SubElement(os_version, "os-version", min="14.0")
    outline = ET.SubElement(root, "choices-outline")
    ET.SubElement(outline, "line", choice="silent-meeting")
    choice = ET.SubElement(root, "choice", id="silent-meeting", visible="false")
    identifier = args.bundle + ".installer"
    ET.SubElement(choice, "pkg-ref", id=identifier)
    ET.SubElement(root, "pkg-ref", id=identifier, version=VERSION, onConclusion="RequireRestart").text = "payload.pkg"
    ET.indent(root)
    ET.ElementTree(root).write(args.stage.parent / "Distribution.xml", encoding="utf-8", xml_declaration=True)


if __name__ == "__main__":
    main()
