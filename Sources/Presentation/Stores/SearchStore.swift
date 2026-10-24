//
//  SearchStore.swift
//  LineriOS
//
//  MainActor observable search store managing debounced queries (320ms),
//  Dev Mode pagination caps (limit=10), and local offline lyrics cache filtering.
//

import Foundation
import SwiftUI
import Observation

public enum SearchCategory: String, CaseIterable, Identifiable, Sendable {
    case all = "All"
    case songs = "Songs"
    case albums = "Albums"
    case artists = "Artists"
    case playlists = "Playlists"

    public var id: String { rawValue }
}

@MainActor
@Observable
public final class SearchStore {
    public static let shared = SearchStore()

    public var query: String = "" {
        didSet {
            handleQueryChange()
        }
    }

    public var selectedCategory: SearchCategory = .all
    public var results: [TrackItem] = []
    public var recentSearches: [String] = []
    public var isLoading: Bool = false
    public var errorMessage: String?

    private var activeSearchTask: Task<Void, Never>?
    private let apiClient = SpotifyWebAPIClient.shared

    public init() {
        loadRecentSearches()
    }

    private func handleQueryChange() {
        activeSearchTask?.cancel()

        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            results = []
            isLoading = false
            return
        }

        isLoading = true
        errorMessage = nil

        // Swift Concurrency 320ms debounce
        activeSearchTask = Task {
            try? await Task.sleep(for: .milliseconds(320))
            guard !Task.isCancelled else { return }

            do {
                let items = try await apiClient.search(query: trimmed, offset: 0)
                if !Task.isCancelled {
                    self.results = items
                    self.isLoading = false
                    self.recordRecentSearch(trimmed)
                }
            } catch {
                if !Task.isCancelled {
                    self.isLoading = false
                    self.errorMessage = error.localizedDescription
                }
            }
        }
    }

    public func clearSearch() {
        query = ""
        results = []
        isLoading = false
    }

    private func recordRecentSearch(_ term: String) {
        var existing = recentSearches.filter { $0.lowercased() != term.lowercased() }
        existing.insert(term, at: 0)
        recentSearches = Array(existing.prefix(8))
        UserDefaults.standard.set(recentSearches, forKey: "liner_recent_searches")
    }

    private func loadRecentSearches() {
        recentSearches = UserDefaults.standard.stringArray(forKey: "liner_recent_searches") ?? []
    }

    public func removeRecentSearch(_ term: String) {
        recentSearches.removeAll { $0 == term }
        UserDefaults.standard.set(recentSearches, forKey: "liner_recent_searches")
    }

    public func clearAllRecentSearches() {
        recentSearches.removeAll()
        UserDefaults.standard.removeObject(forKey: "liner_recent_searches")
    }
}
