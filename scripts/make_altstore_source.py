"""Builds an AltStore source (also read by LiveContainer and SideStore) from this repo's GitHub releases.

usage: make_altstore_source.py releases.jsonl Info.plist output.json
  releases.jsonl  one release object per line, from `gh api repos/OWNER/REPO/releases --paginate --jq '.[]'`
  Info.plist      the app's Info.plist template, used for the privacy usage descriptions
"""
import json
import os
import plistlib
import sys

APP_NAME = "OllieOS"
BUNDLE_ID = os.environ.get("BUNDLE_ID", "codes.ollieg.ollieos")
DEVELOPER_NAME = "obfuscatedgenerated"
MIN_OS_VERSION = "15.0"
TINT_COLOUR = "#A855F7"
WEBSITE = "https://ollieg.codes"
ICON_URL = "https://raw.githubusercontent.com/obfuscatedgenerated/obfuscatedgenerated.github.io/main/public/logo.png"
SUBTITLE = "The OllieOS terminal, as an iOS app."
DESCRIPTION = (
    "OllieOS running on iOS! With a terminal key bar and platform programs "
    "(share, haptics, Face ID privilege prompts, files, camera scanning and more)."
)


def load_releases(releases_path):
    with open(releases_path, encoding="utf-8") as releases_file:
        return [json.loads(line) for line in releases_file if line.strip()]


def load_privacy_descriptions(plist_path):
    with open(plist_path, "rb") as plist_file:
        info = plistlib.load(plist_file)
    return {
        key: value
        for key, value in info.items()
        if key.startswith("NS") and key.endswith("UsageDescription")
    }


def build_versions(releases):
    versions = []
    for release in releases:
        if release.get("draft") or release.get("prerelease"):
            continue

        ipa_asset = next((asset for asset in release.get("assets", []) if asset["name"].endswith(".ipa")), None)
        if ipa_asset is None:
            continue

        version = release["tag_name"].lstrip("v")
        versions.append({
            "version": version,
            "buildVersion": version,
            "date": release["published_at"],
            "localizedDescription": release.get("body") or f"OllieOS {version}",
            "downloadURL": ipa_asset["browser_download_url"],
            "size": ipa_asset["size"],
            "minOSVersion": MIN_OS_VERSION,
        })

    # newest first, compared numerically (2.10.0 > 2.9.1)
    def version_key(version_entry):
        return [int(part) if part.isdigit() else 0 for part in version_entry["version"].split(".")]

    versions.sort(key=version_key, reverse=True)
    return versions


def main():
    releases_path, plist_path, output_path = sys.argv[1:4]

    versions = build_versions(load_releases(releases_path))
    if not versions:
        sys.exit("No releases with an .ipa asset found")

    newest = versions[0]
    app = {
        "name": APP_NAME,
        "bundleIdentifier": BUNDLE_ID,
        "developerName": DEVELOPER_NAME,
        "subtitle": SUBTITLE,
        "localizedDescription": DESCRIPTION,
        "iconURL": ICON_URL,
        "tintColor": TINT_COLOUR,
        "category": "developer",
        "versions": versions,
        "appPermissions": {
            "entitlements": [],
            "privacy": load_privacy_descriptions(plist_path),
        },
        # legacy single-version fields for older clients
        "version": newest["version"],
        "versionDate": newest["date"],
        "versionDescription": newest["localizedDescription"],
        "downloadURL": newest["downloadURL"],
        "size": newest["size"],
    }

    source = {
        "name": APP_NAME,
        "identifier": f"{BUNDLE_ID}.source",
        "subtitle": SUBTITLE,
        "description": DESCRIPTION,
        "iconURL": ICON_URL,
        "website": WEBSITE,
        "tintColor": TINT_COLOUR,
        "apps": [app],
        "news": [],
    }

    with open(output_path, "w", encoding="utf-8") as output_file:
        json.dump(source, output_file, indent=2)
        output_file.write("\n")


if __name__ == "__main__":
    main()