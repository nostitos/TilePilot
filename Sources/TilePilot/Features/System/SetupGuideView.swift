import SwiftUI

struct SetupGuideView: View {
    @EnvironmentObject private var model: AppModel

    private var steps: [SetupGuideStep] {
        model.setupGuideSteps
    }

    private var currentStep: SetupGuideStep? {
        model.currentSetupGuideStep
    }

    private var hasRemainingIncompleteSteps: Bool {
        !model.incompleteSetupGuideSteps.isEmpty
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 18) {
                header

                if let step = currentStep {
                    HStack(alignment: .top, spacing: 18) {
                        stepList
                            .frame(width: 220)
                        stepDetail(step)
                    }
                } else {
                    completionState
                }
            }
            .padding(20)
            .frame(minWidth: 860, idealWidth: 940, minHeight: 560)
            .navigationTitle("Guided Setup")
            .confirmationDialog(
                model.helperMigrationPrompt?.title ?? "Existing Helper Install Detected",
                isPresented: Binding(
                    get: { model.helperMigrationPrompt != nil },
                    set: { isPresented in
                        if !isPresented {
                            model.dismissHelperMigrationPrompt()
                        }
                    }
                ),
                titleVisibility: .visible
            ) {
                Button("Use Existing Install") {
                    model.keepExistingHelperInstall()
                }
                Button("Replace With TilePilot Helpers", role: .destructive) {
                    model.replaceWithManagedHelpers()
                }
                Button("Cancel", role: .cancel) {
                    model.dismissHelperMigrationPrompt()
                }
            } message: {
                Text(model.helperMigrationPrompt?.message ?? "")
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(model.setupGuideCompletionTitle)
                .font(.title2.weight(.semibold))
            Text(model.setupGuideCompletionDetail)
                .font(.body)
                .foregroundStyle(.secondary)

            if let error = model.lastErrorMessage {
                statusMessage(text: error, color: .red)
            } else if let message = model.lastActionMessage {
                statusMessage(text: message, color: .green)
            }
        }
    }

    private var stepList: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Steps")
                .font(.headline)

            ForEach(steps) { step in
                Button {
                    model.selectSetupGuideStep(step.kind)
                } label: {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: step.status.symbolName)
                            .foregroundStyle(color(for: step.status))
                            .frame(width: 16)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(step.title)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary)
                                .multilineTextAlignment(.leading)
                            Text(step.category.title)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(selectionBackground(for: step), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func stepDetail(_ step: SetupGuideStep) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Text(step.category.title.uppercased())
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(color(for: step.status))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(color(for: step.status).opacity(0.12), in: Capsule())

                Text(step.status == .good ? "Complete" : "Needs attention")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(step.status == .good ? .green : .secondary)
            }

            Text(step.title)
                .font(.title3.weight(.semibold))

            Text(step.summary)
                .font(.body)
                .foregroundStyle(.primary)

            GroupBox {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Why TilePilot needs this")
                        .font(.headline)
                    Text(step.whyItMatters)
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            GroupBox {
                VStack(alignment: .leading, spacing: 8) {
                    Text("What to do now")
                        .font(.headline)
                    Text(step.whatToDo)
                        .font(.body)
                        .foregroundStyle(.primary)
                    if let detail = step.detail, !detail.isEmpty {
                        Divider()
                        Text(detail)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    if let verificationText = step.verificationText, !verificationText.isEmpty {
                        Divider()
                        Text(verificationText)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Spacer(minLength: 0)

            HStack(spacing: 10) {
                if let primaryAction = step.primaryAction, !step.isSatisfied {
                    Button(primaryButtonLabel(for: step, action: primaryAction)) {
                        model.performSystemCheckAction(primaryAction)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(primaryActionInFlight(for: step))
                } else {
                    Button(hasRemainingIncompleteSteps ? "Continue" : "Done") {
                        if hasRemainingIncompleteSteps {
                            model.continueSetupGuide()
                        } else {
                            model.dismissSetupGuide()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }

                ForEach(secondaryActions(for: step), id: \.self) { action in
                    Button(secondaryButtonLabel(for: action)) {
                        model.performSystemCheckAction(action)
                    }
                    .buttonStyle(.bordered)
                    .disabled(secondaryActionInFlight(action))
                }

                Spacer()

                if step.isSkippable || step.isBlocking {
                    Button("Skip for Now") {
                        model.dismissSetupGuide()
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var completionState: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("TilePilot is ready")
                .font(.title3.weight(.semibold))
            Text("All required setup is complete. You can reopen Guided Setup later from System or the menu bar if you want to review optional permissions again.")
                .font(.body)
                .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                Button("Continue") {
                    model.dismissSetupGuide()
                }
                .buttonStyle(.borderedProminent)

                Button("Review Steps") {
                    if let first = steps.first {
                        model.selectSetupGuideStep(first.kind)
                    }
                }
                .buttonStyle(.bordered)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func selectionBackground(for step: SetupGuideStep) -> some ShapeStyle {
        if currentStep?.kind == step.kind {
            return AnyShapeStyle(Color.accentColor.opacity(0.14))
        }
        return AnyShapeStyle(Color.secondary.opacity(0.08))
    }

    private func statusMessage(text: String, color: Color) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(color)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(color.opacity(0.10), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func color(for status: SystemCheckStatus) -> Color {
        switch status {
        case .good:
            return .green
        case .notice:
            return .yellow
        case .warning:
            return .orange
        case .error:
            return .red
        }
    }

    private func primaryButtonLabel(for step: SetupGuideStep, action: SystemCheckAction) -> String {
        switch (step.kind, action) {
        case (.installHelpers, .installDependencies):
            return "Install TilePilot Helpers"
        case (.startHelperServices, .startYabai), (.startHelperServices, .startSkhd):
            return "Start Helper Services"
        case (.accessibility, .requestAccessibilityAccess):
            return "Request Accessibility Access"
        case (.startAtLogon, .enableStartAtLogon):
            return "Enable Start at Login"
        case (.missionControl, .openMissionControlSettings):
            return "Open Mission Control Settings"
        case (.screenRecording, .requestScreenRecordingAccess):
            return "Enable Screen Recording"
        default:
            return action.label
        }
    }

    private func secondaryButtonLabel(for action: SystemCheckAction) -> String {
        switch action {
        case .openAccessibilitySettings:
            return "Open Accessibility Settings"
        case .openLoginItemsSettings:
            return "Open Login Items"
        case .openMissionControlSettings:
            return "Open Mission Control Settings"
        case .openMissionControlKeyboardShortcuts:
            return "Open Keyboard Shortcuts"
        case .openScreenRecordingSettings:
            return "Open Screen Recording Settings"
        default:
            return action.label
        }
    }

    private func secondaryActions(for step: SetupGuideStep) -> [SystemCheckAction] {
        step.secondaryActions.filter { !(step.isSatisfied && $0 == .recheck) }
    }

    private func primaryActionInFlight(for step: SetupGuideStep) -> Bool {
        switch step.kind {
        case .installHelpers, .startHelperServices:
            return model.isLaunchingSetupInstaller
        case .accessibility, .screenRecording:
            return false
        case .startAtLogon, .missionControl:
            return false
        }
    }

    private func secondaryActionInFlight(_ action: SystemCheckAction) -> Bool {
        switch action {
        case .recheck:
            return model.isRefreshing || model.isRefreshingBootstrap
        case .installDependencies, .startYabai, .startSkhd, .restartYabai, .restartSkhd:
            return model.isLaunchingSetupInstaller
        default:
            return false
        }
    }
}
