# Changelog

## 2.2.0

- Multiple unmount triggers can now be enabled at once.
- Added a "Dock disconnected" trigger that unmounts volumes when a remembered dock is unplugged, while ignoring MagSafe and other chargers.
- Added an "External display disconnected" trigger for clamshell setups.
- Volumes now remount automatically when a remembered dock is reconnected.
- Added an option to keep volumes unmounted while running on battery, with a new "Mount all" menu action to remount them on demand.
- Fixed the dock disconnected trigger unmounting volumes when an unrelated charger was unplugged, on Macs that report the same placeholder identifiers for every power adapter.
- The dock disconnected trigger now only fires while the lid is closed by default, so a Mac in use never has a volume pulled out from under it.
- Added an "Unmount all and sleep" action, on Shift-Command-S by default, that unmounts every selected volume and then sleeps the Mac.
- Added an option to put the Mac to sleep once a dock or external display disconnect has unmounted every volume, which unplugging a dock in clamshell mode does not do on its own.
- Added a progress panel below the menu bar icon that reports unmounting, remounting and ejecting, and stays on screen when a disk could not be handled.
- Unmount results are now verified, so a disk that is still mounted is reported instead of being treated as unmounted.
- The unmount-all and mount-all keyboard shortcuts can now be changed, and default to Shift-Command-E and Shift-Command-M.
- Docks can be chosen from a list of power adapters Ejectify has seen, so an adapter can be marked as a dock while it is unplugged.
- A power adapter that macOS refuses to describe can now be marked as a dock anyway, matched on its wattage alone after a confirmation that says what that means; adapters of a different wattage still never match it.
- Diagnostics reports now include power adapter, remembered dock, and trigger information.

## 2.1.0

- Added an opt-in whole-disk eject mode for automatically and manually ejecting selected devices without attempting to remount them, including forced-unmount preparation when Force Unmount is enabled.
- Added native-first unlocking and remounting of encrypted APFS volumes, with an optional Ejectify Keychain password fallback that can be disabled from the menu.
- Improved automatic remount reliability for volumes that take time to become available or unmount later than expected around sleep and wake.
- Improved diagnostics reports with clearer app, privileged helper, and macOS disk-operation logs.
- Improved menu reliability when managed volumes mount, unmount, or are renamed.

## 2.0.6

- Fixed discovery of mounted volumes whose Disk Arbitration metadata does not provide a volume name.

## 2.0.5

- Added raw mounted volume discovery metadata to diagnostics reports to help troubleshoot volumes missing from Ejectify.

## 2.0.4

- Added the ability to export a diagnostics report for troubleshooting.
- Aligned menu item capitalization to match Apple system style.

## 2.0.3

- Restored automatic unmount triggers for when the screen is locked or the screen saver starts.
- Expanded and refined localizations for the restored trigger labels.

## 2.0.2

- Cleared stale remount candidates when managed volumes remount outside Ejectify's own mount flow, preventing redundant remount attempts and improving resolved-disk logging.

## 2.0.1

- Added external non-ejectable volumes to the discovery list so more removable media is surfaced consistently.

## 2.0.0

- Added a first-launch onboarding flow with improved presentation, localized copy, and clearer elevated-permissions guidance.
- Introduced privileged helper routing and refined disk operation handling, remount retries, sleep/wake behavior, and logging.
- Added a global shortcut for `Unmount all`.
- Improved packaging, notarization, Sparkle update handling, and release tooling.
- Expanded and corrected localizations, including alignment with Apple system wording for disk ejection strings.

## 1.2.2

- Added support for internal but ejectable volumes such as SD cards.
- Fixed a code signing issue in the release process.
- Added Turkish and Brazilian Portuguese localizations and updated German translations.
- Cleaned up warnings, versioning, and documentation updates around the release.

## 1.2.1

- Fixed a build issue affecting the release.
- Restricted the volume list to external volumes.
- Added extra logging to help debug disk and sleep behavior.
- Added an FAQ section and enabled Italian translations.
- Updated French and Spanish localizations and refreshed the README.

## 1.2.0

- Added `Unmount all`.
- Added a forced unmount option for managed volumes.
- Added a delay before remounting volumes.
- Expanded the app's localization coverage, including Arabic.

## 1.1.0

- Updated Hindi translations.

## 1.0.0

- Initial release of Ejectify.
