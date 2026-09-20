import Foundation

/// Lightweight autocomplete/reranking layer for a closed phrase set.
///
/// This does not try to lip-read arbitrary speech. It combines DTW's visual score
/// with simple phrase priors and recent accepted output, then returns transparent
/// suggestions the UI can show or use for guarded acceptance.
struct PhraseLanguageModel: Sendable {
    var phrases: [String]
    var visualWeight: Float
    var languageWeight: Float
    var minimumVisualScoreForLanguageAcceptance: Float
    var minimumCombinedAcceptance: Float
    var minimumCombinedGap: Float
    var maxVisualPenaltyForRerank: Float

    init(
        phrases: [String],
        visualWeight: Float = 0.72,
        languageWeight: Float = 0.28,
        minimumVisualScoreForLanguageAcceptance: Float = 0.55,
        minimumCombinedAcceptance: Float = 0.70,
        minimumCombinedGap: Float = 0.08,
        maxVisualPenaltyForRerank: Float = 0.12
    ) {
        self.phrases = phrases
        self.visualWeight = visualWeight
        self.languageWeight = languageWeight
        self.minimumVisualScoreForLanguageAcceptance = minimumVisualScoreForLanguageAcceptance
        self.minimumCombinedAcceptance = minimumCombinedAcceptance
        self.minimumCombinedGap = minimumCombinedGap
        self.maxVisualPenaltyForRerank = maxVisualPenaltyForRerank
    }

    func enhance(_ visualPrediction: Prediction, acceptedContext: [String]) -> Prediction {
        let visualCandidates = uniqueVisualCandidates(from: visualPrediction)
        guard !visualCandidates.isEmpty else {
            return Prediction(
                label: visualPrediction.label,
                score: visualPrediction.score,
                accepted: visualPrediction.accepted,
                candidates: visualPrediction.candidates,
                suggestions: nextPhraseSuggestions(acceptedContext: acceptedContext)
            )
        }

        let suggestions = visualCandidates
            .map { candidate in
                suggestion(for: candidate.label, visualScore: candidate.score, acceptedContext: acceptedContext)
            }
            .sorted { lhs, rhs in
                if lhs.combinedScore == rhs.combinedScore {
                    return lhs.visualScore > rhs.visualScore
                }
                return lhs.combinedScore > rhs.combinedScore
            }

        guard let best = suggestions.first else { return visualPrediction }
        let visualBestScore = visualCandidates.map(\.score).max() ?? 0
        let secondCombined = suggestions.dropFirst().first?.combinedScore ?? 0
        let combinedGap = best.combinedScore - secondCombined
        let visuallyPlausible = best.visualScore + maxVisualPenaltyForRerank >= visualBestScore
        let languageCanAccept = best.visualScore >= minimumVisualScoreForLanguageAcceptance
            && best.combinedScore >= minimumCombinedAcceptance
            && combinedGap >= minimumCombinedGap
            && visuallyPlausible

        let accepted: Bool
        let label: String
        let score: Float
        if visualPrediction.accepted {
            accepted = true
            if best.label != visualPrediction.label, visuallyPlausible, combinedGap >= minimumCombinedGap {
                label = best.label
                score = best.combinedScore
            } else {
                label = visualPrediction.label
                score = visualPrediction.score
            }
        } else if languageCanAccept {
            accepted = true
            label = best.label
            score = best.combinedScore
        } else {
            accepted = false
            label = "UNKNOWN"
            score = max(visualPrediction.score, best.combinedScore)
        }

        return Prediction(
            label: label,
            score: score,
            accepted: accepted,
            candidates: reorder(visualPrediction.candidates, by: suggestions),
            suggestions: Array(suggestions.prefix(3))
        )
    }

    func nextWordSuggestions(after words: [String], limit: Int = 3) -> [LanguageSuggestion] {
        let normalizedPrefix = normalize(words)
        var scores: [String: Float] = [:]

        for phrase in phrases {
            let phraseWords = tokenize(phrase)
            guard normalizedPrefix.count < phraseWords.count else { continue }
            guard Array(phraseWords.prefix(normalizedPrefix.count)) == normalizedPrefix else { continue }
            let next = phraseWords[normalizedPrefix.count]
            scores[next, default: 0] += phrasePrior(phrase)
        }

        return scores
            .map { word, languageScore in
                LanguageSuggestion(
                    label: word,
                    visualScore: 0,
                    languageScore: min(1, languageScore),
                    combinedScore: min(1, languageScore)
                )
            }
            .sorted { $0.combinedScore > $1.combinedScore }
            .prefix(limit)
            .map { $0 }
    }

    func nextPhraseSuggestions(acceptedContext: [String], limit: Int = 3) -> [LanguageSuggestion] {
        let ranked = phrases
            .map { phrase in
                suggestion(for: phrase, visualScore: 0, acceptedContext: acceptedContext)
            }
            .sorted { $0.languageScore > $1.languageScore }
        return Array(ranked.prefix(limit))
    }

    private func uniqueVisualCandidates(from prediction: Prediction) -> [Candidate] {
        var seen = Set<String>()
        var result: [Candidate] = []
        for candidate in prediction.candidates {
            let key = candidate.label.lowercased()
            guard !seen.contains(key), candidate.score > 0 else { continue }
            seen.insert(key)
            result.append(candidate)
        }
        if prediction.accepted, !seen.contains(prediction.label.lowercased()) {
            result.append(Candidate(label: prediction.label, distance: 0, score: prediction.score))
        }
        return result
    }

    private func suggestion(for label: String, visualScore: Float, acceptedContext: [String]) -> LanguageSuggestion {
        let languageScore = languageScore(for: label, acceptedContext: acceptedContext)
        let combined = visualWeight * visualScore + languageWeight * languageScore
        return LanguageSuggestion(
            label: label,
            visualScore: visualScore,
            languageScore: languageScore,
            combinedScore: min(1, max(0, combined))
        )
    }

    private func languageScore(for label: String, acceptedContext: [String]) -> Float {
        let prior = phrasePrior(label)
        guard let previous = acceptedContext.last else { return prior }

        let previousWords = tokenize(previous)
        let labelWords = tokenize(label)
        guard !previousWords.isEmpty, !labelWords.isEmpty else { return prior }

        if previousWords == labelWords {
            return min(1, prior + 0.08)
        }
        if previousWords.first == labelWords.first {
            return min(1, prior + 0.12)
        }
        return prior
    }

    private func phrasePrior(_ phrase: String) -> Float {
        guard !phrases.isEmpty else { return 0.5 }
        let normalized = phrase.lowercased()
        if phrases.contains(where: { $0.lowercased() == normalized }) {
            return 0.62
        }
        return 0.40
    }

    private func reorder(_ candidates: [Candidate], by suggestions: [LanguageSuggestion]) -> [Candidate] {
        let rankByLabel = Dictionary(uniqueKeysWithValues: suggestions.enumerated().map { offset, suggestion in
            (suggestion.label.lowercased(), offset)
        })
        return candidates.sorted { lhs, rhs in
            let lhsRank = rankByLabel[lhs.label.lowercased()] ?? Int.max
            let rhsRank = rankByLabel[rhs.label.lowercased()] ?? Int.max
            if lhsRank == rhsRank { return lhs.score > rhs.score }
            return lhsRank < rhsRank
        }
    }

    private func tokenize(_ phrase: String) -> [String] {
        phrase
            .lowercased()
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
    }

    private func normalize(_ words: [String]) -> [String] {
        words.flatMap { tokenize($0) }
    }
}
