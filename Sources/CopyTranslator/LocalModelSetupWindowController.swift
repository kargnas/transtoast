import AppKit
import CopyTranslatorCore

@MainActor
final class LocalModelSetupWindowController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate {
    private let settingsStore: SettingsStore
    private let credentialsProvider: CredentialsProvider
    private let translationService: TranslationService
    private let onSettingsChanged: () -> Void

    private let sourceLanguagePopup = NSPopUpButton()
    private let targetLanguagePopup = NSPopUpButton()
    private let tableView = NSTableView()
    private let detailTitleField = NSTextField(labelWithString: "")
    private let detailBodyField = NSTextField(wrappingLabelWithString: "")
    private let detailStatusField = NSTextField(labelWithString: "")
    private let sampleSegment = NSSegmentedControl(labels: LocalModelSampleLength.allCases.map(\.rawValue), trackingMode: .selectOne, target: nil, action: nil)
    private let sampleTextView = NSTextView()
    private let testOutputTextView = NSTextView()
    private let runButton = NSButton()
    private let useButton = NSButton()
    private let addCustomButton = NSButton()
    private let openSettingsButton = NSButton()

    private var rows = LocalModelComparisonData.rows
    private var selectedRowIndex = 0

    init(
        settingsStore: SettingsStore,
        credentialsProvider: CredentialsProvider,
        translationService: TranslationService,
        onSettingsChanged: @escaping () -> Void
    ) {
        self.settingsStore = settingsStore
        self.credentialsProvider = credentialsProvider
        self.translationService = translationService
        self.onSettingsChanged = onSettingsChanged

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1120, height: 760),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Local Model Setup"
        window.minSize = NSSize(width: 820, height: 560)
        window.center()
        super.init(window: window)
        installContentView(in: window)
        refreshControls()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func showWindow(_ sender: Any?) {
        refreshControls()
        super.showWindow(sender)
        window?.makeKeyAndOrderFront(sender)
    }

    private func makeContentView() -> NSView {
        let container = NSView()

        let header = headerView()
        header.translatesAutoresizingMaskIntoConstraints = false
        header.setContentHuggingPriority(.required, for: .vertical)

        let main = mainSplitView()
        main.translatesAutoresizingMaskIntoConstraints = false
        main.setContentHuggingPriority(.defaultLow, for: .horizontal)
        main.setContentHuggingPriority(.defaultLow, for: .vertical)

        let samples = sampleSection()
        samples.translatesAutoresizingMaskIntoConstraints = false
        samples.setContentHuggingPriority(.defaultLow, for: .horizontal)
        samples.setContentHuggingPriority(.defaultLow, for: .vertical)

        let fresh = freshTestSection()
        fresh.translatesAutoresizingMaskIntoConstraints = false
        fresh.setContentHuggingPriority(.defaultLow, for: .horizontal)
        fresh.setContentHuggingPriority(.defaultLow, for: .vertical)

        let footer = footerView()
        footer.translatesAutoresizingMaskIntoConstraints = false
        footer.setContentHuggingPriority(.required, for: .vertical)

        configureTable()

        [header, main, samples, fresh, footer].forEach(container.addSubview)

        let mainPreferredHeight = main.heightAnchor.constraint(equalTo: container.heightAnchor, multiplier: 0.34)
        mainPreferredHeight.priority = .defaultLow
        let samplePreferredHeight = samples.heightAnchor.constraint(equalTo: container.heightAnchor, multiplier: 0.22)
        samplePreferredHeight.priority = .defaultLow
        let freshPreferredHeight = fresh.heightAnchor.constraint(equalTo: container.heightAnchor, multiplier: 0.18)
        freshPreferredHeight.priority = .defaultLow

        NSLayoutConstraint.activate([
            header.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 18),
            header.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -18),
            header.topAnchor.constraint(equalTo: container.topAnchor, constant: 18),
            header.heightAnchor.constraint(equalToConstant: 66),

            main.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 18),
            main.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -18),
            main.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 12),
            main.heightAnchor.constraint(greaterThanOrEqualToConstant: 240),

            samples.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 18),
            samples.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -18),
            samples.topAnchor.constraint(equalTo: main.bottomAnchor, constant: 12),
            samples.heightAnchor.constraint(greaterThanOrEqualToConstant: 130),

            fresh.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 18),
            fresh.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -18),
            fresh.topAnchor.constraint(equalTo: samples.bottomAnchor, constant: 12),
            fresh.heightAnchor.constraint(greaterThanOrEqualToConstant: 100),

            footer.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 18),
            footer.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -18),
            footer.topAnchor.constraint(equalTo: fresh.bottomAnchor, constant: 14),
            footer.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -18),

            mainPreferredHeight,
            samplePreferredHeight,
            freshPreferredHeight
        ])
        return container
    }

    private func installContentView(in window: NSWindow) {
        guard let contentView = window.contentView else {
            window.contentView = makeContentView()
            return
        }

        let setupView = makeContentView()
        setupView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(setupView)
        NSLayoutConstraint.activate([
            setupView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            setupView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            setupView.topAnchor.constraint(equalTo: contentView.topAnchor),
            setupView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
        ])
    }

    private func headerView() -> NSView {
        let header = NSView()

        let titleRow = NSStackView()
        titleRow.orientation = .horizontal
        titleRow.alignment = .centerY
        titleRow.distribution = .fill
        titleRow.translatesAutoresizingMaskIntoConstraints = false

        let title = NSTextField(labelWithString: "Tested Local Models")
        title.alignment = .left
        title.font = .boldSystemFont(ofSize: 18)
        title.setContentHuggingPriority(.required, for: .horizontal)
        title.setContentCompressionResistancePriority(.required, for: .horizontal)
        titleRow.addArrangedSubview(title)
        titleRow.addArrangedSubview(flexibleSpacer())

        let controls = NSStackView()
        controls.orientation = .horizontal
        controls.alignment = .centerY
        controls.distribution = .fill
        controls.spacing = 10
        controls.translatesAutoresizingMaskIntoConstraints = false

        controls.addArrangedSubview(label("Source"))
        configurePopup(sourceLanguagePopup, cases: TranslationLanguage.sourceLanguageNames.map { ($0, $0) })
        sourceLanguagePopup.target = self
        sourceLanguagePopup.action = #selector(languageChanged)
        sourceLanguagePopup.widthAnchor.constraint(greaterThanOrEqualToConstant: 110).isActive = true
        controls.addArrangedSubview(sourceLanguagePopup)

        controls.addArrangedSubview(label("Target"))
        configurePopup(targetLanguagePopup, cases: TranslationLanguage.targetLanguageNames.map { ($0, $0) })
        targetLanguagePopup.target = self
        targetLanguagePopup.action = #selector(languageChanged)
        targetLanguagePopup.widthAnchor.constraint(greaterThanOrEqualToConstant: 110).isActive = true
        controls.addArrangedSubview(targetLanguagePopup)

        runButton.title = "Run Fresh Test"
        runButton.bezelStyle = .rounded
        runButton.target = self
        runButton.action = #selector(runFreshTest)
        runButton.widthAnchor.constraint(equalToConstant: 130).isActive = true
        controls.addArrangedSubview(runButton)

        addCustomButton.title = "Add Custom Model"
        addCustomButton.bezelStyle = .rounded
        addCustomButton.target = self
        addCustomButton.action = #selector(addCustomModel)
        addCustomButton.widthAnchor.constraint(equalToConstant: 145).isActive = true
        controls.addArrangedSubview(addCustomButton)
        controls.addArrangedSubview(flexibleSpacer())

        header.addSubview(titleRow)
        header.addSubview(controls)
        NSLayoutConstraint.activate([
            titleRow.leadingAnchor.constraint(equalTo: header.leadingAnchor),
            titleRow.trailingAnchor.constraint(equalTo: header.trailingAnchor),
            titleRow.topAnchor.constraint(equalTo: header.topAnchor),
            controls.leadingAnchor.constraint(equalTo: header.leadingAnchor),
            controls.trailingAnchor.constraint(equalTo: header.trailingAnchor),
            controls.topAnchor.constraint(equalTo: titleRow.bottomAnchor, constant: 10),
            controls.bottomAnchor.constraint(equalTo: header.bottomAnchor)
        ])
        return header
    }

    private func mainSplitView() -> NSView {
        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.alignment = .height
        stack.distribution = .fill
        stack.spacing = 14
        stack.setContentHuggingPriority(.defaultLow, for: .horizontal)
        stack.setContentHuggingPriority(.defaultLow, for: .vertical)

        let tableScrollView = NSScrollView()
        tableScrollView.borderType = .bezelBorder
        tableScrollView.hasVerticalScroller = true
        tableScrollView.hasHorizontalScroller = true
        tableScrollView.autohidesScrollers = false
        tableScrollView.documentView = tableView
        tableScrollView.translatesAutoresizingMaskIntoConstraints = false
        tableScrollView.heightAnchor.constraint(greaterThanOrEqualToConstant: 240).isActive = true
        tableScrollView.setContentHuggingPriority(.defaultLow, for: .horizontal)
        tableScrollView.setContentHuggingPriority(.defaultLow, for: .vertical)
        tableScrollView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        tableScrollView.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        stack.addArrangedSubview(tableScrollView)

        let detail = detailPanel()
        detail.widthAnchor.constraint(greaterThanOrEqualToConstant: 240).isActive = true
        detail.widthAnchor.constraint(lessThanOrEqualToConstant: 320).isActive = true
        detail.heightAnchor.constraint(greaterThanOrEqualToConstant: 240).isActive = true
        detail.setContentHuggingPriority(.required, for: .horizontal)
        detail.setContentCompressionResistancePriority(.required, for: .horizontal)
        stack.addArrangedSubview(detail)

        return stack
    }

    private func detailPanel() -> NSView {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.edgeInsets = NSEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
        stack.wantsLayer = true
        stack.layer?.borderColor = NSColor.separatorColor.cgColor
        stack.layer?.borderWidth = 1
        stack.layer?.cornerRadius = 6

        let heading = NSTextField(labelWithString: "Current Choice")
        heading.alignment = .left
        heading.font = .boldSystemFont(ofSize: 14)
        stack.addArrangedSubview(heading)

        detailTitleField.font = .boldSystemFont(ofSize: 13)
        detailTitleField.maximumNumberOfLines = 2
        detailTitleField.lineBreakMode = .byWordWrapping
        stack.addArrangedSubview(detailTitleField)

        detailStatusField.font = .systemFont(ofSize: 12, weight: .medium)
        stack.addArrangedSubview(detailStatusField)

        detailBodyField.maximumNumberOfLines = 12
        detailBodyField.lineBreakMode = .byWordWrapping
        detailBodyField.setContentHuggingPriority(.defaultLow, for: .horizontal)
        stack.addArrangedSubview(detailBodyField)

        return stack
    }

    private func sampleSection() -> NSView {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .width
        stack.distribution = .fill
        stack.spacing = 8
        stack.setContentHuggingPriority(.defaultLow, for: .horizontal)
        stack.setContentHuggingPriority(.defaultLow, for: .vertical)

        let titleRow = NSStackView()
        titleRow.orientation = .horizontal
        titleRow.alignment = .centerY
        titleRow.distribution = .fill
        titleRow.spacing = 10
        titleRow.setContentHuggingPriority(.required, for: .vertical)
        let title = NSTextField(labelWithString: "Sample Outputs From Prior Tests")
        title.alignment = .left
        title.font = .boldSystemFont(ofSize: 14)
        titleRow.addArrangedSubview(title)

        sampleSegment.selectedSegment = 0
        sampleSegment.target = self
        sampleSegment.action = #selector(sampleSegmentChanged)
        sampleSegment.widthAnchor.constraint(greaterThanOrEqualToConstant: 220).isActive = true
        titleRow.addArrangedSubview(sampleSegment)
        titleRow.addArrangedSubview(flexibleSpacer())
        stack.addArrangedSubview(titleRow)

        sampleTextView.isEditable = false
        sampleTextView.isSelectable = true
        sampleTextView.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        configureScrollableTextView(sampleTextView)

        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        scroll.documentView = sampleTextView
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 110).isActive = true
        scroll.setContentHuggingPriority(.defaultLow, for: .horizontal)
        scroll.setContentHuggingPriority(.defaultLow, for: .vertical)
        scroll.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        scroll.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        stack.addArrangedSubview(scroll)

        return stack
    }

    private func freshTestSection() -> NSView {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .width
        stack.distribution = .fill
        stack.spacing = 6
        stack.setContentHuggingPriority(.defaultLow, for: .horizontal)
        stack.setContentHuggingPriority(.defaultLow, for: .vertical)

        let titleRow = NSStackView()
        titleRow.orientation = .horizontal
        titleRow.alignment = .centerY
        titleRow.distribution = .fill
        let title = NSTextField(labelWithString: "Fresh Test Output")
        title.alignment = .left
        title.font = .boldSystemFont(ofSize: 14)
        title.setContentHuggingPriority(.required, for: .horizontal)
        titleRow.addArrangedSubview(title)
        titleRow.addArrangedSubview(flexibleSpacer())
        stack.addArrangedSubview(titleRow)

        testOutputTextView.isEditable = false
        testOutputTextView.isSelectable = true
        testOutputTextView.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        configureScrollableTextView(testOutputTextView)
        testOutputTextView.string = "Prior benchmark results are shown above. Run a fresh test only when you want to validate the selected language pair on this Mac."

        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        scroll.documentView = testOutputTextView
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 80).isActive = true
        scroll.setContentHuggingPriority(.defaultLow, for: .horizontal)
        scroll.setContentHuggingPriority(.defaultLow, for: .vertical)
        scroll.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        scroll.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        stack.addArrangedSubview(scroll)

        return stack
    }

    private func footerView() -> NSView {
        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.distribution = .fill
        stack.spacing = 10

        useButton.title = "Use Recommended"
        useButton.bezelStyle = .rounded
        useButton.target = self
        useButton.action = #selector(useSelectedModel)
        useButton.widthAnchor.constraint(equalToConstant: 150).isActive = true
        useButton.setContentHuggingPriority(.required, for: .horizontal)
        stack.addArrangedSubview(useButton)

        openSettingsButton.title = "Open Settings"
        openSettingsButton.bezelStyle = .rounded
        openSettingsButton.target = self
        openSettingsButton.action = #selector(openSettings)
        openSettingsButton.widthAnchor.constraint(equalToConstant: 130).isActive = true
        openSettingsButton.setContentHuggingPriority(.required, for: .horizontal)
        stack.addArrangedSubview(openSettingsButton)
        stack.addArrangedSubview(flexibleSpacer())

        return stack
    }

    private func flexibleSpacer() -> NSView {
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        spacer.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return spacer
    }

    private func configureTable() {
        tableView.dataSource = self
        tableView.delegate = self
        tableView.headerView = NSTableHeaderView()
        tableView.usesAlternatingRowBackgroundColors = true
        tableView.allowsMultipleSelection = false
        tableView.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        tableView.rowHeight = 44
        tableView.autoresizingMask = [.width, .height]

        addColumn(id: "model", title: "Model", width: 160)
        addColumn(id: "runtime", title: "Runtime", width: 95)
        addColumn(id: "quality", title: "Quality", width: 80)
        addColumn(id: "speedMemory", title: "Speed / Memory", width: 140)
        addColumn(id: "coverage", title: "Coverage", width: 115)
        addColumn(id: "status", title: "Status", width: 95)
        addColumn(id: "notes", title: "Notes", width: 155)

        tableView.target = self
        tableView.action = #selector(tableSelectionChanged)
    }

    private func addColumn(id: String, title: String, width: CGFloat) {
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(id))
        column.title = title
        column.width = width
        column.minWidth = width
        column.resizingMask = [.userResizingMask, .autoresizingMask]
        tableView.addTableColumn(column)
    }

    private func configureScrollableTextView(_ textView: NSTextView) {
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true
    }

    private func refreshControls() {
        configurePopup(sourceLanguagePopup, cases: TranslationLanguage.sourceLanguageNames.map { ($0, $0) })
        configurePopup(targetLanguagePopup, cases: TranslationLanguage.targetLanguageNames.map { ($0, $0) })
        select(sourceLanguagePopup, value: settingsStore.settings.sourceLanguage)
        select(targetLanguagePopup, value: settingsStore.settings.targetLanguage)

        if let row = LocalModelComparisonData.row(forLocalModelID: settingsStore.settings.localModelID),
           let index = rows.firstIndex(where: { $0.id == row.id }) {
            selectedRowIndex = index
        } else if let index = rows.firstIndex(where: \.isRecommended) {
            selectedRowIndex = index
        }

        tableView.reloadData()
        tableView.selectRowIndexes(IndexSet(integer: selectedRowIndex), byExtendingSelection: false)
        updateSelectedRow()
    }

    private func configurePopup(_ popup: NSPopUpButton, cases: [(String, String)]) {
        popup.removeAllItems()
        for item in cases {
            popup.addItem(withTitle: item.0)
            popup.lastItem?.representedObject = item.1
        }
    }

    private func select(_ popup: NSPopUpButton, value: String) {
        for item in popup.itemArray where item.representedObject as? String == value {
            popup.select(item)
            return
        }
    }

    private func label(_ text: String) -> NSTextField {
        let field = NSTextField(labelWithString: text)
        field.font = .systemFont(ofSize: 12, weight: .medium)
        return field
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        rows.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let tableColumn else {
            return nil
        }
        let cellID = NSUserInterfaceItemIdentifier("ComparisonCell-\(tableColumn.identifier.rawValue)")
        let field: NSTextField
        if let existing = tableView.makeView(withIdentifier: cellID, owner: self) as? NSTextField {
            field = existing
        } else {
            field = NSTextField(labelWithString: "")
            field.identifier = cellID
            field.lineBreakMode = .byWordWrapping
            field.maximumNumberOfLines = 2
            field.font = .systemFont(ofSize: 12)
        }

        let item = rows[row]
        switch tableColumn.identifier.rawValue {
        case "model":
            field.stringValue = item.isRecommended ? "\(item.model)  Recommended" : item.model
            field.font = .systemFont(ofSize: 12, weight: item.isRecommended ? .semibold : .regular)
        case "runtime":
            field.stringValue = item.runtime
        case "quality":
            field.stringValue = item.quality
        case "speedMemory":
            field.stringValue = item.speedMemory
        case "coverage":
            field.stringValue = item.coverage
        case "status":
            field.stringValue = item.status
        case "notes":
            field.stringValue = item.notes
        default:
            field.stringValue = ""
        }
        return field
    }

    @objc private func tableSelectionChanged() {
        let selected = tableView.selectedRow
        guard rows.indices.contains(selected) else {
            return
        }
        selectedRowIndex = selected
        updateSelectedRow()
    }

    @objc private func sampleSegmentChanged() {
        updateSamplePreview()
    }

    @objc private func languageChanged() {
        testOutputTextView.string = "Prior benchmark results are shown above. Run a fresh test to validate \(selectedSourceLanguageForBenchmark) -> \(selectedTargetLanguage) on this Mac."
    }

    private func updateSelectedRow() {
        let item = rows[selectedRowIndex]
        detailTitleField.stringValue = item.model
        detailStatusField.stringValue = "\(item.status) | \(item.runtime)"
        detailBodyField.stringValue = [item.detail, item.licenseNote].compactMap { $0 }.joined(separator: "\n\n")
        useButton.title = item.isRecommended ? "Use Recommended" : "Use Selected"
        updateSamplePreview()
    }

    private func updateSamplePreview() {
        let item = rows[selectedRowIndex]
        let length = LocalModelSampleLength.allCases[safe: sampleSegment.selectedSegment] ?? .short
        let samples = item.samples[length] ?? []
        if samples.isEmpty {
            sampleTextView.string = "No saved \(length.rawValue.lowercased()) sample output for \(item.model). Run a fresh test to collect current outputs."
            return
        }

        sampleTextView.string = samples.map { sample in
            """
            [\(sample.title)]
            Source: \(sample.source)
            Output: \(sample.translation)
            """
        }.joined(separator: "\n\n")
    }

    private var selectedSourceLanguageForBenchmark: String {
        let selected = sourceLanguagePopup.selectedItem?.representedObject as? String ?? TranslationLanguage.auto
        let normalized = TranslationLanguage.normalizedName(selected)
        if normalized != TranslationLanguage.auto {
            return normalized
        }
        let target = selectedTargetLanguage
        return target == "Korean" ? "English" : "Korean"
    }

    private var selectedTargetLanguage: String {
        TranslationLanguage.normalizedName(targetLanguagePopup.selectedItem?.representedObject as? String ?? "Korean")
    }

    @objc private func runFreshTest() {
        runButton.isEnabled = false
        testOutputTextView.string = "Running fresh local test...\n"
        Task { [weak self] in
            guard let self else {
                return
            }
            await runFreshTestTask()
            runButton.isEnabled = true
        }
    }

    private func runFreshTestTask() async {
        let sourceLanguage = selectedSourceLanguageForBenchmark
        let targetLanguage = selectedTargetLanguage
        let models = candidateModels(sourceLanguage: sourceLanguage, targetLanguage: targetLanguage)
        let samples = TranslationBenchmarkSamples.samples(sourceLanguage: sourceLanguage).prefix(9)
        let credentials = credentialsProvider.credentials()

        guard !models.isEmpty else {
            appendFresh("No runnable bundled model supports \(sourceLanguage) -> \(targetLanguage).\n")
            return
        }

        appendFresh("Language pair: \(sourceLanguage) -> \(targetLanguage)\n")
        appendFresh("Samples: 3 short, 3 medium, 3 long\n\n")

        for model in models {
            appendFresh("## \(model.title)\n")
            appendFresh("\(model.qualityNote)\n\n")

            for sample in samples {
                var settings = settingsStore.settings
                settings.provider = .localHyMT2
                settings.localModelID = model.id
                settings.sourceLanguage = sourceLanguage
                settings.targetLanguage = targetLanguage

                appendFresh("### \(sample.title)\n")
                do {
                    let result = try await translationService.translateText(
                        sample.text,
                        settings: settings,
                        credentials: credentials
                    )
                    appendFresh("\(result.text)\n\n")
                } catch {
                    appendFresh("ERROR: \(error.localizedDescription)\n\n")
                }
            }
        }
    }

    private func candidateModels(sourceLanguage: String, targetLanguage: String) -> [LocalModelSpec] {
        let customModelsPath = settingsStore.settings.customLocalModelsPath
        let benchmarkModels = LocalModelRegistry.benchmarkModels(
            sourceLanguage: sourceLanguage,
            targetLanguage: targetLanguage,
            customModelsPath: customModelsPath
        )
        if !benchmarkModels.isEmpty {
            return benchmarkModels
        }

        let selectedComparison = rows[selectedRowIndex]
        guard let localModelID = selectedComparison.localModelID,
              let selected = LocalModelRegistry.model(id: localModelID, customModelsPath: customModelsPath),
              selected.backendScriptName != nil,
              selected.supports(sourceLanguage: sourceLanguage, targetLanguage: targetLanguage) else {
            return []
        }
        return [selected]
    }

    @objc private func addCustomModel() {
        if settingsStore.settings.customLocalModelsPath == nil {
            settingsStore.settings.customLocalModelsPath = "~/.config/copy-translator/local-models.json"
            onSettingsChanged()
        }
        testOutputTextView.string = """
        Custom model JSON path:
        \(settingsStore.settings.customLocalModelsPath ?? "~/.config/copy-translator/local-models.json")

        Create a template with:
        uv run scripts/local_model_setup.py --write-template

        Then set customBackendPath to a backend that follows docs/local-runtimes.md.
        """
    }

    @objc private func useSelectedModel() {
        let row = rows[selectedRowIndex]
        let modelID = row.localModelID ?? LocalModelRegistry.defaultModelID
        guard LocalModelRegistry.model(id: modelID, customModelsPath: settingsStore.settings.customLocalModelsPath) != nil else {
            testOutputTextView.string = "\(row.model) is not runnable yet. Choose a supported model or add a custom backend."
            return
        }
        settingsStore.settings.localModelID = modelID
        settingsStore.settings.sourceLanguage = sourceLanguagePopup.selectedItem?.representedObject as? String ?? TranslationLanguage.auto
        settingsStore.settings.targetLanguage = selectedTargetLanguage
        settingsStore.settings.hasCompletedLocalModelSelection = true
        onSettingsChanged()
        testOutputTextView.string = "Saved selected model: \(row.model)"
    }

    @objc private func openSettings() {
        settingsStore.settings.hasCompletedLocalModelSelection = true
        onSettingsChanged()
        window?.close()
    }

    private func appendFresh(_ text: String) {
        testOutputTextView.string += text
        testOutputTextView.scrollToEndOfDocument(nil)
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        guard indices.contains(index) else {
            return nil
        }
        return self[index]
    }
}
