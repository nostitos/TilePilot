enum SetupGuideAutomaticPresentationPolicy {
    static func shouldPresent(
        startupGraceElapsed: Bool,
        hasBootstrapSnapshot: Bool,
        hasDoctorSnapshot: Bool,
        hasIncompleteEssentialSteps: Bool,
        dismissedThisSession: Bool
    ) -> Bool {
        startupGraceElapsed
            && hasBootstrapSnapshot
            && hasDoctorSnapshot
            && hasIncompleteEssentialSteps
            && !dismissedThisSession
    }
}
