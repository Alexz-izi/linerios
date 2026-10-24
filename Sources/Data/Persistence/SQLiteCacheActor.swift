//
//  SQLiteCacheActor.swift
//  LineriOS
//
//  Thread-safe SQLite storage actor using the system libsqlite3 C API with WAL journal mode.
//  Provides permanent caching for LRCLIB synced lyrics, LAB artwork palettes, and offline metadata.
//

import Foundation
import SQLite3

public actor SQLiteCacheActor {
    public static let shared = SQLiteCacheActor()

    private var db: OpaquePointer?
    private let dbURL: URL

    public struct CacheStatistics: Sendable {
        public let lyricsCount: Int
        public let paletteCount: Int
        public let databaseSizeBytes: Int64
        
        public init(lyricsCount: Int, paletteCount: Int, databaseSizeBytes: Int64) {
            self.lyricsCount = lyricsCount
            self.paletteCount = paletteCount
            self.databaseSizeBytes = databaseSizeBytes
        }
    }

    public init(databaseURL: URL? = nil) {
        let url: URL
        if let customURL = databaseURL {
            url = customURL
        } else {
            let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            url = docs.appendingPathComponent("liner_cache.sqlite")
        }
        self.dbURL = url

        var dbPointer: OpaquePointer?
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
        if sqlite3_open_v2(url.path, &dbPointer, flags, nil) == SQLITE_OK {
            self.db = dbPointer
            Self.executeRaw(db: dbPointer, sql: "PRAGMA journal_mode = WAL;")
            Self.executeRaw(db: dbPointer, sql: "PRAGMA synchronous = NORMAL;")
            Self.executeRaw(db: dbPointer, sql: "PRAGMA foreign_keys = ON;")
            Self.createTables(db: dbPointer)
        } else {
            self.db = nil
            RingBufferLogger.shared.log(level: .error, category: "SQLite", message: "Failed to open database at \(url.path)")
        }
    }

    deinit {
        if let db = db {
            sqlite3_close(db)
        }
    }

    // MARK: - Database Setup

    private static func createTables(db: OpaquePointer?) {
        let createLyricsSQL = """
        CREATE TABLE IF NOT EXISTS lyrics_cache (
            track_uri TEXT PRIMARY KEY,
            provider TEXT NOT NULL,
            granularity TEXT NOT NULL,
            lines_json BLOB NOT NULL,
            plain_text TEXT,
            user_offset_ms INTEGER DEFAULT 0,
            updated_at INTEGER NOT NULL
        );
        """

        let createPaletteSQL = """
        CREATE TABLE IF NOT EXISTS palette_cache (
            artwork_url TEXT PRIMARY KEY,
            bg_hex_0 TEXT NOT NULL,
            bg_hex_1 TEXT NOT NULL,
            bg_hex_2 TEXT NOT NULL,
            bg_hex_3 TEXT NOT NULL,
            accent_hex TEXT NOT NULL,
            extracted_at INTEGER NOT NULL
        );
        """

        let createMetadataSQL = """
        CREATE TABLE IF NOT EXISTS metadata_cache (
            spotify_uri TEXT PRIMARY KEY,
            entity_type TEXT NOT NULL,
            payload_json BLOB NOT NULL,
            cached_at INTEGER NOT NULL
        );
        """

        executeRaw(db: db, sql: createLyricsSQL)
        executeRaw(db: db, sql: createPaletteSQL)
        executeRaw(db: db, sql: createMetadataSQL)
    }

    private static func executeRaw(db: OpaquePointer?, sql: String) {
        guard let db = db else { return }
        var errMsg: UnsafeMutablePointer<CChar>?
        if sqlite3_exec(db, sql, nil, nil, &errMsg) != SQLITE_OK {
            let message = errMsg != nil ? String(cString: errMsg!) : "Unknown error"
            RingBufferLogger.shared.log(level: .warn, category: "SQLite", message: "Raw SQL failed: \(message)")
            sqlite3_free(errMsg)
        }
    }

    private func executeRaw(sql: String) {
        Self.executeRaw(db: self.db, sql: sql)
    }

    // MARK: - Lyrics Cache Operations

    public func saveLyrics(_ payload: LyricsPayload) throws {
        guard let db = db else { throw SQLiteError.databaseNotOpen }

        let linesData = try JSONEncoder().encode(payload.lines)
        let sql = """
        INSERT INTO lyrics_cache (track_uri, provider, granularity, lines_json, plain_text, user_offset_ms, updated_at)
        VALUES (?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(track_uri) DO UPDATE SET
            provider = excluded.provider,
            granularity = excluded.granularity,
            lines_json = excluded.lines_json,
            plain_text = excluded.plain_text,
            updated_at = excluded.updated_at;
        """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw SQLiteError.prepareFailed(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(statement) }

        sqlite3_bind_text(statement, 1, (payload.trackURI as NSString).utf8String, -1, nil)
        sqlite3_bind_text(statement, 2, (payload.sourceProvider as NSString).utf8String, -1, nil)
        sqlite3_bind_text(statement, 3, (payload.granularity.rawValue as NSString).utf8String, -1, nil)
        linesData.withUnsafeBytes { rawBuffer in
            sqlite3_bind_blob(statement, 4, rawBuffer.baseAddress, Int32(linesData.count), nil)
        }
        if let plain = payload.plainTextFallback {
            sqlite3_bind_text(statement, 5, (plain as NSString).utf8String, -1, nil)
        } else {
            sqlite3_bind_null(statement, 5)
        }
        sqlite3_bind_int(statement, 6, Int32(payload.userOffsetMs))
        sqlite3_bind_int64(statement, 7, Int64(payload.fetchedAt.timeIntervalSince1970))

        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw SQLiteError.stepFailed(String(cString: sqlite3_errmsg(db)))
        }
    }

    public func getLyrics(trackURI: String) throws -> LyricsPayload? {
        guard let db = db else { throw SQLiteError.databaseNotOpen }

        let sql = "SELECT provider, granularity, lines_json, plain_text, user_offset_ms, updated_at FROM lyrics_cache WHERE track_uri = ?;"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw SQLiteError.prepareFailed(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(statement) }

        sqlite3_bind_text(statement, 1, (trackURI as NSString).utf8String, -1, nil)

        if sqlite3_step(statement) == SQLITE_ROW {
            let provider = String(cString: sqlite3_column_text(statement, 0))
            let granStr = String(cString: sqlite3_column_text(statement, 1))
            let granularity = LyricsSyncGranularity(rawValue: granStr) ?? .lineSynced

            let blobPtr = sqlite3_column_blob(statement, 2)
            let blobBytes = sqlite3_column_bytes(statement, 2)
            let linesData = Data(bytes: blobPtr!, count: Int(blobBytes))
            let lines = try JSONDecoder().decode([LyricLine].self, from: linesData)

            let plainText: String?
            if let plainPtr = sqlite3_column_text(statement, 3) {
                plainText = String(cString: plainPtr)
            } else {
                plainText = nil
            }

            let userOffset = Int(sqlite3_column_int(statement, 4))
            let timestamp = Double(sqlite3_column_int64(statement, 5))

            return LyricsPayload(
                trackURI: trackURI,
                sourceProvider: provider,
                granularity: granularity,
                lines: lines,
                plainTextFallback: plainText,
                userOffsetMs: userOffset,
                fetchedAt: Date(timeIntervalSince1970: timestamp)
            )
        }
        return nil
    }

    public func updateUserOffset(trackURI: String, offsetMs: Int) {
        guard let db = db else { return }
        let sql = "UPDATE lyrics_cache SET user_offset_ms = ? WHERE track_uri = ?;"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(statement) }

        sqlite3_bind_int(statement, 1, Int32(offsetMs))
        sqlite3_bind_text(statement, 2, (trackURI as NSString).utf8String, -1, nil)
        sqlite3_step(statement)
    }

    // MARK: - Palette Cache Operations

    public func savePalette(artworkURL: String, palette: ExtractedPalette) throws {
        guard let db = db else { throw SQLiteError.databaseNotOpen }

        let sql = """
        INSERT INTO palette_cache (artwork_url, bg_hex_0, bg_hex_1, bg_hex_2, bg_hex_3, accent_hex, extracted_at)
        VALUES (?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(artwork_url) DO UPDATE SET
            bg_hex_0 = excluded.bg_hex_0,
            bg_hex_1 = excluded.bg_hex_1,
            bg_hex_2 = excluded.bg_hex_2,
            bg_hex_3 = excluded.bg_hex_3,
            accent_hex = excluded.accent_hex,
            extracted_at = excluded.extracted_at;
        """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw SQLiteError.prepareFailed(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(statement) }

        sqlite3_bind_text(statement, 1, (artworkURL as NSString).utf8String, -1, nil)
        sqlite3_bind_text(statement, 2, (palette.bgHex0 as NSString).utf8String, -1, nil)
        sqlite3_bind_text(statement, 3, (palette.bgHex1 as NSString).utf8String, -1, nil)
        sqlite3_bind_text(statement, 4, (palette.bgHex2 as NSString).utf8String, -1, nil)
        sqlite3_bind_text(statement, 5, (palette.bgHex3 as NSString).utf8String, -1, nil)
        sqlite3_bind_text(statement, 6, (palette.accentHex as NSString).utf8String, -1, nil)
        sqlite3_bind_int64(statement, 7, Int64(palette.extractedAt.timeIntervalSince1970))

        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw SQLiteError.stepFailed(String(cString: sqlite3_errmsg(db)))
        }
    }

    public func getPalette(artworkURL: String) throws -> ExtractedPalette? {
        guard let db = db else { throw SQLiteError.databaseNotOpen }

        let sql = "SELECT bg_hex_0, bg_hex_1, bg_hex_2, bg_hex_3, accent_hex, extracted_at FROM palette_cache WHERE artwork_url = ?;"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw SQLiteError.prepareFailed(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(statement) }

        sqlite3_bind_text(statement, 1, (artworkURL as NSString).utf8String, -1, nil)

        if sqlite3_step(statement) == SQLITE_ROW {
            let h0 = String(cString: sqlite3_column_text(statement, 0))
            let h1 = String(cString: sqlite3_column_text(statement, 1))
            let h2 = String(cString: sqlite3_column_text(statement, 2))
            let h3 = String(cString: sqlite3_column_text(statement, 3))
            let acc = String(cString: sqlite3_column_text(statement, 4))
            let ts = Double(sqlite3_column_int64(statement, 5))

            return ExtractedPalette(
                bgHex0: h0,
                bgHex1: h1,
                bgHex2: h2,
                bgHex3: h3,
                accentHex: acc,
                extractedAt: Date(timeIntervalSince1970: ts)
            )
        }
        return nil
    }

    // MARK: - Metadata Operations

    public func saveMetadata<T: Codable>(uri: String, type: String, payload: T) throws {
        guard let db = db else { throw SQLiteError.databaseNotOpen }
        let data = try JSONEncoder().encode(payload)

        let sql = """
        INSERT INTO metadata_cache (spotify_uri, entity_type, payload_json, cached_at)
        VALUES (?, ?, ?, ?)
        ON CONFLICT(spotify_uri) DO UPDATE SET
            payload_json = excluded.payload_json,
            cached_at = excluded.cached_at;
        """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw SQLiteError.prepareFailed(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(statement) }

        sqlite3_bind_text(statement, 1, (uri as NSString).utf8String, -1, nil)
        sqlite3_bind_text(statement, 2, (type as NSString).utf8String, -1, nil)
        data.withUnsafeBytes { raw in
            sqlite3_bind_blob(statement, 3, raw.baseAddress, Int32(data.count), nil)
        }
        sqlite3_bind_int64(statement, 4, Int64(Date().timeIntervalSince1970))

        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw SQLiteError.stepFailed(String(cString: sqlite3_errmsg(db)))
        }
    }

    public func getMetadata<T: Codable>(uri: String, as type: T.Type) throws -> T? {
        guard let db = db else { throw SQLiteError.databaseNotOpen }

        let sql = "SELECT payload_json FROM metadata_cache WHERE spotify_uri = ?;"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw SQLiteError.prepareFailed(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(statement) }

        sqlite3_bind_text(statement, 1, (uri as NSString).utf8String, -1, nil)

        if sqlite3_step(statement) == SQLITE_ROW {
            let blobPtr = sqlite3_column_blob(statement, 0)
            let blobBytes = sqlite3_column_bytes(statement, 0)
            let data = Data(bytes: blobPtr!, count: Int(blobBytes))
            return try JSONDecoder().decode(T.self, from: data)
        }
        return nil
    }

    // MARK: - Maintenance & Diagnostics

    public func getAllCachedLyrics() throws -> [LyricsPayload] {
        guard let db = db else { throw SQLiteError.databaseNotOpen }

        let sql = "SELECT track_uri, provider, granularity, lines_json, plain_text, user_offset_ms, updated_at FROM lyrics_cache;"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw SQLiteError.prepareFailed(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(statement) }

        var results: [LyricsPayload] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            let uri = String(cString: sqlite3_column_text(statement, 0))
            let provider = String(cString: sqlite3_column_text(statement, 1))
            let granStr = String(cString: sqlite3_column_text(statement, 2))
            let granularity = LyricsSyncGranularity(rawValue: granStr) ?? .lineSynced

            let blobPtr = sqlite3_column_blob(statement, 3)
            let blobBytes = sqlite3_column_bytes(statement, 3)
            let linesData = Data(bytes: blobPtr!, count: Int(blobBytes))
            let lines = (try? JSONDecoder().decode([LyricLine].self, from: linesData)) ?? []

            let plainText: String?
            if let plainPtr = sqlite3_column_text(statement, 4) {
                plainText = String(cString: plainPtr)
            } else {
                plainText = nil
            }

            let userOffset = Int(sqlite3_column_int(statement, 5))
            let timestamp = Double(sqlite3_column_int64(statement, 6))

            let payload = LyricsPayload(
                trackURI: uri,
                sourceProvider: provider,
                granularity: granularity,
                lines: lines,
                plainTextFallback: plainText,
                userOffsetMs: userOffset,
                fetchedAt: Date(timeIntervalSince1970: timestamp)
            )
            results.append(payload)
        }
        return results
    }

    public func clearLyrics() {
        executeRaw(sql: "DELETE FROM lyrics_cache;")
        executeRaw(sql: "VACUUM;")
    }

    public func clearPalettes() {
        executeRaw(sql: "DELETE FROM palette_cache;")
        executeRaw(sql: "VACUUM;")
    }

    public func clearPaletteCache() {
        clearPalettes()
    }

    public func clearLocalCache() {
        clearLyrics()
        clearPalettes()
    }

    public func getDatabaseSizeBytes() -> Int64 {
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: dbURL.path)
            return attributes[.size] as? Int64 ?? 0
        } catch {
            return 0
        }
    }

    public func getCacheStatistics() -> CacheStatistics {
        let lCount = getTableRowCount(table: "lyrics_cache")
        let pCount = getTableRowCount(table: "palette_cache")
        let size = getDatabaseSizeBytes()
        return CacheStatistics(lyricsCount: lCount, paletteCount: pCount, databaseSizeBytes: size)
    }

    private func getTableRowCount(table: String) -> Int {
        guard let db = db else { return 0 }
        var statement: OpaquePointer?
        let sql = "SELECT COUNT(*) FROM \(table);"
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return 0 }
        defer { sqlite3_finalize(statement) }
        if sqlite3_step(statement) == SQLITE_ROW {
            return Int(sqlite3_column_int(statement, 0))
        }
        return 0
    }
}

public enum SQLiteError: LocalizedError, Sendable {
    case databaseNotOpen
    case prepareFailed(String)
    case stepFailed(String)

    public var errorDescription: String? {
        switch self {
        case .databaseNotOpen: return "SQLite database is not open."
        case .prepareFailed(let msg): return "SQLite statement preparation failed: \(msg)"
        case .stepFailed(let msg): return "SQLite step failed: \(msg)"
        }
    }
}
