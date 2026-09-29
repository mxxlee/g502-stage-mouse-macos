import AppKit
import ApplicationServices
import CryptoKit
import IOKit.hid
import ServiceManagement

enum Action: String, CaseIterable {
    case none
    case historyBack, historyForward
    case missionControl, appExpose
    case nextApp, previousApp
    case leftSpace, rightSpace
    case showDesktop

    var title: String {
        switch self {
        case .none: return L10n.string("action.none")
        case .historyBack: return L10n.string("action.historyBack")
        case .historyForward: return L10n.string("action.historyForward")
        case .missionControl: return L10n.string("action.missionControl")
        case .appExpose: return L10n.string("action.appExpose")
        case .nextApp: return L10n.string("action.nextApp")
        case .previousApp: return L10n.string("action.previousApp")
        case .leftSpace: return L10n.string("action.leftSpace")
        case .rightSpace: return L10n.string("action.rightSpace")
        case .showDesktop: return L10n.string("action.showDesktop")
        }
    }
}

private struct LocalUpdateManifest: Decodable {
    let version: String
    let archive: String
    let sha256: String
    let notes: String?
}

private enum ButtonEventSource: String {
    case hidppSpy = "HID++ 0x8110"
    case ioHID = "IOHID"
    case cgEvent = "CGEvent"
}

private enum WakeRecoveryReason {
    case wake
    case session

    var reconnectKey: String {
        switch self {
        case .wake: return "diagnostic.wakeReconnect"
        case .session: return "diagnostic.sessionReconnect"
        }
    }

    var channelNotReadyKey: String {
        switch self {
        case .wake: return "diagnostic.channelNotReadyAfterWake"
        case .session: return "diagnostic.channelNotReadyAfterSession"
        }
    }
}

private enum ButtonSpyRetryReason {
    case deviceReturned
    case unexpectedStop
    case startupStop
    case initializationFailed

    var diagnosticKey: String {
        switch self {
        case .deviceReturned: return "diagnostic.retry.deviceReturned"
        case .unexpectedStop: return "diagnostic.retry.unexpectedStop"
        case .startupStop: return "diagnostic.retry.startupStop"
        case .initializationFailed: return "diagnostic.retry.initializationFailed"
        }
    }
}

private struct PhysicalButtonEvent {
    let button: Int
    let pressed: Bool
    let source: ButtonEventSource
    let timestamp: TimeInterval
    let physicalIndex: Int?
}

final class LogitechHIDMonitor {
    private let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
    private let supportedProductIDs = Set([0xC53A, 0xC547, 0xC098])
    private var matchedDevices: [CFHashCode: String] = [:]
    var onButton: ((Int, Bool, TimeInterval) -> Void)?
    var onDevice: ((String?, Bool) -> Void)?

    func start() {
        let matches: [[String: Any]] = supportedProductIDs.map {
            [
                kIOHIDVendorIDKey as String: 0x046D,
                kIOHIDProductIDKey as String: $0
            ]
        }
        IOHIDManagerSetDeviceMatchingMultiple(manager, matches as CFArray)
        let buttonMatches: [[String: Any]] = (3...9).map {
            [
                kIOHIDElementUsagePageKey as String: kHIDPage_Button,
                kIOHIDElementUsageKey as String: $0
            ]
        }
        IOHIDManagerSetInputValueMatchingMultiple(manager, buttonMatches as CFArray)
        let context = Unmanaged.passUnretained(self).toOpaque()

        IOHIDManagerRegisterDeviceMatchingCallback(manager, { context, _, _, device in
            guard let context else { return }
            let monitor = Unmanaged<LogitechHIDMonitor>.fromOpaque(context).takeUnretainedValue()
            let product = IOHIDDeviceGetProperty(device, kIOHIDProductKey as CFString) as? String
            let pid = IOHIDDeviceGetProperty(device, kIOHIDProductIDKey as CFString) as? Int
            guard let pid, monitor.supportedProductIDs.contains(pid) else { return }
            let displayName: String?
            if pid == 0xC53A {
                displayName = L10n.string("device.powerplayReceiver")
            } else if pid == 0xC547 {
                displayName = L10n.string("device.lightspeedReceiver")
            } else {
                displayName = product == "USB Receiver" ? L10n.string("device.logitechReceiver") : product
            }
            let key = CFHash(device)
            monitor.matchedDevices[key] = displayName
            DispatchQueue.main.async { monitor.onDevice?(displayName, true) }
        }, context)

        IOHIDManagerRegisterDeviceRemovalCallback(manager, { context, _, _, device in
            guard let context else { return }
            let monitor = Unmanaged<LogitechHIDMonitor>.fromOpaque(context).takeUnretainedValue()
            monitor.matchedDevices.removeValue(forKey: CFHash(device))
            if monitor.matchedDevices.isEmpty {
                DispatchQueue.main.async { monitor.onDevice?(nil, false) }
            }
        }, context)

        IOHIDManagerRegisterInputValueCallback(manager, { context, _, _, value in
            guard let context else { return }
            let monitor = Unmanaged<LogitechHIDMonitor>.fromOpaque(context).takeUnretainedValue()
            let element = IOHIDValueGetElement(value)
            let device = IOHIDElementGetDevice(element)
            guard let pid = IOHIDDeviceGetProperty(
                    device,
                    kIOHIDProductIDKey as CFString
                  ) as? Int,
                  monitor.supportedProductIDs.contains(pid) else {
                return
            }
            let page = IOHIDElementGetUsagePage(element)
            let usage = Int(IOHIDElementGetUsage(element))
            guard page == UInt32(kHIDPage_Button),
                  (3...9).contains(usage) else { return }
            let pressed = IOHIDValueGetIntegerValue(value) != 0
            let timestamp = ProcessInfo.processInfo.systemUptime
            DispatchQueue.main.async { monitor.onButton?(usage, pressed, timestamp) }
        }, context)

        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
        IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private static let syntheticMouseEventMarker: Int64 = 0x475035303258
    private static let hoverRecoveryPreferenceKey = "g502x.hoverRecoveryEnabled"
    private static let hoverRecoveryKeyboardQuietPeriod: TimeInterval = 0.4
    private static let freeScrollPreferenceKey = "g502x.freeScrollEnabled"
    private static let freeScrollActivationDistance: CGFloat = 3
    private static let freeScrollMultiplier: CGFloat = 2
    private var statusItem: NSStatusItem!
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var hoverEventTap: CFMachPort?
    private var hoverRunLoopSource: CFRunLoopSource?
    private var hoverRecoveryEnabled = false
    private var hoverRecoveryWorkItem: DispatchWorkItem?
    private var hoverRecoveryBurstGeneration = 0
    private var freeScrollEnabled = false
    private var freeScrollTracking = false
    private var freeScrollDidMove = false
    private var freeScrollDistance: CGFloat = 0
    private var freeScrollDisplacementX: CGFloat = 0
    private var freeScrollDisplacementY: CGFloat = 0
    private var freeScrollPendingX: CGFloat = 0
    private var freeScrollPendingY: CGFloat = 0
    private var freeScrollFlushWorkItem: DispatchWorkItem?
    private var freeScrollGeneration = 0
    private var mappings: [Int: Action] = [:]
    private var detectionMode = false
    private var detectedButtons = Set<Int>()
    private let buttons = Array(3...9)
    private var visualConfig: VisualConfigWindowController?
    private let hidMonitor = LogitechHIDMonitor()
    private var lastAcceptedButtonEvents: [Int: PhysicalButtonEvent] = [:]
    private let crossSourceDeduplicationWindow: TimeInterval = 0.045
    private var syntheticNavigationEventDeadline: TimeInterval = 0
    private var connectedDevice: (name: String?, connected: Bool) = (nil, false)
    private var buttonSpyProcess: Process?
    private var buttonSpyProcessGeneration = 0
    private var buttonSpyLifecycleToken = 0
    private var buttonSpyStartInProgress = false
    private var buttonSpyPaused = false
    private let buttonSpyQueue = DispatchQueue(label: "fr.remy.g502stagemouse.button-spy")
    private var buttonSpyBuffer = ""
    private var buttonSpyBufferGeneration = 0
    private var buttonSpyReady = false
    private var buttonSpyDiagnostic = ""
    private var expectedButtonSpyStops = Set<Int>()
    private var reconnectWorkItem: DispatchWorkItem?
    private var reconnectAttempt = 0
    private let reconnectDelays: [TimeInterval] = [0.5, 1, 2, 5, 15, 60]
    private var reconnectStatus: String?
    private var wakeRecoveryGeneration = 0
    private var wakeRecoveryWorkItem: DispatchWorkItem?
    private let wakeRecoveryDelays: [TimeInterval] = [0.75, 2, 5]
    private var systemSleeping = false
    private var isTerminating = false
    private var accessibilityWarningShown = false
    private var physicalIndexToG: [Int: Int] = [
        2: 3,  // clic molette
        3: 4,  // arrière
        5: 5,  // avant
        4: 6,  // DPI shift
        10: 7, // DPI -
        9: 8,  // DPI +
        8: 9   // profil
    ]
    private var calibrationTarget: Int?
    private var calibrationAlert: NSAlert?
    private var updateTimer: Timer?
    private var updateCheckInProgress = false
    private var deferredUpdateVersion: String?
    private var batteryPercent: Int?
    private var batteryEstimated = false
    private var batteryCharging = false
    private var batteryStatus: String?
    private var batteryAvailable = false
    private var dpiOperationInProgress = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        loadMappings()
        migrateNavigationMappings()
        loadPhysicalIndexMappings()
        disableLegacyHoverActivation()
        loadHoverRecoverySetting()
        loadFreeScrollSetting()
        makeMenu()
        observePowerState()
        startHIDMonitor()
        startButtonSpy()
        requestInputMonitoring()
        requestAccessibility()
        startEventTap()
        startHoverEventTap()
        startUpdateMonitoring()
    }

    private func observePowerState() {
        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(
            self,
            selector: #selector(systemWillSleep(_:)),
            name: NSWorkspace.willSleepNotification,
            object: nil
        )
        center.addObserver(
            self,
            selector: #selector(systemDidWake(_:)),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )
        center.addObserver(
            self,
            selector: #selector(sessionDidResignActive(_:)),
            name: NSWorkspace.sessionDidResignActiveNotification,
            object: nil
        )
        center.addObserver(
            self,
            selector: #selector(sessionDidBecomeActive(_:)),
            name: NSWorkspace.sessionDidBecomeActiveNotification,
            object: nil
        )
    }

    private func loadMappings() {
        let defaults: [Int: Action] = [
            3: .missionControl,
            4: .historyBack,
            5: .historyForward,
            6: .appExpose,
            7: .leftSpace,
            8: .rightSpace,
            9: .showDesktop
        ]
        for button in buttons {
            let key = "g502x.g\(button)"
            mappings[button] = UserDefaults.standard.string(forKey: key).flatMap(Action.init(rawValue:))
                ?? defaults[button] ?? Action.none
        }
    }

    private func migrateNavigationMappings() {
        let migrationKey = "g502x.navigationButtons.v15"
        guard !UserDefaults.standard.bool(forKey: migrationKey) else { return }
        mappings[4] = .historyBack
        mappings[5] = .historyForward
        UserDefaults.standard.set(Action.historyBack.rawValue, forKey: "g502x.g4")
        UserDefaults.standard.set(Action.historyForward.rawValue, forKey: "g502x.g5")
        UserDefaults.standard.set(true, forKey: migrationKey)
    }

    private func loadPhysicalIndexMappings() {
        for button in buttons {
            let key = "g502x.physicalIndex.g\(button)"
            guard UserDefaults.standard.object(forKey: key) != nil else { continue }
            let index = UserDefaults.standard.integer(forKey: key)
            let stale = physicalIndexToG.compactMap { entry in
                entry.key == index || entry.value == button ? entry.key : nil
            }
            stale.forEach { physicalIndexToG.removeValue(forKey: $0) }
            physicalIndexToG[index] = button
        }
    }

    // Les versions précédentes pouvaient mettre au premier plan une fenêtre au
    // simple survol. Ce comportement est retiré : une ancienne préférence ne
    // doit jamais le réactiver après une mise à jour.
    private func disableLegacyHoverActivation() {
        let key = "g502x.activateWindowOnHover"
        UserDefaults.standard.set(false, forKey: key)
    }

    // Ce garde-fou ne change jamais l'application active et ne simule aucun
    // clic. Il envoie seulement un micro-mouvement du pointeur afin de forcer
    // WindowServer à réévaluer le survol quand son rendu se fige après un clic.
    private func loadHoverRecoverySetting() {
        hoverRecoveryEnabled = UserDefaults.standard.bool(forKey: Self.hoverRecoveryPreferenceKey)
    }

    private func loadFreeScrollSetting() {
        freeScrollEnabled = UserDefaults.standard.bool(forKey: Self.freeScrollPreferenceKey)
    }

    private func makeMenu() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = NSImage(
            systemSymbolName: "computermouse.fill",
            accessibilityDescription: L10n.string("visual.window.title")
        )
        rebuildMenu()
    }

    private func rebuildMenu() {
        let menu = NSMenu()
        let state = systemSleeping
            ? L10n.string("status.sleeping")
            : buttonSpyReady && !AXIsProcessTrusted()
            ? L10n.string("status.buttonsNeedAccessibility")
            : buttonSpyReady
            ? L10n.string("status.powerplayButtonsActive")
            : reconnectStatus != nil
            ? reconnectStatus!
            : connectedDevice.connected
            ? L10n.string("status.initializingHID")
            : (!AXIsProcessTrusted()
                ? L10n.string("status.permissionRequired")
                : L10n.string("status.receiverMissing"))
        let stateItem = NSMenuItem(title: L10n.format("menu.status", state), action: nil, keyEquivalent: "")
        stateItem.isEnabled = false
        menu.addItem(stateItem)

        let versionItem = NSMenuItem(title: L10n.format("menu.version", "14.7"), action: nil, keyEquivalent: "")
        versionItem.isEnabled = false
        menu.addItem(versionItem)

        let batteryItem = NSMenuItem(title: batteryDisplayText(), action: nil, keyEquivalent: "")
        batteryItem.isEnabled = false
        menu.addItem(batteryItem)
        menu.addItem(.separator())

        let detection = NSMenuItem(
            title: L10n.string(detectionMode ? "menu.identify.stop" : "menu.identify.start"),
            action: #selector(toggleDetection),
            keyEquivalent: ""
        )
        detection.target = self
        menu.addItem(detection)
        let visual = NSMenuItem(title: L10n.string("menu.visualConfig"), action: #selector(openVisualConfig), keyEquivalent: ",")
        visual.target = self
        menu.addItem(visual)

        let hoverRecovery = NSMenuItem(
            title: L10n.string("menu.hoverRecovery"),
            action: #selector(toggleHoverRecovery),
            keyEquivalent: ""
        )
        hoverRecovery.target = self
        hoverRecovery.state = hoverRecoveryEnabled ? .on : .off
        menu.addItem(hoverRecovery)

        let testHoverRecovery = NSMenuItem(
            title: L10n.string("menu.testHoverRecovery"),
            action: #selector(testHoverRecoveryNow),
            keyEquivalent: ""
        )
        testHoverRecovery.target = self
        testHoverRecovery.isEnabled = !systemSleeping && AXIsProcessTrusted()
        menu.addItem(testHoverRecovery)

        let freeScroll = NSMenuItem(
            title: L10n.string("menu.freeScroll"),
            action: #selector(toggleFreeScroll),
            keyEquivalent: ""
        )
        freeScroll.target = self
        freeScroll.state = freeScrollEnabled ? .on : .off
        freeScroll.isEnabled = AXIsProcessTrusted() && !systemSleeping
        menu.addItem(freeScroll)

        for button in buttons {
            let label = L10n.format(
                detectedButtons.contains(button) ? "button.menu.detected" : "button.menu.generic",
                button
            )
            let item = NSMenuItem(title: label, action: nil, keyEquivalent: "")
            let submenu = NSMenu()
            for action in Action.allCases {
                let actionItem = NSMenuItem(title: action.title, action: #selector(selectAction(_:)), keyEquivalent: "")
                actionItem.target = self
                actionItem.representedObject = ["button": button, "action": action.rawValue] as [String : Any]
                actionItem.state = mappings[button] == action ? .on : .off
                submenu.addItem(actionItem)
            }
            item.submenu = submenu
            menu.addItem(item)
        }

        menu.addItem(.separator())
        let login = NSMenuItem(title: L10n.string("menu.launchAtLogin"), action: #selector(toggleLogin), keyEquivalent: "")
        login.target = self
        if #available(macOS 13.0, *) {
            login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        }
        menu.addItem(login)

        let permissions = NSMenuItem(title: L10n.string("menu.openAccessibilitySettings"), action: #selector(openAccessibility), keyEquivalent: "")
        permissions.target = self
        permissions.state = AXIsProcessTrusted() ? .on : .off
        menu.addItem(permissions)

        let testAction = NSMenuItem(title: L10n.string("menu.testMissionControl"), action: #selector(testMissionControl), keyEquivalent: "")
        testAction.target = self
        menu.addItem(testAction)

        let inputPermission = NSMenuItem(title: L10n.string("menu.openInputMonitoringSettings"), action: #selector(openInputMonitoring), keyEquivalent: "")
        inputPermission.target = self
        menu.addItem(inputPermission)

        let diagnostic = NSMenuItem(title: L10n.string("menu.hidDiagnostic"), action: #selector(showHIDDiagnostic), keyEquivalent: "")
        diagnostic.target = self
        menu.addItem(diagnostic)

        let restore = NSMenuItem(
            title: L10n.string("menu.restoreOriginalProfile"),
            action: #selector(restoreOriginalProfile),
            keyEquivalent: ""
        )
        restore.target = self
        menu.addItem(restore)

        let restart = NSMenuItem(title: L10n.string("menu.restartDetection"), action: #selector(restartTap), keyEquivalent: "")
        restart.target = self
        menu.addItem(restart)

        let update = NSMenuItem(title: L10n.string("menu.checkForUpdates"), action: #selector(checkForUpdatesManually), keyEquivalent: "")
        update.target = self
        menu.addItem(update)
        let languageItem = NSMenuItem(
            title: L10n.string("language.menu.title"),
            action: nil,
            keyEquivalent: ""
        )
        let languageMenu = NSMenu()
        for language in AppLanguage.allCases {
            let item = NSMenuItem(
                title: L10n.string(language.titleKey),
                action: #selector(selectLanguage(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = language.rawValue
            item.state = language == L10n.selectedLanguage ? .on : .off
            languageMenu.addItem(item)
        }
        languageItem.submenu = languageMenu
        menu.addItem(languageItem)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: L10n.string("menu.quit"), action: #selector(quitApp), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
        statusItem.menu = menu
    }

    @objc private func selectLanguage(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? String,
              let language = AppLanguage(rawValue: rawValue),
              language != L10n.selectedLanguage else { return }
        L10n.select(language)
        relaunchForLanguageChange()
    }

    private func relaunchForLanguageChange() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["-n", Bundle.main.bundlePath]
        LanguageRelaunch.run(
            process: process,
            terminate: { NSApp.terminate(nil) },
            onFailure: {
                rebuildMenu()
                let alert = NSAlert()
                alert.messageText = L10n.string("language.relaunch.title")
                alert.informativeText = L10n.string("language.relaunch.message")
                alert.addButton(withTitle: L10n.string("common.close"))
                alert.runModal()
            }
        )
    }

    private func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    private func requestInputMonitoring() {
        if !CGPreflightListenEventAccess() {
            _ = CGRequestListenEventAccess()
        }
    }

    private func startHIDMonitor() {
        hidMonitor.onDevice = { [weak self] name, connected in
            guard let self else { return }
            self.connectedDevice = (name, connected)
            self.visualConfig?.updateDevice(name: name, connected: connected)
            if connected {
                self.appendButtonSpyDiagnostic(L10n.format(
                    "diagnostic.deviceReturned",
                    name ?? L10n.string("device.g502X")
                ))
                self.reconnectAttempt = 0
                if !self.buttonSpyReady,
                   self.buttonSpyProcess?.isRunning != true,
                   !self.buttonSpyStartInProgress {
                    self.scheduleButtonSpyRestart(reason: .deviceReturned, resetBackoff: true)
                }
            } else {
                self.batteryAvailable = false
                self.batteryPercent = nil
                self.batteryStatus = nil
                self.appendButtonSpyDiagnostic(L10n.string("diagnostic.deviceDisconnected"))
                self.stopButtonSpyAndRestoreMode(waitUntilExit: false)
            }
            self.refreshBatteryUI()
            self.rebuildMenu()
        }
        hidMonitor.onButton = { [weak self] button, pressed, timestamp in
            guard let self else { return }
            if !self.buttonSpyReady,
               self.buttonSpyProcess?.isRunning != true,
               !self.buttonSpyStartInProgress {
                self.reconnectAttempt = 0
                self.reconnectWorkItem?.cancel()
                self.reconnectWorkItem = nil
                self.startButtonSpy()
            }
            self.receiveButtonEvent(PhysicalButtonEvent(
                button: button,
                pressed: pressed,
                source: .ioHID,
                timestamp: timestamp,
                physicalIndex: nil
            ))
        }
        hidMonitor.start()
    }

    @discardableResult
    private func receiveButtonEvent(_ event: PhysicalButtonEvent) -> Bool {
        guard buttons.contains(event.button),
              !systemSleeping,
              !isTerminating else {
            return false
        }

        // Le flux 0x8110 reste prioritaire quand il est actif. IOHID et CGEvent
        // ne sont que des secours : les laisser passer en parallèle peut doubler
        // un raccourci après la reconnexion du receiver.
        if event.source != .hidppSpy, buttonSpyReady {
            return false
        }

        // Pendant l'association, seule la source qui connaît l'index physique peut
        // valider la calibration. Une notification normalisée ne doit pas masquer
        // l'événement 0x8110 qui arrive quelques millisecondes plus tard.
        if calibrationTarget != nil, event.physicalIndex == nil {
            return false
        }

        if let previous = lastAcceptedButtonEvents[event.button],
           previous.pressed == event.pressed,
           previous.source != event.source,
           abs(event.timestamp - previous.timestamp) <= crossSourceDeduplicationWindow {
            return false
        }
        lastAcceptedButtonEvents[event.button] = event

        guard event.pressed else { return true }

        if let target = calibrationTarget,
           let physicalIndex = event.physicalIndex,
           physicalIndex >= 2 {
            completeCalibration(index: physicalIndex, button: target)
            return true
        }

        detectedButtons.insert(event.button)
        statusItem.button?.title = L10n.format("status.buttonPressed", event.button)
        visualConfig?.highlight(button: event.button)
        rebuildMenu()

        // En mode défilement libre, CGEvent décide au relâchement si G3 était
        // un clic court ou un glisser. Le flux HID++ ne doit pas déclencher
        // l'action immédiatement au début du maintien.
        if freeScrollEnabled && event.button == 3 && eventTap != nil {
            return true
        }

        guard !detectionMode,
              let action = mappings[event.button],
              action != .none else {
            return true
        }
        perform(action)
        return true
    }

    private func startEventTap() {
        guard AXIsProcessTrusted() else {
            rebuildMenu()
            return
        }
        let mask = (1 << CGEventType.otherMouseDown.rawValue)
            | (1 << CGEventType.otherMouseUp.rawValue)
            | (1 << CGEventType.otherMouseDragged.rawValue)
        let callback: CGEventTapCallBack = { _, type, event, userInfo in
            guard let userInfo else { return Unmanaged.passUnretained(event) }
            let app = Unmanaged<AppDelegate>.fromOpaque(userInfo).takeUnretainedValue()
            if event.getIntegerValueField(.eventSourceUserData)
                == AppDelegate.syntheticMouseEventMarker {
                return Unmanaged.passUnretained(event)
            }
            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                app.resetFreeScrollTracking()
                if let eventTap = app.eventTap {
                    CGEvent.tapEnable(tap: eventTap, enable: true)
                }
                return Unmanaged.passUnretained(event)
            }
            if type == .otherMouseDragged, app.freeScrollTracking {
                return app.handleFreeScrollDrag(event)
            }
            if type == .otherMouseDown || type == .otherMouseUp {
                // CGEvent numérote les boutons à partir de zéro ; HID/G HUB utilise G1, G2…
                let button = Int(event.getIntegerValueField(.mouseEventButtonNumber)) + 1
                if button == 3, app.freeScrollEnabled {
                    return app.handleFreeScrollButton(
                        pressed: type == .otherMouseDown,
                        event: event
                    )
                }
                return app.handleCGEvent(
                    button: button,
                    pressed: type == .otherMouseDown,
                    event: event
                )
            }
            return Unmanaged.passUnretained(event)
        }
        eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(mask),
            callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        )
        guard let eventTap else {
            rebuildMenu()
            return
        }
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: eventTap, enable: true)
        rebuildMenu()
    }

    private func stopEventTap() {
        resetFreeScrollTracking()
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
            CFMachPortInvalidate(eventTap)
        }
        eventTap = nil
        runLoopSource = nil
    }

    // Le stabilisateur observe uniquement les fins de clic dans un tap passif.
    // Un listen-only tap ne peut ni modifier ni avaler les clics primaires.
    private func startHoverEventTap() {
        guard hoverRecoveryEnabled, AXIsProcessTrusted() else { return }
        let mask = (1 << CGEventType.leftMouseUp.rawValue)
            | (1 << CGEventType.rightMouseUp.rawValue)
        let callback: CGEventTapCallBack = { _, type, event, userInfo in
            guard let userInfo else { return Unmanaged.passUnretained(event) }
            let app = Unmanaged<AppDelegate>.fromOpaque(userInfo).takeUnretainedValue()
            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                if let hoverEventTap = app.hoverEventTap {
                    CGEvent.tapEnable(tap: hoverEventTap, enable: true)
                }
                return Unmanaged.passUnretained(event)
            }
            if type == .leftMouseUp || type == .rightMouseUp {
                DispatchQueue.main.async {
                    app.scheduleHoverRecoveryAfterClick()
                }
            }
            return Unmanaged.passUnretained(event)
        }
        hoverEventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .tailAppendEventTap,
            options: .listenOnly,
            eventsOfInterest: CGEventMask(mask),
            callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        )
        guard let hoverEventTap else { return }
        hoverRunLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, hoverEventTap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), hoverRunLoopSource, .commonModes)
        CGEvent.tapEnable(tap: hoverEventTap, enable: true)
    }

    private func stopHoverEventTap() {
        if let hoverRunLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), hoverRunLoopSource, .commonModes)
        }
        if let hoverEventTap {
            CGEvent.tapEnable(tap: hoverEventTap, enable: false)
            CFMachPortInvalidate(hoverEventTap)
        }
        hoverEventTap = nil
        hoverRunLoopSource = nil
    }

    @objc private func toggleHoverRecovery() {
        hoverRecoveryEnabled.toggle()
        UserDefaults.standard.set(hoverRecoveryEnabled, forKey: Self.hoverRecoveryPreferenceKey)
        if hoverRecoveryEnabled {
            startHoverEventTap()
            scheduleHoverRecovery(delay: 0.05)
        } else {
            stopHoverEventTap()
            hoverRecoveryWorkItem?.cancel()
            hoverRecoveryWorkItem = nil
            hoverRecoveryBurstGeneration += 1
        }
        rebuildMenu()
    }

    @objc private func testHoverRecoveryNow() {
        performHoverRecoveryPulse(requireEnabled: false, protectTyping: false)
    }

    @objc private func toggleFreeScroll() {
        freeScrollEnabled.toggle()
        UserDefaults.standard.set(freeScrollEnabled, forKey: Self.freeScrollPreferenceKey)
        if !freeScrollEnabled {
            resetFreeScrollTracking()
        }
        rebuildMenu()
    }

    private func scheduleHoverRecoveryAfterClick() {
        guard hoverRecoveryEnabled else { return }
        // Le faux état d'occlusion apparaît après la fin du clic. Un bref délai
        // évite d'interférer avec le traitement normal de l'application visée.
        scheduleHoverRecovery(delay: 0.08)
    }

    private func scheduleHoverRecovery(delay: TimeInterval) {
        hoverRecoveryWorkItem?.cancel()
        hoverRecoveryBurstGeneration += 1
        let work = DispatchWorkItem { [weak self] in
            self?.performHoverRecoveryPulse()
        }
        hoverRecoveryWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func performHoverRecoveryPulse(
        requireEnabled: Bool = true,
        protectTyping: Bool = true
    ) {
        guard (!requireEnabled || hoverRecoveryEnabled),
              !systemSleeping,
              !isTerminating,
              AXIsProcessTrusted() else { return }

        // Ne jamais injecter de mouvement pendant un clic maintenu ou un
        // glisser-déposer, quel que soit le bouton physique utilisé.
        let state = CGEventSourceStateID.combinedSessionState
        guard !anyMouseButtonPressed(state: state) else { return }
        guard !protectTyping || !keyboardInputIsRecent(state: state) else { return }

        // Plusieurs événements rapprochés reproduisent l'activité qui réveille
        // le rendu, mais chacun reprend la position réelle du pointeur. Il n'y a
        // donc ni micro-téléportation, ni passage accidentel sur l'écran voisin.
        hoverRecoveryBurstGeneration += 1
        let generation = hoverRecoveryBurstGeneration
        for delay in [0.0, 0.008, 0.016] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self,
                      generation == self.hoverRecoveryBurstGeneration,
                      (!requireEnabled || self.hoverRecoveryEnabled),
                      !self.systemSleeping,
                      !self.isTerminating,
                      !self.anyMouseButtonPressed(state: state),
                      (!protectTyping || !self.keyboardInputIsRecent(state: state)),
                      let location = CGEvent(source: nil)?.location else { return }
                self.postHoverRecoveryMove(at: location)
            }
        }
    }

    private func anyMouseButtonPressed(state: CGEventSourceStateID) -> Bool {
        for rawValue in UInt32(0)...UInt32(31) {
            guard let button = CGMouseButton(rawValue: rawValue) else { continue }
            if CGEventSource.buttonState(state, button: button) {
                return true
            }
        }
        return false
    }

    private func keyboardInputIsRecent(state: CGEventSourceStateID) -> Bool {
        let threshold = Self.hoverRecoveryKeyboardQuietPeriod
        return CGEventSource.secondsSinceLastEventType(state, eventType: .keyDown) < threshold
            || CGEventSource.secondsSinceLastEventType(state, eventType: .keyUp) < threshold
            || CGEventSource.secondsSinceLastEventType(state, eventType: .flagsChanged) < threshold
    }

    private func postHoverRecoveryMove(at location: CGPoint) {
        guard let event = CGEvent(
            mouseEventSource: nil,
            mouseType: .mouseMoved,
            mouseCursorPosition: location,
            mouseButton: .left
        ) else { return }
        event.setIntegerValueField(.eventSourceUserData, value: Self.syntheticMouseEventMarker)
        event.post(tap: .cghidEventTap)
    }

    private func handleFreeScrollButton(
        pressed: Bool,
        event: CGEvent
    ) -> Unmanaged<CGEvent>? {
        _ = receiveButtonEvent(PhysicalButtonEvent(
            button: 3,
            pressed: pressed,
            source: .cgEvent,
            timestamp: ProcessInfo.processInfo.systemUptime,
            physicalIndex: nil
        ))

        if pressed {
            resetFreeScrollTracking()
            freeScrollTracking = true
            freeScrollDidMove = false
            freeScrollDistance = 0
            freeScrollDisplacementX = 0
            freeScrollDisplacementY = 0
            freeScrollPendingX = 0
            freeScrollPendingY = 0
            return nil
        }

        guard freeScrollTracking else {
            return Unmanaged.passUnretained(event)
        }
        let didScroll = freeScrollDidMove
        let clickLocation = event.location
        if didScroll {
            flushFreeScroll()
        }
        resetFreeScrollTracking()

        if !didScroll && !detectionMode {
            DispatchQueue.main.async { [weak self] in
                self?.performShortMiddleClick(at: clickLocation)
            }
        }
        return nil
    }

    private func handleFreeScrollDrag(_ event: CGEvent) -> Unmanaged<CGEvent>? {
        guard freeScrollEnabled, freeScrollTracking else {
            return Unmanaged.passUnretained(event)
        }

        let deltaX = CGFloat(event.getDoubleValueField(.mouseEventDeltaX))
        let deltaY = CGFloat(event.getDoubleValueField(.mouseEventDeltaY))
        freeScrollDisplacementX += deltaX
        freeScrollDisplacementY += deltaY
        freeScrollDistance = hypot(freeScrollDisplacementX, freeScrollDisplacementY)

        guard freeScrollDistance >= Self.freeScrollActivationDistance else {
            return nil
        }
        freeScrollDidMove = true
        freeScrollPendingX += deltaX
        freeScrollPendingY += deltaY
        scheduleFreeScrollFlush()
        return nil
    }

    private func scheduleFreeScrollFlush() {
        guard freeScrollFlushWorkItem == nil else { return }
        let generation = freeScrollGeneration
        let work = DispatchWorkItem { [weak self] in
            guard let self, generation == self.freeScrollGeneration else { return }
            self.freeScrollFlushWorkItem = nil
            self.flushFreeScroll()
        }
        freeScrollFlushWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.008, execute: work)
    }

    private func flushFreeScroll() {
        guard freeScrollEnabled, freeScrollTracking, freeScrollDidMove else {
            freeScrollPendingX = 0
            freeScrollPendingY = 0
            return
        }
        let deltaX = freeScrollPendingX
        let deltaY = freeScrollPendingY
        freeScrollPendingX = 0
        freeScrollPendingY = 0
        postFreeScroll(deltaX: deltaX, deltaY: deltaY)
    }

    private func performShortMiddleClick(at location: CGPoint) {
        guard freeScrollEnabled, !systemSleeping, !isTerminating else { return }
        guard let action = mappings[3], action != .none else {
            postNativeMiddleClick(at: location)
            return
        }
        perform(action)
    }

    private func postNativeMiddleClick(at location: CGPoint) {
        guard let down = CGEvent(
            mouseEventSource: nil,
            mouseType: .otherMouseDown,
            mouseCursorPosition: location,
            mouseButton: .center
        ), let up = CGEvent(
            mouseEventSource: nil,
            mouseType: .otherMouseUp,
            mouseCursorPosition: location,
            mouseButton: .center
        ) else { return }
        for event in [down, up] {
            event.setIntegerValueField(.eventSourceUserData, value: Self.syntheticMouseEventMarker)
            event.setIntegerValueField(.mouseEventButtonNumber, value: 2)
        }
        down.post(tap: .cghidEventTap)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.012) {
            up.post(tap: .cghidEventTap)
        }
    }

    private func postFreeScroll(deltaX: CGFloat, deltaY: CGFloat) {
        let horizontal = Int32((-deltaX * Self.freeScrollMultiplier).rounded())
        let vertical = Int32((-deltaY * Self.freeScrollMultiplier).rounded())
        guard horizontal != 0 || vertical != 0,
              let event = CGEvent(
                scrollWheelEvent2Source: nil,
                units: .pixel,
                wheelCount: 2,
                wheel1: vertical,
                wheel2: horizontal,
                wheel3: 0
              ) else { return }
        event.setIntegerValueField(.eventSourceUserData, value: Self.syntheticMouseEventMarker)
        event.post(tap: .cghidEventTap)
    }

    private func resetFreeScrollTracking() {
        freeScrollGeneration += 1
        freeScrollFlushWorkItem?.cancel()
        freeScrollFlushWorkItem = nil
        freeScrollTracking = false
        freeScrollDidMove = false
        freeScrollDistance = 0
        freeScrollDisplacementX = 0
        freeScrollDisplacementY = 0
        freeScrollPendingX = 0
        freeScrollPendingY = 0
    }

    private func handleCGEvent(
        button: Int,
        pressed: Bool,
        event: CGEvent
    ) -> Unmanaged<CGEvent>? {
        guard buttons.contains(button) else { return Unmanaged.passUnretained(event) }
        if (button == 4 || button == 5),
           ProcessInfo.processInfo.systemUptime <= syntheticNavigationEventDeadline {
            return Unmanaged.passUnretained(event)
        }
        _ = receiveButtonEvent(PhysicalButtonEvent(
            button: button,
            pressed: pressed,
            source: .cgEvent,
            timestamp: ProcessInfo.processInfo.systemUptime,
            physicalIndex: nil
        ))
        let shouldConsume = !detectionMode && mappings[button] != Action.none
        return shouldConsume ? nil : Unmanaged.passUnretained(event)
    }

    private func perform(_ action: Action) {
        if action == .missionControl {
            let launcher = URL(fileURLWithPath: "/System/Applications/Mission Control.app")
            if NSWorkspace.shared.open(launcher) {
                return
            }
        }
        guard action == .none || ensureAccessibilityForActions() else { return }
        switch action {
        case .none: break
        case .historyBack: auxiliaryMouseButton(number: 3)
        case .historyForward: auxiliaryMouseButton(number: 4)
        case .missionControl: shortcut(keyCode: 126, flags: .maskControl)
        case .appExpose: shortcut(keyCode: 125, flags: .maskControl)
        case .nextApp: shortcut(keyCode: 48, flags: .maskCommand)
        case .previousApp: shortcut(keyCode: 48, flags: [.maskCommand, .maskShift])
        case .leftSpace: shortcut(keyCode: 123, flags: .maskControl)
        case .rightSpace: shortcut(keyCode: 124, flags: .maskControl)
        case .showDesktop: shortcut(keyCode: 103, flags: [])
        }
    }

    private func auxiliaryMouseButton(number: UInt32) {
        guard let location = CGEvent(source: nil)?.location,
              let button = CGMouseButton(rawValue: number),
              let down = CGEvent(
            mouseEventSource: nil,
            mouseType: .otherMouseDown,
            mouseCursorPosition: location,
            mouseButton: button
        ),
              let up = CGEvent(
            mouseEventSource: nil,
            mouseType: .otherMouseUp,
            mouseCursorPosition: location,
            mouseButton: button
        ) else {
            return
        }
        for event in [down, up] {
            event.setIntegerValueField(
                .eventSourceUserData,
                value: Self.syntheticMouseEventMarker
            )
            event.setIntegerValueField(.mouseEventButtonNumber, value: Int64(number))
            event.setIntegerValueField(.mouseEventClickState, value: 1)
        }
        syntheticNavigationEventDeadline = ProcessInfo.processInfo.systemUptime + 0.12
        down.post(tap: .cghidEventTap)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.012) {
            up.post(tap: .cghidEventTap)
        }
    }

    private func ensureAccessibilityForActions() -> Bool {
        guard !AXIsProcessTrusted() else {
            accessibilityWarningShown = false
            return true
        }
        requestAccessibility()
        guard !accessibilityWarningShown else { return false }
        accessibilityWarningShown = true
        let alert = NSAlert()
        alert.messageText = L10n.string("accessibility.blocked.title")
        alert.informativeText = L10n.string("accessibility.blocked.message")
        alert.addButton(withTitle: L10n.string("accessibility.open"))
        alert.addButton(withTitle: L10n.string("common.later"))
        if alert.runModal() == .alertFirstButtonReturn {
            openAccessibility()
        }
        rebuildMenu()
        return false
    }

    @objc private func testMissionControl() {
        perform(.missionControl)
    }

    private func shortcut(keyCode: CGKeyCode, flags: CGEventFlags) {
        guard let down = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: true),
              let up = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: false) else { return }
        down.flags = flags
        up.flags = flags
        down.post(tap: .cghidEventTap)
        usleep(35_000)
        up.post(tap: .cghidEventTap)
    }

    @objc private func toggleDetection() {
        detectionMode.toggle()
        if detectionMode {
            detectedButtons.removeAll()
            statusItem.button?.title = L10n.string("status.identifying")
        } else {
            statusItem.button?.title = ""
        }
        rebuildMenu()
    }

    @objc private func selectAction(_ sender: NSMenuItem) {
        guard let info = sender.representedObject as? [String: Any],
              let button = info["button"] as? Int,
              let raw = info["action"] as? String,
              let action = Action(rawValue: raw) else { return }
        mappings[button] = action
        UserDefaults.standard.set(action.rawValue, forKey: "g502x.g\(button)")
        rebuildMenu()
    }

    @objc private func openVisualConfig() {
        if visualConfig == nil {
            visualConfig = VisualConfigWindowController(
                getMappings: { [weak self] in self?.mappings ?? [:] },
                setMapping: { [weak self] button, action in
                    guard let self else { return }
                    self.mappings[button] = action
                    UserDefaults.standard.set(action.rawValue, forKey: "g502x.g\(button)")
                    self.rebuildMenu()
                },
                startCalibration: { [weak self] button in
                    self?.startCalibration(for: button)
                },
                readDPI: { [weak self] completion in
                    guard let self else { return }
                    self.readCurrentDPI(completion: completion)
                },
                setDPI: { [weak self] value, persist, completion in
                    guard let self else { return }
                    self.setDPI(value, persist: persist, completion: completion)
                }
            )
        }
        visualConfig?.showAndFocus()
        visualConfig?.updateDevice(name: connectedDevice.name, connected: connectedDevice.connected)
        refreshBatteryUI()
    }

    private func startCalibration(for button: Int) {
        guard buttonSpyReady else {
            let unavailable = NSAlert()
            unavailable.messageText = L10n.string("calibration.unavailable.title")
            unavailable.informativeText = L10n.string("calibration.unavailable.message")
            unavailable.addButton(withTitle: L10n.string("common.ok"))
            unavailable.runModal()
            return
        }
        calibrationTarget = button
        let alert = NSAlert()
        calibrationAlert = alert
        alert.messageText = L10n.format("calibration.title", button)
        alert.informativeText = L10n.format("calibration.instruction", button)
        alert.addButton(withTitle: L10n.string("common.cancel"))
        _ = alert.runModal()
        if calibrationTarget == button {
            calibrationTarget = nil
        }
        calibrationAlert = nil
    }

    private func completeCalibration(index: Int, button: Int) {
        guard calibrationTarget == button else { return }
        let stale = physicalIndexToG.compactMap { entry in
            entry.key == index || entry.value == button ? entry.key : nil
        }
        stale.forEach { physicalIndexToG.removeValue(forKey: $0) }
        physicalIndexToG[index] = button
        UserDefaults.standard.set(index, forKey: "g502x.physicalIndex.g\(button)")
        calibrationTarget = nil
        visualConfig?.showCalibration(index: index, button: button)
        if let alert = calibrationAlert {
            alert.window.orderOut(nil)
            NSApp.abortModal()
        }
        statusItem.button?.title = L10n.format("status.buttonCalibrated", button)
        rebuildMenu()
    }

    @objc private func restartTap() {
        stopEventTap()
        stopHoverEventTap()
        requestAccessibility()
        startEventTap()
        startHoverEventTap()
        buttonSpyPaused = false
        stopButtonSpyAndRestoreMode(waitUntilExit: false)
        reconnectAttempt = 0
        startButtonSpy()
    }

    @objc private func systemWillSleep(_ notification: Notification) {
        systemSleeping = true
        reconnectStatus = nil
        cancelWakeRecovery()
        hoverRecoveryWorkItem?.cancel()
        hoverRecoveryWorkItem = nil
        hoverRecoveryBurstGeneration += 1
        resetFreeScrollTracking()
        appendButtonSpyDiagnostic(L10n.string("diagnostic.macOSWillSleep"))
        stopButtonSpyAndRestoreMode(waitUntilExit: false)
        rebuildMenu()
    }

    @objc private func systemDidWake(_ notification: Notification) {
        resumeAfterInactivity(reason: .wake)
    }

    @objc private func sessionDidResignActive(_ notification: Notification) {
        systemSleeping = true
        cancelWakeRecovery()
        hoverRecoveryWorkItem?.cancel()
        hoverRecoveryWorkItem = nil
        hoverRecoveryBurstGeneration += 1
        resetFreeScrollTracking()
        appendButtonSpyDiagnostic(L10n.string("diagnostic.sessionInactive"))
        stopButtonSpyAndRestoreMode(waitUntilExit: false)
        rebuildMenu()
    }

    @objc private func sessionDidBecomeActive(_ notification: Notification) {
        resumeAfterInactivity(reason: .session)
    }

    // Le verrouillage de session peut couper le canal HID++ sans déclencher un
    // vrai didWake. On utilise donc la même reprise pour le réveil et le retour
    // de session, avec plusieurs essais après la remise sous tension du receiver.
    private func resumeAfterInactivity(reason: WakeRecoveryReason) {
        systemSleeping = false
        appendButtonSpyDiagnostic(L10n.string(reason.reconnectKey))
        // Un tap peut rester alloué mais ne plus livrer d'événements après un
        // verrouillage ou une veille. Le recréer reproduit automatiquement le
        // bouton « Relancer la détection » sans dépendre d'un port devenu zombie.
        stopEventTap()
        stopHoverEventTap()
        startEventTap()
        startHoverEventTap()
        startWakeRecovery(reason: reason)
        rebuildMenu()
    }

    @objc private func openAccessibility() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }

    @objc private func openInputMonitoring() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")!)
    }

    @objc private func showHIDDiagnostic() {
        let text = buttonSpyDiagnostic.isEmpty
            ? L10n.string("diagnostic.channelInitializing")
            : buttonSpyDiagnostic
        let alert = NSAlert()
        alert.messageText = buttonSpyReady
            ? L10n.string("diagnostic.active.title")
            : L10n.string("diagnostic.title")
        alert.informativeText = text
        alert.addButton(withTitle: L10n.string("common.close"))
        alert.addButton(withTitle: L10n.string("common.copy"))
        if alert.runModal() == .alertSecondButtonReturn {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
        }
    }

    private func runHelper(_ arguments: [String], in directory: URL) throws -> String {
        let helper = try helperURL()
        let process = Process()
        let output = Pipe()
        process.executableURL = helper
        process.arguments = arguments
        process.currentDirectoryURL = directory
        process.standardOutput = output
        process.standardError = output
        try process.run()
        process.waitUntilExit()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        let text = String(data: data, encoding: .utf8) ?? ""
        guard process.terminationStatus == 0 else {
            throw NSError(
                domain: "G502StageMouse",
                code: Int(process.terminationStatus),
                userInfo: [NSLocalizedDescriptionKey: text.isEmpty ? L10n.string("error.hidCommandFailed") : text]
            )
        }
        return text
    }

    private func helperURL() throws -> URL {
        if let helper = Bundle.main.url(forAuxiliaryExecutable: "opengcontrol")
            ?? Bundle.main.url(forResource: "opengcontrol", withExtension: nil) {
            return helper
        }
        throw NSError(
            domain: "G502StageMouse",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: L10n.string("error.hidModuleMissing")]
        )
    }

    private func receiverSelection(in directory: URL) throws -> (path: String, pid: String) {
        let listing = try runHelper(["--output", "json", "list"], in: directory)
        guard let data = listing.data(using: .utf8),
              let devices = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw NSError(
                domain: "G502StageMouse",
                code: 3,
                userInfo: [NSLocalizedDescriptionKey: L10n.format("error.hidDeviceListUnreadable", listing)]
            )
        }
        for wantedPID in ["C53A", "C547", "C098"] {
            if let device = devices.first(where: { ($0["pid"] as? String) == wantedPID }),
               let path = device["path"] as? String {
                return (path, wantedPID)
            }
        }
        throw NSError(
            domain: "G502StageMouse",
            code: 4,
            userInfo: [NSLocalizedDescriptionKey: L10n.format("error.receiverNotFound", listing)]
        )
    }

    private func applicationSupportURL() throws -> URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("G502StageMouse", isDirectory: true)
        try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        return support
    }

    private func latestOriginalProfileBackup(in support: URL) throws -> URL {
        let keys: Set<URLResourceKey> = [.contentModificationDateKey]
        let candidates = try FileManager.default.contentsOfDirectory(
            at: support,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles]
        ).filter {
            $0.pathExtension.lowercased() == "toml"
                && $0.lastPathComponent.hasPrefix("profil-")
                && $0.lastPathComponent.contains("-avant-stage-mouse-")
        }
        guard let latest = candidates.max(by: { first, second in
            let firstDate = (try? first.resourceValues(forKeys: keys).contentModificationDate) ?? .distantPast
            let secondDate = (try? second.resourceValues(forKeys: keys).contentModificationDate) ?? .distantPast
            return firstDate < secondDate
        }) else {
            throw NSError(
                domain: "G502StageMouse",
                code: 5,
                userInfo: [NSLocalizedDescriptionKey: L10n.format("error.originalBackupMissing", support.path)]
            )
        }
        return latest
    }

    private var shouldRunButtonSpy: Bool {
        connectedDevice.connected && !buttonSpyPaused && !systemSleeping && !isTerminating
    }

    private func appendButtonSpyDiagnostic(_ message: String) {
        buttonSpyDiagnostic += "\n\(message)"
        if buttonSpyDiagnostic.count > 8_000 {
            buttonSpyDiagnostic = String(buttonSpyDiagnostic.suffix(8_000))
        }
    }

    private func stopButtonSpyAndRestoreMode(waitUntilExit: Bool = true) {
        reconnectWorkItem?.cancel()
        reconnectWorkItem = nil
        reconnectStatus = nil
        buttonSpyLifecycleToken += 1
        buttonSpyStartInProgress = false
        buttonSpyReady = false
        lastAcceptedButtonEvents.removeAll()

        guard let process = buttonSpyProcess else { return }
        let generation = buttonSpyProcessGeneration
        buttonSpyProcess = nil
        if process.isRunning {
            expectedButtonSpyStops.insert(generation)
            process.terminate()
            if waitUntilExit {
                process.waitUntilExit()
            }
        }
    }

    private func cancelWakeRecovery() {
        wakeRecoveryGeneration += 1
        wakeRecoveryWorkItem?.cancel()
        wakeRecoveryWorkItem = nil
    }

    private func startWakeRecovery(reason: WakeRecoveryReason) {
        cancelWakeRecovery()
        let generation = wakeRecoveryGeneration
        scheduleWakeRecoveryAttempt(reason: reason, attempt: 0, generation: generation)
    }

    private func scheduleWakeRecoveryAttempt(
        reason: WakeRecoveryReason,
        attempt: Int,
        generation: Int
    ) {
        guard generation == wakeRecoveryGeneration,
              attempt < wakeRecoveryDelays.count else {
            return
        }
        let work = DispatchWorkItem { [weak self] in
            guard let self,
                  generation == self.wakeRecoveryGeneration,
                  self.shouldRunButtonSpy,
                  !self.buttonSpyReady else {
                return
            }
            if self.buttonSpyProcess?.isRunning == true {
                self.appendButtonSpyDiagnostic(L10n.string(reason.channelNotReadyKey))
                self.stopButtonSpyAndRestoreMode(waitUntilExit: false)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
                guard let self,
                      generation == self.wakeRecoveryGeneration,
                      self.shouldRunButtonSpy,
                      !self.buttonSpyReady else {
                    return
                }
                self.startButtonSpy()
                self.scheduleWakeRecoveryAttempt(
                    reason: reason,
                    attempt: attempt + 1,
                    generation: generation
                )
            }
        }
        wakeRecoveryWorkItem = work
        DispatchQueue.main.asyncAfter(
            deadline: .now() + wakeRecoveryDelays[attempt],
            execute: work
        )
    }

    private func scheduleButtonSpyRestart(reason: ButtonSpyRetryReason, resetBackoff: Bool = false) {
        guard shouldRunButtonSpy,
              buttonSpyProcess?.isRunning != true,
              !buttonSpyStartInProgress else {
            return
        }
        if resetBackoff {
            reconnectAttempt = 0
        }
        reconnectWorkItem?.cancel()

        let delayIndex = min(reconnectAttempt, reconnectDelays.count - 1)
        let delay = reconnectDelays[delayIndex]
        reconnectAttempt = min(reconnectAttempt + 1, reconnectDelays.count - 1)
        reconnectStatus = L10n.format(
            "status.reconnectIn",
            delay.formatted(.number.precision(.fractionLength(delay < 1 ? 1 : 0)))
        )
        appendButtonSpyDiagnostic(L10n.format(
            reason.diagnosticKey,
            String(delay),
            delayIndex + 1,
            reconnectDelays.count
        ))

        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.reconnectWorkItem = nil
            self.startButtonSpy()
        }
        reconnectWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
        rebuildMenu()
    }

    private func resumeButtonSpy() {
        buttonSpyPaused = false
        reconnectAttempt = 0
        reconnectStatus = nil
        startButtonSpy()
    }

    private func readCurrentDPI(completion: @escaping (Result<Int, Error>) -> Void) {
        performDPIOperation(arguments: ["dpi", "get"], completion: completion)
    }

    private func setDPI(
        _ value: Int,
        persist: Bool,
        completion: @escaping (Result<Int, Error>) -> Void
    ) {
        let normalized = max(100, min(25_600, 100 + Int(round(Double(value - 100) / 50.0)) * 50))
        var arguments = ["dpi", "set", "\(normalized)"]
        if persist {
            arguments.append("--persist")
        }
        performDPIOperation(arguments: arguments, completion: completion)
    }

    private func performDPIOperation(
        arguments: [String],
        completion: @escaping (Result<Int, Error>) -> Void
    ) {
        guard !dpiOperationInProgress else {
            completion(.failure(NSError(
                domain: "G502StageMouse.DPI",
                code: 20,
                userInfo: [NSLocalizedDescriptionKey: L10n.string("dpi.error.busy")]
            )))
            return
        }
        dpiOperationInProgress = true
        buttonSpyPaused = true
        stopButtonSpyAndRestoreMode()
        statusItem.button?.title = L10n.string("status.dpiBusy")

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let support = try self.applicationSupportURL()
                let receiver = try self.receiverSelection(in: support)
                let output = try self.runHelper(
                    ["--device", receiver.path, "--output", "json"] + arguments,
                    in: support
                )
                guard let data = output.data(using: .utf8),
                      let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let dpi = json["dpi"] as? Int else {
                    throw NSError(
                        domain: "G502StageMouse.DPI",
                        code: 21,
                        userInfo: [NSLocalizedDescriptionKey: L10n.format("dpi.error.unreadableResponse", output)]
                    )
                }
                DispatchQueue.main.async {
                    self.dpiOperationInProgress = false
                    self.statusItem.button?.title = ""
                    self.resumeButtonSpy()
                    completion(.success(dpi))
                }
            } catch {
                DispatchQueue.main.async {
                    self.dpiOperationInProgress = false
                    self.statusItem.button?.title = ""
                    self.resumeButtonSpy()
                    completion(.failure(error))
                }
            }
        }
    }

    private func startButtonSpy() {
        guard shouldRunButtonSpy,
              buttonSpyProcess?.isRunning != true,
              !buttonSpyStartInProgress else {
            return
        }
        reconnectWorkItem?.cancel()
        reconnectWorkItem = nil
        reconnectStatus = L10n.string("status.connectingHID")
        buttonSpyStartInProgress = true
        buttonSpyLifecycleToken += 1
        let lifecycleToken = buttonSpyLifecycleToken
        buttonSpyProcessGeneration += 1
        let generation = buttonSpyProcessGeneration
        rebuildMenu()

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let support = try self.applicationSupportURL()
                let receiver = try self.receiverSelection(in: support)
                let helper = try self.helperURL()
                let process = Process()
                let output = Pipe()
                process.executableURL = helper
                process.arguments = [
                    "--device", receiver.path,
                    "--output", "json",
                    "buttons"
                ]
                process.currentDirectoryURL = support
                process.standardOutput = output
                process.standardError = output
                output.fileHandleForReading.readabilityHandler = { [weak self] handle in
                    let data = handle.availableData
                    guard !data.isEmpty else { return }
                    let chunk = String(decoding: data, as: UTF8.self)
                    self?.buttonSpyQueue.async {
                        self?.consumeButtonSpy(chunk, generation: generation)
                    }
                }
                process.terminationHandler = { [weak self] process in
                    DispatchQueue.main.async {
                        guard let self else { return }
                        let expected = self.expectedButtonSpyStops.remove(generation) != nil
                        if self.buttonSpyProcessGeneration == generation {
                            if self.buttonSpyProcess === process {
                                self.buttonSpyProcess = nil
                            }
                            self.buttonSpyReady = false
                            self.buttonSpyStartInProgress = false
                        }
                        if !expected {
                            self.appendButtonSpyDiagnostic(L10n.format(
                                "diagnostic.channelStopped",
                                Int(process.terminationStatus)
                            ))
                            self.scheduleButtonSpyRestart(reason: .unexpectedStop)
                        }
                        self.rebuildMenu()
                    }
                }
                try process.run()
                DispatchQueue.main.async {
                    guard self.buttonSpyLifecycleToken == lifecycleToken,
                          self.shouldRunButtonSpy else {
                        self.expectedButtonSpyStops.insert(generation)
                        if process.isRunning {
                            process.terminate()
                        }
                        return
                    }
                    self.buttonSpyStartInProgress = false
                    guard process.isRunning else {
                        self.scheduleButtonSpyRestart(reason: .startupStop)
                        return
                    }
                    self.buttonSpyProcess = process
                    self.connectedDevice = (
                        receiver.pid == "C53A"
                            ? L10n.string("device.powerplayReceiver")
                            : L10n.format("device.lightspeedReceiverWithPID", receiver.pid),
                        true
                    )
                    self.visualConfig?.updateDevice(
                        name: self.connectedDevice.name,
                        connected: true
                    )
                    self.rebuildMenu()
                }
            } catch {
                DispatchQueue.main.async {
                    guard self.buttonSpyLifecycleToken == lifecycleToken else { return }
                    self.buttonSpyStartInProgress = false
                    self.appendButtonSpyDiagnostic(L10n.format(
                        "diagnostic.connectionFailed",
                        error.localizedDescription
                    ))
                    self.buttonSpyReady = false
                    self.scheduleButtonSpyRestart(reason: .initializationFailed)
                }
            }
        }
    }

    private func consumeButtonSpy(_ chunk: String, generation: Int) {
        if buttonSpyBufferGeneration != generation {
            buttonSpyBufferGeneration = generation
            buttonSpyBuffer = ""
        }
        buttonSpyBuffer += chunk
        while let newline = buttonSpyBuffer.firstIndex(of: "\n") {
            let line = String(buttonSpyBuffer[..<newline])
            buttonSpyBuffer.removeSubrange(...newline)
            DispatchQueue.main.async {
                self.processButtonSpyLine(line, generation: generation)
            }
        }
    }

    private func processButtonSpyLine(_ line: String, generation: Int) {
        guard generation == buttonSpyProcessGeneration else { return }
        appendButtonSpyDiagnostic(line)
        guard let data = line.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return
        }
        if (json["ready"] as? Bool) == true {
            buttonSpyReady = true
            reconnectAttempt = 0
            reconnectStatus = nil
            visualConfig?.updateDevice(name: connectedDevice.name, connected: true)
            rebuildMenu()
            return
        }
        if let available = json["battery_available"] as? Bool {
            batteryAvailable = available
            if available {
                batteryPercent = json["battery_percent"] as? Int
                batteryEstimated = json["battery_estimated"] as? Bool ?? false
                batteryCharging = json["battery_charging"] as? Bool ?? false
                batteryStatus = json["battery_status"] as? String
            } else {
                batteryPercent = nil
                batteryEstimated = false
                batteryCharging = false
                batteryStatus = nil
            }
            refreshBatteryUI()
            rebuildMenu()
            return
        }
        guard let pressed = json["pressed"] as? Bool,
              let index = json["button_index"] as? Int,
              let gButton = physicalIndexToG[index] else {
            return
        }
        receiveButtonEvent(PhysicalButtonEvent(
            button: gButton,
            pressed: pressed,
            source: .hidppSpy,
            timestamp: ProcessInfo.processInfo.systemUptime,
            physicalIndex: index
        ))
    }

    private func batteryDisplayText() -> String {
        batteryText(detail: false)
    }

    private func batteryDetailText() -> String {
        batteryText(detail: true)
    }

    private func batteryText(detail: Bool) -> String {
        guard connectedDevice.connected else {
            return L10n.string(detail ? "battery.detail.mouseDisconnected" : "battery.mouseDisconnected")
        }
        guard batteryAvailable else {
            return buttonSpyReady
                ? L10n.string(detail ? "battery.detail.unavailable" : "battery.unavailable")
                : L10n.string(detail ? "battery.detail.reading" : "battery.reading")
        }

        let level: String
        if let batteryPercent {
            level = L10n.format(
                batteryEstimated ? "battery.level.estimated" : "battery.level.exact",
                batteryPercent
            )
        } else {
            level = L10n.string("battery.level.unknown")
        }

        let key: String
        if batteryCharging {
            key = detail ? "battery.detail.charging" : "battery.charging"
        } else if batteryStatus == "charged" {
            key = detail ? "battery.detail.charged" : "battery.charged"
        } else if batteryStatus == "charging error" {
            key = detail ? "battery.detail.chargingError" : "battery.chargingError"
        } else {
            key = connectedDevice.name?.contains("POWERPLAY") == true
                ? (detail ? "battery.detail.powerplayNotCharging" : "battery.powerplayNotCharging")
                : (detail ? "battery.detail.notCharging" : "battery.notCharging")
        }
        return L10n.format(key, level)
    }

    private func refreshBatteryUI() {
        visualConfig?.updateBattery(
            text: batteryDetailText(),
            charging: batteryCharging,
            available: batteryAvailable
        )
    }

    private func startUpdateMonitoring() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            self.checkForLocalUpdate(manual: false)
        }
        let timer = Timer(timeInterval: 30 * 60, repeats: true) { [weak self] _ in
            self?.checkForLocalUpdate(manual: false)
        }
        timer.tolerance = 5 * 60
        RunLoop.main.add(timer, forMode: .common)
        updateTimer = timer
    }

    @objc private func checkForUpdatesManually() {
        checkForLocalUpdate(manual: true)
    }

    private func checkForLocalUpdate(manual: Bool) {
        guard !updateCheckInProgress else { return }
        updateCheckInProgress = true
        let currentVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"

        DispatchQueue.global(qos: .utility).async {
            do {
                let updates = try self.applicationSupportURL().appendingPathComponent("Updates", isDirectory: true)
                let manifestURL = updates.appendingPathComponent("manifest.json")
                guard FileManager.default.fileExists(atPath: manifestURL.path) else {
                    DispatchQueue.main.async {
                        self.finishUpdateCheckWithoutUpdate(manual: manual, currentVersion: currentVersion)
                    }
                    return
                }

                let manifest = try JSONDecoder().decode(
                    LocalUpdateManifest.self,
                    from: Data(contentsOf: manifestURL)
                )
                guard manifest.version.compare(currentVersion, options: .numeric) == .orderedDescending else {
                    DispatchQueue.main.async {
                        self.finishUpdateCheckWithoutUpdate(manual: manual, currentVersion: currentVersion)
                    }
                    return
                }
                guard manifest.archive == URL(fileURLWithPath: manifest.archive).lastPathComponent,
                      !manifest.archive.contains(".."),
                      manifest.archive.lowercased().hasSuffix(".zip") else {
                    throw NSError(
                        domain: "G502StageMouse.Update",
                        code: 10,
                        userInfo: [NSLocalizedDescriptionKey: L10n.string("update.invalidManifest")]
                    )
                }
                let archiveURL = updates.appendingPathComponent(manifest.archive)
                guard FileManager.default.fileExists(atPath: archiveURL.path) else {
                    throw NSError(
                        domain: "G502StageMouse.Update",
                        code: 11,
                        userInfo: [NSLocalizedDescriptionKey: L10n.format("update.archiveMissing", manifest.archive)]
                    )
                }

                DispatchQueue.main.async {
                    self.updateCheckInProgress = false
                    guard manual || self.deferredUpdateVersion != manifest.version else { return }
                    self.offerUpdate(manifest, archiveURL: archiveURL)
                }
            } catch {
                DispatchQueue.main.async {
                    self.updateCheckInProgress = false
                    guard manual else { return }
                    let alert = NSAlert()
                    alert.messageText = L10n.string("update.checkFailed.title")
                    alert.informativeText = error.localizedDescription
                    alert.addButton(withTitle: L10n.string("common.close"))
                    alert.runModal()
                }
            }
        }
    }

    private func finishUpdateCheckWithoutUpdate(manual: Bool, currentVersion: String) {
        updateCheckInProgress = false
        guard manual else { return }
        let alert = NSAlert()
        alert.messageText = L10n.string("update.current.title")
        alert.informativeText = L10n.format("update.current.version", currentVersion)
        alert.addButton(withTitle: L10n.string("common.ok"))
        alert.runModal()
    }

    private func offerUpdate(_ manifest: LocalUpdateManifest, archiveURL: URL) {
        let alert = NSAlert()
        alert.messageText = L10n.format("update.available.title", manifest.version)
        alert.informativeText = L10n.string("update.available.message")
        alert.addButton(withTitle: L10n.string("update.installAndRelaunch"))
        alert.addButton(withTitle: L10n.string("update.later"))
        if alert.runModal() == .alertFirstButtonReturn {
            installLocalUpdate(manifest, archiveURL: archiveURL)
        } else {
            deferredUpdateVersion = manifest.version
        }
    }

    private func runExecutable(_ executable: String, arguments: [String]) throws -> String {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = output
        process.standardError = output
        try process.run()
        process.waitUntilExit()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        let text = String(data: data, encoding: .utf8) ?? ""
        guard process.terminationStatus == 0 else {
            throw NSError(
                domain: "G502StageMouse.Update",
                code: Int(process.terminationStatus),
                userInfo: [NSLocalizedDescriptionKey:
                    text.isEmpty ? L10n.format("update.executableFailed", executable) : text]
            )
        }
        return text
    }

    private func installLocalUpdate(_ manifest: LocalUpdateManifest, archiveURL: URL) {
        buttonSpyPaused = true
        stopButtonSpyAndRestoreMode()
        statusItem.button?.title = L10n.string("status.updateBusy")
        let currentBundle = Bundle.main.bundleURL.standardizedFileURL

        DispatchQueue.global(qos: .userInitiated).async {
            let fileManager = FileManager.default
            let temporary = fileManager.temporaryDirectory
                .appendingPathComponent("G502StageMouseUpdate-\(UUID().uuidString)", isDirectory: true)
            defer { try? fileManager.removeItem(at: temporary) }

            do {
                let archiveData = try Data(contentsOf: archiveURL)
                let checksum = SHA256.hash(data: archiveData).map { String(format: "%02x", $0) }.joined()
                guard checksum.caseInsensitiveCompare(manifest.sha256) == .orderedSame else {
                    throw NSError(
                        domain: "G502StageMouse.Update",
                        code: 12,
                        userInfo: [NSLocalizedDescriptionKey: L10n.string("update.invalidChecksum")]
                    )
                }

                guard !currentBundle.path.contains("/AppTranslocation/"),
                      currentBundle.pathExtension == "app" else {
                    throw NSError(
                        domain: "G502StageMouse.Update",
                        code: 13,
                        userInfo: [NSLocalizedDescriptionKey: L10n.string("update.moveToApplications")]
                    )
                }

                try fileManager.createDirectory(at: temporary, withIntermediateDirectories: true)
                _ = try self.runExecutable("/usr/bin/ditto", arguments: ["-x", "-k", archiveURL.path, temporary.path])
                let candidate = temporary.appendingPathComponent("G502 Stage Mouse.app", isDirectory: true)
                guard let candidateBundle = Bundle(url: candidate),
                      candidateBundle.bundleIdentifier == "fr.remy.g502stagemouse",
                      (candidateBundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) == manifest.version else {
                    throw NSError(
                        domain: "G502StageMouse.Update",
                        code: 14,
                        userInfo: [NSLocalizedDescriptionKey: L10n.string("update.unexpectedArchiveVersion")]
                    )
                }
                _ = try self.runExecutable(
                    "/usr/bin/codesign",
                    arguments: ["--verify", "--deep", "--strict", candidate.path]
                )

                let parent = currentBundle.deletingLastPathComponent()
                guard fileManager.isWritableFile(atPath: parent.path) else {
                    throw NSError(
                        domain: "G502StageMouse.Update",
                        code: 15,
                        userInfo: [NSLocalizedDescriptionKey: L10n.format("update.directoryNotWritable", parent.path)]
                    )
                }
                let staged = parent.appendingPathComponent(".G502 Stage Mouse.app.update-\(UUID().uuidString)")
                let previous = parent.appendingPathComponent(".G502 Stage Mouse.app.previous")
                _ = try self.runExecutable("/usr/bin/ditto", arguments: [candidate.path, staged.path])
                _ = try self.runExecutable(
                    "/usr/bin/codesign",
                    arguments: ["--verify", "--deep", "--strict", staged.path]
                )

                if fileManager.fileExists(atPath: previous.path) {
                    try fileManager.removeItem(at: previous)
                }
                try fileManager.moveItem(at: currentBundle, to: previous)
                do {
                    try fileManager.moveItem(at: staged, to: currentBundle)
                } catch {
                    try? fileManager.moveItem(at: previous, to: currentBundle)
                    throw error
                }

                _ = try self.runExecutable("/usr/bin/open", arguments: ["-n", currentBundle.path])
                DispatchQueue.main.async {
                    NSApp.terminate(nil)
                }
            } catch {
                DispatchQueue.main.async {
                    self.statusItem.button?.title = ""
                    let alert = NSAlert()
                    alert.messageText = L10n.string("update.installFailed.title")
                    alert.informativeText = error.localizedDescription
                    alert.addButton(withTitle: L10n.string("common.close"))
                    alert.runModal()
                    self.resumeButtonSpy()
                }
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        isTerminating = true
        buttonSpyPaused = true
        updateTimer?.invalidate()
        hoverRecoveryWorkItem?.cancel()
        hoverRecoveryWorkItem = nil
        hoverRecoveryBurstGeneration += 1
        resetFreeScrollTracking()
        cancelWakeRecovery()
        stopEventTap()
        stopHoverEventTap()
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        stopButtonSpyAndRestoreMode()
    }

    @objc private func restoreOriginalProfile() {
        let support: URL
        let originalBackup: URL
        do {
            support = try applicationSupportURL()
            originalBackup = try latestOriginalProfileBackup(in: support)
        } catch {
            let missing = NSAlert()
            missing.messageText = L10n.string("restore.backupMissing.title")
            missing.informativeText = error.localizedDescription
            missing.addButton(withTitle: L10n.string("common.close"))
            missing.runModal()
            return
        }

        let confirmation = NSAlert()
        confirmation.messageText = L10n.string("restore.confirm.title")
        confirmation.informativeText = L10n.format("restore.confirm.message", originalBackup.lastPathComponent)
        confirmation.addButton(withTitle: L10n.string("restore.confirm.action"))
        confirmation.addButton(withTitle: L10n.string("common.cancel"))
        guard confirmation.runModal() == .alertFirstButtonReturn else { return }

        buttonSpyPaused = true
        stopButtonSpyAndRestoreMode()
        statusItem.button?.title = L10n.string("status.restoreBusy")
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let receiver = try self.receiverSelection(in: support)
                let target = ["--device", receiver.path]

                let activeOutput = try self.runHelper(target + ["--output", "json", "profile", "active"], in: support)
                guard let data = activeOutput.data(using: .utf8),
                      let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let active = json["active_profile"] as? Int else {
                    throw NSError(
                        domain: "G502StageMouse",
                        code: 2,
                        userInfo: [NSLocalizedDescriptionKey: L10n.format("error.activeProfileUnknown", activeOutput)]
                    )
                }

                let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
                let currentBackup = "profil-\(active)-avant-restauration-\(stamp).toml"
                _ = try self.runHelper(target + ["profile", "export", "\(active)", currentBackup], in: support)
                _ = try self.runHelper(target + ["profile", "import", originalBackup.path], in: support)
                _ = try self.runHelper(target + ["--output", "json", "profile", "list"], in: support)

                DispatchQueue.main.async {
                    self.statusItem.button?.title = ""
                    let success = NSAlert()
                    success.messageText = L10n.string("restore.success.title")
                    success.informativeText = L10n.format(
                        "restore.success.message",
                        originalBackup.lastPathComponent,
                        currentBackup
                    )
                    success.addButton(withTitle: L10n.string("common.ok"))
                    success.runModal()
                    self.resumeButtonSpy()
                }
            } catch {
                DispatchQueue.main.async {
                    self.statusItem.button?.title = ""
                    let failure = NSAlert()
                    failure.messageText = L10n.string("restore.failed.title")
                    failure.informativeText = L10n.format(
                        "diagnostic.failureDetails",
                        error.localizedDescription,
                        self.buttonSpyDiagnostic
                    )
                    failure.addButton(withTitle: L10n.string("common.close"))
                    failure.runModal()
                    self.resumeButtonSpy()
                }
            }
        }
    }

    @objc private func toggleLogin() {
        guard #available(macOS 13.0, *) else { return }
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            let alert = NSAlert()
            alert.messageText = L10n.string("restore.loginFailed.title")
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
        rebuildMenu()
    }

    @objc private func quitApp() { NSApp.terminate(nil) }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
