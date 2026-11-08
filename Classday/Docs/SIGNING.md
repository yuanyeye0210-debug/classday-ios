# Signing

Classday does not ship a provisioning profile, certificate, or IPA.

## Identifiers

| Target | Bundle ID | Entitlements file |
| --- | --- | --- |
| Classday | `com.classday.app` | `Config/Classday.entitlements` |
| ClassdayWidget | `com.classday.app.widget` | `Config/ClassdayWidget.entitlements` |

Both entitlements contain one App Group:

`group.com.classday.shared`

The same string is `AppGroup.identifier` in `ClassdayCore/Sources/ClassdayCore/Models.swift`. The shared file name is `classday-store.json`.

Signing style is Automatic. `DEVELOPMENT_TEAM` is empty until you select a team in Xcode.

## Steps

1. Open `Classday.xcodeproj` in Xcode 16 or newer.
2. Select the Classday target, Signing & Capabilities, and choose your Team.
3. Select ClassdayWidget and choose the same Team.
4. Add the App Groups capability to both targets if Xcode did not take it from the entitlements file. The group id must be exactly `group.com.classday.shared`.
5. Run the Classday scheme. The widget extension is embedded; you do not run it as its own app.

A personal team can run on the simulator and on a registered iPhone. App Groups on a personal team work for development installs. They do not produce an App Store build.

If the group container is unavailable, 我的 shows that widgets cannot sync. The timetable is still stored under Application Support. After the group starts working, the next save is what the widget reads. Use 恢复演示数据 or edit a course once so the app writes the shared file and reloads timelines.

## URL scheme

The app registers `classday`. Widget and notification taps open `classday://course/<UUID>?meeting=<UUID>`.

## Encryption export

`ITSAppUsesNonExemptEncryption` is false. The app does not implement its own encryption. That flag is only so Xcode's export compliance question has an honest answer. It is not an App Store submission.

## Unsigned IPA for Sideloadly

`Classday-v1.ipa` from the `classday-ios-ipa` GitHub Actions workflow is an unsigned arm64 iOS device build (`CODE_SIGNING_ALLOWED=NO`, SDK `iphoneos`). It is not a simulator build and it is not an App Store package. Sideloadly can re-sign it with your Apple ID and install it.

The widget extension is inside `Payload/Classday.app/PlugIns/ClassdayWidget.appex`. Re-signing must cover both the app and the appex. The project still declares App Group `group.com.classday.shared` on both targets. A free Apple ID / Sideloadly profile often does not include that App Group. In that case the app still stores the timetable on the phone, 我的 says the group is unavailable, and the widgets show the unsynced empty state until a profile that contains the same group is used. The widget target is not removed to work around that.

## Changing the group id

Update both entitlements files and `AppGroup.identifier`, then regenerate nothing else. The portal record must match.
