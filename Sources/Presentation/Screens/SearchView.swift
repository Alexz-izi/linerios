//
//  SearchView.swift
//  LineriOS
//
//  Screens S4 & S5: Debounced Spotify search and results browser.
//  Implements category filter pills, top-result hero card, and 10-item paginated track rows.
//

import SwiftUI

public struct SearchView: View {
    @Bindable private var searchStore = SearchStore.shared
    @Bindable private var playerStore = PlayerStore.shared
    @Bindable private var theme = ThemeManager.shared

    public init() {}

    public var body: some View {
        NavigationStack {
            ZStack {
                AdaptiveAtmosphereMeshView()

                VStack(spacing: 16) {
                    // Floating Search Capsule (Top 59pt safe-area)
                    searchBarCapsule
                        .padding(.top, 59)

                    // Category Filter Pills
                    categoryFilterBar

                    // Content: Recent Searches or Results
                    if searchStore.query.isEmpty {
                        idleRecentSearchesView
                    } else if searchStore.isLoading {
                        loadingView
                    } else if searchStore.results.isEmpty {
                        noResultsView
                    } else {
                        searchResultsList
                    }
                }
                .padding(.horizontal, 20)
            }
            .ignoresSafeArea()
        }
    }

    // MARK: - Search Bar Capsule
    private var searchBarCapsule: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(theme.textMuted)

            TextField("Artists, songs, or lyrics", text: $searchStore.query)
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundColor(theme.textPrimary)
                .autocorrectionDisabled()

            if !searchStore.query.isEmpty {
                Button(action: { searchStore.clearSearch() }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(theme.textMuted)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(theme.currentPreset.glassTintColor)
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(theme.specularRimColor.opacity(0.3), lineWidth: 1)
                )
        )
    }

    // MARK: - Category Filter Bar
    private var categoryFilterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(SearchCategory.allCases) { category in
                    Button(action: {
                        searchStore.selectedCategory = category
                    }) {
                        Text(category.rawValue)
                            .font(.system(size: 12, weight: searchStore.selectedCategory == category ? .bold : .medium, design: .rounded))
                            .foregroundColor(searchStore.selectedCategory == category ? theme.activeAccent : theme.textMuted)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(
                                searchStore.selectedCategory == category ? theme.activeAccent.opacity(0.18) : theme.currentPreset.bgSecondary
                            )
                            .clipShape(Capsule())
                            .overlay(
                                Capsule().stroke(theme.specularRimColor.opacity(0.2), lineWidth: 0.8)
                            )
                    }
                }
            }
        }
    }

    // MARK: - Idle State (Recent Searches)
    private var idleRecentSearchesView: some View {
        VStack(alignment: .leading, spacing: 14) {
            if !searchStore.recentSearches.isEmpty {
                HStack {
                    Text("RECENT SEARCHES")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundColor(theme.textMuted)
                    Spacer()
                    Button("Clear All") {
                        searchStore.clearAllRecentSearches()
                    }
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(Color(hex: "#F43F5E"))
                }

                ForEach(searchStore.recentSearches, id: \.self) { term in
                    HStack {
                        Image(systemName: "clock.arrow.circlepath")
                            .foregroundColor(theme.textMuted)
                        Button(term) {
                            searchStore.query = term
                        }
                        .foregroundColor(theme.textPrimary)
                        .font(.system(size: 14, weight: .medium))

                        Spacer()

                        Button(action: { searchStore.removeRecentSearch(term) }) {
                            Image(systemName: "xmark")
                                .font(.system(size: 11))
                                .foregroundColor(theme.textMuted)
                        }
                    }
                    .padding(.vertical, 6)
                }
            }

            Spacer()
        }
        .padding(.top, 12)
    }

    // MARK: - Search Results List
    private var searchResultsList: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(spacing: 12) {
                // Top Result Hero Card
                if let top = searchStore.results.first {
                    topResultHeroCard(top)
                }

                // Remaining Track Rows
                ForEach(searchStore.results.dropFirst()) { track in
                    trackRow(track)
                }

                Color.clear.frame(height: 120)
            }
        }
    }

    private func topResultHeroCard(_ track: TrackItem) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("TOP RESULT")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundColor(theme.textMuted)

            HStack(spacing: 14) {
                if let url = track.artworkURL {
                    AsyncImage(url: url) { phase in
                        if let img = phase.image {
                            img.resizable().aspectRatio(contentMode: .fill)
                        } else {
                            Color.gray.opacity(0.3)
                        }
                    }
                    .frame(width: 64, height: 64)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(track.title)
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundColor(theme.textPrimary)
                        .lineLimit(1)

                    Text(track.artistName)
                        .font(.system(size: 13))
                        .foregroundColor(theme.textMuted)
                        .lineLimit(1)
                }

                Spacer()

                Button(action: {
                    playerStore.playTrack(uri: track.uri)
                }) {
                    Image(systemName: "play.fill")
                        .font(.system(size: 18))
                        .foregroundColor(theme.currentPreset.bgPrimary)
                        .frame(width: 44, height: 44)
                        .background(theme.activeAccent)
                        .clipShape(Circle())
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(theme.currentPreset.glassTintColor)
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(theme.specularRimColor.opacity(0.3), lineWidth: 1)
                )
        )
    }

    private func trackRow(_ track: TrackItem) -> some View {
        Button(action: {
            playerStore.playTrack(uri: track.uri)
        }) {
            HStack(spacing: 12) {
                if let url = track.artworkURL {
                    AsyncImage(url: url) { phase in
                        if let img = phase.image {
                            img.resizable().aspectRatio(contentMode: .fill)
                        } else {
                            Color.gray.opacity(0.3)
                        }
                    }
                    .frame(width: 46, height: 46)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 4) {
                        Text(track.title)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(theme.textPrimary)
                            .lineLimit(1)

                        if track.isExplicit {
                            Text("E")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(Color.gray)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(Color.white.opacity(0.12))
                                .clipShape(RoundedRectangle(cornerRadius: 3))
                        }
                    }

                    Text(track.artistName)
                        .font(.system(size: 12))
                        .foregroundColor(theme.textMuted)
                        .lineLimit(1)
                }

                Spacer()

                Text(track.formattedDuration)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(theme.textMuted)
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
    }

    private var loadingView: some View {
        VStack(spacing: 12) {
            Spacer()
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: theme.activeAccent))
            Text("Searching catalog...")
                .font(.system(size: 13))
                .foregroundColor(theme.textMuted)
            Spacer()
        }
    }

    private var noResultsView: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "magnifyingglass")
                .font(.system(size: 36))
                .foregroundColor(theme.textMuted.opacity(0.5))
            Text("No Results Found")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(theme.textPrimary)
            Spacer()
        }
    }
}
