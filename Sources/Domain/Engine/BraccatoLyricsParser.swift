//
//  BraccatoLyricsParser.swift
//  LineriOS
//
//  High-performance lyrics parser supporting Standard LRC [mm:ss.xx],
//  Enhanced LRC <mm:ss.xx> word tokens, and Apple Music / TTML syllable spans.
//

import Foundation

public struct BraccatoLyricsParser: Sendable {
    public init() {}

    // MARK: - Public API

    public func parse(
        content: String,
        trackURI: String,
        provider: String = "Parsed"
    ) -> LyricsPayload {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)

        // Check if explicit instrumental track
        if isInstrumental(content: trimmed) {
            return LyricsPayload(
                trackURI: trackURI,
                sourceProvider: provider,
                granularity: .instrumental,
                lines: [],
                plainTextFallback: "Instrumental"
            )
        }

        // Detect TTML format
        if trimmed.hasPrefix("<tt") || trimmed.contains("<tt ") || trimmed.contains("<p begin=") {
            return parseTTML(content: trimmed, trackURI: trackURI, provider: provider)
        }

        // Detect LRC (Standard or Enhanced)
        return parseLRC(content: trimmed, trackURI: trackURI, provider: provider)
    }

    // MARK: - LRC Parser (Standard & Enhanced)

    private func parseLRC(content: String, trackURI: String, provider: String) -> LyricsPayload {
        let lines = content.components(separatedBy: .newlines)
        var parsedLines: [LyricLine] = []
        var isEnhancedLRC = false

        // Regex for [mm:ss.xx] or [mm:ss.xxx] line timestamps
        let lineRegex = try? NSRegularExpression(pattern: #"^\[(\d{1,2}):(\d{2})(?:\.(\d{2,3}))?\](.*)$"#)

        for rawLine in lines {
            let lineStr = rawLine.trimmingCharacters(in: .whitespaces)
            guard !lineStr.isEmpty else { continue }

            // Skip header metadata tags [ti:], [ar:], [al:], etc.
            if lineStr.hasPrefix("[ti:") || lineStr.hasPrefix("[ar:") || lineStr.hasPrefix("[al:") ||
               lineStr.hasPrefix("[by:") || lineStr.hasPrefix("[offset:") {
                continue
            }

            let range = NSRange(lineStr.startIndex..<lineStr.endIndex, in: lineStr)
            guard let match = lineRegex?.firstMatch(in: lineStr, options: [], range: range) else {
                continue
            }

            guard let minRange = Range(match.range(at: 1), in: lineStr),
                  let secRange = Range(match.range(at: 2), in: lineStr),
                  let textRange = Range(match.range(at: 4), in: lineStr) else {
                continue
            }

            let minutes = Int(lineStr[minRange]) ?? 0
            let seconds = Int(lineStr[secRange]) ?? 0
            var millis = 0
            if match.range(at: 3).location != NSNotFound,
               let msRange = Range(match.range(at: 3), in: lineStr) {
                let msStr = String(lineStr[msRange])
                if msStr.count == 2 {
                    millis = (Int(msStr) ?? 0) * 10
                } else {
                    millis = Int(msStr) ?? 0
                }
            }

            let startTimeMs = (minutes * 60 + seconds) * 1000 + millis
            let remainingText = String(lineStr[textRange]).trimmingCharacters(in: .whitespaces)

            // Check for Enhanced LRC inline timestamps <mm:ss.xx>
            if remainingText.contains("<") && remainingText.contains(">") {
                let words = parseEnhancedLRCWords(from: remainingText, lineStartTimeMs: startTimeMs)
                if !words.isEmpty {
                    isEnhancedLRC = true
                    let cleanText = words.map(\.text).joined()
                    let endTimeMs = words.last?.endTimeMs ?? (startTimeMs + 3000)
                    parsedLines.append(LyricLine(
                        startTimeMs: startTimeMs,
                        endTimeMs: endTimeMs,
                        text: cleanText,
                        words: words
                    ))
                    continue
                }
            }

            parsedLines.append(LyricLine(
                startTimeMs: startTimeMs,
                endTimeMs: startTimeMs + 3000, // Will be resolved during post-processing
                text: remainingText,
                words: []
            ))
        }

        // Post-process line end times
        let sortedLines = resolveLineEndTimes(parsedLines)
        let granularity: LyricsSyncGranularity = isEnhancedLRC ? .syllableSynced : (sortedLines.isEmpty ? .plainText : .lineSynced)

        return LyricsPayload(
            trackURI: trackURI,
            sourceProvider: provider,
            granularity: granularity,
            lines: sortedLines,
            plainTextFallback: sortedLines.isEmpty ? content : nil
        )
    }

    private func parseEnhancedLRCWords(from text: String, lineStartTimeMs: Int) -> [LyricWordToken] {
        // Pattern: <mm:ss.xx> word <mm:ss.xx>
        let wordRegex = try? NSRegularExpression(pattern: #"<(\d{1,2}):(\d{2})(?:\.(\d{2,3}))?>([^<]*)"#)
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let matches = wordRegex?.matches(in: text, options: [], range: range), !matches.isEmpty else {
            return []
        }

        var tokens: [LyricWordToken] = []
        for i in 0..<matches.count {
            let match = matches[i]
            guard let minRange = Range(match.range(at: 1), in: text),
                  let secRange = Range(match.range(at: 2), in: text),
                  let wordRange = Range(match.range(at: 4), in: text) else { continue }

            let min = Int(text[minRange]) ?? 0
            let sec = Int(text[secRange]) ?? 0
            var ms = 0
            if match.range(at: 3).location != NSNotFound,
               let msRange = Range(match.range(at: 3), in: text) {
                let msStr = String(text[msRange])
                ms = msStr.count == 2 ? (Int(msStr) ?? 0) * 10 : (Int(msStr) ?? 0)
            }

            let wordStartTime = (min * 60 + sec) * 1000 + ms
            let wordText = String(text[wordRange])

            // Determine word end time
            let wordEndTime: Int
            if i + 1 < matches.count {
                let nextMatch = matches[i + 1]
                let nextMinRange = Range(nextMatch.range(at: 1), in: text)!
                let nextSecRange = Range(nextMatch.range(at: 2), in: text)!
                let nextMin = Int(text[nextMinRange]) ?? 0
                let nextSec = Int(text[nextSecRange]) ?? 0
                var nextMs = 0
                if nextMatch.range(at: 3).location != NSNotFound,
                   let nextMsRange = Range(nextMatch.range(at: 3), in: text) {
                    let nextMsStr = String(text[nextMsRange])
                    nextMs = nextMsStr.count == 2 ? (Int(nextMsStr) ?? 0) * 10 : (Int(nextMsStr) ?? 0)
                }
                wordEndTime = (nextMin * 60 + nextSec) * 1000 + nextMs
            } else {
                wordEndTime = wordStartTime + 800
            }

            tokens.append(LyricWordToken(
                text: wordText,
                startTimeMs: wordStartTime,
                endTimeMs: max(wordEndTime, wordStartTime + 100)
            ))
        }

        return tokens
    }

    // MARK: - TTML Parser

    private func parseTTML(content: String, trackURI: String, provider: String) -> LyricsPayload {
        var lines: [LyricLine] = []

        // Extract <p begin="..." end="..."> tags
        let paragraphPattern = #"<p\s+begin="([^"]+)"\s+end="([^"]+)"[^>]*>(.*?)</p>"#
        guard let pRegex = try? NSRegularExpression(pattern: paragraphPattern, options: [.dotMatchesLineSeparators]) else {
            return parseLRC(content: content, trackURI: trackURI, provider: provider)
        }

        let fullRange = NSRange(content.startIndex..<content.endIndex, in: content)
        let matches = pRegex.matches(in: content, options: [], range: fullRange)

        for match in matches {
            guard let beginRange = Range(match.range(at: 1), in: content),
                  let endRange = Range(match.range(at: 2), in: content),
                  let innerRange = Range(match.range(at: 3), in: content) else { continue }

            let beginMs = parseTimestamp(String(content[beginRange]))
            let endMs = parseTimestamp(String(content[endRange]))
            let innerText = String(content[innerRange])

            // Parse syllable <span> tokens if present
            let words = parseTTMLSpans(innerXML: innerText, defaultStartMs: beginMs)
            let cleanLineText = words.isEmpty ? stripXMLTags(innerText) : words.map(\.text).joined()

            lines.append(LyricLine(
                startTimeMs: beginMs,
                endTimeMs: endMs,
                text: cleanLineText,
                words: words
            ))
        }

        let sorted = lines.sorted { $0.startTimeMs < $1.startTimeMs }
        let hasWords = sorted.contains { !$0.words.isEmpty }

        return LyricsPayload(
            trackURI: trackURI,
            sourceProvider: provider,
            granularity: hasWords ? .syllableSynced : (sorted.isEmpty ? .plainText : .lineSynced),
            lines: sorted,
            plainTextFallback: sorted.isEmpty ? content : nil
        )
    }

    private func parseTTMLSpans(innerXML: String, defaultStartMs: Int) -> [LyricWordToken] {
        let spanPattern = #"<span\s+begin="([^"]+)"\s+end="([^"]+)"[^>]*>(.*?)</span>"#
        guard let spanRegex = try? NSRegularExpression(pattern: spanPattern, options: [.dotMatchesLineSeparators]) else {
            return []
        }

        let range = NSRange(innerXML.startIndex..<innerXML.endIndex, in: innerXML)
        let matches = spanRegex.matches(in: innerXML, options: [], range: range)

        var tokens: [LyricWordToken] = []
        for match in matches {
            guard let bRange = Range(match.range(at: 1), in: innerXML),
                  let eRange = Range(match.range(at: 2), in: innerXML),
                  let tRange = Range(match.range(at: 3), in: innerXML) else { continue }

            let startMs = parseTimestamp(String(innerXML[bRange]))
            let endMs = parseTimestamp(String(innerXML[eRange]))
            let wordText = stripXMLTags(String(innerXML[tRange]))

            tokens.append(LyricWordToken(
                text: wordText,
                startTimeMs: startMs,
                endTimeMs: endMs
            ))
        }

        return tokens
    }

    // MARK: - Post-Processing & Time Resolvers

    private func resolveLineEndTimes(_ lines: [LyricLine]) -> [LyricLine] {
        let sorted = lines.sorted { $0.startTimeMs < $1.startTimeMs }
        var result: [LyricLine] = []

        for i in 0..<sorted.count {
            let current = sorted[i]
            let resolvedEndMs: Int
            if !current.words.isEmpty, let lastWord = current.words.last {
                resolvedEndMs = lastWord.endTimeMs
            } else if i + 1 < sorted.count {
                // Line ends when the next line begins (or at maximum 8s)
                let nextStart = sorted[i + 1].startTimeMs
                resolvedEndMs = min(nextStart, current.startTimeMs + 8000)
            } else {
                resolvedEndMs = current.startTimeMs + 4000
            }

            result.append(LyricLine(
                id: current.id,
                startTimeMs: current.startTimeMs,
                endTimeMs: max(resolvedEndMs, current.startTimeMs + 500),
                text: current.text,
                words: current.words
            ))
        }

        return result
    }

    private func parseTimestamp(_ raw: String) -> Int {
        // Formats: "00:01:23.456", "01:23.456", or seconds "123.456s"
        let clean = raw.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "s", with: "")
        let parts = clean.components(separatedBy: ":")

        if parts.count == 3 {
            let h = Int(parts[0]) ?? 0
            let m = Int(parts[1]) ?? 0
            let s = Double(parts[2]) ?? 0.0
            return Int((Double(h * 3600 + m * 60) + s) * 1000)
        } else if parts.count == 2 {
            let m = Int(parts[0]) ?? 0
            let s = Double(parts[1]) ?? 0.0
            return Int((Double(m * 60) + s) * 1000)
        } else if let s = Double(clean) {
            return Int(s * 1000)
        }
        return 0
    }

    private func stripXMLTags(_ text: String) -> String {
        return text.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression, range: nil)
    }

    private func isInstrumental(content: String) -> Bool {
        let lower = content.lowercased()
        return lower.contains("[au: instrumental]") ||
               lower.contains("[instrumental]") ||
               lower == "instrumental"
    }
}
