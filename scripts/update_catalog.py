#!/usr/bin/env python3
"""Publish IPA release metadata without changing bundle IDs or app data."""
import argparse
import hashlib
import json
import os
import plistlib
import re
import struct
import tempfile
import urllib.request
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
REPOSITORY = "Strezzy/ios-apps"
RAW = f"https://raw.githubusercontent.com/{REPOSITORY}/main"


def load(path):
    return json.loads(path.read_text())


def save(path, data):
    path.write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n")


def entitlements(data):
    # Read XML entitlements directly from a thin arm64 Mach-O signature.
    if data[:4] != b"\xcf\xfa\xed\xfe":
        raise ValueError("Expected a thin 64-bit iPhone executable")
    ncmds = struct.unpack_from("<I", data, 16)[0]
    offset = 32
    for _ in range(ncmds):
        cmd, size = struct.unpack_from("<II", data, offset)
        if size < 8 or offset + size > len(data):
            raise ValueError("Invalid Mach-O load commands")
        if cmd == 0x1D:
            start, length = struct.unpack_from("<II", data, offset + 8)
            signature = data[start:start + length]
            magic, total, count = struct.unpack_from(">III", signature)
            if magic != 0xFADE0CC0 or total > len(signature):
                raise ValueError("Invalid code signature")
            has_der = False
            for index in range(count):
                slot, pos = struct.unpack_from(">II", signature, 12 + index * 8)
                if slot == 5:
                    kind, blob_length = struct.unpack_from(">II", signature, pos)
                    if kind != 0xFADE7171:
                        raise ValueError("Invalid entitlement blob")
                    return sorted(plistlib.loads(signature[pos + 8:pos + blob_length]))
                has_der |= slot == 7
            if has_der:
                raise ValueError("DER-only entitlements require a verified XML declaration")
            return []
        offset += size
    return []


def inspect_ipa(path):
    with zipfile.ZipFile(path) as archive:
        candidates = [n for n in archive.namelist()
                      if re.fullmatch(r"Payload/[^/]+\.app/Info\.plist", n)]
        if len(candidates) != 1:
            raise ValueError("IPA must contain exactly one root application")
        plist_name = candidates[0]
        info = plistlib.loads(archive.read(plist_name))
        base = plist_name.rsplit("/", 1)[0]
        executable = info["CFBundleExecutable"]
        if "/" in executable or executable in (".", ".."):
            raise ValueError("Invalid executable name")
        if "iPhoneOS" not in info.get("CFBundleSupportedPlatforms", []):
            raise ValueError("Simulator apps cannot be published")
        required = ("CFBundleIdentifier", "CFBundleShortVersionString", "CFBundleVersion", "MinimumOSVersion")
        for key in required:
            if not isinstance(info.get(key), str) or not info[key]:
                raise ValueError(f"Missing {key}")
        permissions = set(entitlements(archive.read(f"{base}/{executable}")))
        privacy = {k: v for k, v in info.items() if k.startswith("NS") and k.endswith("UsageDescription")}
        for name in archive.namelist():
            if name.startswith(base + "/") and name.endswith(".appex/Info.plist"):
                extension = plistlib.loads(archive.read(name))
                ext_base = name.rsplit("/", 1)[0]
                permissions.update(entitlements(archive.read(f"{ext_base}/{extension['CFBundleExecutable']}")))
                privacy.update({k: v for k, v in extension.items() if k.startswith("NS") and k.endswith("UsageDescription")})
    return info, {"entitlements": sorted(permissions), "privacy": privacy}


def version_key(version):
    value = version["version"]
    if not re.fullmatch(r"\d+(?:\.\d+)*", value):
        raise ValueError("Use a numeric Apple version when publishing")
    parts = [int(p) for p in value.split(".")]
    while parts and parts[-1] == 0:
        parts.pop()
    return tuple(parts), tuple(int(p) for p in version["buildVersion"].split("."))


def update(catalog, registry, paths, tag, date, notes):
    catalog["apps"] = [app for app in catalog["apps"] if app["bundleIdentifier"] in registry]
    for app in catalog["apps"]:
        metadata = registry[app["bundleIdentifier"]]
        app.update({key: value for key, value in metadata.items() if key != "icon"})
        app["iconURL"] = f"{RAW}/assets/{metadata['icon']}"
    seen = set()
    for path in paths:
        info, permissions = inspect_ipa(path)
        bundle = info["CFBundleIdentifier"]
        if bundle not in registry or bundle in seen:
            raise ValueError(f"Unregistered or duplicate app: {bundle}")
        seen.add(bundle)
        if not re.fullmatch(r"[A-Za-z0-9._-]+", path.name):
            raise ValueError("Use a plain filename for release assets")
        download = f"https://github.com/{REPOSITORY}/releases/download/{tag}/{path.name}"
        digest = hashlib.sha256(path.read_bytes()).hexdigest()
        version = {"version": info["CFBundleShortVersionString"],
                   "buildVersion": info["CFBundleVersion"],
                   "buildNumber": info["CFBundleVersion"],
                   "date": date, "localizedDescription": notes[:4000],
                   "downloadURL": download, "size": path.stat().st_size,
                   "minOSVersion": info["MinimumOSVersion"], "sha256": digest}
        app = next((a for a in catalog["apps"] if a["bundleIdentifier"] == bundle), None)
        if app is None:
            app = {**registry[bundle], "bundleIdentifier": bundle, "developerName": "Strezzy", "versions": []}
            app["iconURL"] = f"{RAW}/assets/{app.pop('icon')}"
            catalog["apps"].append(app)
        same = next((v for v in app["versions"] if version_key(v) == version_key(version)), None)
        if same:
            if same.get("sha256") != digest:
                raise ValueError(f"Bump the version/build number before replacing {app['name']}")
            continue
        if app["versions"] and version_key(version) < version_key(app["versions"][0]):
            raise ValueError(f"Refusing to downgrade {app['name']}")
        app["versions"].insert(0, version)
        app["appPermissions"] = permissions
        # Classic compatibility fields; versions is authoritative.
        app.update(version=version["version"], versionDate=date, versionDescription=notes[:4000],
                   downloadURL=download, size=version["size"])
    catalog["apps"].sort(key=lambda a: list(registry).index(a["bundleIdentifier"]))
    return catalog


def api(path):
    request = urllib.request.Request(f"https://api.github.com/repos/{REPOSITORY}/{path}", headers={
        "Accept": "application/vnd.github+json", "User-Agent": "Strezzy-App-Catalog",
        "Authorization": f"Bearer {os.environ['GH_TOKEN']}"})
    with urllib.request.urlopen(request, timeout=60) as response:
        return json.load(response)


def readme_text(catalog, template):
    downloads = ["| App | Version | Download | Requires |",
                 "| --- | --- | --- | --- |"]
    for app in catalog["apps"]:
        version = app["versions"][0]
        downloads.append(
            f"| <img src=\"{app['iconURL']}\" width=\"44\" alt=\"\"/> **{app['name']}** — {app['subtitle']} "
            f"| {version['version']} ({version['buildVersion']}) | [Download IPA]({version['downloadURL']}) "
            f"| iOS {version['minOSVersion']}+ |")
    details = "\n\n".join(f"### {app['name']}\n\n{app['localizedDescription']}" for app in catalog["apps"])
    text = template
    replacements = {"{{SOURCE_URL}}": f"{RAW}/apps.json",
                    "{{APP_DOWNLOADS}}": "\n".join(downloads),
                    "{{APP_DETAILS}}": details}
    for placeholder, value in replacements.items():
        text = text.replace(placeholder, value)
    return text


def render_readme(catalog):
    template = (ROOT / "scripts" / "README.template.md").read_text(encoding="utf-8")
    (ROOT / "README.md").write_text(readme_text(catalog, template), encoding="utf-8")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--tag", required=True)
    parser.add_argument("--local", nargs="+", type=Path)
    parser.add_argument("--date")
    parser.add_argument("--notes", default="")
    args = parser.parse_args()
    if not re.fullmatch(r"[A-Za-z0-9._-]+", args.tag):
        raise ValueError("Release tag must use letters, numbers, dots, hyphens, or underscores")
    catalog = load(ROOT / "apps.json")
    registry = load(ROOT / "app-registry.json")
    with tempfile.TemporaryDirectory() as directory:
        if args.local:
            if not args.date:
                parser.error("--date is required for local input")
            paths, date, notes = args.local, args.date, args.notes
        else:
            release = api(f"releases/tags/{args.tag}")
            if release["draft"] or release["prerelease"]:
                raise ValueError("Only published regular releases enter the catalog")
            paths = []
            for asset in release["assets"]:
                if not asset["name"].lower().endswith(".ipa"):
                    continue
                if not re.fullmatch(r"[A-Za-z0-9._-]+", asset["name"]):
                    raise ValueError("Invalid release asset name")
                path = Path(directory) / asset["name"]
                request = urllib.request.Request(asset["browser_download_url"], headers={"User-Agent": "Strezzy-App-Catalog"})
                with urllib.request.urlopen(request, timeout=120) as response, path.open("wb") as output:
                    while chunk := response.read(1024 * 1024):
                        output.write(chunk)
                if path.stat().st_size != asset["size"]:
                    raise ValueError("Release asset size does not match")
                paths.append(path)
            if not paths:
                raise ValueError("Release has no IPA assets")
            date, notes = release["published_at"], release.get("body") or "App update."
        update(catalog, registry, paths, args.tag, date, notes)
        save(ROOT / "apps.json", catalog)
        render_readme(catalog)
    print(f"Catalog verified: {len(catalog['apps'])} apps")


if __name__ == "__main__":
    main()
