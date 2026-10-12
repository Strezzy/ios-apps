# Publishing and catalog maintenance

These notes cover how I publish app updates and maintain the download page.

## Publish an update

1. Build the app and increase its version or build number. Keep its bundle identifier unchanged.
2. [Create a release](https://github.com/Strezzy/ios-apps/releases/new) with a new tag, attach the IPA, write the release notes, and publish it as a regular release.
3. The **Update app catalog** workflow reads the IPA's bundle identifier, version, minimum iOS version, permissions, file size, and SHA-256 checksum. It updates `apps.json` and regenerates `README.md`.
4. Refresh the source in LiveContainer to check the listing.

Drafts and prereleases stay out of the catalog. If an asset is added after publication, run **Update app catalog** manually with that release tag. If a run fails, check its Actions log before rerunning it.

A new build needs a new version or build number. Do not replace a published IPA with different bytes under the same version and build. Keep older published assets available unless an app is being withdrawn.

## Change the public wording

- Edit each app's name, subtitle, and description in `app-registry.json`. The updater copies that metadata into the catalog.
- Edit the page introduction, directions, and development note in `scripts/README.template.md`. The release workflow uses that template, so later releases retain those edits.
- Keep the current `apps.json` and generated `README.md` in sync when changing the wording between releases.
- The source's overall name, subtitle, and description are in `apps.json`.

To regenerate the page from the current catalog without downloading or publishing a release, run this from the repository root:

```sh
python3 -c 'import json; from scripts.update_catalog import render_readme; render_readme(json.load(open("apps.json")))'
```

## Add or withdraw an app

To add an app, register its exact bundle identifier and metadata in `app-registry.json`, add its PNG icon to `assets/`, and publish its IPA in a new release.

To withdraw an app, remove it from the registry, the current catalog, the download page, and public release attachments. Remove unused artwork as well. The updater drops catalog entries missing from the registry and rejects unregistered IPAs, so an old upload cannot silently restore the listing.

## Catalog format

The catalog follows the [AltStore Classic source format](https://faq.altstore.io/developers/make-a-source). It includes both `buildVersion` and `buildNumber` for client compatibility. Latest versions come first, and bundle identifiers stay unchanged across updates.

## LiveContainer update directions

The public update directions were checked against the available LiveContainer source at commit `4dbe0f9a626de801184a42c0be8d2cb105058e3d`:

- [App installer and replacement logic](https://github.com/LiveContainerMirror/LiveContainer/blob/4dbe0f9a626de801184a42c0be8d2cb105058e3d/LiveContainerSwiftUI/Views/AppList/LCAppListView.swift)
- [Sources refresh and install controls](https://github.com/LiveContainerMirror/LiveContainer/blob/4dbe0f9a626de801184a42c0be8d2cb105058e3d/LiveContainerSwiftUI/Views/LCAltStoreSourcesView.swift)
- [Container selection](https://github.com/LiveContainerMirror/LiveContainer/blob/4dbe0f9a626de801184a42c0be8d2cb105058e3d/LiveContainerSwiftUI/Views/AppList/LCAppBanner/LCAppBannerViewController.swift)

Replacing an existing app copies its saved container list and default container identifier. The update instructions describe that behavior; they do not guarantee every app's own data migration.
