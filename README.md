<p align="center"><img src="docs/logo.png" width="96" alt="Open Timeline logo"></p>

<h1 align="center">Open Timeline</h1>

<p align="center">A private diary for you and anyone you choose to share it with, one person or many. Posts with a time, a place, text, photos and videos, kept in a Google Drive folder you control as plain files.</p>

<p align="center">
  <img src="docs/screenshots/timeline.png" width="180" alt="Timeline">
  <img src="docs/screenshots/calendar.png" width="180" alt="Calendar">
  <img src="docs/screenshots/map.png" width="180" alt="Map">
  <img src="docs/screenshots/post.png" width="180" alt="Post editor">
</p>

## What it does

- **Posts** with a date and time, an optional location, a title, text, tags (rename, merge or delete them in Settings), and any number of photos and videos.
- **Stamps.** Photograph a page of stamps with the camera or pick a photo. The phone finds each stamp and crops it (or you crop by hand), and each is saved as a one-image entry with an event, a country, a date and a place. Several photos can share one set of details. Stamps show up on the timeline as a compact strip.
- **Events.** A stamp can belong to an event, such as "Kyoto trip". The event is also added to the stamp's tags automatically, so any post can use it as an ordinary tag and the Tag filter gathers the diary posts and the stamps together.
- **Collection.** The Collection tab is a shelf with one booklet per country. Each has a kraft-paper cover with the country's flag as the spine (drawn for East and Southeast Asia so far), a contents page that jumps to each event, and pages of stamps laid out as a collage. A stamp can be Small, Medium or Large, and either a mounted print or cut out of its photo by the phone's on-device AI. Pages turn like a book.
- **Timeline, Calendar and Map** views, with "On this day" memories, filters by date, tag and person, and search.
- **One diary, as many people as you like.** Each person uses their own Google account and their own phone, and everyone points the app at the same shared Drive folder. It works just as well with only you. Each person picks their own colour.
- **Sync on a button press.** Nothing syncs on its own. A notification keeps a running sync going if you lock the phone. If you both edit the same post, nothing is lost: different changes are all kept, and clashing text keeps both versions with a warning.
- **No server and no account with us.** The app talks directly to Google Drive. There is no analytics, advertising or tracking.
- **Your data stays readable.** Posts are ordinary Markdown files and photos sit beside them, so you can read the diary without the app.

Android only. Open Timeline is a sideloaded app, not on the Play Store: download the APK from [Releases](https://github.com/YosYohannes/open-timeline/releases). The app tells you when a newer release is out, and you can turn that off in Settings.

## Sharing it with others

1. One person creates a folder called `OpenTimeline` in **My Drive** and shares it with everyone else as **Editor**. If you are the only user, skip the sharing.
2. Everyone installs the APK, opens **Settings**, tap **Sign in with Google**, and paste the same folder link.
3. Write posts. Press the **Sync** icon whenever you want to exchange them.

Files you upload count against your own Google storage, even inside the shared folder. Only a file's owner can delete it, so deleting a post marks it as deleted and each phone removes the photos it uploaded.

## Your data

```
OpenTimeline/                       shared Drive folder
  README.md                         written by the app, explains the format
  2026/
    20261016-143205-k3f9.md         a post: header (time, place, tags...) and text
    20261016-143205-k3f9_x7q2.jpg   its photo
```

```markdown
---
id: "20261016-143205-k3f9"
author: "someone@example.com"
time: "2026-10-16T14:32:05+02:00"
title: "Weekend at the coast"
location: [52.1083, 4.2733]
place: "Scheveningen beach"
tags: ["beach", "family"]
media: ["20261016-143205-k3f9_x7q2.jpg"]
---
We drove out early to beat the traffic...
```

A stamp is the same kind of file with a few more header fields. `size` and `blend` appear only when they are not the defaults (medium, off):

```markdown
---
id: "20260701-100000-z000"
time: "2026-07-01T10:00:00+09:00"
kind: "stamp"
series: "JR West eki stamps"
country: "JP"
place: "Osaka Station"
size: "large"
blend: true
media: ["20260701-100000-z000_aaaa.png"]
---
```

There is no compression or encryption, by design. Any text editor opens a post, and the folder also works as an [Obsidian](https://obsidian.md) vault.

## Credits

The app icon is based on the `diary` icon from [Arcticons](https://github.com/Arcticons-Team/Arcticons), licensed [CC BY-SA 4.0](https://creativecommons.org/licenses/by-sa/4.0/). The coloured version (filled shapes in kraft paper colours) is a modification of it and is shared under the same licence. The single-colour themed icon follows the original lines.

## Privacy and terms

- [Privacy policy](PRIVACY.md)
- [Terms of service](TERMS.md)

## Run your own copy

A clone or fork can run on its own Google Cloud project and its own releases, with nothing of the original author's in the build. You need Flutter (stable) and the Android SDK; `tool/env.sh` shows how the development environment is set up.

**1. Google Cloud.** Sign-in needs your own project:

1. Enable the **Google Drive API**.
2. In **Google Auth Platform**, set the audience to **External**, add the scope `https://www.googleapis.com/auth/drive`, and add the Gmail addresses of the people who will use the app as test users (or publish the app).
3. Create an **Android** OAuth client with your application ID (see below) and the SHA-1 of the key that signs your APK. For the default debug key: `keytool -list -v -keystore ~/.android/debug.keystore -alias androiddebugkey -storepass android`.
4. Create a **Web application** OAuth client and keep its client ID.

**2. Your settings.** Copy [`env.example.json`](env.example.json) to `env.json` in the project root. It is ignored by git, so it stays on your machine.

| Key | What it is |
| --- | --- |
| `GOOGLE_WEB_CLIENT_ID` | The Web application client ID from step 1. Without it, sign-in is disabled. |
| `UPDATE_REPO` | `owner/name` of the GitHub repository whose latest release the app checks for updates. Leave it out to remove the update check and its switch. |
| `APPLICATION_ID` | The Android package name. Leave it out to keep `com.opentimeline.open_timeline`; set your own if you want to install next to the original app. The Android OAuth client in step 1 must use the same value. |

**3. Build.** Pass the file to Flutter:

```bash
source tool/env.sh
flutter test
flutter run --dart-define-from-file=env.json
flutter build apk --release --dart-define-from-file=env.json
```

A release build is signed with the debug key unless you set up your own. To use one, copy [`android/key.properties.example`](android/key.properties.example) to `android/key.properties` (ignored by git) and fill in your keystore. Back up that keystore: if it is lost, sign-in stops working and updates will not install over the existing app.

**4. Releases.** The update check reads the latest release of `UPDATE_REPO` and offers the first `.apk` attached to it. Name each release tag after the version in `pubspec.yaml` (for example `v1.2.0`), and give every release a higher build number (`1.2.0+10`) than the one before, because Android refuses to install a lower build over a higher one.

**5. Text that names the author.** Edit these by hand, since they are documents and not settings: [`PRIVACY.md`](PRIVACY.md) and [`TERMS.md`](TERMS.md) (name, repository and contact links), the release link near the top of this README, and `title` in [`_config.yml`](_config.yml) if you publish the pages.

```
lib/models/   post model and its Markdown file format
lib/store/    the local journal folder on the phone
lib/sync/     Google sign-in, Drive client, merge and the sync engine
lib/ui/       timeline, calendar, map, post editor, settings
test/         unit and widget tests, including a two-phone sync simulation
```
