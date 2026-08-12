// rounds/0014 —— SessionRestoring/SessionHistoryProviding（会话持久化 B/C/D 块）的真 actor 级单测。
//
// 风格延续 FrameReplayTests.swift：每个测试是一个返回 `Bool`（或 `async -> Bool`）的普通函数，
// `fail`/`pass`/`collectUpTo`/`freshClient`（同目录 FrameReplayTests.swift 定义，同一个
// `frame-replay-tests` target/module，无需重新 import 即可直接用）。
//
// 这里只测 KernelClient 层新增的两个加法式协议本身（`OpenclawGatewayKernelClient` 的 extension 实现，
// 见 OpenclawGatewayKernelClient.swift 文件底部）——`SessionStore`（AgentShellCore）如何调用它们是
// SessionPersistenceTests.swift 与 SessionStore.swift 本身的职责，两者分开验证。`SessionStore` 侧
// 依赖真实 WebSocket `connect()` 才能跑到 `restorePersistedSessionsIfNeeded()`，不可离线单测——见
// SessionStore.swift 该方法文档注释与本轮交付报告"C 通路选择"一节。

import Foundation
@testable import KernelClient
import D2Generated

/// 供 testSupportStubRPC 的 responder 闭包记录"被请求了哪些 offset"——闭包是 `@Sendable`，需要一个
/// 引用类型 box 才能在闭包内部安全 mutate（与 FrameReplayTests.swift 的 `EventBox` 同款理由）。
final class OffsetCallLog: @unchecked Sendable {
    var requestedOffsets: [Int?] = []
}

/// 供 testSupportStubRPC 的 responder 闭包记录"被调用了几次"——同上，reference-type box。
final class RPCCallCounter: @unchecked Sendable {
    var count = 0
}

// MARK: - SessionRestoring（B/D 块）

/// **B(适配器状态重建)+D(重新订阅)一次性验证**：`restoreSession(sessionID:kernelKey:)` 必须(a)真的把
/// kernelKey 播种进映射表（用 `currentKernelKey` 反查确认，不是只顺手返回一个能用的 stream 却没真的
/// 播种）、(b)返回的 stream 是活的、能观察到*之后*到达的新事件（不是只读快照）——用真实
/// `testSupportFeedFrame` 灌一条寻址到这个 kernelKey 的 `session.message` wire 帧，走的是生产代码
/// `handleIncoming -> handleSessionMessageEvent -> ourSessionID(forKernelKey:)` 完整分发路径：如果
/// 映射没被正确播种，`ourSessionID(forKernelKey:)` 会返回 nil，这条帧会被
/// `handleSessionMessageEvent` 开头的 guard 静默丢弃，下面 `collectUpTo` 会超时拿到空数组。
func testRestoreSessionSeedsKernelKeyAndReestablishesEventFlow() async -> Bool {
    let name = "rounds/0014 B/D: restoreSession(sessionID:kernelKey:) seeds kernelKeyBySessionID and returns a live stream that observes new incoming frames (not a read-only snapshot)"
    let client = freshClient()
    let sessionID = "sess-restore-b-d-1"
    let kernelKey = "kernel-key-restore-b-d-1"

    // `restoreSession` 内部完整复用 `subscribe()`（含它背景 Task 里真正发起的
    // `sessions.messages.subscribe` RPC，见 restoreSession 自己的文档注释）——不 stub 这条 RPC 的话，
    // `freshClient()` 没有真实连接，`request()` 会在背景 Task 里 throw `.notConnected`，被
    // `subscribe()` 的 catch 分支转成 `continuation.finish(throwing:)`，与下面 `testSupportFeedFrame`
    // 构成一场谁先谁后的竞态——一旦背景 Task 先跑到 `finish(throwing:)`，stream 已经终止，
    // 之后 `continuation.yield` 变成静默 no-op，`collectUpTo` 会拿到 0 个事件（本测试第一版正是这样
    // 假失败过一次，靠这条 stub 收口）。照抄同目录 FrameReplayTests.swift
    // `testSubscribeReturnsBeforeServerSubscriptionAckArrives` 的既有模式：先 stub 好这条 RPC 的
    // 成功响应，让背景 Task 走向"正常完成"而不是"因未连接而报错"。
    await client.testSupportStubRPC(method: "sessions.messages.subscribe") { _ in
        ["subscribed": true, "key": kernelKey]
    }

    let stream = await client.restoreSession(sessionID: sessionID, kernelKey: kernelKey)

    let seededKey = await client.currentKernelKey(sessionID: sessionID)
    guard seededKey == kernelKey else {
        return fail(name, "expected currentKernelKey(sessionID:) to return the seeded kernelKey \(kernelKey), got \(String(describing: seededKey))")
    }

    // 注意：嵌套的 "message" 字典必须显式 `as JSONObject`——否则 Swift 会把它推断成
    // `[String: String]`（两个值都是字符串字面量），`encodeFrame` 里的
    // `JSONSerialization.isValidJSONObject` 对这种嵌套字典的识别不可靠，会导致整帧编码静默失败、
    // `testSupportFeedFrame` 提前 return，事件从不到达——这正是本文件同一目录
    // FrameReplayTests.swift 里所有构造 `session.message` 帧的既有测试统一采用的写法（例如
    // `testSubscribeReturnsBeforeServerSubscriptionAckArrives`），这里照抄同一个已验证过的模式。
    await client.testSupportFeedFrame([
        "type": "event",
        "event": "session.message",
        "payload": [
            "sessionKey": kernelKey,
            "message": ["role": "assistant", "content": "restored session is live"] as JSONObject,
            "messageId": "msg-restore-b-d-1",
        ] as JSONObject,
    ])

    let events = await collectUpTo(stream, maxCount: 1)
    guard events.count == 1, case .messageDelta(let e) = events[0] else {
        return fail(name, "expected exactly 1 messageDelta event on the restored stream, got \(events.count): \(events)")
    }
    guard e.payload.delta == "restored session is live" else {
        return fail(name, "expected delta text 'restored session is live', got '\(e.payload.delta)'")
    }
    return pass(name, "restoreSession() 播种的 kernelKey 经 currentKernelKey() 反查一致（\(seededKey ?? "nil")），且返回的 stream 在合成事件到达后真的 yield 了对应的 messageDelta——证明 B(映射重建)与 D(重新订阅、非只读快照)都成立")
}

/// **B 的边界确认**：`restoreSession` 只应该重新播种映射 + 重新订阅，不应该意外触发 D1 §2.1 的
/// `sessions.create` RPC（那会在内核侧铸造一个全新会话，语义上完全不是"恢复"）。给 `sessions.create`
/// 注册一个会计数的 stub，驱动 `restoreSession` 之后确认它的调用次数是 0。
func testRestoreSessionDoesNotCallSessionsCreateRpc() async -> Bool {
    let name = "rounds/0014 B: restoreSession() re-seeds the kernelKey mapping without re-issuing a sessions.create RPC — it reconnects an existing kernel session, it does not mint a new one"
    let client = freshClient()
    let callCount = RPCCallCounter()
    await client.testSupportStubRPC(method: "sessions.create") { _ in
        callCount.count += 1
        return ["key": "unexpected-key-from-sessions-create", "sessionId": "unexpected-session-id"]
    }

    _ = await client.restoreSession(sessionID: "sess-no-create-1", kernelKey: "kernel-key-no-create-1")
    // subscribe() 内部真正发起 sessions.messages.subscribe 的背景 Task 是 fire-and-forget 的（见
    // subscribe() 文档注释）——没有为它注册 stub，它会独立地因为"未连接"而失败并把错误封进 stream，
    // 这里不消费那个 stream、也不关心它的结果，只等一小段时间确保"如果 restoreSession 真的会触发
    // sessions.create（不应该）"，那次调用已经有机会发生。
    try? await Task.sleep(nanoseconds: 50_000_000)

    guard callCount.count == 0 else {
        return fail(name, "expected sessions.create to be called 0 times by restoreSession(), got \(callCount.count)")
    }
    let seededKey = await client.currentKernelKey(sessionID: "sess-no-create-1")
    guard seededKey == "kernel-key-no-create-1" else {
        return fail(name, "expected kernelKey mapping to be seeded correctly regardless, got \(String(describing: seededKey))")
    }
    return pass(name, "restoreSession() 完成后 sessions.create RPC 调用次数=0，且映射仍正确播种（kernelKey=\(seededKey ?? "nil")）——确认它只是重新播种映射 + 重新建立订阅通道，没有意外触发铸造新内核会话的 RPC")
}

// MARK: - SessionHistoryProviding（C 块）——反证2 的证据来源

/// **反证2 的直接证据来源**：stub `chat.history` 分两页作答（第一页 `hasMore:true`+`nextOffset:5`，
/// 第二页 `offset:5` 时 `hasMore:false`），断言 `fetchFullHistory` 真的发起了第二次带 offset 的请求
/// （不是只取第一页就返回），且合并结果按 seq 升序正确排列。请求到的 offset 序列与合并后的记录数会
/// 原样打印——这正是任务书要求的"贴出证明翻页发生了的输出（例如第二次请求带上了 cursor）"。
func testFetchFullHistoryPaginatesAcrossMultiplePages() async -> Bool {
    let name = "rounds/0014 C / 反证2: fetchFullHistory() follows hasMore/nextOffset across multiple chat.history pages, not just the first page"
    let client = freshClient()
    let kernelKey = "kernel-key-history-pagination-1"
    let offsetLog = OffsetCallLog()

    await client.testSupportStubRPC(method: "chat.history") { params in
        let requestedOffset = params["offset"] as? Int
        offsetLog.requestedOffsets.append(requestedOffset)
        if requestedOffset == nil {
            return [
                "sessionKey": kernelKey,
                "messages": [
                    ["role": "user", "content": "page1-user", "__openclaw": ["id": "id-p1-u", "seq": 20]] as JSONObject,
                    ["role": "assistant", "content": "page1-assistant", "__openclaw": ["id": "id-p1-a", "seq": 21]] as JSONObject,
                ] as [Any],
                "hasMore": true,
                "nextOffset": 5,
            ]
        } else if requestedOffset == 5 {
            return [
                "sessionKey": kernelKey,
                "messages": [
                    ["role": "assistant", "content": "page2-older-assistant", "__openclaw": ["id": "id-p2-a", "seq": 10]] as JSONObject,
                ] as [Any],
                "hasMore": false,
            ]
        } else {
            throw KernelClientError.protocolMismatch("unexpected offset \(String(describing: requestedOffset)) requested in test stub")
        }
    }

    do {
        let records = try await client.fetchFullHistory(kernelKey: kernelKey, pageLimit: 50)
        print("  [反证2 evidence] chat.history 被请求的 offset 序列（证明确实翻页了，不是只取第一页）：\(offsetLog.requestedOffsets)")
        print("  [反证2 evidence] fetchFullHistory 合并两页后返回的记录数=\(records.count)，按 seq 升序的 texts=\(records.map { $0.text })")

        guard offsetLog.requestedOffsets == [nil, 5] else {
            return fail(name, "expected chat.history to be called twice with offsets [nil, 5], got \(offsetLog.requestedOffsets)")
        }
        guard records.count == 3 else {
            return fail(name, "expected 3 combined records from both pages, got \(records.count): \(records.map { $0.text })")
        }
        guard records.map({ $0.text }) == ["page2-older-assistant", "page1-user", "page1-assistant"] else {
            return fail(name, "expected records sorted ascending by seq (page2's older seq=10 first), got \(records.map { $0.text })")
        }
        return pass(name, "两次真实分页请求(offset=\(offsetLog.requestedOffsets))都被 fetchFullHistory 发起并合并——第 2 页的内容确实进入了最终结果，不是只取了第一页；且按 seq 升序正确排序")
    } catch {
        return fail(name, "fetchFullHistory threw unexpectedly: \(error)")
    }
}

/// 服务端分页缺陷防御：`nextOffset` 卡在同一个值不推进时，`fetchFullHistory` 必须诚实 throw，不能
/// 静默死循环——精神上照抄 reconcile-history.py `resolve_online_history` 的"重复 cursor 拒绝继续"
/// 纪律（见该脚本与 OpenclawGatewayKernelClient.fetchFullHistory 的文档注释）。
func testFetchFullHistoryRejectsRepeatedNextOffsetInsteadOfLoopingForever() async -> Bool {
    let name = "rounds/0014 C: fetchFullHistory() throws instead of looping forever when chat.history returns a non-advancing (repeated) nextOffset"
    let client = freshClient()
    let kernelKey = "kernel-key-history-stuck-cursor-1"

    await client.testSupportStubRPC(method: "chat.history") { _ in
        [
            "sessionKey": kernelKey,
            "messages": [["role": "assistant", "content": "x", "__openclaw": ["id": "id-x", "seq": 1]] as JSONObject] as [Any],
            "hasMore": true,
            "nextOffset": 3,
        ]
    }

    do {
        let records = try await client.fetchFullHistory(kernelKey: kernelKey, pageLimit: 50)
        return fail(name, "expected fetchFullHistory to throw on a repeated nextOffset, but it returned \(records.count) records without error")
    } catch {
        print("  [evidence] fetchFullHistory 在检测到 nextOffset 不推进后如实抛错（未静默死循环）：\(error)")
        return pass(name, "stuck cursor（重复 nextOffset=3）被正确识别并 throw，未静默死循环：\(error)")
    }
}

/// 纯函数测试，不需要 actor：验证 `EventMapping.swift` 的 `parseHistoryRecord`/
/// `extractHistoryMessageText` 正确处理字符串 content、数组 block content（且只拼接 "text" 类型的
/// block，忽略 toolCall 等其它类型）、缺失 role 退化为 "unknown"、以及非对象输入安全返回 nil 四种
/// 情况。
func testParseHistoryRecordExtractsStringAndBlockContentIgnoringNonTextBlocks() -> Bool {
    let name = "rounds/0014 C: parseHistoryRecord() extracts text from both string content and array-of-blocks content (ignoring non-text blocks), and defaults missing role to 'unknown'"

    let stringContentRecord = parseHistoryRecord([
        "role": "user", "content": "plain string content",
        "__openclaw": ["id": "id-1", "seq": 7],
    ] as JSONObject)
    guard let r1 = stringContentRecord, r1.role == "user", r1.text == "plain string content", r1.id == "id-1", r1.seq == 7 else {
        return fail(name, "string-content case failed: \(String(describing: stringContentRecord))")
    }

    let blockContentRecord = parseHistoryRecord([
        "role": "assistant",
        "content": [
            ["type": "text", "text": "hello "] as JSONObject,
            ["type": "toolCall", "id": "tool_1", "name": "exec"] as JSONObject,
            ["type": "text", "text": "world"] as JSONObject,
        ] as [Any],
        "__openclaw": ["id": "id-2", "seq": 8],
    ] as JSONObject)
    guard let r2 = blockContentRecord, r2.text == "hello world" else {
        return fail(name, "block-content case failed to concatenate only text blocks and ignore toolCall: \(String(describing: blockContentRecord))")
    }

    let missingRoleRecord = parseHistoryRecord(["content": "no role here"] as JSONObject)
    guard let r3 = missingRoleRecord, r3.role == "unknown" else {
        return fail(name, "missing-role case failed to default to 'unknown': \(String(describing: missingRoleRecord))")
    }

    let notAnObject = parseHistoryRecord("just a string, not a JSON object")
    guard notAnObject == nil else {
        return fail(name, "expected parseHistoryRecord to return nil for a non-object raw value, got \(String(describing: notAnObject))")
    }

    return pass(name, "字符串 content / 数组 block content（正确忽略 toolCall block，只拼接 text）/ 缺失 role 退化为 unknown / 非对象输入返回 nil，四种情况全部符合预期")
}
