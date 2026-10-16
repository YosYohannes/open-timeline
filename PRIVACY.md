# Privacy Policy

**Open Timeline** is a private diary app for one person or a small group. This policy explains what the app does with your information.

Last updated: 17 October 2026

## The short version

- Your diary lives on your phone and in a Google Drive folder that you choose. **Nothing is sent to the developer.** There is no Open Timeline server.
- There is no analytics, advertising, tracking or crash reporting in the app.
- The app does not encrypt your posts. Anyone who can open your Drive folder or your unlocked phone can read them.

## Who is responsible

Open Timeline is an open-source hobby project by Yos Yohannes ([github.com/YosYohannes/open-timeline](https://github.com/YosYohannes/open-timeline)). Questions or requests: please [open an issue](https://github.com/YosYohannes/open-timeline/issues).

## What the app handles

| Information | Why | Where it goes |
|---|---|---|
| Your posts: text, titles, tags, time, optional location, photos and videos | This is the diary | Stored in the app's private storage on your phone, and copied to the Google Drive folder you choose when you press **Sync** |
| Your Google account email | To sign in, and to mark which posts are yours | Stays on your phone and, as the author of each post, in your Drive folder |
| Google Drive access | To read and write the diary folder | A token held by Google on your phone. The developer never receives it |
| Your chosen colour, folder ID and settings | To remember your preferences | Stored on your phone. Your colour is also saved inside your posts so other people's phones can show it |

## Permissions the app asks for

- **Location**, only when you tap **Current** in a post. The app reads your position once to fill in the post's location. It does not track you, and it does not use location in the background.
- **Camera**, only when you tap **Photo** or **Video**.
- **Photos and videos**, only when you choose files to attach.
- **Internet**, to sync with Google Drive, load map images and check for updates.

## Google sign-in and Google Drive

The app uses Google Sign-In and the Google Drive API to sync your diary. It asks for the `drive` permission. This permission covers your whole Drive, because a narrower one cannot see files that other people create in the shared folder. **The app only lists, reads and writes files inside the folder you select**, and it does not look at the rest of your Drive.

The use of information received from Google APIs adheres to the [Google API Services User Data Policy](https://developers.google.com/terms/api-services-user-data-policy), including the Limited Use requirements. The app uses this information only to provide the diary and sync features you see. It is not used for advertising, and it is not transferred to anyone else.

You can revoke the app's access at any time at [myaccount.google.com/permissions](https://myaccount.google.com/permissions).

## Other services the app contacts

- **Google Drive and Google Sign-In**, as described above. Google's [privacy policy](https://policies.google.com/privacy) applies.
- **OpenStreetMap map images.** When you view a map, the app downloads map tiles from `tile.openstreetmap.org`. OpenStreetMap can see your IP address, the area of the map you are viewing, and the app's identifier. It does not receive your posts. See the [OSMF privacy policy](https://osmfoundation.org/wiki/Privacy_Policy).
- **GitHub, to check for updates.** When the app opens, it asks `api.github.com` for the latest release of this project. GitHub can see your IP address and the app's request, and nothing from your diary is sent. You can turn this off in **Settings**.
- **Place search and address lookup.** When you search for a place by name, or use your current location to suggest a place name, the app asks the **location lookup service built into your Android phone**, which on most phones is provided by Google. That service receives the place text you typed or your coordinates. It does not receive your post text.

## Sharing

The only people who can see your diary are those who can open your Drive folder. If you share the folder with someone, they can read and edit every post in it. Do not share the folder with anyone you do not want to read your diary.

## Keeping and deleting your data

- Your posts are kept until you delete them. Deleting a post in the app marks it as deleted in the shared folder so the other phones follow. To remove files completely, delete them in Google Drive.
- Uninstalling the app removes the copy on your phone. Files already in Drive stay there until you delete them.
- You can sign out in the app's **Settings** and revoke access in your Google account.

## Children

Open Timeline is not directed at children, and the developer does not knowingly collect information from children.

## Changes to this policy

Changes are published in this repository, and the date at the top changes with them. The full history is visible in the repository's commits.

## Contact

[github.com/YosYohannes/open-timeline/issues](https://github.com/YosYohannes/open-timeline/issues)
