# GTasksTray

A native macOS menu bar app for Google Tasks. The menu bar icon shows your open task count. Click it to view tasks across all your lists, see notes and scheduled dates, mark tasks complete, or add a new task. The **Completed** section shows the five most recent completions. Select **Show more** to see older ones.

Completing a task plays a short sound and animates the checkmark. You can mute the sound or switch between English and Polish in the app’s **⋯** menu. GTasksTray starts in Polish when Polish is your preferred system language and in English otherwise. It remembers your selection.

**Open in Chrome** switches to an existing Google Tasks tab or opens a new one. macOS may ask for permission to automate Chrome the first time. Without that permission, the app opens a new tab.

## Build and run

You need macOS 13 or later and Xcode with Swift 6. Install Google Chrome if you want to open the web view from the app.

```sh
./scripts/build-app.sh
open dist/GTasksTray.app
```

Look for the GTasksTray icon in the menu bar. You can also move `dist/GTasksTray.app` to your Applications folder.

## Connect your Google account

1. Select or create a project in Google Cloud and enable the Google Tasks API. [Google Cloud Console](https://console.cloud.google.com/) · [Google Tasks API](https://console.cloud.google.com/apis/library/tasks.googleapis.com)
2. Set up the OAuth consent screen. For a personal Google account, select **External** and add your email as a test user under **Audience**. Add the `https://www.googleapis.com/auth/tasks` scope under **Data Access**. [Google Auth Platform](https://console.cloud.google.com/auth/overview)
3. Under **Clients**, create an OAuth client of type **Desktop app** and download its JSON file.
4. Click the GTasksTray icon, select **Choose OAuth file…**, and open the downloaded file. Select **Sign in with Google**, choose your account in the browser, and grant access to your tasks.
5. Return to GTasksTray. The app syncs every 90 seconds, and you can refresh it manually from the panel header.

GTasksTray stores the OAuth client settings and refresh token in the macOS Keychain. If the OAuth app is set to **External → Testing**, Google expires the authorization after seven days and GTasksTray prompts you to sign in again. [Google Cloud documentation](https://support.google.com/cloud/answer/15549945)

If you use more than one Google account, choose the same account in Chrome and GTasksTray. You can schedule tasks by date in GTasksTray. To set a time, recurrence, or deadline, open Google Tasks in Chrome. [Google Tasks API reference](https://developers.google.com/workspace/tasks/reference/rest/v1/tasks)

## Tests

```sh
swift test
```

The tests cover pagination, open task counts, creating and completing tasks, sorting completed tasks, date formatting, and the local OAuth callback.
