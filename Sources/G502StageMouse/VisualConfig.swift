import AppKit
import SceneKit

final class MouseSceneView: SCNView {
    var highlightedButton: Int? { didSet { highlightPart() } }
    var mappings: [Int: Action] = [:]

    private let cameraNode = SCNNode()
    private var modelNode: SCNNode?

    // Map each geometry node name to its original materials (for reset)
    private var originalMaterials: [String: [SCNMaterial]] = [:]

    // Map G-buttons to the geometry node names they should highlight
    // Based on the USDZ analysis:
    //   Object_0 = base/chassis
    //   Object_1 = upper shell
    //   Object_2 = left side buttons (thumb area)
    //   Object_3 = small left element (scroll wheel area)
    //   Object_4 = right side
    //   Object_5 = top surface
    private let buttonToMeshes: [Int: [String]] = [
        3: ["Object_3"],             // G3: scroll click
        4: ["Object_2"],             // G4: thumb back
        5: ["Object_2"],             // G5: thumb forward (same mesh as G4)
        6: ["Object_2"],             // G6: sniper (thumb area)
        7: ["Object_5"],             // G7: DPI - (top surface)
        8: ["Object_5"],             // G8: DPI + (top surface)
        9: ["Object_3"]              // G9: profile (near scroll wheel)
    ]

    override init(frame: NSRect, options: [String : Any]? = nil) {
        super.init(frame: frame, options: options)
        setupScene()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupScene() {
        self.scene = SCNScene()
        self.backgroundColor = .clear
        self.autoenablesDefaultLighting = true
        self.allowsCameraControl = true
        self.antialiasingMode = .multisampling4X

        // Camera
        cameraNode.camera = SCNCamera()
        cameraNode.camera?.fieldOfView = 35
        cameraNode.position = SCNVector3(x: 0, y: 6, z: 14)
        cameraNode.eulerAngles = SCNVector3(x: -CGFloat.pi / 10, y: 0, z: 0)
        self.scene?.rootNode.addChildNode(cameraNode)

        // Ambient light for softer shadows
        let ambient = SCNNode()
        ambient.light = SCNLight()
        ambient.light?.type = .ambient
        ambient.light?.intensity = 400
        ambient.light?.color = NSColor(white: 0.9, alpha: 1)
        self.scene?.rootNode.addChildNode(ambient)

        // Load the USDZ model
        if let url = Bundle.main.url(forResource: "mouse", withExtension: "usdz"),
           let referenceNode = SCNReferenceNode(url: url) {
            referenceNode.load()

            // Scale down to a reasonable size – the raw model is ~15 units wide
            // We want it to fit nicely; 0.25 makes it ~3.5 units wide
            referenceNode.scale = SCNVector3(0.25, 0.25, 0.25)

            // Center the model
            let (min, max) = referenceNode.boundingBox
            let cx = (min.x + max.x) / 2
            let cy = (min.y + max.y) / 2
            let cz = (min.z + max.z) / 2
            referenceNode.pivot = SCNMatrix4MakeTranslation(cx, cy, cz)

            self.scene?.rootNode.addChildNode(referenceNode)
            self.modelNode = referenceNode

            // Cache the original materials for each geometry node
            cacheOriginalMaterials(referenceNode)

            // Slow rotation
            let rotate = SCNAction.rotateBy(x: 0, y: CGFloat.pi * 2, z: 0, duration: 30)
            referenceNode.runAction(SCNAction.repeatForever(rotate))
        } else {
            // Fallback
            let box = SCNBox(width: 3, height: 1.2, length: 5, chamferRadius: 0.5)
            let mat = SCNMaterial()
            mat.diffuse.contents = NSColor.darkGray
            box.materials = [mat]
            let node = SCNNode(geometry: box)
            self.scene?.rootNode.addChildNode(node)
            self.modelNode = node
        }
    }

    private func cacheOriginalMaterials(_ node: SCNNode) {
        if let geo = node.geometry, let name = node.name {
            originalMaterials[name] = geo.materials.map { $0.copy() as! SCNMaterial }
        }
        for child in node.childNodes {
            cacheOriginalMaterials(child)
        }
    }

    private func findNode(named name: String, in node: SCNNode) -> SCNNode? {
        if node.name == name && node.geometry != nil { return node }
        for child in node.childNodes {
            if let found = findNode(named: name, in: child) { return found }
        }
        return nil
    }

    private func resetAllMaterials() {
        guard let model = modelNode else { return }
        for (name, materials) in originalMaterials {
            if let node = findNode(named: name, in: model) {
                node.geometry?.materials = materials.map { $0.copy() as! SCNMaterial }
            }
        }
    }

    private func highlightPart() {
        SCNTransaction.begin()
        SCNTransaction.animationDuration = 0.35

        // Reset everything first
        resetAllMaterials()

        guard let button = highlightedButton,
              let meshNames = buttonToMeshes[button],
              let model = modelNode else {
            SCNTransaction.commit()
            return
        }

        // Highlight the target meshes
        let highlightColor = NSColor.systemOrange
        for meshName in meshNames {
            if let node = findNode(named: meshName, in: model) {
                for material in node.geometry?.materials ?? [] {
                    material.emission.contents = highlightColor
                    material.emission.intensity = 0.6
                }
            }
        }

        SCNTransaction.commit()

        // Pulse animation on the model
        guard let model = modelNode else { return }
        let pulse = SCNAction.sequence([
            SCNAction.scale(to: 0.27, duration: 0.1),
            SCNAction.scale(to: 0.25, duration: 0.25)
        ])
        model.runAction(pulse)
    }
}

final class VisualConfigWindowController: NSWindowController, NSWindowDelegate {
    private let diagram = MouseSceneView(frame: .zero)
    private let detectedLabel = NSTextField(wrappingLabelWithString: L10n.string("visual.detection.waiting"))
    private let deviceLabel = NSTextField(labelWithString: L10n.string("device.searchingReceiver"))
    private let dpiSlider = NSSlider(value: 1_600, minValue: 100, maxValue: 25_600, target: nil, action: nil)
    private let dpiField = NSTextField(string: "1600")
    private let dpiPreset = NSPopUpButton(frame: .zero, pullsDown: false)
    private let dpiPersist = NSButton(checkboxWithTitle: L10n.string("dpi.persist"), target: nil, action: nil)
    private let dpiApply = NSButton(title: L10n.string("dpi.apply"), target: nil, action: nil)
    private let dpiStatus = NSTextField(labelWithString: L10n.string("dpi.readingCurrent"))
    private var popups: [Int: NSPopUpButton] = [:]
    private let swipePopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let swipeDistanceSlider = NSSlider(
        value: DesktopSwipeGesture.defaultActivationDistance,
        minValue: DesktopSwipeGesture.activationDistanceRange.lowerBound,
        maxValue: DesktopSwipeGesture.activationDistanceRange.upperBound,
        target: nil,
        action: nil
    )
    private let swipeDistanceValue = NSTextField(labelWithString: "")
    private let pollingPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let pollingStatus = NSTextField(labelWithString: "")
    private static let pollingRates = [125, 250, 500, 1000]
    private var currentPollingRate: Int?
    private let swipeReverse = NSButton(checkboxWithTitle: L10n.string("swipe.reverse"), target: nil, action: nil)
    private var displayedDeviceName: String?
    private var displayedDeviceConnected = false
    private var displayedBattery: String?

    private let getMappings: () -> [Int: Action]
    private let setMapping: (Int, Action) -> Void
    private let startCalibration: (Int) -> Void
    private let getDesktopSwipeButton: () -> Int?
    private let setDesktopSwipeButton: (Int?) -> Void
    private let getDesktopSwipeReversed: () -> Bool
    private let setDesktopSwipeReversed: (Bool) -> Void
    private let getDesktopSwipeDistance: () -> Double
    private let setDesktopSwipeDistance: (Double) -> Void
    private let readPollingRate: (@escaping (Result<Int, Error>) -> Void) -> Void
    private let setPollingRate: (Int, @escaping (Result<Int, Error>) -> Void) -> Void
    private let readDPI: (@escaping (Result<Int, Error>) -> Void) -> Void
    private let setDPI: (Int, Bool, @escaping (Result<Int, Error>) -> Void) -> Void

    init(
        getMappings: @escaping () -> [Int: Action],
        setMapping: @escaping (Int, Action) -> Void,
        startCalibration: @escaping (Int) -> Void,
        getDesktopSwipeButton: @escaping () -> Int?,
        setDesktopSwipeButton: @escaping (Int?) -> Void,
        getDesktopSwipeReversed: @escaping () -> Bool,
        setDesktopSwipeReversed: @escaping (Bool) -> Void,
        getDesktopSwipeDistance: @escaping () -> Double,
        setDesktopSwipeDistance: @escaping (Double) -> Void,
        readPollingRate: @escaping (@escaping (Result<Int, Error>) -> Void) -> Void,
        setPollingRate: @escaping (Int, @escaping (Result<Int, Error>) -> Void) -> Void,
        readDPI: @escaping (@escaping (Result<Int, Error>) -> Void) -> Void,
        setDPI: @escaping (Int, Bool, @escaping (Result<Int, Error>) -> Void) -> Void
    ) {
        self.getMappings = getMappings
        self.setMapping = setMapping
        self.startCalibration = startCalibration
        self.getDesktopSwipeButton = getDesktopSwipeButton
        self.setDesktopSwipeButton = setDesktopSwipeButton
        self.getDesktopSwipeReversed = getDesktopSwipeReversed
        self.setDesktopSwipeReversed = setDesktopSwipeReversed
        self.getDesktopSwipeDistance = getDesktopSwipeDistance
        self.setDesktopSwipeDistance = setDesktopSwipeDistance
        self.readPollingRate = readPollingRate
        self.setPollingRate = setPollingRate
        self.readDPI = readDPI
        self.setDPI = setDPI

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1024, height: 780),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = L10n.string("visual.window.title")
        window.minSize = NSSize(width: 960, height: 740)
        window.collectionBehavior.insert(.fullScreenPrimary)
        window.isRestorable = false
        window.setFrameAutosaveName("G502StageMouse.VisualConfiguration")
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true

        let visualEffect = NSVisualEffectView()
        visualEffect.material = .underWindowBackground
        visualEffect.blendingMode = .behindWindow
        visualEffect.state = .active
        window.contentView = visualEffect

        super.init(window: window)
        window.delegate = self
        buildInterface()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func configureCard(_ view: NSVisualEffectView, radius: CGFloat = 14) {
        view.wantsLayer = true
        view.material = .hudWindow
        view.blendingMode = .withinWindow
        view.state = .active
        view.layer?.cornerRadius = radius
        view.layer?.masksToBounds = true
        view.layer?.borderWidth = 1
        view.layer?.borderColor = NSColor.white.withAlphaComponent(0.1).cgColor
    }

    private func setDetectionState(_ message: String, color: NSColor, highlightedButton: Int? = nil) {
        detectedLabel.stringValue = message
        detectedLabel.textColor = color
        diagram.highlightedButton = highlightedButton
    }

    private func buildInterface() {
        guard let content = window?.contentView else { return }

        diagram.translatesAutoresizingMaskIntoConstraints = false
        diagram.mappings = getMappings()
        content.addSubview(diagram)

        let sidebarCard = NSVisualEffectView()
        configureCard(sidebarCard, radius: 20)
        sidebarCard.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(sidebarCard)

        // ⚙️ Settings button
        let settingsButton = NSButton(frame: .zero)
        settingsButton.bezelStyle = .regularSquare
        settingsButton.isBordered = false
        settingsButton.image = NSImage(systemSymbolName: "gearshape.fill", accessibilityDescription: L10n.string("visual.settings"))
        settingsButton.contentTintColor = .secondaryLabelColor
        settingsButton.translatesAutoresizingMaskIntoConstraints = false
        settingsButton.target = self
        settingsButton.action = #selector(openSettings(_:))
        content.addSubview(settingsButton)

        NSLayoutConstraint.activate([
            // 3D view takes the left ~60%
            diagram.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            diagram.trailingAnchor.constraint(equalTo: sidebarCard.leadingAnchor, constant: -16),
            diagram.topAnchor.constraint(equalTo: content.topAnchor),
            diagram.bottomAnchor.constraint(equalTo: content.bottomAnchor),

            // Sidebar on the right, 360pt wide
            sidebarCard.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),
            sidebarCard.topAnchor.constraint(equalTo: content.topAnchor, constant: 40),
            sidebarCard.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -40),
            sidebarCard.widthAnchor.constraint(equalToConstant: 360),

            settingsButton.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -24),
            settingsButton.topAnchor.constraint(equalTo: content.topAnchor, constant: 12),
            settingsButton.widthAnchor.constraint(equalToConstant: 28),
            settingsButton.heightAnchor.constraint(equalToConstant: 28)
        ])

        // ── Sidebar content ──

        let heading = NSTextField(labelWithString: L10n.string("visual.heading"))
        heading.font = .systemFont(ofSize: 22, weight: .bold)
        heading.alignment = .center

        let subheading = NSTextField(wrappingLabelWithString: L10n.string("visual.instruction"))
        subheading.font = .systemFont(ofSize: 12)
        subheading.textColor = .secondaryLabelColor
        subheading.alignment = .center

        // Compact status card (connection + detection)
        let statusCard = NSVisualEffectView()
        configureCard(statusCard, radius: 10)
        statusCard.translatesAutoresizingMaskIntoConstraints = false
        statusCard.heightAnchor.constraint(greaterThanOrEqualToConstant: 48).isActive = true

        deviceLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        deviceLabel.textColor = .labelColor
        deviceLabel.alignment = .center
        detectedLabel.font = .systemFont(ofSize: 11)
        detectedLabel.textColor = .secondaryLabelColor
        detectedLabel.alignment = .center
        detectedLabel.maximumNumberOfLines = 2

        let statusStack = NSStackView(views: [deviceLabel, detectedLabel])
        statusStack.orientation = .vertical
        statusStack.alignment = .centerX
        statusStack.spacing = 3
        statusStack.translatesAutoresizingMaskIntoConstraints = false
        statusCard.addSubview(statusStack)

        NSLayoutConstraint.activate([
            statusStack.leadingAnchor.constraint(equalTo: statusCard.leadingAnchor, constant: 12),
            statusStack.trailingAnchor.constraint(equalTo: statusCard.trailingAnchor, constant: -12),
            statusStack.centerYAnchor.constraint(equalTo: statusCard.centerYAnchor)
        ])

        // ── DPI Card ──

        let dpiCard = NSVisualEffectView()
        configureCard(dpiCard, radius: 10)
        dpiCard.translatesAutoresizingMaskIntoConstraints = false
        dpiCard.heightAnchor.constraint(equalToConstant: 144).isActive = true

        let dpiTitle = NSTextField(labelWithString: L10n.string("dpi.title"))
        dpiTitle.font = .systemFont(ofSize: 13, weight: .semibold)
        dpiStatus.font = .systemFont(ofSize: 11)
        dpiStatus.textColor = .secondaryLabelColor
        dpiStatus.lineBreakMode = .byTruncatingTail

        let formatter = NumberFormatter()
        formatter.allowsFloats = false
        formatter.minimum = 100
        formatter.maximum = 25_600
        dpiField.formatter = formatter
        dpiField.alignment = .right
        dpiField.controlSize = .small
        dpiField.target = self
        dpiField.action = #selector(dpiFieldChanged(_:))
        dpiField.widthAnchor.constraint(equalToConstant: 54).isActive = true

        dpiSlider.numberOfTickMarks = 0
        dpiSlider.isContinuous = true
        dpiSlider.target = self
        dpiSlider.action = #selector(dpiSliderChanged(_:))

        let dpiUnit = NSTextField(labelWithString: "DPI")
        dpiUnit.font = .systemFont(ofSize: 11, weight: .medium)
        dpiUnit.textColor = .secondaryLabelColor

        let dpiHeader = NSStackView(views: [dpiTitle, NSView(), dpiField, dpiUnit])
        dpiHeader.orientation = .horizontal
        dpiHeader.alignment = .centerY
        dpiHeader.spacing = 6

        let minimum = NSTextField(labelWithString: "100")
        let maximum = NSTextField(labelWithString: "25k")
        for label in [minimum, maximum] {
            label.font = .monospacedDigitSystemFont(ofSize: 9, weight: .regular)
            label.textColor = .tertiaryLabelColor
        }
        let dpiRange = NSStackView(views: [minimum, dpiSlider, maximum])
        dpiRange.orientation = .horizontal
        dpiRange.alignment = .centerY
        dpiRange.spacing = 7

        dpiPreset.addItem(withTitle: L10n.string("dpi.preset"))
        for value in [400, 800, 1_200, 1_600, 3_200, 6_400] {
            dpiPreset.addItem(withTitle: "\(value)")
            dpiPreset.lastItem?.representedObject = value
        }
        dpiPreset.controlSize = .small
        dpiPreset.target = self
        dpiPreset.action = #selector(dpiPresetChanged(_:))

        dpiPersist.controlSize = .small
        dpiPersist.state = .on

        dpiApply.controlSize = .small
        dpiApply.bezelStyle = .rounded
        dpiApply.target = self
        dpiApply.action = #selector(applyDPI(_:))

        let dpiActionButtons = NSStackView(views: [dpiPreset, NSView(), dpiApply])
        dpiActionButtons.orientation = .horizontal
        dpiActionButtons.alignment = .centerY
        dpiActionButtons.spacing = 4

        let dpiActions = NSStackView(views: [dpiActionButtons, dpiPersist])
        dpiActions.orientation = .vertical
        dpiActions.alignment = .width
        dpiActions.spacing = 2

        let dpiStack = NSStackView(views: [dpiHeader, dpiRange, dpiActions, dpiStatus])
        dpiStack.orientation = .vertical
        dpiStack.alignment = .width
        dpiStack.spacing = 6
        dpiStack.translatesAutoresizingMaskIntoConstraints = false
        dpiCard.addSubview(dpiStack)

        NSLayoutConstraint.activate([
            dpiStack.leadingAnchor.constraint(equalTo: dpiCard.leadingAnchor, constant: 12),
            dpiStack.trailingAnchor.constraint(equalTo: dpiCard.trailingAnchor, constant: -12),
            dpiStack.topAnchor.constraint(equalTo: dpiCard.topAnchor, constant: 9),
            dpiStack.bottomAnchor.constraint(equalTo: dpiCard.bottomAnchor, constant: -9)
        ])

        // ── Main Stack ──

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .width
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false

        stack.addArrangedSubview(heading)
        stack.addArrangedSubview(subheading)
        stack.setCustomSpacing(14, after: subheading)
        stack.addArrangedSubview(statusCard)
        stack.setCustomSpacing(14, after: statusCard)

        // ── Button mapping rows (the main content) ──

        let physicalNameKeys: [Int: String] = [
            3: "visual.button.g3", 4: "visual.button.g4", 5: "visual.button.g5",
            6: "visual.button.g6", 7: "visual.button.g7", 8: "visual.button.g8", 9: "visual.button.g9"
        ]

        for button in 3...9 {
            let row = NSStackView()
            row.orientation = .horizontal
            row.alignment = .centerY
            row.spacing = 6
            row.edgeInsets = NSEdgeInsets(top: 4, left: 8, bottom: 4, right: 6)
            row.wantsLayer = true
            row.layer?.cornerRadius = 7
            if button.isMultiple(of: 2) {
                row.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.05).cgColor
            }
            row.heightAnchor.constraint(equalToConstant: 32).isActive = true

            let physicalName = physicalNameKeys[button].map { L10n.string($0) }
                ?? L10n.format("visual.button.generic", button)
            let label = NSTextField(labelWithString: physicalName)
            label.font = .systemFont(ofSize: 12, weight: .medium)
            label.widthAnchor.constraint(equalToConstant: 88).isActive = true

            let popup = NSPopUpButton(frame: .zero, pullsDown: false)
            popup.controlSize = .small
            for action in Action.allCases {
                popup.addItem(withTitle: action.title)
                popup.lastItem?.representedObject = action.rawValue
            }
            popup.target = self
            popup.action = #selector(actionChanged(_:))
            popup.tag = button
            if let action = getMappings()[button], let index = Action.allCases.firstIndex(of: action) {
                popup.selectItem(at: index)
            }
            popups[button] = popup

            // Small link icon instead of "Associer" button
            let associate = NSButton(frame: .zero)
            associate.bezelStyle = .regularSquare
            associate.isBordered = false
            associate.image = NSImage(systemSymbolName: "link", accessibilityDescription: L10n.string("visual.associate"))
            associate.contentTintColor = .tertiaryLabelColor
            associate.target = self
            associate.action = #selector(calibrateButton(_:))
            associate.tag = button
            associate.widthAnchor.constraint(equalToConstant: 20).isActive = true
            associate.heightAnchor.constraint(equalToConstant: 20).isActive = true

            row.addArrangedSubview(label)
            row.addArrangedSubview(popup)
            row.addArrangedSubview(NSView()) // flexible spacer
            row.addArrangedSubview(associate)
            stack.addArrangedSubview(row)
        }

        stack.setCustomSpacing(14, after: stack.arrangedSubviews.last!)

        let swipeTitle = NSTextField(labelWithString: L10n.string("swipe.title"))
        swipeTitle.font = .systemFont(ofSize: 13, weight: .semibold)
        swipePopup.controlSize = .small
        swipePopup.addItem(withTitle: L10n.string("swipe.off"))
        for button in 4...9 {
            swipePopup.addItem(withTitle: L10n.string("visual.button.g\(button)"))
            swipePopup.lastItem?.tag = button
        }
        swipePopup.itemArray.first?.tag = 0
        swipePopup.selectItem(withTag: getDesktopSwipeButton() ?? 0)
        swipePopup.target = self
        swipePopup.action = #selector(swipeButtonChanged(_:))
        let swipeHeader = NSStackView(views: [swipeTitle, NSView(), swipePopup])
        swipeHeader.orientation = .horizontal
        swipeHeader.alignment = .centerY
        swipeHeader.spacing = 6
        let swipeHelp = NSTextField(wrappingLabelWithString: L10n.string("swipe.help"))
        swipeHelp.font = .systemFont(ofSize: 11)
        swipeHelp.textColor = .secondaryLabelColor
        swipeHelp.maximumNumberOfLines = 0
        swipeDistanceSlider.controlSize = .small
        swipeDistanceSlider.doubleValue = getDesktopSwipeDistance()
        swipeDistanceSlider.target = self
        swipeDistanceSlider.action = #selector(swipeDistanceChanged(_:))
        swipeDistanceValue.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        swipeDistanceValue.textColor = .secondaryLabelColor
        swipeDistanceValue.setContentHuggingPriority(.required, for: .horizontal)
        let swipeDistanceLabel = NSTextField(labelWithString: L10n.string("swipe.distance"))
        swipeDistanceLabel.font = .systemFont(ofSize: 11)
        swipeDistanceLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        let swipeDistanceRow = NSStackView(views: [swipeDistanceLabel, swipeDistanceSlider, swipeDistanceValue])
        swipeDistanceRow.orientation = .horizontal
        swipeDistanceRow.alignment = .centerY
        swipeDistanceRow.spacing = 8
        updateSwipeDistanceLabel()
        swipeReverse.controlSize = .small
        swipeReverse.state = getDesktopSwipeReversed() ? .on : .off
        swipeReverse.target = self
        swipeReverse.action = #selector(swipeReverseChanged(_:))
        let swipeStack = NSStackView(views: [swipeHeader, swipeHelp, swipeDistanceRow, swipeReverse])
        swipeStack.orientation = .vertical
        swipeStack.alignment = .width
        swipeStack.spacing = 4
        stack.addArrangedSubview(swipeStack)
        swipeStack.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        stack.setCustomSpacing(14, after: swipeStack)

        let pollingTitle = NSTextField(labelWithString: L10n.string("polling.title"))
        pollingTitle.font = .systemFont(ofSize: 13, weight: .semibold)
        pollingPopup.controlSize = .small
        for rate in Self.pollingRates {
            pollingPopup.addItem(withTitle: L10n.format("polling.value", rate))
            pollingPopup.lastItem?.tag = rate
        }
        pollingPopup.isEnabled = false
        pollingPopup.target = self
        pollingPopup.action = #selector(pollingRateChanged(_:))
        pollingStatus.font = .systemFont(ofSize: 11)
        pollingStatus.textColor = .secondaryLabelColor
        pollingStatus.lineBreakMode = .byTruncatingTail
        let pollingHeader = NSStackView(views: [pollingTitle, NSView(), pollingPopup])
        pollingHeader.orientation = .horizontal
        pollingHeader.alignment = .centerY
        pollingHeader.spacing = 6
        let pollingHelp = NSTextField(wrappingLabelWithString: L10n.string("polling.help"))
        pollingHelp.font = .systemFont(ofSize: 11)
        pollingHelp.textColor = .secondaryLabelColor
        pollingHelp.maximumNumberOfLines = 0
        let pollingStack = NSStackView(views: [pollingHeader, pollingHelp, pollingStatus])
        pollingStack.orientation = .vertical
        pollingStack.alignment = .width
        pollingStack.spacing = 4
        stack.addArrangedSubview(pollingStack)
        pollingStack.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        stack.setCustomSpacing(14, after: pollingStack)

        stack.addArrangedSubview(dpiCard)
        dpiCard.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true

        // ── Scroll view ──

        let scroll = NSScrollView()
        scroll.documentView = stack
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.translatesAutoresizingMaskIntoConstraints = false
        sidebarCard.addSubview(scroll)

        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: sidebarCard.leadingAnchor, constant: 20),
            scroll.trailingAnchor.constraint(equalTo: sidebarCard.trailingAnchor, constant: -20),
            scroll.topAnchor.constraint(equalTo: sidebarCard.topAnchor, constant: 24),
            scroll.bottomAnchor.constraint(equalTo: sidebarCard.bottomAnchor, constant: -24),
            stack.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor)
        ])
    }

    @objc private func openSettings(_ sender: NSButton) {
        let popover = NSPopover()
        let vc = NSViewController()
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 250, height: 60))

        let message = NSTextField(wrappingLabelWithString: L10n.string("visual.settings.message"))
        message.frame = NSRect(x: 16, y: 12, width: 218, height: 38)
        message.textColor = .secondaryLabelColor
        view.addSubview(message)

        vc.view = view
        popover.contentViewController = vc
        popover.behavior = .transient
        popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .maxY)
    }

    @objc private func actionChanged(_ sender: NSPopUpButton) {
        guard let raw = sender.selectedItem?.representedObject as? String,
              let action = Action(rawValue: raw) else { return }
        setMapping(sender.tag, action)
        diagram.mappings = getMappings()
        setDetectionState(L10n.format("visual.detection.action", sender.tag, action.title), color: action.blocksNativeInput ? .systemGreen : .secondaryLabelColor, highlightedButton: sender.tag)
    }

    @objc private func calibrateButton(_ sender: NSButton) {
        setDetectionState(L10n.format("calibration.waiting", sender.tag), color: .systemOrange)
        startCalibration(sender.tag)
    }

    private func normalizedDPI(_ value: Int) -> Int { max(100, min(25_600, 100 + Int(round(Double(value - 100) / 50.0)) * 50)) }
    private func updateDPIControls(_ value: Int) {
        let normalized = normalizedDPI(value)
        dpiSlider.doubleValue = Double(normalized)
        dpiField.integerValue = normalized
    }

    @objc private func dpiSliderChanged(_ sender: NSSlider) { updateDPIControls(Int(sender.doubleValue)); dpiStatus.stringValue = L10n.string("dpi.ready") }
    @objc private func dpiFieldChanged(_ sender: NSTextField) { updateDPIControls(sender.integerValue); dpiStatus.stringValue = L10n.string("dpi.ready") }
    @objc private func dpiPresetChanged(_ sender: NSPopUpButton) {
        guard let value = sender.selectedItem?.representedObject as? Int else { return }
        updateDPIControls(value); dpiStatus.stringValue = L10n.string("dpi.ready")
    }

    @objc private func applyDPI(_ sender: NSButton) {
        let value = normalizedDPI(dpiField.integerValue)
        updateDPIControls(value)
        dpiApply.isEnabled = false; dpiSlider.isEnabled = false
        dpiStatus.stringValue = L10n.string("dpi.applying"); dpiStatus.textColor = .systemOrange
        setDPI(value, dpiPersist.state == .on) { [weak self] result in
            guard let self else { return }
            self.dpiApply.isEnabled = true; self.dpiSlider.isEnabled = true
            switch result {
            case .success(let applied):
                self.updateDPIControls(applied); self.dpiStatus.stringValue = L10n.format("dpi.applied", applied); self.dpiStatus.textColor = .systemGreen
            case .failure(let error):
                self.dpiStatus.stringValue = L10n.string("dpi.failed"); self.dpiStatus.textColor = .systemRed
                let alert = NSAlert(); alert.messageText = L10n.string("dpi.error.title"); alert.informativeText = error.localizedDescription; alert.runModal()
            }
        }
    }

    private func refreshPollingRate() {
        pollingPopup.isEnabled = false
        pollingStatus.stringValue = L10n.string("polling.reading")
        pollingStatus.textColor = .secondaryLabelColor
        readPollingRate { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let rate):
                self.showPollingRate(rate)
                self.pollingStatus.stringValue = ""
                self.pollingPopup.isEnabled = true
            case .failure:
                self.pollingStatus.stringValue = L10n.string("polling.unavailable")
                self.pollingStatus.textColor = .systemRed
            }
        }
    }

    private func showPollingRate(_ rate: Int) {
        currentPollingRate = rate
        pollingPopup.selectItem(withTag: rate)
    }

    @objc private func pollingRateChanged(_ sender: NSPopUpButton) {
        let rate = sender.selectedItem?.tag ?? 0
        guard rate != 0 else { return }
        sender.isEnabled = false
        pollingStatus.stringValue = L10n.string("dpi.applying")
        pollingStatus.textColor = .systemOrange
        setPollingRate(rate) { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let applied):
                self.showPollingRate(applied)
                self.pollingStatus.stringValue = L10n.format("polling.applied", applied)
                self.pollingStatus.textColor = .systemGreen
            case .failure:
                if let previous = self.currentPollingRate { self.showPollingRate(previous) }
                self.pollingStatus.stringValue = L10n.string("polling.failed")
                self.pollingStatus.textColor = .systemRed
            }
            self.pollingPopup.isEnabled = true
        }
    }

    private func refreshDPI() {
        dpiApply.isEnabled = false; dpiStatus.stringValue = L10n.string("dpi.reading")
        readDPI { [weak self] result in
            guard let self else { return }
            self.dpiApply.isEnabled = true
            switch result {
            case .success(let dpi):
                self.updateDPIControls(dpi); self.dpiStatus.stringValue = L10n.format("dpi.current", dpi); self.dpiStatus.textColor = .systemGreen
            case .failure:
                self.dpiStatus.stringValue = L10n.string("dpi.unavailable"); self.dpiStatus.textColor = .systemRed
            }
            self.refreshPollingRate()
        }
    }

    func showAndFocus() {
        diagram.mappings = getMappings()
        diagram.scene?.isPaused = false
        diagram.isPlaying = true
        showWindow(nil); window?.center(); window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        refreshDPI()
    }

    func windowWillClose(_ notification: Notification) {
        diagram.isPlaying = false
        diagram.scene?.isPaused = true
    }

    func highlight(button: Int) {
        let action = getMappings()[button] ?? .systemDefault
        let desc = action.title
        setDetectionState(L10n.format("visual.detection.detected", button, desc), color: .systemGreen, highlightedButton: button)
        popups[button]?.becomeFirstResponder()
    }

    func showCalibration(index: Int, button: Int) {
        setDetectionState(L10n.format("calibration.assigned", button, index), color: .systemGreen, highlightedButton: button)
    }

    func updateDevice(name: String?, connected: Bool) {
        displayedDeviceName = name
        displayedDeviceConnected = connected
        if !connected { displayedBattery = nil }
        refreshDeviceLabel()
    }

    private func updateSwipeDistanceLabel() {
        swipeDistanceValue.stringValue = L10n.format(
            "swipe.distance.value",
            Int(swipeDistanceSlider.doubleValue.rounded())
        )
    }

    @objc private func swipeReverseChanged(_ sender: NSButton) {
        setDesktopSwipeReversed(sender.state == .on)
    }

    @objc private func swipeDistanceChanged(_ sender: NSSlider) {
        sender.doubleValue = (sender.doubleValue / 10).rounded() * 10
        updateSwipeDistanceLabel()
        setDesktopSwipeDistance(sender.doubleValue)
    }

    @objc private func swipeButtonChanged(_ sender: NSPopUpButton) {
        let tag = sender.selectedItem?.tag ?? 0
        setDesktopSwipeButton(tag == 0 ? nil : tag)
    }

    func updateBattery(text: String, charging: Bool, available: Bool, showsSymbol: Bool = true) {
        if available {
            let symbol = charging ? "⚡️" : "🔋"
            displayedBattery = showsSymbol ? "\(symbol) \(text)" : text
        } else {
            displayedBattery = nil
        }
        refreshDeviceLabel()
    }

    private func refreshDeviceLabel() {
        guard displayedDeviceConnected else {
            deviceLabel.stringValue = L10n.string("device.receiverMissing")
            deviceLabel.textColor = .systemRed
            return
        }
        let name = displayedDeviceName ?? L10n.string("device.powerplay")
        deviceLabel.stringValue = displayedBattery.map { L10n.format("device.connectedWithBattery", name, $0) }
            ?? L10n.format("device.connected", name)
        deviceLabel.textColor = .labelColor
    }
}
