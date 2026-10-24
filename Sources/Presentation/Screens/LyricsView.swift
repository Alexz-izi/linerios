//
//  LyricsView.swift
//  LineriOS
//
//  Screen S9: Full-screen 120Hz ProMotion synchronized lyrics visualizer.
//  Renders syllable-synced karaoke text fills, active-line specular glows, distance blurs,
//  and on-device ±100ms timing offset controls.
//

import SwiftUI

public struct LyricsView: View {
    @Bindable private var store = LyricsStore.shared
    @Bindable private var playerStore = PlayerStore.shared

    @State private var showOffsetPill: Bool = false
    @State private var showImportSheet: Bool = false
    @State private var pastedLyricsText: String = ""

    private let theme = ThemePreset.midnight

    public init() {}

    public var body: some View {
        ZStack {
            theme.bgPrimary.ignoresSafeArea()

            VStack(spacing: 0) {
                // Header Bar with Track Meta & Offset Trigger
                lyricsHeaderBar
                    .padding(.top, 16)
                    .padding(.horizontal, 24)

                // Main Synchronized Lyrics Stream
                if store.isLoading {
                    loadingShimmerView
                } else if let lyrics = store.lyrics, !lyrics.lines.isEmpty {
                    lyricsScrollView(lines: lyrics.lines)
                } else if store.lyrics?.granularity == .instrumental {
                    instrumentalView
                } else {
                    emptyLyricsFallbackView
                }
            }

            // Floating Offset Stepper Pill
            if showOffsetPill {
                VStack {
                    Spacer()
                    offsetAdjustmentPill
                        .padding(.bottom, 48)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .onAppear {
            if let snapshot = playerStore.currentSnapshot {
                store.loadLyrics(for: snapshot)
            }
        }
        .sheet(isPresented: $showImportSheet) {
            importLyricsSheet
        }
    }

    // MARK: - Header Bar
    private var lyricsHeaderBar: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text(playerStore.trackTitle)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundColor(theme.textPrimary)
                    .lineLimit(1)

                Text(playerStore.artistName)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(theme.textMuted)
                    .lineLimit(1)
            }

            Spacer()

            // Offset Pill Toggle Button
            Button(action: {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                    showOffsetPill.toggle()
                }
            }) {
                HStack(spacing: 4) {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 12))
                    if store.userOffsetMs != 0 {
                        Text("\(store.userOffsetMs > 0 ? "+" : "")\(store.userOffsetMs)ms")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                    }
                }
                .foregroundColor(store.userOffsetMs != 0 ? theme.accentPrimary : theme.textMuted)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(theme.bgSecondary)
                .clipShape(Capsule())
            }
        }
    }

    // MARK: - Lyrics Scroll View
    private func lyricsScrollView(lines: [LyricLine]) -> some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 28) {
                    // Safe top spacing
                    Color.clear.frame(height: 60)

                    ForEach(Array(lines.enumerated()), id: \.element.id) { index, line in
                        let isActive = (store.activeLineIndex == index)
                        let blurRadius = store.blurForLine(index: index)
                        let opacity = store.opacityForLine(index: index)

                        lyricLineRow(line: line, isActive: isActive)
                            .id(index)
                            .blur(radius: blurRadius)
                            .opacity(opacity)
                            .scaleEffect(isActive ? 1.02 : 0.98)
                            .animation(.interactiveSpring(response: 0.3, dampingFraction: 0.7), value: isActive)
                    }

                    // Safe bottom spacing
                    Color.clear.frame(height: 120)
                }
                .padding(.horizontal, 24)
            }
            .onChange(of: store.activeLineIndex) { _, newIndex in
                if let idx = newIndex {
                    withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) {
                        proxy.scrollTo(idx, anchor: .center)
                    }
                }
            }
        }
    }

    // MARK: - Lyric Line Row (Syllable vs Line)
    private func lyricLineRow(line: LyricLine, isActive: Bool) -> some View {
        Group {
            if !line.words.isEmpty {
                // Syllable / Word Karaoke Stream
                wrappingWordsView(words: line.words, isActive: isActive)
            } else {
                // Standard Line Synced
                Text(line.text)
                    .font(.system(size: 26, weight: isActive ? .bold : .semibold, design: .rounded))
                    .foregroundColor(isActive ? theme.textPrimary : theme.textMuted)
            }
        }
    }

    private func wrappingWordsView(words: [LyricWordToken], isActive: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            ForEach(words) { token in
                let progress = store.progressForWord(token)
                Text(token.text)
                    .font(.system(size: 26, weight: isActive ? .bold : .semibold, design: .rounded))
                    .overlay(
                        GeometryReader { geo in
                            Rectangle()
                                .fill(theme.accentPrimary)
                                .frame(width: geo.size.width * progress)
                                .mask(
                                    Text(token.text)
                                        .font(.system(size: 26, weight: isActive ? .bold : .semibold, design: .rounded))
                                )
                        }
                    )
                    .foregroundColor(isActive ? theme.textPrimary.opacity(0.35) : theme.textMuted)
            }
        }
    }

    // MARK: - Floating Offset Stepper Pill
    private var offsetAdjustmentPill: some View {
        HStack(spacing: 12) {
            Button("-100ms") {
                store.adjustOffset(by: -100)
            }
            .font(.system(size: 12, weight: .bold, design: .monospaced))
            .foregroundColor(theme.textPrimary)

            Divider()
                .frame(height: 16)
                .background(theme.textMuted.opacity(0.4))

            Text("\(store.userOffsetMs > 0 ? "+" : "")\(store.userOffsetMs)ms")
                .font(.system(size: 13, weight: .bold, design: .monospaced))
                .foregroundColor(theme.accentPrimary)

            Divider()
                .frame(height: 16)
                .background(theme.textMuted.opacity(0.4))

            Button("+100ms") {
                store.adjustOffset(by: 100)
            }
            .font(.system(size: 12, weight: .bold, design: .monospaced))
            .foregroundColor(theme.textPrimary)

            if store.userOffsetMs != 0 {
                Button("Reset") {
                    store.resetOffset()
                }
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(Color(hex: "#F43F5E"))
                .padding(.leading, 4)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            Capsule()
                .fill(Color.black.opacity(0.85))
                .overlay(
                    Capsule().stroke(theme.specularRimColor.opacity(0.4), lineWidth: 1)
                )
        )
    }

    // MARK: - State Fallbacks
    private var loadingShimmerView: some View {
        VStack(spacing: 24) {
            Spacer()
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: theme.accentPrimary))
            Text("Searching synced lyrics...")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(theme.textMuted)
            Spacer()
        }
    }

    private var instrumentalView: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "guitars.fill")
                .font(.system(size: 48))
                .foregroundColor(theme.accentPrimary)
            Text("Instrumental Track")
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundColor(theme.textPrimary)
            Text("No vocals present for this composition.")
                .font(.system(size: 13))
                .foregroundColor(theme.textMuted)
            Spacer()
        }
    }

    private var emptyLyricsFallbackView: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "quote.bubble")
                .font(.system(size: 44))
                .foregroundColor(theme.textMuted.opacity(0.5))

            Text("No Synced Lyrics Found")
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .foregroundColor(theme.textPrimary)

            Button(action: { showImportSheet = true }) {
                HStack(spacing: 6) {
                    Image(systemName: "doc.badge.plus")
                    Text("Import .lrc or Paste Text")
                }
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(theme.bgPrimary)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(theme.accentPrimary)
                .clipShape(Capsule())
            }
            Spacer()
        }
    }

    // MARK: - Import Sheet
    private var importLyricsSheet: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text("Paste LRC or TTML Text Below:")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(theme.textPrimary)

                TextEditor(text: $pastedLyricsText)
                    .font(.system(size: 12, design: .monospaced))
                    .padding(12)
                    .background(theme.bgSecondary)
                    .cornerRadius(12)

                Button("Save and Sync") {
                    if let uri = playerStore.currentSnapshot?.trackURI, !pastedLyricsText.isEmpty {
                        Task {
                            let _ = try? await CompositeLyricsRepository.shared.importLocalLyrics(
                                content: pastedLyricsText,
                                trackURI: uri
                            )
                            if let snapshot = playerStore.currentSnapshot {
                                store.loadLyrics(for: snapshot)
                            }
                            showImportSheet = false
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(theme.accentPrimary)
                .foregroundColor(theme.bgPrimary)
                .clipShape(Capsule())
            }
            .padding(20)
            .navigationTitle("Import Lyrics")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showImportSheet = false }
                }
            }
        }
    }
}
