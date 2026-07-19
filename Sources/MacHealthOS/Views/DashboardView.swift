import SwiftUI

struct DashboardView: View {
    @Environment(AppModel.self) private var appModel

    private let columns = [
        GridItem(.flexible(minimum: 220), spacing: 16),
        GridItem(.flexible(minimum: 220), spacing: 16),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                statusSection
                storageSection
                performanceSection
                securitySection
                automationSection
                activitySection
                actionsSection
                aiExplanationSection
            }
            .padding(24)
        }
        .frame(minWidth: 860, minHeight: 560)
        .sheet(
            isPresented: Binding(
                get: { appModel.isMaintenanceCenterPresented },
                set: { newValue in
                    if !newValue {
                        appModel.dismissMaintenanceCenter()
                    }
                }
            )
        ) {
            MaintenanceCenterView()
                .environment(appModel)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Mac Health OS")
                .font(.largeTitle.weight(.semibold))
            Text("Native macOS dashboard shell for local Mac health checks.")
                .foregroundStyle(.secondary)
        }
    }

    private var statusSection: some View {
        GroupBox("Current Status") {
            LazyVGrid(columns: columns, alignment: .leading, spacing: 16) {
                StatusCard(title: "Health Score", value: appModel.healthScore, detail: appModel.healthScoreDetail)
                StatusCard(title: "Storage Status", value: appModel.storageStatus, detail: appModel.storageStatusDetail)
                StatusCard(title: "Performance Status", value: appModel.performanceStatus, detail: appModel.performanceStatusDetail)
                StatusCard(title: "Security Status", value: appModel.securityStatus, detail: appModel.securityStatusDetail)
                StatusCard(title: "Automation Status", value: appModel.automationStatus, detail: appModel.automationStatusDetail)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 4)
        }
    }

    private var storageSection: some View {
        StorageDetailsView()
    }

    private var performanceSection: some View {
        PerformanceDetailsView()
    }

    private var securitySection: some View {
        SecurityDetailsView()
    }

    private var automationSection: some View {
        AutomationDetailsView()
    }

    private var activitySection: some View {
        GroupBox("Latest Activity") {
            VStack(alignment: .leading, spacing: 12) {
                LabeledContent("Latest scan timestamp") {
                    Text(appModel.latestScanDisplayText)
                        .monospacedDigit()
                }

                LabeledContent("Status") {
                    Text(appModel.lastStatusMessage)
                        .multilineTextAlignment(.trailing)
                }

                LabeledContent("Latest report") {
                    Text(appModel.latestReportDisplayText)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 4)
        }
    }

    private var actionsSection: some View {
        GroupBox("Actions") {
            LazyVGrid(columns: columns, alignment: .leading, spacing: 12) {
                Button("Analyze My Mac") {
                    appModel.analyzeMyMac()
                }
                .buttonStyle(.borderedProminent)

                Button("Generate Report") {
                    appModel.generateReport(openAfterCreate: true)
                }

                Button(appModel.isExplainingWithAI ? "Explaining with AI…" : "Explain with AI") {
                    appModel.explainWithAI()
                }
                .disabled(appModel.isExplainingWithAI)

                Button("Run Safe Maintenance") {
                    appModel.runSafeMaintenance()
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 4)
        }
    }

    @ViewBuilder
    private var aiExplanationSection: some View {
        if appModel.isExplainingWithAI || appModel.latestAIExplanation != nil {
            GroupBox("AI Explanation") {
                VStack(alignment: .leading, spacing: 12) {
                    if appModel.isExplainingWithAI {
                        ProgressView("Generating AI explanation from the local report…")
                    }

                    if let latestAIExplanation = appModel.latestAIExplanation {
                        LabeledContent("Provider") {
                            Text(latestAIExplanation.provider.displayName)
                        }

                        LabeledContent("Generated") {
                            Text(appModel.latestAIExplanationTimestampText)
                                .monospacedDigit()
                        }

                        Text(appModel.latestAIExplanationDisclaimer)
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        VStack(alignment: .leading, spacing: 14) {
                            ForEach(latestAIExplanation.sections) { section in
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(section.title)
                                        .font(.headline)

                                    if section.items.isEmpty {
                                        Text("None.")
                                            .foregroundStyle(.secondary)
                                    } else {
                                        ForEach(section.items, id: \.self) { item in
                                            Text("• \(item)")
                                                .textSelection(.enabled)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 4)
            }
        }
    }
}

private struct StatusCard: View {
    let title: String
    let value: String
    let detail: String

    init(title: String, value: String, detail: String = "No live diagnostics in this build.") {
        self.title = title
        self.value = value
        self.detail = detail
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
            Text(value)
                .font(.title3.weight(.medium))
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
