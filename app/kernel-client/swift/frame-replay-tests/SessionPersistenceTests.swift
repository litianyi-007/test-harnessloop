// rounds/0014 A 块 —— SessionPersistenceStore 的离线单测（不需要 actor/网络，纯文件系统）。
//
// 和 SessionStoreGroupingTests.swift 一样 `@testable import AgentShellCore`；`fail`/`pass`（同目录
// FrameReplayTests.swift 定义，同一个 frame-replay-tests target/module）无需重新 import 即可直接用。
//
// 每个测试用 `AGENT_SHELL_STATE_DIR` 风格的 `directoryOverride:` 指向一个独立的临时目录（`/tmp` 下
// 带 UUID 的子目录，测试结束时 `defer` 清理），既互相隔离，也绝不触碰开发者机器上真实的
// `~/Library/Application Support/dev.test-harnessloop.agent-shell/`。

import Foundation
@testable import AgentShellCore
import D2Generated

private func persistenceTestSessionHandle(sessionID: String) -> SessionHandle {
    SessionHandle(
        billing: Billing(tokenRef: "test"), createdAt: Date(), kernel: .openclaw,
        kernelSessionID: "kernel-session-\(sessionID)", sessionID: sessionID
    )
}

private func freshPersistenceTempDirectory(_ label: String) -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("agent-shell-persistence-tests-\(label)-\(UUID().uuidString)", isDirectory: true)
}

/// 基本正确性：save() 写入的字段（sessionID/kernelKey/title）经 load() 原样取回。
func testSessionPersistenceRoundTripsSavedSessions() -> Bool {
    let name = "rounds/0014 A: SessionPersistenceStore.save() then .load() round-trips sessionID/kernelKey/title correctly"
    let dir = freshPersistenceTempDirectory("roundtrip")
    defer { try? FileManager.default.removeItem(at: dir) }
    let store = SessionPersistenceStore(directoryOverride: dir)

    let record = PersistedSession(
        handle: persistenceTestSessionHandle(sessionID: "sess-roundtrip-1"),
        kernelKey: "kernel-key-roundtrip-1", title: "会话 1", createdAt: Date()
    )
    store.save([record])
    let loaded = store.load()

    guard loaded.count == 1 else {
        return fail(name, "expected 1 loaded session, got \(loaded.count)")
    }
    let got = loaded[0]
    guard got.handle.sessionID == "sess-roundtrip-1", got.kernelKey == "kernel-key-roundtrip-1", got.title == "会话 1" else {
        return fail(name, "round-tripped fields mismatch: sessionID=\(got.handle.sessionID) kernelKey=\(got.kernelKey) title=\(got.title)")
    }
    return pass(name, "save() 后 load() 正确取回 sessionID/kernelKey/title（文件路径=\(store.fileURL.path)）")
}

/// **反证1 的直接证据来源**：写坏 sessions.json 后，load() 必须安全回退到空列表（不 throw、不
/// crash），且随后仍可正常继续新建/持久化会话（"坏数据不得永久卡死壳"）。写入的坏字节内容与
/// load() 观察到的行为都原样打印——这正是任务书要求的"贴出你实际写入的坏内容与观察到的行为"。
func testSessionPersistenceCorruptFileFallsBackToEmptyListWithoutCrashing() -> Bool {
    let name = "rounds/0014 反证1: a corrupted sessions.json makes load() fall back to an empty list (not a crash), and the shell can keep creating/persisting sessions afterward"
    let dir = freshPersistenceTempDirectory("corrupt")
    defer { try? FileManager.default.removeItem(at: dir) }
    let store = SessionPersistenceStore(directoryOverride: dir)

    // 先写一条正常记录，证明"文件存在过、不是从来没写过"这件事本身不是接下来红/绿判定的原因。
    store.save([PersistedSession(
        handle: persistenceTestSessionHandle(sessionID: "sess-before-corruption"),
        kernelKey: "kernel-key-before-corruption", title: "会话 1", createdAt: Date()
    )])
    guard store.load().count == 1 else {
        return fail(name, "precondition failed: expected 1 session before corrupting the file")
    }

    let garbage = Data("{this is not valid JSON at all, and not even close: [[[".utf8)
    try? garbage.write(to: store.fileURL)
    print("  [反证1 evidence] 写入的坏字节内容：\(String(data: garbage, encoding: .utf8) ?? "<undecodable>")")

    let loaded = store.load()
    print("  [反证1 evidence] load() 观察到的行为：返回 \(loaded.count) 条记录（未 throw、未 crash）")
    guard loaded.isEmpty else {
        return fail(name, "expected load() to return an empty list after corruption, got \(loaded.count) records")
    }

    // "壳应回到空列表并可继续新建会话"——用 save() 模拟"继续新建会话后被持久化"这一步，证明损坏的
    // 文件不会永久卡死后续的写入/读取（下一次 save() 用 .atomic 整体覆盖，天然自愈）。
    store.save([PersistedSession(
        handle: persistenceTestSessionHandle(sessionID: "sess-after-corruption"),
        kernelKey: "kernel-key-after-corruption", title: "新会话", createdAt: Date()
    )])
    let reloaded = store.load()
    guard reloaded.count == 1, reloaded[0].handle.sessionID == "sess-after-corruption" else {
        return fail(name, "expected the shell to keep working after corruption (able to save+load a fresh session), got \(reloaded.count) records")
    }
    return pass(name, "写坏 sessions.json 后 load() 安全回退到空列表（未 crash/未 throw），且随后仍可正常新建并持久化会话（\(reloaded.count) 条，sessionID=\(reloaded[0].handle.sessionID)）")
}

/// reset() 的字面语义：删除持久化文件本身；之后 load() 仍然安全（不是"文件不存在就报错"）。
func testSessionPersistenceResetRemovesFileAndSubsequentLoadIsEmpty() -> Bool {
    let name = "rounds/0014 A: SessionPersistenceStore.reset() deletes the persisted file; load() afterward is empty and does not error"
    let dir = freshPersistenceTempDirectory("reset")
    defer { try? FileManager.default.removeItem(at: dir) }
    let store = SessionPersistenceStore(directoryOverride: dir)

    store.save([PersistedSession(
        handle: persistenceTestSessionHandle(sessionID: "sess-reset-1"),
        kernelKey: "kernel-key-reset-1", title: "会话 1", createdAt: Date()
    )])
    guard FileManager.default.fileExists(atPath: store.fileURL.path) else {
        return fail(name, "precondition failed: expected sessions.json to exist after save()")
    }

    store.reset()
    guard !FileManager.default.fileExists(atPath: store.fileURL.path) else {
        return fail(name, "expected reset() to delete the persisted file, but it still exists at \(store.fileURL.path)")
    }
    guard store.load().isEmpty else {
        return fail(name, "expected load() after reset() to be empty")
    }
    return pass(name, "reset() 删除了持久化文件（\(store.fileURL.path)），之后 load() 安全返回空列表")
}

/// 从未写过的目录：load() 必须是纯读操作，不能有"顺手把目录/文件创建出来"这类副作用。
func testSessionPersistenceMissingFileReturnsEmptyWithoutCreatingAnything() -> Bool {
    let name = "rounds/0014 A: load() on a directory that has never been written to returns an empty list without creating the file/directory as a side effect"
    let dir = freshPersistenceTempDirectory("missing")
    defer { try? FileManager.default.removeItem(at: dir) }
    let store = SessionPersistenceStore(directoryOverride: dir)

    let loaded = store.load()
    guard loaded.isEmpty else {
        return fail(name, "expected empty list for a never-written directory, got \(loaded.count)")
    }
    guard !FileManager.default.fileExists(atPath: store.fileURL.path) else {
        return fail(name, "expected load() to be read-only (no side-effect file creation), but \(store.fileURL.path) exists")
    }
    return pass(name, "从未写过的目录上 load() 安全返回空列表，且没有产生任何副作用文件")
}
