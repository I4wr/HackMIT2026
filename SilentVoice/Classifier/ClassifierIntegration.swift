import Foundation

/// How Person 4 should call this module once TrueDepth frames arrive.
///
/// ```swift
/// var classifier = DTWClassifier(
///     acceptanceThreshold: 0.75,   // start here for real data
///     minimumScoreGap: 0.05,
///     minimumMotionEnergy: 0.02
/// )
/// classifier.train(samples: storedCalibrationSamples)
///
/// let prediction = classifier.predict(frames: recordedFrames)
/// if prediction.accepted {
///     speechOutput.speak(prediction.label)
/// } else {
///     // Show UNKNOWN + prediction.candidates + prediction.score
/// }
/// ```
///
/// Until the real classifier is trained, use `MockClassifier` in the UI.
enum ClassifierIntegration {
    static let syntheticAcceptance: Float = 0.40
    static let syntheticGap: Float = 0.02
    static let syntheticMotionEnergy: Float = 0.01

    static let realDataAcceptanceHint: Float = 0.75
    static let realDataGapHint: Float = 0.05
    static let realDataMotionEnergyHint: Float = 0.02
}
