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

    public init(databaseURL: URL? = nil) {
        if let customURL = databaseURL {
            self.dbURL = customURL
        } else {
            let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            self.dbURL = docs.appendingPathComponent("liner_cache.sqlite")
        }
        openDatabase()
        createTables()
    }

    deinit {
        if let db = db {
            sqlite3_close(db)
        }
    }

    // MARK: - Database Setup

    private func openDatabase() {
        var dbPointer: OpaquePointer?
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
        if sqlite3_open_v2(dbURL.path, &dbPointer, flags, nil) == SQLITE_OK {
            self.db = dbPointer
            // Enable WAL mode for high-concurrency read/write without SQLITE_BUSY locks
            executeRaw(sql: "PRAGMA journal_mode = WAL;")
            executeRaw(sql: "PRAGMA synchronous = NORMAL;")
            executeRaw(sql: "PRAGMA foreign_keys = ON;")
        } else {
            RingBufferLogger.shared.log(level: .error, category: "SQLite", message: "Failed to open database at \(dbURL.path)")
        }
    }

    private func createTables() {
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

        executeRaw(sql: createLyricsSQL)
        executeRaw(sql: createPaletteSQL)
        executeRaw(sql: createMetadataSQL)
    }

    private func executeRaw(sql: String) {
        guard let db = db else { return }
        var errorMsg: UnsafeMutablePointer<CChar>?
        if sqlite3_exec(db, sql, nil, nil, &errorMsg) != SQLITE_OK {
            if let errorMsg = errorMsg {
                let error = String(cString: errorMsg)
                RingBufferLogger.shared.log(level: .error, category: "SQLite", message: "SQL Error: \(error)")
                sqlite3_free(errorMsg)
            }
        }
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
            let granularityStr = String(cString: sqlite3_column_text(statement, 1))
            let granularity = LyricsSyncGranularity(rawValue: granularityStr) ?? .lineSynced

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
            let updatedAtTimestamp = Double(sqlite3_column_int64(statement, 5))
            let fetchedAt = Date(timeIntervalSince1970: updatedAtTimestamp)

            return LyricsPayload(
                trackURI: trackURI,
                sourceProvider: provider,
                granularity: granularity,
                lines: lines,
                plainTextFallback: plainText,
                userOffsetMs: userOffset,
                fetchedAt: fetchedAt
            )
        }

        return nil
    }

    public func updateUserOffset(trackURI: String, offsetMs: Int) throws {
        guard let db = db else { throw SQLiteError.databaseNotOpen }

        let sql = "UPDATE lyrics_cache SET user_offset_ms = ? WHERE track_uri = ?;"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw SQLiteError.prepareFailed(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(statement) }

        sqlite3_bind_int(statement, 1, Int32(offsetMs))
        sqlite3_bind_text(statement, 2, (trackURI as NSString).utf8String, -1, nil)

        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw SQLiteError.stepFailed(String(cString: sqlite3_errmsg(db)))
        }
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
            let c0 = String(cString: sqlite3_column_text(statement, 0))
            let c1 = String(cString: sqlite3_column_text(statement, 1))
            let c2 = String(cString: sqlite3_column_text(statement, 2))
            let c3 = String(cString: sqlite3_column_text(statement, 3))
            let accent = String(cString: sqlite3_column_text(statement, 4))
            let timestamp = Double(sqlite3_column_int64(statement, 5))

            return ExtractedPalette(
                bgHex0: c0,
                bgHex1: c1,
                bgHex2: c2,
                bgHex3: c3,
                accentHex: accent,
                extractedAt: Date(timeIntervalSince1970: timestamp)
            )
        }
        return nil
    }

    // MARK: - Bulk Export / Cleanup

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

    public func getDatabaseSizeBytes() -> Int64 {
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: dbURL.path)
            return attributes[.size] as? Int64 ?? 0
        } catch {
            return 0
        }
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
