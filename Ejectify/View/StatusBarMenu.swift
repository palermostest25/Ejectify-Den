//
//  StatusBarMenu.swift
//  Ejectify
//
//  Created by Niels Mouthaan on 21/11/2020.
//

import AppKit
import Carbon

/// Builds and updates the status bar menu for volume actions and preferences.
final class StatusBarMenu: NSMenu {


    /// Destination URL used by the Help action.
    private let helpURL = URL(string: "https://ejectify.app/help")!

    /// Cached mounted volumes shown in the menu.
    private var volumes: [Volume]

    /// Required initializer for storyboard/nib usage.
    required init(coder: NSCoder) {
        volumes = Volume.mountedVolumes()
        super.init(coder: coder)
        configureMenuBehavior()
        listenForOperationRouterNotifications()
        updateMenu()
        listenForVolumeNotifications()
    }

    /// Initializes the menu, loads mounted volumes, and starts notifications.
    init() {
        volumes = Volume.mountedVolumes()
        super.init(title: "Ejectify")
        configureMenuBehavior()
        listenForOperationRouterNotifications()
        updateMenu()
        listenForVolumeNotifications()
    }

    /// Takes over item enabling and refreshes the menu each time it opens so live state is shown.
    private func configureMenuBehavior() {
        autoenablesItems = false
        delegate = self
    }

    /// Removes registered workspace observers before deallocation.
    deinit {
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        NotificationCenter.default.removeObserver(self, name: .volumeOperationRouterDidChange, object: VolumeOperationRouter.shared)
    }

    /// Starts observing mount, unmount, and rename events to keep the menu current.
    private func listenForVolumeNotifications() {
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(volumeDidRename(notification:)), name: NSWorkspace.didRenameVolumeNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(volumeDidMount(notification:)), name: NSWorkspace.didMountNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(volumeDidUnmount(notification:)), name: NSWorkspace.didUnmountNotification, object: nil)
    }

    /// Observes router state changes so the menu can reflect daemon availability updates.
    private func listenForOperationRouterNotifications() {
        NotificationCenter.default.addObserver(self, selector: #selector(operationRouterDidChange(_:)), name: .volumeOperationRouterDidChange, object: VolumeOperationRouter.shared)
    }

    /// Rebuilds the menu whenever operation routing availability changes.
    @objc private func operationRouterDidChange(_ notification: Notification) {
        if Thread.isMainThread {
            updateMenu()
            return
        }

        performSelector(onMainThread: #selector(updateMenuFromMainThread), with: nil, waitUntilDone: false)
    }

    /// Rebuilds the menu from the main thread when observer callbacks arrive off-main.
    @objc private func updateMenuFromMainThread() {
        updateMenu()
    }

    /// Handles mount notifications and logs mount metadata provided by NSWorkspace.
    @objc private func volumeDidMount(notification: Notification) {
        guard Thread.isMainThread else {
            performSelector(onMainThread: #selector(volumeDidMount(notification:)), with: notification, waitUntilDone: false)
            return
        }

        guard let volume = managedVolume(from: notification, urlKey: NSWorkspace.volumeURLUserInfoKey) else {
            return
        }

        Log.volumeOperations.log("Volume did mount: \(volume.logLabel)")
        upsertCachedVolume(volume)
        updateMenu()
    }

    /// Handles unmount notifications and logs unmount metadata provided by NSWorkspace.
    @objc private func volumeDidUnmount(notification: Notification) {
        guard Thread.isMainThread else {
            performSelector(onMainThread: #selector(volumeDidUnmount(notification:)), with: notification, waitUntilDone: false)
            return
        }

        guard let url = notificationURL(from: notification, urlKey: NSWorkspace.volumeURLUserInfoKey),
              let volumeIndex = cachedVolumeIndex(for: url) else {
            return
        }

        let volume = volumes.remove(at: volumeIndex)
        Log.volumeOperations.log("Volume did unmount: \(volume.logLabel)")
        updateMenu()
    }

    /// Handles rename notifications and logs stable volume correlation metadata.
    @objc private func volumeDidRename(notification: Notification) {
        guard Thread.isMainThread else {
            performSelector(onMainThread: #selector(volumeDidRename(notification:)), with: notification, waitUntilDone: false)
            return
        }

        let oldVolumeIndex = notificationURL(from: notification, urlKey: NSWorkspace.oldVolumeURLUserInfoKey)
            .flatMap(cachedVolumeIndex(for:))
        let renamedVolume = managedVolume(from: notification, urlKey: NSWorkspace.volumeURLUserInfoKey)

        if let oldVolumeIndex {
            Log.volumeOperations.log("Volume did rename; \(volumes[oldVolumeIndex].logLabel)")
        }

        switch (oldVolumeIndex, renamedVolume) {
        case let (oldVolumeIndex?, renamedVolume?):
            replaceCachedVolume(at: oldVolumeIndex, with: renamedVolume)
        case let (oldVolumeIndex?, nil):
            volumes.remove(at: oldVolumeIndex)
        case let (nil, renamedVolume?):
            upsertCachedVolume(renamedVolume)
        case (nil, nil):
            return
        }

        updateMenu()
    }

    /// Returns the volume URL stored under a workspace notification user-info key.
    private func notificationURL(from notification: Notification, urlKey: String) -> URL? {
        notification.userInfo?[urlKey] as? URL
    }

    /// Returns the cached index whose normalized mounted path matches `url`.
    private func cachedVolumeIndex(for url: URL) -> Int? {
        let targetPath = url.standardizedFileURL.path
        return volumes.firstIndex(where: { $0.url.standardizedFileURL.path == targetPath })
    }

    /// Returns the cached index matching a volume's stable identifier or normalized mounted path.
    private func cachedVolumeIndex(matching volume: Volume, excluding excludedIndex: Int? = nil) -> Int? {
        let targetPath = volume.url.standardizedFileURL.path
        return volumes.indices.first { index in
            index != excludedIndex
                && (volumes[index].id == volume.id || volumes[index].url.standardizedFileURL.path == targetPath)
        }
    }

    /// Replaces a matching cached volume or appends a newly mounted volume.
    private func upsertCachedVolume(_ volume: Volume) {
        if let volumeIndex = cachedVolumeIndex(matching: volume) {
            volumes[volumeIndex] = volume
        } else {
            volumes.append(volume)
        }
    }

    /// Replaces a renamed cache entry while removing any duplicate entry for the resolved volume.
    private func replaceCachedVolume(at oldVolumeIndex: Int, with renamedVolume: Volume) {
        var replacementIndex = oldVolumeIndex
        if let duplicateIndex = cachedVolumeIndex(matching: renamedVolume, excluding: oldVolumeIndex) {
            volumes.remove(at: duplicateIndex)
            if duplicateIndex < replacementIndex {
                replacementIndex -= 1
            }
        }

        volumes[replacementIndex] = renamedVolume
    }

    /// Resolves a notification URL to a managed volume using the same filter as `mountedVolumes`.
    private func managedVolume(from notification: Notification, urlKey: String) -> Volume? {
        guard let url = notification.userInfo?[urlKey] as? URL else {
            return nil
        }

        return Volume.fromURL(url: url)
    }

    /// Rebuilds all top-level menu sections from current app state.
    private func updateMenu() {
        guard Thread.isMainThread else {
            performSelector(onMainThread: #selector(updateMenuFromMainThread), with: nil, waitUntilDone: false)
            return
        }

        removeAllItems()
        buildActionsMenu()
        buildVolumesMenu()
        buildPreferencesMenu()
        buildAppMenu()
    }

    /// Builds the top "Actions" section.
    private func buildActionsMenu() {
        let isUnmountHotKeyRegistered = MainActor.assumeIsolated {
            AppDelegate.shared.isUnmountAllHotKeyRegistered
        }
        let isMountHotKeyRegistered = MainActor.assumeIsolated {
            AppDelegate.shared.isMountAllHotKeyRegistered
        }
        let hasPendingRemountCandidates = MainActor.assumeIsolated {
            AppDelegate.shared.activityController?.hasPendingRemountCandidates ?? false
        }
        let allVolumesActionTitle = Preference.ejectInsteadOfUnmount
            ? String(localized: "Eject all")
            : String(localized: "Unmount all")
        let unmountAllItem = NSMenuItem(
            title: allVolumesActionTitle,
            action: #selector(unmountAllClicked(menuItem:)),
            keyEquivalent: ""
        )
        unmountAllItem.target = self
        unmountAllItem.isEnabled = !volumes.isEmpty
        applyShortcut(for: .unmountAll, to: unmountAllItem, isRegistered: isUnmountHotKeyRegistered)
        addItem(unmountAllItem)

        // Ejected disks are never remounted automatically, so a manual mount action would have nothing to act on.
        guard !Preference.ejectInsteadOfUnmount else {
            return
        }

        let mountAllItem = NSMenuItem(title: String(localized: "Mount all"), action: #selector(mountAllClicked(menuItem:)), keyEquivalent: "")
        mountAllItem.target = self
        mountAllItem.isEnabled = hasPendingRemountCandidates
        applyShortcut(for: .mountAll, to: mountAllItem, isRegistered: isMountHotKeyRegistered)
        addItem(mountAllItem)

        let isSleepHotKeyRegistered = MainActor.assumeIsolated {
            AppDelegate.shared.isUnmountAllAndSleepHotKeyRegistered
        }
        let unmountAndSleepItem = NSMenuItem(
            title: String(localized: "Unmount all and sleep"),
            action: #selector(unmountAllAndSleepClicked(menuItem:)),
            keyEquivalent: ""
        )
        unmountAndSleepItem.target = self
        unmountAndSleepItem.isEnabled = !volumes.isEmpty
        applyShortcut(for: .unmountAllAndSleep, to: unmountAndSleepItem, isRegistered: isSleepHotKeyRegistered)
        addItem(unmountAndSleepItem)
    }

    /// Shows an action's global shortcut next to its menu item, but only while that shortcut is actually registered.
    private func applyShortcut(for action: GlobalShortcut.Action, to menuItem: NSMenuItem, isRegistered: Bool) {
        guard isRegistered else {
            return
        }

        let shortcut = Preference.shortcut(for: action)
        menuItem.keyEquivalent = shortcut.menuKeyEquivalent
        menuItem.keyEquivalentModifierMask = shortcut.modifierFlags
    }

    /// Builds the "Volumes" section with one toggle row per mounted volume.
    private func buildVolumesMenu() {
        addItem(NSMenuItem.separator())

        addVolumeSection(title: String(localized: "Internal"), category: .internalVolume)
        addVolumeSection(title: String(localized: "External"), category: .external)
        addVolumeSection(title: String(localized: "Disk Images"), category: .diskImage)
    }

    /// Adds one grouped volume section in the configured category order.
    private func addVolumeSection(title: String, category: Volume.Category) {
        let volumesForCategory = volumes.filter { $0.category == category }
        guard !volumesForCategory.isEmpty else {
            return
        }

        addItem(NSMenuItem.sectionHeader(title: title))
        for volume in volumesForCategory {
            let volumeItem = NSMenuItem(title: volume.name, action: #selector(volumeClicked(menuItem:)), keyEquivalent: "")
            volumeItem.target = self
            volumeItem.state = volume.enabled ? .on : .off
            volumeItem.representedObject = volume
            addItem(volumeItem)
        }
    }

    /// Builds user-configurable app preferences.
    private func buildPreferencesMenu() {
        addItem(NSMenuItem.separator())

        addItem(NSMenuItem.sectionHeader(title: String(localized: "Preferences")))

        let launchAtLoginItem = NSMenuItem(title: String(localized: "Launch at login"), action: #selector(launchAtLoginClicked(menuItem:)), keyEquivalent: "")
        launchAtLoginItem.target = self
        launchAtLoginItem.state = Preference.launchAtLogin ? .on : .off
        addItem(launchAtLoginItem)

        let unmountWhenTitle = Preference.ejectInsteadOfUnmount
            ? String(localized: "Eject when")
            : String(localized: "Unmount when")
        let unmountWhenItem = NSMenuItem(title: unmountWhenTitle, action: nil, keyEquivalent: "")
        unmountWhenItem.submenu = buildUnmountWhenMenu()
        addItem(unmountWhenItem)

        let dockItem = NSMenuItem(title: String(localized: "Dock"), action: nil, keyEquivalent: "")
        dockItem.submenu = buildDockMenu()
        addItem(dockItem)

        let ejectInsteadOfUnmountItem = NSMenuItem(
            title: String(localized: "Eject instead of unmount"),
            action: #selector(ejectInsteadOfUnmountClicked(menuItem:)),
            keyEquivalent: ""
        )
        ejectInsteadOfUnmountItem.target = self
        ejectInsteadOfUnmountItem.state = Preference.ejectInsteadOfUnmount ? .on : .off
        addItem(ejectInsteadOfUnmountItem)

        let forceUnmountItem = NSMenuItem(title: String(localized: "Force unmount"), action: #selector(forceUnmountClicked(menuItem:)), keyEquivalent: "")
        forceUnmountItem.target = self
        forceUnmountItem.state = Preference.forceUnmount ? .on : .off
        addItem(forceUnmountItem)

        let unlockVolumesWhenNeededItem = NSMenuItem(
            title: String(localized: "Unlock volumes when needed"),
            action: #selector(unlockVolumesWhenNeededClicked(menuItem:)),
            keyEquivalent: ""
        )
        unlockVolumesWhenNeededItem.target = self
        unlockVolumesWhenNeededItem.state = Preference.unlockVolumesWhenNeeded ? .on : .off
        addItem(unlockVolumesWhenNeededItem)

        let elevatedPermissionsItem = NSMenuItem(title: String(localized: "Use elevated permissions"), action: #selector(elevatedPermissionsClicked(menuItem:)), keyEquivalent: "")
        elevatedPermissionsItem.target = self
        elevatedPermissionsItem.state = elevatedPermissionsMenuState
        addItem(elevatedPermissionsItem)

        let shortcutsItem = NSMenuItem(
            title: String(localized: "Keyboard Shortcuts…"),
            action: #selector(shortcutSettingsClicked),
            keyEquivalent: ""
        )
        shortcutsItem.target = self
        addItem(shortcutsItem)

        let muteNotificationsItem = NSMenuItem(title: String(localized: "Force mute notifications"), action: #selector(muteNotificationsClicked(menuItem:)), keyEquivalent: "")
        muteNotificationsItem.target = self
        muteNotificationsItem.state = isForceMuteNotificationsEnabled() ? .on : .off
        addItem(muteNotificationsItem)
    }

    /// Converts menu state toggles to a Bool value.
    private func toggledValue(for state: NSControl.StateValue) -> Bool {
        state == .off
    }

    /// Represents enabled elevated permissions only when routing is actively using the privileged helper.
    private var elevatedPermissionsMenuState: NSControl.StateValue {
        VolumeOperationRouter.shared.isUsingPrivilegedHelper ? .on : .off
    }

    /// Returns whether force-muting notifications is enabled in the system Disk Arbitration plist, treating any read failure or missing value as unmuted (`false`).
    private func isForceMuteNotificationsEnabled() -> Bool {
        guard
            let preferences = NSDictionary(contentsOfFile: PrivilegedHelperConfiguration.diskArbitrationPreferencesPath),
            let rawValue = preferences[PrivilegedHelperConfiguration.disableEjectNotificationKey]
        else {
            return false
        }

        if let boolValue = rawValue as? Bool {
            return boolValue
        }

        if let numberValue = rawValue as? NSNumber {
            return numberValue.boolValue
        }

        if let stringValue = rawValue as? String {
            return NSString(string: stringValue).boolValue
        }

        return false
    }

    /// Builds the submenu for selecting which events trigger automatic unmounting.
    private func buildUnmountWhenMenu() -> NSMenu {
        let title = Preference.ejectInsteadOfUnmount
            ? String(localized: "Eject when")
            : String(localized: "Unmount when")
        let unmountWhenMenu = NSMenu(title: title)
        unmountWhenMenu.autoenablesItems = false

        let selectedTriggers = Preference.unmountWhen
        unmountWhenMenu.addItem(makeUnmountWhenMenuItem(title: String(localized: "System starts sleeping"), unmountWhen: .systemStartsSleeping, selectedTriggers: selectedTriggers))
        unmountWhenMenu.addItem(makeUnmountWhenMenuItem(title: String(localized: "Display turned off"), unmountWhen: .screensStartedSleeping, selectedTriggers: selectedTriggers))
        unmountWhenMenu.addItem(makeUnmountWhenMenuItem(title: String(localized: "Screen is locked"), unmountWhen: .screenIsLocked, selectedTriggers: selectedTriggers))
        unmountWhenMenu.addItem(makeUnmountWhenMenuItem(title: String(localized: "Screensaver started"), unmountWhen: .screensaverStarted, selectedTriggers: selectedTriggers))
        unmountWhenMenu.addItem(NSMenuItem.separator())
        unmountWhenMenu.addItem(makeUnmountWhenMenuItem(title: String(localized: "Dock disconnected"), unmountWhen: .dockDisconnected, selectedTriggers: selectedTriggers))
        unmountWhenMenu.addItem(makeUnmountWhenMenuItem(title: String(localized: "External display disconnected"), unmountWhen: .externalDisplayDisconnected, selectedTriggers: selectedTriggers))

        return unmountWhenMenu
    }

    /// Creates an "Unmount when" menu entry that toggles one trigger in the selection.
    private func makeUnmountWhenMenuItem(
        title: String,
        unmountWhen: Preference.UnmountWhen,
        selectedTriggers: Set<Preference.UnmountWhen>
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: #selector(unmountWhenChanged(menuItem:)), keyEquivalent: "")
        item.target = self
        item.state = selectedTriggers.contains(unmountWhen) ? .on : .off
        item.representedObject = unmountWhen

        // The dock trigger can only fire once the user has remembered the dock it should watch for.
        if unmountWhen == .dockDisconnected, selectedTriggers.contains(unmountWhen), Preference.rememberedDocks.isEmpty {
            item.attributedTitle = makeHintTitle(title: title, hint: String(localized: "No dock remembered"), isWarning: true)
        }

        return item
    }

    /// Builds the submenu for dock detection and battery behavior.
    private func buildDockMenu() -> NSMenu {
        let dockMenu = NSMenu(title: String(localized: "Dock"))
        dockMenu.autoenablesItems = false

        let currentAdapter = PowerAdapterObserver.snapshotCurrentAdapter()
        if let currentAdapter {
            // Recording here means an adapter is offered in the menu even when no observer is running.
            Preference.recordKnownPowerAdapter(currentAdapter)
        }

        let connectedItem = NSMenuItem(title: connectedAdapterDescription(for: currentAdapter), action: nil, keyEquivalent: "")
        connectedItem.isEnabled = false
        dockMenu.addItem(connectedItem)

        addPowerAdapterSection(to: dockMenu, currentAdapter: currentAdapter)

        dockMenu.addItem(NSMenuItem.separator())

        let requireClosedLidItem = NSMenuItem(
            title: String(localized: "Only when the lid is closed"),
            action: #selector(requireClosedLidClicked(menuItem:)),
            keyEquivalent: ""
        )
        requireClosedLidItem.target = self
        requireClosedLidItem.state = Preference.requireClosedLidForDockTrigger ? .on : .off
        dockMenu.addItem(requireClosedLidItem)

        let sleepAfterDockDisconnectItem = NSMenuItem(
            title: String(localized: "Sleep after unmounting"),
            action: #selector(sleepAfterDockDisconnectClicked(menuItem:)),
            keyEquivalent: ""
        )
        sleepAfterDockDisconnectItem.target = self
        sleepAfterDockDisconnectItem.state = Preference.sleepAfterDockDisconnect ? .on : .off
        dockMenu.addItem(sleepAfterDockDisconnectItem)

        let keepUnmountedOnBatteryItem = NSMenuItem(
            title: String(localized: "Keep volumes unmounted on battery"),
            action: #selector(keepUnmountedOnBatteryClicked(menuItem:)),
            keyEquivalent: ""
        )
        keepUnmountedOnBatteryItem.target = self
        keepUnmountedOnBatteryItem.state = Preference.keepUnmountedOnBattery ? .on : .off
        dockMenu.addItem(keepUnmountedOnBatteryItem)

        return dockMenu
    }

    /// Adds one checkable row per known power adapter so docks can be selected while unplugged.
    private func addPowerAdapterSection(to dockMenu: NSMenu, currentAdapter: PowerAdapterIdentity?) {
        dockMenu.addItem(NSMenuItem.separator())
        dockMenu.addItem(NSMenuItem.sectionHeader(title: String(localized: "Power adapters")))

        let knownAdapters = Preference.knownPowerAdapters
        guard !knownAdapters.isEmpty else {
            let emptyItem = NSMenuItem(title: String(localized: "Connect your dock to remember it"), action: nil, keyEquivalent: "")
            emptyItem.isEnabled = false
            dockMenu.addItem(emptyItem)
            return
        }

        let rememberedDocks = Preference.rememberedDocks
        for adapter in knownAdapters {
            dockMenu.addItem(makeAdapterMenuItem(for: adapter, currentAdapter: currentAdapter, rememberedDocks: rememberedDocks))
        }

        guard !rememberedDocks.isEmpty else {
            return
        }

        let forgetAllItem = NSMenuItem(
            title: String(localized: "Forget all remembered docks"),
            action: #selector(forgetAllDocksClicked(menuItem:)),
            keyEquivalent: ""
        )
        forgetAllItem.target = self
        dockMenu.addItem(forgetAllItem)
    }

    /// Creates one adapter row whose checkmark means "treat this adapter as a dock".
    private func makeAdapterMenuItem(
        for adapter: PowerAdapterIdentity,
        currentAdapter: PowerAdapterIdentity?,
        rememberedDocks: [PowerAdapterIdentity]
    ) -> NSMenuItem {
        let item = NSMenuItem(title: adapter.displayName, action: #selector(dockAdapterToggled(menuItem:)), keyEquivalent: "")
        item.target = self
        item.state = adapter.isRemembered(in: rememberedDocks) ? .on : .off
        item.representedObject = adapter

        // An adapter macOS barely describes can never be recognized again, so it cannot act as a dock.
        guard adapter.isIdentifiable else {
            item.isEnabled = false
            item.attributedTitle = makeHintTitle(
                title: adapter.displayName,
                hint: String(localized: "Cannot be identified reliably"),
                isWarning: true
            )
            return item
        }

        if currentAdapter?.matches(adapter) == true {
            item.attributedTitle = makeHintTitle(title: adapter.displayName, hint: String(localized: "Connected"), isWarning: false)
        }

        return item
    }

    /// Returns the menu line describing the adapter the Mac is drawing power from right now.
    private func connectedAdapterDescription(for adapter: PowerAdapterIdentity?) -> String {
        guard let adapter else {
            return String(localized: "Not connected to power")
        }

        let connectedNow = "\(String(localized: "Connected now:")) \(adapter.displayName)"
        guard adapter.isLikelyAppleCharger else {
            return connectedNow
        }

        return "\(connectedNow) (\(String(localized: "Apple charger")))"
    }

    /// Builds a menu title with a smaller trailing hint, marked with a warning sign when needed.
    private func makeHintTitle(title: String, hint: String, isWarning: Bool) -> NSAttributedString {
        let attributedTitle = NSMutableAttributedString(
            string: title,
            attributes: [.font: NSFont.menuFont(ofSize: 0)]
        )
        let hintText = isWarning ? "  \u{26A0}\u{FE0E} \(hint)" : "  \(hint)"
        attributedTitle.append(
            NSAttributedString(
                string: hintText,
                attributes: [
                    .font: NSFont.menuFont(ofSize: NSFont.smallSystemFontSize),
                    .foregroundColor: NSColor.secondaryLabelColor
                ]
            )
        )
        return attributedTitle
    }

    /// Builds app-level actions such as Help and Quit.
    private func buildAppMenu() {
        addItem(NSMenuItem.separator())

        let helpItem = NSMenuItem(title: String(localized: "About Ejectify"), action: #selector(helpClicked), keyEquivalent: "")
        helpItem.target = self
        addItem(helpItem)

        let saveDiagnosticsReportItem = NSMenuItem(title: String(localized: "Generate Diagnostics Report…"), action: #selector(saveDiagnosticsReportClicked), keyEquivalent: "")
        saveDiagnosticsReportItem.target = self
        addItem(saveDiagnosticsReportItem)

        let checkForUpdatesItem = NSMenuItem(title: String(localized: "Check for Updates…"), action: #selector(checkForUpdatesClicked), keyEquivalent: "")
        checkForUpdatesItem.target = self
        addItem(checkForUpdatesItem)

        let quitItem = NSMenuItem(title: String(localized: "Quit Ejectify"), action: #selector(quitClicked), keyEquivalent: "")
        quitItem.target = self
        addItem(quitItem)
    }

    /// Unmounts all currently enabled volumes from the menu action.
    @objc private func unmountAllClicked(menuItem _: NSMenuItem) {
        MainActor.assumeIsolated {
            AppDelegate.shared.performManualUnmountAll()
        }
    }

    /// Mounts every volume waiting to be remounted, regardless of the battery preference.
    @objc private func mountAllClicked(menuItem _: NSMenuItem) {
        MainActor.assumeIsolated {
            AppDelegate.shared.activityController?.performManualMountPass()
        }
    }

    /// Unmounts every enabled volume and puts the Mac to sleep.
    @objc private func unmountAllAndSleepClicked(menuItem _: NSMenuItem) {
        MainActor.assumeIsolated {
            AppDelegate.shared.activityController?.performManualUnmountAndSleep()
        }
    }

    /// Toggles automatic handling for a specific volume row.
    @objc private func volumeClicked(menuItem: NSMenuItem) {
        guard let volume = menuItem.representedObject as? Volume else {
            return
        }
        let newEnabledValue = toggledValue(for: menuItem.state)
        volume.enabled = newEnabledValue

        Log.volumeOperations.log("Volume auto-unmount toggled; \(volume.logLabel); enabled=\(newEnabledValue)")
        updateMenu()
    }

    /// Toggles launch-at-login preference from the menu.
    @objc private func launchAtLoginClicked(menuItem: NSMenuItem) {
        Preference.launchAtLogin = toggledValue(for: menuItem.state)
        updateMenu()
    }

    /// Toggles privileged helper registration for elevated mount, unmount, and eject attempts.
    @MainActor
    @objc private func elevatedPermissionsClicked(menuItem: NSMenuItem) {
        let shouldEnable = toggledValue(for: menuItem.state)
        let operationRouter = VolumeOperationRouter.shared
        let didSucceed: Bool

        if shouldEnable {
            didSucceed = operationRouter.requestPrivilegedExecutionMode()
            guard !didSucceed else {
                updateMenu()
                return
            }

            showPermissionAlert(
                messageText: String(localized: "Could not enable elevated permissions."),
                informativeText: String(localized: "Check System Settings if Ejectify is enabled.")
            )
            updateMenu()
            return
        }

        didSucceed = operationRouter.disablePrivilegedExecutionMode()
        guard didSucceed else {
            showPermissionAlert(
                messageText: String(localized: "Could not disable elevated permissions.")
            )
            updateMenu()
            return
        }

        updateMenu()
    }

    /// Toggles one trigger in the unmount trigger selection, keeping at least one trigger enabled.
    @objc private func unmountWhenChanged(menuItem: NSMenuItem) {
        guard let unmountWhen = menuItem.representedObject as? Preference.UnmountWhen else {
            return
        }

        var selectedTriggers = Preference.unmountWhen
        selectedTriggers.formSymmetricDifference([unmountWhen])

        guard !selectedTriggers.isEmpty else {
            Log.preferences.warning("Unmount trigger change rejected; reason=at least one trigger must stay enabled")
            NSSound.beep()
            updateMenu()
            return
        }

        Preference.unmountWhen = selectedTriggers
        updateMenu()
    }

    /// Toggles whether one power adapter is treated as a dock.
    @MainActor
    @objc private func dockAdapterToggled(menuItem: NSMenuItem) {
        guard let adapter = menuItem.representedObject as? PowerAdapterIdentity, adapter.isIdentifiable else {
            return
        }

        var rememberedDocks = Preference.rememberedDocks

        guard !adapter.isRemembered(in: rememberedDocks) else {
            rememberedDocks.removeAll { $0.matches(adapter) }
            Preference.rememberedDocks = rememberedDocks
            Log.preferences.log("Remembered dock forgotten; adapter=\(adapter.logDescription)")
            updateMenu()
            return
        }

        guard !adapter.isLikelyAppleCharger || confirmRememberingAppleCharger() else {
            Log.preferences.info("Remembering adapter cancelled; reason=apple charger confirmation declined")
            return
        }

        rememberedDocks.append(adapter)
        Preference.rememberedDocks = rememberedDocks
        Log.preferences.log("Remembered dock added; adapter=\(adapter.logDescription)")
        updateMenu()
    }

    /// Asks for confirmation before treating an Apple charger as a dock.
    @MainActor
    private func confirmRememberingAppleCharger() -> Bool {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = String(localized: "This looks like an Apple charger.")
        alert.informativeText = String(localized: "Remembering it as a dock means unplugging your charger will unmount your volumes. Remember anyway?")
        // Cancel is added first so it stays the default button.
        alert.addButton(withTitle: String(localized: "Cancel"))
        alert.addButton(withTitle: String(localized: "Remember anyway"))
        return alert.runModal() == .alertSecondButtonReturn
    }

    /// Forgets every remembered dock.
    @objc private func forgetAllDocksClicked(menuItem _: NSMenuItem) {
        guard !Preference.rememberedDocks.isEmpty else {
            return
        }

        Preference.rememberedDocks = []
        Log.preferences.log("All remembered docks forgotten")
        updateMenu()
    }

    /// Toggles whether the dock trigger only fires while the lid is closed.
    @objc private func requireClosedLidClicked(menuItem: NSMenuItem) {
        Preference.requireClosedLidForDockTrigger = toggledValue(for: menuItem.state)
        updateMenu()
    }

    /// Toggles whether the Mac sleeps once a dock or display disconnect has unmounted every volume.
    @objc private func sleepAfterDockDisconnectClicked(menuItem: NSMenuItem) {
        Preference.sleepAfterDockDisconnect = toggledValue(for: menuItem.state)
        updateMenu()
    }

    /// Toggles whether automatic remount passes are skipped while running on battery.
    @objc private func keepUnmountedOnBatteryClicked(menuItem: NSMenuItem) {
        Preference.keepUnmountedOnBattery = toggledValue(for: menuItem.state)
        updateMenu()
    }

    /// Toggles force-unmount preference from the menu.
    @objc private func forceUnmountClicked(menuItem: NSMenuItem) {
        Preference.forceUnmount = toggledValue(for: menuItem.state)
        updateMenu()
    }

    /// Toggles Ejectify-managed encrypted-volume password fallback from the menu.
    @objc private func unlockVolumesWhenNeededClicked(menuItem: NSMenuItem) {
        Preference.unlockVolumesWhenNeeded = toggledValue(for: menuItem.state)
        updateMenu()
    }

    /// Toggles whole-disk eject mode from the menu.
    @objc private func ejectInsteadOfUnmountClicked(menuItem: NSMenuItem) {
        Preference.ejectInsteadOfUnmount = toggledValue(for: menuItem.state)
        updateMenu()
    }

    /// Toggles muting of system "Disk Not Ejected Properly" notifications.
    @MainActor
    @objc private func muteNotificationsClicked(menuItem: NSMenuItem) {
        let shouldMute = toggledValue(for: menuItem.state)
        VolumeOperationRouter.shared.setEjectNotificationsMuted(shouldMute) { [weak self] success, details in
            guard let self else {
                return
            }

            guard success else {
                showPermissionAlert(
                    messageText: shouldMute ? String(localized: "Could not mute notifications") : String(localized: "Could not unmute notifications"),
                    informativeText: details
                )
                updateMenu()
                return
            }

            showRestartRequiredAlert(shouldMute: shouldMute)
            updateMenu()
        }
    }

    /// Opens the window for changing global keyboard shortcuts.
    @MainActor
    @objc private func shortcutSettingsClicked() {
        AppDelegate.shared.showShortcutSettings()
    }

    /// Opens the Ejectify Help Center website.
    @objc private func helpClicked() {
        NSWorkspace.shared.open(helpURL)
    }

    /// Starts the diagnostics report save flow from the status menu.
    @MainActor
    @objc private func saveDiagnosticsReportClicked() {
        AppDelegate.shared.saveDiagnosticsReport()
    }

    /// Starts a manual Sparkle update check from the status menu.
    @MainActor
    @objc private func checkForUpdatesClicked() {
        AppDelegate.shared.checkForUpdates()
    }

    /// Terminates the app from the menu action.
    @MainActor
    @objc private func quitClicked() {
        NSApplication.shared.terminate(nil)
    }

    /// Shows a user-friendly alert for elevated permission registration failures.
    @MainActor
    private func showPermissionAlert(messageText: String, informativeText: String? = nil) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = messageText
        alert.informativeText = informativeText ?? ""
        alert.runModal()
    }

    /// Shows a restart-required alert and optionally triggers immediate restart.
    @MainActor
    private func showRestartRequiredAlert(shouldMute: Bool) {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = String(localized: "Restart required")
        alert.informativeText = shouldMute
            ? String(localized: "Please restart your Mac to apply the change and mute notifications.")
            : String(localized: "Please restart your Mac to apply the change and unmute notifications.")
        alert.addButton(withTitle: String(localized: "Restart"))
        alert.addButton(withTitle: String(localized: "Later"))

        let result = alert.runModal()
        guard result == .alertFirstButtonReturn else {
            return
        }

        requestSystemRestart()
    }

    /// Requests a soft restart through the shared system power action requester.
    @MainActor
    private func requestSystemRestart() {
        SystemPowerActionRequester.requestRestart()
    }
}

extension StatusBarMenu: NSMenuDelegate {

    /// Rebuilds the menu before it is shown so volume and power adapter state is always current.
    func menuNeedsUpdate(_ menu: NSMenu) {
        guard menu === self else {
            return
        }

        volumes = Volume.mountedVolumes()
        updateMenu()
    }
}
