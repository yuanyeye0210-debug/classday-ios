# Signing

Classday does not ship a provisioning profile, certificate, or a signature. The GitHub Actions IPA is unsigned. SideStore, with LocalDevVPN, signs it with a free Apple ID. Xcode can sign it too when you have a Mac.

## Identifiers

| Target | Bundle ID | Entitlements file |
| --- | --- | --- |
| Classday | `com.classday.app` | `Config/Classday.entitlements` |
| ClassdayWidget | `com.classday.app.widget` | `Config/ClassdayWidget.entitlements` |

Both entitlements contain one App Group, and both Info.plists list the same id under `ALTAppGroups` (the key AltStore and SideStore read when they register a group):

`group.com.classday.shared`

That string is `AppGroup.identifier` in `ClassdayCore/Sources/ClassdayCore/AppGroupResolver.swift`. It is the first candidate, not the only one the running app will accept. The shared file name is `classday-store.json`.

Signing style is Automatic. `DEVELOPMENT_TEAM` is empty until you select a team in Xcode.

## Xcode

1. Open `Classday.xcodeproj` in Xcode 16 or newer.
2. Select the Classday target, Signing & Capabilities, and choose your Team.
3. Select ClassdayWidget and choose the same Team.
4. Add the App Groups capability to both targets if Xcode did not take it from the entitlements file. Leave the group id as `group.com.classday.shared`.
5. Run the Classday scheme. The widget extension is embedded; you do not run it as its own app.

A paid team can register that exact group. A personal team in Xcode often cannot: the portal answers `An Application Group with Identifier 'group.com.classday.shared' is not available` when another team already owns the string. Use the SideStore path below in that case. The app reads the group the installed profile actually grants.

If no shared group can be opened, 我的 explains what the profiles contained and the timetable stays under Application Support. Widgets cannot see that fallback. After a group starts working, the next launch copies the on-device file into the group and reloads timelines. Use 恢复演示数据 or edit a course once if the widget is still empty.

## URL scheme

The app registers `classday`. Widget and notification taps open `classday://course/<UUID>?meeting=<UUID>`.

## Encryption export

`ITSAppUsesNonExemptEncryption` is false. The app does not implement its own encryption. That flag is only so Xcode's export compliance question has an honest answer. It is not an App Store submission.

## Unsigned IPA

`Classday-vX.Y.Z.ipa` from the `classday-ios-ipa` workflow is an unsigned arm64 iOS device build (`CODE_SIGNING_ALLOWED=NO`, SDK `iphoneos`). It is not a simulator build and it is not an App Store package. On a version bump or a `v*` tag the workflow publishes that IPA to [classday-releases](https://github.com/yuanyeye0210-debug/classday-releases) and keeps only the current and previous files there.

The widget extension is `Payload/Classday.app/PlugIns/ClassdayWidget.appex`. Re-signing has to cover the app and the appex. The widget target is not removed to work around a missing group.

The Mach-O has no code signature, so a signer that only copies entitlements out of the signature will not see the App Group there. Two unsigned hints are in the IPA anyway:

- `archived-expanded-entitlements.xcent` in the `.app` and in the `.appex`, copied from the entitlements files. Resign scripts that still look for that Xcode filename find `com.apple.security.application-groups`.
- `ALTAppGroups` in both Info.plists, set to `group.com.classday.shared`.

## SideStore and LocalDevVPN with a free Apple ID

SideStore signs the unsigned IPA with the free Apple ID. LocalDevVPN has to be connected while SideStore installs or refreshes an app. Add the source once; after that SideStore offers new versions on its own. 我的 → 检查更新 reads the same source and opens SideStore to it, with the IPA link as a fallback.

Source URL:

`https://raw.githubusercontent.com/yuanyeye0210-debug/classday-releases/main/apps.json`

One-time SideStore link (the `url` query is the source, percent-encoded):

`sidestore://source?url=https%3A%2F%2Fraw.githubusercontent.com%2Fyuanyeye0210-debug%2Fclassday-releases%2Fmain%2Fapps.json`

The source lists only the current IPA and the previous one (`version`, `buildVersion`, date, download URL, size, release notes, iOS 17). `buildVersion` is `CFBundleVersion` and increases on every `Tools/bump-version.sh` release. SideStore uses the first version in that list as the latest.

### Free Apple ID limits

- **3 apps installed at once**, and SideStore itself is one of them. LocalDevVPN is another. 课曜 fills the third slot. A fourth sideloaded app has to replace one of these.
- **10 App IDs every 7 days.** The widget extension uses an App ID of its own (`com.classday.app.widget`) in addition to the app (`com.classday.app`). SideStore and LocalDevVPN register their own App IDs too. Do not strip `ClassdayWidget.appex` to save an ID; that removes the widgets.
- The widget is an extension inside the 课曜 app, not a fourth installed app.
- A free signature lasts about 7 days. Leave LocalDevVPN connected and let SideStore refresh it. Refresh keeps the same bundle ID so the timetable is replaced, not installed a second time.

### First install

1. On a computer, install SideStore with its current installer (iloader, or the tool the SideStore getting-started page names) and the free Apple ID. On the iPhone open **设置 → 通用 → VPN 与设备管理**, trust that Apple ID, and turn on Developer Mode if iOS asks.
2. Install LocalDevVPN and connect it. SideStore installs and refreshes need that connection.
3. In SideStore, add the source URL above (Sources → add, or open the `sidestore://source?url=` link).
4. Install 课曜 from that source. Leave the widget extension in the package. If Apple says `com.classday.app` is already taken and SideStore must change the bundle ID, keep that automatic ID and use it again on later refreshes. The app and the widget are signed in the same install.
5. Open 课曜 once. That copies the on-phone timetable into the shared group and reloads the widgets. Add **下一节** and **今日课程** from the widget gallery if they are not on the Home Screen yet. The English home-screen name is Heptara.

Later versions: connect LocalDevVPN, open SideStore, and install the update it shows. 检查更新 jumps to the same source. The direct IPA link is only for when that link cannot open SideStore: the file lands in 文件, then SideStore's + button installs it.

### App Group

Free accounts can use App Groups. Apple's developer API enables that with capability `APG3427HIY`, then the profile is downloaded. If the group is assigned after the profile is built, the profile comes back with an empty `com.apple.security.application-groups` array and the install still succeeds. The app then shows the warning, because there is no container to open.

`group.com.classday.shared` is often already registered to some other team. Apple's error is `An Application Group with Identifier 'group.com.classday.shared' is not available`. SideStore registers a new id under **your** team and writes that id into both provisioning profiles. The forms Classday probes, after the original id, are the ones those tools use:

| Form | Who uses it |
| --- | --- |
| `group.com.classday.shared.<TEAMID>` | Retry when the original id is taken. Team ID is the 10-character id from the profile. |
| `group.<TEAMID>.com.classday.shared` | Team prefix after `group.`, same idea as a portal id that embeds the team. |
| `group.<bundle id>` | SideStore and AltStore. `<bundle id>` is the main app's id after the signer rewrites it. |
| `group.<bundle id>.<TEAMID>` | Impactor-style, when a foreign group namespace is rejected. |
| `group.<TEAMID>.<bundle id>` | Team prefix on the bundle id. |

The app and the widget each parse their own `embedded.mobileprovision` and the other target's. They build one candidate list. An id is used only when it is granted to both profiles (or when neither profile lists a group, in which case both try the same fallback list) and `FileManager.containerURL(forSecurityApplicationGroupIdentifier:)` plus `UserDefaults(suiteName:)` both round-trip. The first candidate that passes is the store. `group.com.classday.shared` stays first.

If the SideStore log contains `An Application Group with Identifier 'group.com.classday.shared' is not available`, refresh the same IPA with the same Apple ID so SideStore can register the Team ID or bundle-id form. Classday reads whichever id landed in both profiles.

我的 keeps the warning when no shared group opened. The text includes any group ids the profiles did contain. The widgets then show **读不到课表**.

## What the free-account build includes

The default IPA is still the iPhone app plus `ClassdayWidget.appex`. There is no Apple Watch target and no complication, so a free account is not asked for a third App ID. iPad landscape is the same target with a wider layout, not a second app.

These stay inside the two App IDs:

- Widgets, including the large week board, the fan stack, and lock-screen accessories.
- Interactive widget buttons and Shortcuts (`已到教室`, `推迟 10 分钟`, `下一节在哪上课`). They write the shared App Group.
- Live Activities and the Dynamic Island, updated locally. Remote push updates are not requested.
- The Control Center control is compiled for iOS 18 and hidden on iOS 17.
- Fénix login uses `ASWebAuthenticationSession`. You register the app yourself. See below.
- Calendar import, iCal subscribe, photo recognition, QR share, and Maps directions.

These degrade, with a Chinese explanation in 学习:

- **iCloud / CloudKit.** The IPA does not declare the iCloud entitlement, because a free Apple ID profile usually rejects it and SideStore would drop or fail the install. 尝试 iCloud reports that and keeps the timetable on the phone.
- **Live Activity push.** The countdown is updated while the app is running. A push token for updates after the app is suspended needs a paid account. That entitlement is not in this IPA.
- **System calendar.** The first sync asks for calendar access. If you deny it, the timetable stays inside 课曜.

### Fénix

1. Open [Fénix](https://fenix.tecnico.ulisboa.pt/) → Personal → Manage Applications.
2. Create an application. Set the redirect URI to `classday://fenix`.
3. Copy the client id and secret into 我的 → 考试、作业、导入和分享.
4. Tap 用 Fénix 登录并导入. Classes come from `/api/fenix/v1/person/calendar/classes` and exams from `/evaluations`.

## Changing the preferred group id

Change both entitlements files, both `ALTAppGroups` arrays, and `AppGroup.identifier` together. The portal record has to match the preferred id. A free-account resign may still grant a different id; the resolver picks that up without another source edit.
