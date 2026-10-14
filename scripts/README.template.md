# Strezzy’s iPhone Apps

I'm Strezzy. These are passion projects I build for myself and share here for free. This page has my app downloads, a quick explanation of what each one does, and directions for installing and updating them in LiveContainer.

## Downloads

{{APP_DOWNLOADS}}

The number in parentheses is the build number. If the version number stays the same, a higher build number means a newer update. You can read what's changed on the [releases page](https://github.com/Strezzy/ios-apps/releases).

## Yes, they're vibe-coded

**All of my apps are vibe-coded.** I use AI tools to help write the code, while I direct development, give detailed instructions, beta test, and work through bugs and revisions. I spend **$200+ a month** on those tools and **5–8+ hours a day** on development and testing.

These are personal passion projects, shared for free. Constructive feedback is welcome. If AI-assisted development is a dealbreaker, you're free to pass. If you'd prefer a different process, you're also welcome to contribute the budget and put in the hours. The tools help with the code; the bill and the time are still mine.

## What each app does

{{APP_DETAILS}}

## Add my apps to LiveContainer

You only need to add this source once.

1. Open **LiveContainer → Sources → +**.
2. Paste the address below and add the source.
3. Open **Strezzy’s Apps** and tap **Install** beside the app you want.

```text
{{SOURCE_URL}}
```

You can also download an IPA from the table above and import it through **Apps → + → Install IPA File** in LiveContainer.

## Native suite rename

**The first native Facet, Veil, Lucid and Echo releases use new bundle IDs.** Keep the old installation and export important files before removing it. Data does not automatically transfer to the new app identity. See [the one-time installation note](docs/NATIVE-SUITE-UPGRADE.md). Prism and Music are unchanged.

## Update an app and keep your data

**Leave the old version installed.** Replacing that existing copy lets LiveContainer reuse its data container, where the app keeps your files and settings. Keep a separate copy of any files you can't replace before updating.

1. Open **Sources** in LiveContainer and tap the circular refresh button (**Refresh All**).
2. Open **Strezzy’s Apps** and tap **Install** beside the app you want to update. The button can still say **Install** for an update.
3. When LiveContainer finds the existing app, select that existing entry in the **Installation** prompt. It may appear as a name ending in `.app`. **Install as new** creates a separate copy.
4. Wait for the installation to finish, then open the app using the same data container as before.

**Updating with a downloaded IPA:** Download the newer IPA, open **Apps → + → Install IPA File**, and select the file. Choose the existing app entry in the installation prompt.

### If the app opens with an empty library

Check which data container is selected. If you use more than one, long-press the app in LiveContainer and choose your previous one under **Containers**. A different container can make the app look empty even when your files are still in the original one. Avoid deleting the app or clearing its data while you're checking.

These steps cover updates to an app already inside LiveContainer. Moving an app from a separate installation into LiveContainer needs its own data transfer.

## Found a problem?

[Open an issue](https://github.com/Strezzy/ios-apps/issues) with the app name, version and build number, your iPhone model, and your iOS version. Tell me what you were doing and what happened. Screenshots help when they show the problem; please keep personal files and voice recordings out of public reports.

---

[Publishing and catalog maintenance](docs/PUBLISHING.md)
