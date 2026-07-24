// SG-5 Stage C：跨语言 parity 测试——移植 ../../swift/FrameReplayTests.swift（25 条真 actor 级测试
// 场景，SG-5 rework 第二次收残，对抗审 T-045 codex 确认性再审 MUST-FIX 之后的权威 spec）。
//
// 每个测试函数在 C# 侧的编号/命名与 Swift 源一一对应（`TestXxx` <-> `testXxx`），对**同一组输入
// wire 帧**驱动 C# 的 `OpenclawGatewayKernelClient`/`EventMapping`，断言产出的 D2 KernelEvent 与
// Swift 侧同一场景断言的字段逐一一致（字段值本身抄自 Swift 源的断言，不是另起一套期望值）。
//
// C# 没有 XCTest/SwiftPM 等价物，延续 Swift 源文件头注释同样的风格：每个测试是一个返回 `bool`
// （或 `Task<bool>`）的普通函数，`RunAsync()` 依次跑、打印每条的 PASS/FAIL，最后返回总体是否全过。

#nullable enable
using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text.Json;
using System.Threading;
using System.Threading.Channels;
using System.Threading.Tasks;
using D2;

namespace KernelClient.Tests
{
    using JSONObject = Dictionary<string, object?>;

    public static class FrameReplayTests
    {
        // MARK: - 小工具

        private static bool Fail(string testName, string reason)
        {
            Console.WriteLine($"  [FAIL] {testName}: {reason}");
            return false;
        }

        private static bool Pass(string testName, string detail)
        {
            Console.WriteLine($"  [PASS] {testName}: {detail}");
            return true;
        }

        /// <summary>收集 channel 上最多 maxCount 个事件，超过 timeoutMs 还没凑够就提前放弃。</summary>
        private static async Task<List<EventMessageUnion>> CollectUpToAsync(
            ChannelReader<EventMessageUnion> reader, int maxCount, int timeoutMs = 300)
        {
            var events = new List<EventMessageUnion>();
            using var cts = new CancellationTokenSource(TimeSpan.FromMilliseconds(timeoutMs));
            for (int i = 0; i < maxCount; i++)
            {
                try
                {
                    events.Add(await reader.ReadAsync(cts.Token));
                }
                catch
                {
                    break;
                }
            }
            return events;
        }

        /// <summary>同上，但驱动真实 Subscribe() 返回的 IAsyncEnumerable（不是 TestSupportRegisterSession 的 channel）。</summary>
        private static async Task<List<EventMessageUnion>> CollectUpToAsync(
            IAsyncEnumerable<EventMessageUnion> stream, int maxCount, int timeoutMs = 300)
        {
            var events = new List<EventMessageUnion>();
            using var cts = new CancellationTokenSource(TimeSpan.FromMilliseconds(timeoutMs));
            await using var enumerator = stream.GetAsyncEnumerator(cts.Token);
            for (int i = 0; i < maxCount; i++)
            {
                try
                {
                    if (!await enumerator.MoveNextAsync()) break;
                    events.Add(enumerator.Current);
                }
                catch
                {
                    break;
                }
            }
            return events;
        }

        private static OpenclawGatewayKernelClient FreshClient() =>
            new OpenclawGatewayKernelClient(new Uri("ws://127.0.0.1:1"), "dummy-test-token");

        private static SessionHandle TestHandle(string sessionId, string kernelKey) => new SessionHandle
        {
            Billing = new Billing { TokenRef = "test" },
            CreatedAt = DateTimeOffset.UtcNow,
            Kernel = D2.Kernel.Openclaw,
            KernelSessionId = kernelKey,
            SessionId = sessionId,
        };

        // MARK: - F3：per-run 单调 seq + 保留原始 ts（纯函数，回归覆盖）

        /// <summary>
        /// 镜像 Swift `testSeqOrderingWithinRunAndOriginTS`：同一条 assistant 消息里 text+toolCall
        /// 两个 content block 必须拿到严格递增的 run 内 seq（[1,2]），且 ts 都等于 message.timestamp
        /// 换算值（不是 DateTimeOffset.UtcNow）。
        /// </summary>
        private static bool TestSeqOrderingWithinRunAndOriginTs()
        {
            var name = "F3 seq ordering + origin ts";
            long messageTimestampMs = 1_784_876_055_901;
            var payload = new JSONObject
            {
                ["sessionKey"] = "agent:main:dashboard:test",
                ["message"] = new JSONObject
                {
                    ["role"] = "assistant",
                    ["content"] = new List<object?>
                    {
                        new JSONObject { ["type"] = "text", ["text"] = "先看看目录" },
                        new JSONObject { ["type"] = "toolCall", ["id"] = "tool_abc123", ["name"] = "exec", ["arguments"] = new JSONObject { ["command"] = "ls" } },
                    },
                    ["timestamp"] = messageTimestampMs,
                },
            };
            long counter = 0;
            var events = EventMapping.MapOpenclawSessionMessageToKernelEvents(payload, "s1", "run-1", () => ++counter);
            if (events.Count != 2) return Fail(name, $"expected 2 events (text + toolCall), got {events.Count}");

            var seqs = events.Select(e => e switch
            {
                MessageDeltaEventMessageCase m => m.Value.Seq,
                ToolCallEventMessageCase t => t.Value.Seq,
                _ => -1L,
            }).ToList();
            if (!seqs.SequenceEqual(new long[] { 1, 2 }))
                return Fail(name, $"expected strictly increasing per-run seq [1,2], got [{string.Join(",", seqs)}]");

            var expectedTs = DateTimeOffset.FromUnixTimeMilliseconds(messageTimestampMs);
            foreach (var e in events)
            {
                DateTimeOffset ts = e switch
                {
                    MessageDeltaEventMessageCase m => m.Value.Ts,
                    ToolCallEventMessageCase t => t.Value.Ts,
                    _ => default,
                };
                if (Math.Abs((ts - expectedTs).TotalSeconds) >= 0.001)
                    return Fail(name, $"ts {ts:o} 不等于 message.timestamp 换算值 {expectedTs:o}");
            }
            return Pass(name, $"seq=[{string.Join(",", seqs)}] ts 均等于 message.timestamp（非 DateTimeOffset.UtcNow）");
        }

        // MARK: - F6：无 stopReason 的合法 end 不再默认 error（纯函数，回归覆盖）

        private static bool TestNoStopReasonEndMapsToCompleted()
        {
            var name = "F6 no-stopReason end -> completed (not error)";
            var data = new JSONObject { ["phase"] = "end" };
            long counter = 0;
            var evt = EventMapping.MapOpenclawAgentLifecycleToTurnComplete(data, "s1", "run-1", DateTimeOffset.UtcNow, null, () => ++counter);
            if (evt is not TurnCompleteEventMessageCase tc) return Fail(name, "expected .turnComplete case");
            if (tc.Value.Payload.StopReason != StopReason.Completed)
                return Fail(name, $"expected stopReason=.completed, got {tc.Value.Payload.StopReason}");
            return Pass(name, $"stopReason={tc.Value.Payload.StopReason}");
        }

        private static bool TestUnknownStopReasonAlsoMapsToCompleted()
        {
            var name = "F6 unrecognized stopReason(toolUse) -> completed";
            var data = new JSONObject { ["phase"] = "end", ["stopReason"] = "toolUse" };
            long counter = 0;
            var evt = EventMapping.MapOpenclawAgentLifecycleToTurnComplete(data, "s1", "run-1", DateTimeOffset.UtcNow, null, () => ++counter);
            if (evt is not TurnCompleteEventMessageCase tc || tc.Value.Payload.StopReason != StopReason.Completed)
                return Fail(name, "expected .completed");
            return Pass(name, $"stopReason={tc.Value.Payload.StopReason}");
        }

        // MARK: - M2：lifecycle phase:error 不再误报 completed

        /// <summary>
        /// 修前（db489f0e）fail / 修后 pass：mapper 若忽略 data.phase 只看 stopReason，会把真实的
        /// assistant 错误终止误报成 completed。镜像 Swift `testLifecyclePhaseErrorMapsToErrorStopReasonPureMapper`。
        /// </summary>
        private static bool TestLifecyclePhaseErrorMapsToErrorStopReasonPureMapper()
        {
            var name = "M2 mapper: phase=='error' maps stopReason=.error regardless of stopReason field";
            var data = new JSONObject { ["phase"] = "error", ["stopReason"] = "rpc", ["error"] = "boom" };
            long counter = 0;
            var evt = EventMapping.MapOpenclawAgentLifecycleToTurnComplete(data, "s1", "run-1", DateTimeOffset.UtcNow, null, () => ++counter);
            if (evt is not TurnCompleteEventMessageCase e) return Fail(name, "expected .turnComplete");
            if (e.Value.Payload.StopReason != StopReason.Error)
                return Fail(name, $"expected stopReason=.error, got {e.Value.Payload.StopReason} — 修前默认折叠成 .completed");
            return Pass(name, $"stopReason={e.Value.Payload.StopReason}");
        }

        /// <summary>同上，但走真实 dispatch（HandleAgentEvent 的 "lifecycle" 分支，aborted:false）。</summary>
        private static async Task<bool> TestLifecyclePhaseErrorDispatchesAsErrorStopReason()
        {
            var name = "M2 real dispatch: agent(stream:lifecycle,phase:error,aborted:false) -> turnComplete(stopReason:.error)";
            var client = FreshClient();
            var sessionId = "sess-lifecycle-error-1";
            var runId = "run-lifecycle-error-1";
            var kernelKey = "kernel-key-lifecycle-error";
            var channel = client.TestSupportRegisterSession(sessionId, kernelKey);

            client.TestSupportFeedFrame(new JSONObject
            {
                ["type"] = "event",
                ["event"] = "agent",
                ["payload"] = new JSONObject
                {
                    ["runId"] = runId,
                    ["sessionKey"] = kernelKey,
                    ["stream"] = "lifecycle",
                    ["data"] = new JSONObject { ["phase"] = "error", ["aborted"] = false, ["error"] = "boom: assistant error" },
                    ["ts"] = 1_784_871_600_000L,
                },
            });

            var events = await CollectUpToAsync(channel.Reader, 2);
            if (events.Count != 1 || events[0] is not TurnCompleteEventMessageCase e)
                return Fail(name, $"expected exactly 1 turnComplete event, got {events.Count}");
            if (e.Value.Payload.StopReason != StopReason.Error)
                return Fail(name, $"expected stopReason=.error, got {e.Value.Payload.StopReason} — 修前会被误报为 .completed");
            return Pass(name, "phase:error 正确映射为 turnComplete(stopReason:.error)，未被误报为 completed");
        }

        // MARK: - M1：approval 双向 join（跨 run 不串号 + pending-first 缓冲 + approvalReplay 消费）

        /// <summary>
        /// 修前 fail / 修后 pass：session.approval 落地时若用全 session 的"最近一次 runId"关联，会被
        /// 后到达的 run-B 审批帧串号。镜像 Swift `testApprovalCrossRunDoesNotStealLastActiveRunID`。
        /// </summary>
        private static async Task<bool> TestApprovalCrossRunDoesNotStealLastActiveRunId()
        {
            var name = "M1 approval-A keeps its OWN runId (run-A) even after run-B's approval frame arrives";
            var client = FreshClient();
            var sessionId = "sess-cross-run-1";
            var kernelKey = "kernel-key-cross-run-1";
            var channel = client.TestSupportRegisterSession(sessionId, kernelKey);

            JSONObject AgentApprovalFrame(string runId, string approvalId, string toolCallId) => new JSONObject
            {
                ["type"] = "event",
                ["event"] = "agent",
                ["payload"] = new JSONObject
                {
                    ["runId"] = runId,
                    ["sessionKey"] = kernelKey,
                    ["stream"] = "approval",
                    ["data"] = new JSONObject { ["phase"] = "requested", ["toolCallId"] = toolCallId, ["approvalId"] = approvalId },
                    ["ts"] = 1_784_871_700_000L,
                },
            };
            JSONObject SessionApprovalFrame(string approvalId, long createdAtMs) => new JSONObject
            {
                ["type"] = "event",
                ["event"] = "session.approval",
                ["payload"] = new JSONObject
                {
                    ["sessionKey"] = kernelKey,
                    ["updatedAtMs"] = createdAtMs,
                    ["phase"] = "pending",
                    ["approval"] = new JSONObject
                    {
                        ["id"] = approvalId,
                        ["status"] = "pending",
                        ["presentation"] = new JSONObject { ["kind"] = "exec", ["commandText"] = $"echo {approvalId}" },
                        ["createdAtMs"] = createdAtMs,
                        ["expiresAtMs"] = createdAtMs + 1_800_000,
                    },
                },
            };

            // REPRO 顺序：agent approval-A(run-A) -> agent approval-B(run-B) -> session.approval(approval-A) 才姗姗来迟。
            client.TestSupportFeedFrame(AgentApprovalFrame("run-A", "approval-A", "tool-A"));
            client.TestSupportFeedFrame(AgentApprovalFrame("run-B", "approval-B", "tool-B"));
            client.TestSupportFeedFrame(SessionApprovalFrame("approval-A", 1_784_871_700_100));

            var events = await CollectUpToAsync(channel.Reader, 2);
            if (events.Count != 1 || events[0] is not ApprovalRequestEventMessageCase e)
                return Fail(name, $"expected exactly 1 approvalRequest, got {events.Count}");
            if (e.Value.RunId != "run-A")
                return Fail(name, $"approval-A must keep runId=run-A, got {e.Value.RunId} — 修前会串成 run-B");
            if (e.Value.Payload.ToolCallId != "tool-A")
                return Fail(name, $"unexpected toolCallID {e.Value.Payload.ToolCallId}");
            if (client.TestSupportHasBufferedApproval("approval-A"))
                return Fail(name, "approval-A 的双向 join 缓存应该在成功 join 后被清掉");
            return Pass(name, "approval-A 正确保留 runId=run-A（未被 run-B 的到达串号），join 成功后缓存已清");
        }

        /// <summary>
        /// 修前 fail / 修后 pass：session.approval(pending) 先到达时若查不到 toolCallId 直接丢弃，
        /// approval_request 永久丢失。镜像 Swift `testApprovalPendingFirstIsBufferedNotDropped`。
        /// </summary>
        private static async Task<bool> TestApprovalPendingFirstIsBufferedNotDropped()
        {
            var name = "M1 session.approval arriving BEFORE its agent(stream:approval) frame is buffered, not dropped";
            var client = FreshClient();
            var sessionId = "sess-pending-first-1";
            var kernelKey = "kernel-key-pending-first-1";
            var channel = client.TestSupportRegisterSession(sessionId, kernelKey);

            var approvalId = "approval-pending-first-1";
            client.TestSupportFeedFrame(new JSONObject
            {
                ["type"] = "event",
                ["event"] = "session.approval",
                ["payload"] = new JSONObject
                {
                    ["sessionKey"] = kernelKey,
                    ["updatedAtMs"] = 1_784_871_800_000L,
                    ["phase"] = "pending",
                    ["approval"] = new JSONObject
                    {
                        ["id"] = approvalId,
                        ["status"] = "pending",
                        ["presentation"] = new JSONObject { ["kind"] = "exec", ["commandText"] = "echo pending-first" },
                        ["createdAtMs"] = 1_784_871_800_000L,
                        ["expiresAtMs"] = 1_784_873_600_000L,
                    },
                },
            });

            if (!client.TestSupportHasBufferedApproval(approvalId))
                return Fail(name, "expected the pending session.approval to be buffered while waiting for the agent frame");

            client.TestSupportFeedFrame(new JSONObject
            {
                ["type"] = "event",
                ["event"] = "agent",
                ["payload"] = new JSONObject
                {
                    ["runId"] = "run-pending-first-1",
                    ["sessionKey"] = kernelKey,
                    ["stream"] = "approval",
                    ["data"] = new JSONObject { ["phase"] = "requested", ["toolCallId"] = "tool-pending-first-1", ["approvalId"] = approvalId },
                    ["ts"] = 1_784_871_800_100L,
                },
            });

            var events = await CollectUpToAsync(channel.Reader, 1);
            if (events.Count != 1 || events[0] is not ApprovalRequestEventMessageCase e)
                return Fail(name, $"expected the buffered session.approval to be emitted once the agent frame supplies runId/toolCallId, got {events.Count} — 修前这条 approval_request 永久丢失");
            if (e.Value.Payload.ReqId != approvalId || e.Value.Payload.ToolCallId != "tool-pending-first-1" || e.Value.RunId != "run-pending-first-1")
                return Fail(name, $"unexpected joined fields reqID={e.Value.Payload.ReqId} toolCallID={e.Value.Payload.ToolCallId} runID={e.Value.RunId}");
            if (client.TestSupportHasBufferedApproval(approvalId))
                return Fail(name, "buffer entry should be cleared after successful join");
            return Pass(name, $"session.approval 先到时被正确缓冲，agent 帧补上后正确补发 approvalRequest(reqID={approvalId})");
        }

        /// <summary>
        /// 修前 fail / 修后 pass：subscribe() 若完全不读 approvalReplay 字段，断线重连前就已 pending
        /// 的审批永远不会出现在事件流里。镜像 Swift `testApprovalReplayConsumedFromSubscribeResponse`。
        /// </summary>
        private static async Task<bool> TestApprovalReplayConsumedFromSubscribeResponse()
        {
            var name = "M1 subscribe() consumes approvalReplay + joins with later agent approval frame";
            var client = FreshClient();
            var sessionId = "sess-replay-1";
            var kernelKey = "kernel-key-replay-1";
            client.TestSupportRegisterSession(sessionId, kernelKey);

            var approvalId = "approval-replay-1";
            client.TestSupportStubRpc("sessions.messages.subscribe", _ => Task.FromResult(new JSONObject
            {
                ["subscribed"] = true,
                ["key"] = kernelKey,
                ["approvalReplay"] = new JSONObject
                {
                    ["sessionKey"] = kernelKey,
                    ["updatedAtMs"] = 1_784_871_300_000L,
                    ["truncated"] = false,
                    ["approvals"] = new List<object?>
                    {
                        new JSONObject
                        {
                            ["id"] = approvalId,
                            ["status"] = "pending",
                            ["presentation"] = new JSONObject { ["kind"] = "exec", ["commandText"] = "echo replay" },
                            ["createdAtMs"] = 1_784_871_300_000L,
                            ["expiresAtMs"] = 1_784_873_100_000L,
                            ["urlPath"] = $"/approve/{approvalId}",
                        },
                    },
                },
            }));

            var handle = TestHandle(sessionId, kernelKey);
            var stream = client.Subscribe(handle);
            // 让 subscribe() 内部的后台任务真正跑完 RPC + ConsumeApprovalReplay（真实异步时序，不是 seed）。
            await Task.Delay(150);

            if (!client.TestSupportHasBufferedApproval(approvalId))
                return Fail(name, "expected the approvalReplay entry to be buffered awaiting the agent frame — 修前完全不读这个字段，连缓冲都不会发生");

            client.TestSupportFeedFrame(new JSONObject
            {
                ["type"] = "event",
                ["event"] = "agent",
                ["payload"] = new JSONObject
                {
                    ["runId"] = "run-replay-1",
                    ["sessionKey"] = kernelKey,
                    ["stream"] = "approval",
                    ["data"] = new JSONObject { ["phase"] = "requested", ["toolCallId"] = "tool-replay-1", ["approvalId"] = approvalId },
                    ["ts"] = 1_784_871_300_500L,
                },
            });

            var events = await CollectUpToAsync(stream, 1);
            if (events.Count != 1 || events[0] is not ApprovalRequestEventMessageCase e)
                return Fail(name, $"expected exactly 1 approvalRequest after agent frame arrives, got {events.Count}");
            if (e.Value.Payload.ReqId != approvalId || e.Value.Payload.ToolCallId != "tool-replay-1" || e.Value.RunId != "run-replay-1")
                return Fail(name, $"unexpected fields reqID={e.Value.Payload.ReqId} toolCallID={e.Value.Payload.ToolCallId} runID={e.Value.RunId}");
            return Pass(name, $"approvalReplay 里的 pending 审批被正确缓冲，agent 帧补上后正确 join 产出 approvalRequest(reqID={approvalId})");
        }

        // MARK: - F5：非 exec 工具（item stream）诚实映射（纯函数，回归覆盖）

        private static bool TestNonExecToolItemHonestMapping()
        {
            var name = "F5 non-exec tool (item stream) honest output=null";
            var data = new JSONObject
            {
                ["itemId"] = "tool:tool_p8yLr7taJUMG2ePajv3zPtmR",
                ["phase"] = "end",
                ["kind"] = "tool",
                ["title"] = "tool_call",
                ["status"] = "completed",
                ["name"] = "tool_call",
                ["toolCallId"] = "tool_p8yLr7taJUMG2ePajv3zPtmR",
                ["startedAt"] = 1_784_876_075_348L,
                ["endedAt"] = 1_784_876_075_377L,
            };
            long counter = 0;
            var evt = EventMapping.MapOpenclawAgentToolItemToToolResult(data, "s1", "run-1", DateTimeOffset.UtcNow, () => ++counter);
            if (evt == null) return Fail(name, "expected non-nil toolResult event");
            if (evt is not ToolResultEventMessageCase e) return Fail(name, "expected .toolResult case");
            if (e.Value.Payload.ToolCallId != "tool_p8yLr7taJUMG2ePajv3zPtmR")
                return Fail(name, $"unexpected toolCallID {e.Value.Payload.ToolCallId}");
            if (e.Value.Payload.IsError != false) return Fail(name, "expected isError=false for status=completed");
            if (e.Value.Payload.DurationMs != 29)
                return Fail(name, $"expected durationMS=29 (endedAt-startedAt), got {e.Value.Payload.DurationMs}");
            if (e.Value.Payload.Output != null)
                return Fail(name, $"expected output to be JSON null (honest gap, no output field observed on wire), got {e.Value.Payload.Output}");
            return Pass(name, "toolCallId=tool_p8yLr7taJUMG2ePajv3zPtmR isError=false durationMS=29 output=null（诚实,非编造）");
        }

        private static bool TestExecToolNameFiltering()
        {
            var name = "F5 exec tool name filtering (IsOpenclawExecToolName)";
            if (!EventMapping.IsOpenclawExecToolName("exec")) return Fail(name, "\"exec\" should be treated as exec tool");
            if (!EventMapping.IsOpenclawExecToolName("bash")) return Fail(name, "\"bash\" should be treated as exec tool");
            if (EventMapping.IsOpenclawExecToolName("update_plan")) return Fail(name, "\"update_plan\" should NOT be treated as exec tool");
            if (EventMapping.IsOpenclawExecToolName("tool_call")) return Fail(name, "\"tool_call\" (generic dispatcher name) should NOT be treated as exec tool");
            return Pass(name, "exec/bash 判定为 exec，update_plan/tool_call 判定为非 exec");
        }

        // MARK: - F5：seq gap error 事件（纯函数，回归覆盖）

        private static bool TestSeqGapErrorEvent()
        {
            var name = "F5 seq-gap agent(stream:error) -> evt.error";
            var data = new JSONObject { ["reason"] = "seq gap", ["expected"] = 5L, ["received"] = 8L };
            long counter = 0;
            var evt = EventMapping.MapOpenclawAgentErrorToKernelEvent(data, "s1", "run-1", DateTimeOffset.UtcNow, () => ++counter);
            if (evt == null) return Fail(name, "expected non-nil error event");
            if (evt is not ErrorEventMessageCase e) return Fail(name, "expected .error case");
            if (e.Value.Payload.Code != PayloadCode.Unknown) return Fail(name, $"expected code=.unknown, got {e.Value.Payload.Code}");
            if (e.Value.Payload.NativeCode != "seq gap") return Fail(name, $"expected nativeCode=\"seq gap\", got {e.Value.Payload.NativeCode}");
            if (!e.Value.Payload.Message.Contains("5") || !e.Value.Payload.Message.Contains("8"))
                return Fail(name, $"expected message to mention expected=5/received=8, got {e.Value.Payload.Message}");
            return Pass(name, $"code=unknown nativeCode=\"seq gap\" message=\"{e.Value.Payload.Message}\"");
        }

        // MARK: - F8/M5：shutdown 去重 + 真实 transport close

        private static async Task<bool> TestShutdownThenTransportCloseDedup()
        {
            var name = "F8/M6 shutdown then REAL transport-close dedup";
            var client = FreshClient();
            var sessionId = "sess-shutdown-transport-1";
            var channel = client.TestSupportRegisterSession(sessionId, "kernel-key-shutdown-transport");

            var shutdownFrame = new JSONObject
            {
                ["type"] = "event",
                ["event"] = "shutdown",
                ["payload"] = new JSONObject { ["reason"] = "gateway stopping", ["restartExpectedMs"] = null },
                ["seq"] = 2L,
            };
            client.TestSupportFeedFrame(shutdownFrame);

            if (!client.TestSupportSessionTerminalEmitted(sessionId))
                return Fail(name, "sessionTerminalEmitted should be true right after shutdown");

            // 真实传输层断开（不是又喂一遍同一个 shutdown 帧）。
            client.TestSupportSimulateTransportClosed();

            var events = await CollectUpToAsync(channel.Reader, 2);
            if (events.Count != 1 || events[0] is not SessionEndEventMessageCase e || e.Value.Payload.Reason != PurpleReason.KernelExited)
                return Fail(name, $"expected exactly 1 sessionEnd(kernel_exited) from shutdown, no second one from transport close, got {events.Count} — 修前 shutdown/transportClosed 各自独立 yield,会看到两条矛盾终态");
            return Pass(name, "shutdown 后真实 transport close 未产出第二条矛盾的 sessionEnd（去重生效）");
        }

        // MARK: - M1：send()/stop() 会话锁——真实获取/拒绝/自动释放

        private static async Task<bool> TestSendLockRealAcquireRejectAndRelease()
        {
            var name = "M1 send() real session lock: acquire during in-flight RPC, reject concurrent, auto-release after";
            var client = FreshClient();
            var sessionId = "sess-send-real-lock";
            var kernelKey = "kernel-key-send-real-lock";
            client.TestSupportRegisterSession(sessionId, kernelKey);
            client.TestSupportStubRpc("sessions.send", async _ =>
            {
                await Task.Delay(200); // 200ms 窗口,足够第二次并发 send() 在这期间被拒绝
                return new JSONObject { ["runId"] = "run-real-lock-1", ["status"] = "started", ["messageSeq"] = 1L };
            });
            var handle = TestHandle(sessionId, kernelKey);

            var initialLock = client.TestSupportLockState(sessionId);
            if (initialLock != "idle") return Fail(name, $"expected initial lock idle, got {initialLock}");

            var firstSend = client.SendAsync(handle, new Input { Kind = InputKind.Text, Text = "first" });
            await Task.Delay(40); // 足够第一次 send() 真实拿到锁、进入 RPC 等待

            var lockDuringFlight = client.TestSupportLockState(sessionId);
            if (lockDuringFlight != "send_pending")
                return Fail(name, $"expected lock=send_pending while first send() RPC in flight, got {lockDuringFlight} — 说明锁没有被真实获取");

            try
            {
                await client.SendAsync(handle, new Input { Kind = InputKind.Text, Text = "second" });
                return Fail(name, "expected concurrent second send() to be rejected while first is in flight");
            }
            catch (KernelClientException ex) when (ex.Kind == KernelClientErrorKind.RpcRejected && ex.Code == "session_locked")
            {
                // 期望路径
            }
            catch (Exception ex)
            {
                return Fail(name, $"unexpected error from concurrent send(): {ex}");
            }

            SendResultPayload firstResult;
            try
            {
                firstResult = await firstSend;
            }
            catch
            {
                return Fail(name, "first send() did not complete as expected");
            }
            if (firstResult.RunId != "run-real-lock-1") return Fail(name, "first send() did not complete as expected");

            var lockAfter = client.TestSupportLockState(sessionId);
            if (lockAfter != "idle") return Fail(name, $"expected lock released back to idle after first send() completes, got {lockAfter}");

            return Pass(name, "真实并发下: 第一次 send() 在飞行中持锁 send_pending,第二次被拒 session_locked,完成后锁自动释放回 idle");
        }

        private static async Task<bool> TestSendLockReleasedAfterRpcFailure()
        {
            var name = "M1 send() lock released to idle after RPC throws";
            var client = FreshClient();
            var sessionId = "sess-send-fail-lock";
            var kernelKey = "kernel-key-send-fail-lock";
            client.TestSupportRegisterSession(sessionId, kernelKey);
            client.TestSupportStubRpc("sessions.send", _ => throw new KernelClientException(KernelClientErrorKind.Transport, "simulated send failure"));
            var handle = TestHandle(sessionId, kernelKey);

            try
            {
                await client.SendAsync(handle, new Input { Kind = InputKind.Text, Text = "x" });
                return Fail(name, "expected send() to throw");
            }
            catch (KernelClientException ex) when (ex.Kind == KernelClientErrorKind.Transport)
            {
                // 期望路径
            }
            catch (Exception ex)
            {
                return Fail(name, $"unexpected error {ex}");
            }

            var lockState = client.TestSupportLockState(sessionId);
            if (lockState != "idle") return Fail(name, $"expected lock idle after send() RPC failure, got {lockState}");
            return Pass(name, "send() RPC 抛错后锁正确释放回 idle");
        }

        private static async Task<bool> TestStopRejectedWhileSendInFlight()
        {
            var name = "M1 stop() rejected with session_locked while a REAL send() is in flight";
            var client = FreshClient();
            var sessionId = "sess-stop-vs-send";
            var kernelKey = "kernel-key-stop-vs-send";
            client.TestSupportRegisterSession(sessionId, kernelKey);
            client.TestSupportStubRpc("sessions.send", async _ =>
            {
                await Task.Delay(200);
                return new JSONObject { ["runId"] = "run-x", ["status"] = "started", ["messageSeq"] = 1L };
            });
            var handle = TestHandle(sessionId, kernelKey);

            var sendTask = client.SendAsync(handle, new Input { Kind = InputKind.Text, Text = "x" });
            await Task.Delay(40);

            try
            {
                await client.StopAsync(handle);
                try { await sendTask; } catch { /* best effort drain */ }
                return Fail(name, "expected stop() to be rejected while send() is in flight");
            }
            catch (KernelClientException ex) when (ex.Kind == KernelClientErrorKind.RpcRejected && ex.Code == "session_locked")
            {
                try { await sendTask; } catch { }
                return Pass(name, "stop() 在真实 send() 飞行期间被正确 reject(session_locked)");
            }
            catch (Exception ex)
            {
                try { await sendTask; } catch { }
                return Fail(name, $"unexpected error {ex}");
            }
        }

        // MARK: - M3：stop() 状态机——真实调用四条路径 + 锁/pendingStop 清理

        private static async Task<bool> TestStopNoActiveRunEmitsOperationCompletedMirror()
        {
            var name = "M3 stop() no active run -> operation_completed(succeeded) mirror + Promise succeeded";
            var client = FreshClient();
            var sessionId = "sess-stop-noactive";
            var kernelKey = "kernel-key-stop-noactive";
            var channel = client.TestSupportRegisterSession(sessionId, kernelKey);
            client.TestSupportStubRpc("sessions.abort", _ => Task.FromResult(new JSONObject { ["ok"] = true, ["abortedRunId"] = null, ["status"] = "no-active-run" }));
            client.TestSupportStubRpc("sessions.delete", _ => Task.FromResult(new JSONObject { ["deleted"] = true }));
            var handle = TestHandle(sessionId, kernelKey);

            StopResultPayload result;
            try { result = await client.StopAsync(handle); }
            catch { return Fail(name, "stop() unexpectedly threw"); }
            if (result.Outcome != StopResultPayloadOutcome.Succeeded)
                return Fail(name, $"expected Promise outcome=.succeeded, got {result.Outcome}");

            var events = await CollectUpToAsync(channel.Reader, 3);
            if (events.Count != 2)
                return Fail(name, $"expected 2 events (operation_completed mirror + session_end), got {events.Count} — 修前这条路径只发 session_end,完全没有 operation_completed 镜像");
            if (events[0] is not OperationCompletedEventMessageCase op)
                return Fail(name, $"expected first event .operationCompleted, got {events[0].WireType}");
            if (op.Value.Payload.OperationId != result.OperationId || op.Value.Payload.Outcome != PayloadOutcome.Succeeded)
                return Fail(name, $"operationCompleted must mirror Promise: got id={op.Value.Payload.OperationId} outcome={op.Value.Payload.Outcome}, Promise id={result.OperationId}");
            if (events[1] is not SessionEndEventMessageCase end || end.Value.Payload.Reason != PurpleReason.Stopped)
                return Fail(name, "expected second event sessionEnd(reason:.stopped)");
            return Pass(name, $"operationId={result.OperationId} 双通道 outcome 均为 succeeded,session_end(stopped) 紧随其后");
        }

        private static async Task<bool> TestStopTimeoutEmitsOperationCompletedMirror()
        {
            var name = "M3 stop() waiting for aborted-run terminal times out -> operation_completed(timed_out) mirror";
            var client = FreshClient();
            var sessionId = "sess-stop-timeout";
            var kernelKey = "kernel-key-stop-timeout";
            var channel = client.TestSupportRegisterSession(sessionId, kernelKey);
            client.TestSupportSetStopTimeoutSeconds(1);
            client.TestSupportStubRpc("sessions.abort", _ => Task.FromResult(new JSONObject { ["ok"] = true, ["abortedRunId"] = "run-timeout-1", ["status"] = "aborted" }));
            client.TestSupportStubRpc("sessions.delete", _ => Task.FromResult(new JSONObject { ["deleted"] = true }));
            var handle = TestHandle(sessionId, kernelKey);

            StopResultPayload result;
            try { result = await client.StopAsync(handle); }
            catch { return Fail(name, "stop() unexpectedly threw"); }
            if (result.Outcome != StopResultPayloadOutcome.TimedOut)
                return Fail(name, $"expected Promise outcome=.timedOut, got {result.Outcome}");

            var events = await CollectUpToAsync(channel.Reader, 3, 800);
            if (events.Count != 2)
                return Fail(name, $"expected 2 events (operation_completed(timed_out) mirror + session_end), got {events.Count} — 修前这条路径 Promise 会报 timedOut 但 Event 完全没有镜像");
            if (events[0] is not OperationCompletedEventMessageCase op || op.Value.Payload.Outcome != PayloadOutcome.TimedOut || op.Value.Payload.OperationId != result.OperationId)
                return Fail(name, $"expected operation_completed(timed_out) mirroring Promise operationId={result.OperationId}");
            return Pass(name, $"超时路径 operationId={result.OperationId} Promise 与 Event 均报 timed_out");
        }

        private static async Task<bool> TestStopDeleteFailureDoesNotContradictAlreadyEmittedOutcome()
        {
            var name = "M3 stop() active-run success + sessions.delete deleted:false must not contradict already-emitted operation_completed(succeeded)";
            var client = FreshClient();
            var sessionId = "sess-stop-deletefail";
            var kernelKey = "kernel-key-stop-deletefail";
            var runId = "run-deletefail-1";
            var channel = client.TestSupportRegisterSession(sessionId, kernelKey);

            // 用一条无害的 run_status 帧模拟"目前有一个活跃 run"这一前置状态（刷新 lastRunId），走真实 dispatch。
            client.TestSupportFeedFrame(new JSONObject
            {
                ["type"] = "event",
                ["event"] = "agent",
                ["payload"] = new JSONObject { ["runId"] = runId, ["sessionKey"] = kernelKey, ["stream"] = "run_status", ["data"] = new JSONObject() },
            });

            client.TestSupportStubRpc("sessions.abort", _ => Task.FromResult(new JSONObject { ["ok"] = true, ["abortedRunId"] = runId, ["status"] = "aborted" }));
            client.TestSupportStubRpc("sessions.delete", _ => Task.FromResult(new JSONObject { ["deleted"] = false }));
            var handle = TestHandle(sessionId, kernelKey);

            var stopTask = client.StopAsync(handle);
            // stop() 此刻已经发起 sessions.abort 并开始等待该 run 的 aborted lifecycle 终态——喂一条真实
            // 形状的 aborted lifecycle 帧,唤醒等待、发出 operation_completed(succeeded)+turn_complete(cancelled)。
            await Task.Delay(60);
            client.TestSupportFeedFrame(new JSONObject
            {
                ["type"] = "event",
                ["event"] = "agent",
                ["payload"] = new JSONObject
                {
                    ["runId"] = runId,
                    ["sessionKey"] = kernelKey,
                    ["stream"] = "lifecycle",
                    ["data"] = new JSONObject { ["phase"] = "end", ["status"] = "cancelled", ["aborted"] = true, ["stopReason"] = "rpc" },
                    ["ts"] = 1_784_871_400_000L,
                },
            });

            StopResultPayload result;
            try { result = await stopTask; }
            catch { return Fail(name, "stop() unexpectedly threw"); }
            if (result.Outcome != StopResultPayloadOutcome.Succeeded)
                return Fail(name, $"expected Promise outcome=.succeeded despite sessions.delete deleted:false, got {result.Outcome} — 修前会把它翻成 .rejected,与已经发出的 operation_completed(succeeded) 矛盾");

            var events = await CollectUpToAsync(channel.Reader, 4);
            if (events.Count != 3)
                return Fail(name, $"expected exactly 3 events (operation_completed + turn_complete(cancelled) + session_end(stopped)), got {events.Count}");
            if (events[0] is not OperationCompletedEventMessageCase op || op.Value.Payload.Outcome != PayloadOutcome.Succeeded || op.Value.Payload.OperationId != result.OperationId)
                return Fail(name, "expected first event operation_completed(succeeded) matching Promise operationId");
            if (events[1] is not TurnCompleteEventMessageCase turn || turn.Value.Payload.StopReason != StopReason.Cancelled)
                return Fail(name, "expected second event turn_complete(cancelled)");
            if (events[2] is not SessionEndEventMessageCase end || end.Value.Payload.Reason != PurpleReason.Stopped)
                return Fail(name, "expected third event session_end(stopped)");
            return Pass(name, $"operationId={result.OperationId}: Promise=.succeeded, Event.outcome=.succeeded 一致,即使 sessions.delete 报告 deleted:false");
        }

        private static async Task<bool> TestStopAbortRpcThrowReleasesLockAndEmitsRejectedMirror()
        {
            var name = "M3 stop() sessions.abort throws -> lock released + pendingStop cleaned + operation_completed(rejected) mirror; second stop() not falsely session_locked";
            var client = FreshClient();
            var sessionId = "sess-stop-abort-throws";
            var kernelKey = "kernel-key-stop-abort-throws";
            var channel = client.TestSupportRegisterSession(sessionId, kernelKey);
            client.TestSupportStubRpc("sessions.abort", _ => throw new KernelClientException(KernelClientErrorKind.Transport, "simulated: kernel client not connected"));
            var handle = TestHandle(sessionId, kernelKey);

            try
            {
                await client.StopAsync(handle);
                return Fail(name, "expected stop() to rethrow the abort RPC error");
            }
            catch (KernelClientException ex) when (ex.Kind == KernelClientErrorKind.Transport)
            {
                if (!ex.Message.Contains("simulated")) return Fail(name, $"unexpected transport error message {ex.Message}");
            }
            catch (Exception ex)
            {
                return Fail(name, $"expected KernelClientException(Transport), got {ex}");
            }

            var lockAfterFailure = client.TestSupportLockState(sessionId);
            if (lockAfterFailure != "idle")
                return Fail(name, $"expected lock released to idle after abort throw, got {lockAfterFailure} — 修前锁永久卡在 stop_in_progress");
            if (client.TestSupportHasPendingStop(sessionId))
                return Fail(name, "expected pendingStop to be cleaned up after abort throw");

            var events = await CollectUpToAsync(channel.Reader, 1, 200);
            if (events.Count != 1 || events[0] is not OperationCompletedEventMessageCase op || op.Value.Payload.Outcome != PayloadOutcome.Rejected)
                return Fail(name, $"expected operation_completed(rejected) mirror after abort throw, got {events.Count} events");

            // 关键复现：第二次 stop() 不应该被 session_locked 拒绝——它应该照样命中同一个 stub,再次抛出同样
            // 的 transport 错误,证明锁真的被释放了(不是被绕过)。
            try
            {
                await client.StopAsync(handle);
                return Fail(name, "expected second stop() to also throw the stubbed transport error");
            }
            catch (KernelClientException ex) when (ex.Kind == KernelClientErrorKind.RpcRejected && ex.Code == "session_locked")
            {
                return Fail(name, "second stop() incorrectly rejected with session_locked — 锁没有被正确释放,复现了修前的永久锁死缺陷");
            }
            catch (KernelClientException ex) when (ex.Kind == KernelClientErrorKind.Transport)
            {
                return Pass(name, "第一次 stop() 抛错后锁正确释放为 idle + pendingStop 清理 + operation_completed(rejected) 镜像已发出;第二次 stop() 正常再次尝试(而不是被 session_locked 挡住)");
            }
            catch (Exception ex)
            {
                return Fail(name, $"unexpected error on second stop(): {ex}");
            }
        }

        private static async Task<bool> TestStopCleansUpAllSessionCaches()
        {
            var name = "M5 stop() success cleans up pendingStop/lock/terminal flag/orphaned approval buffer";
            var client = FreshClient();
            var sessionId = "sess-cleanup-1";
            var kernelKey = "kernel-key-cleanup-1";
            client.TestSupportRegisterSession(sessionId, kernelKey);

            // 留一个"从未匹配上"的 pending-first 审批缓冲。
            client.TestSupportFeedFrame(new JSONObject
            {
                ["type"] = "event",
                ["event"] = "session.approval",
                ["payload"] = new JSONObject
                {
                    ["sessionKey"] = kernelKey,
                    ["updatedAtMs"] = 1_784_871_500_000L,
                    ["phase"] = "pending",
                    ["approval"] = new JSONObject
                    {
                        ["id"] = "approval-orphan-1",
                        ["status"] = "pending",
                        ["presentation"] = new JSONObject { ["kind"] = "exec", ["commandText"] = "echo orphan" },
                        ["createdAtMs"] = 1_784_871_500_000L,
                        ["expiresAtMs"] = 1_784_873_300_000L,
                    },
                },
            });
            if (!client.TestSupportHasBufferedApproval("approval-orphan-1"))
                return Fail(name, "expected the orphan pending-first approval to be buffered before cleanup");

            client.TestSupportStubRpc("sessions.abort", _ => Task.FromResult(new JSONObject { ["ok"] = true, ["abortedRunId"] = null, ["status"] = "no-active-run" }));
            client.TestSupportStubRpc("sessions.delete", _ => Task.FromResult(new JSONObject { ["deleted"] = true }));
            var handle = TestHandle(sessionId, kernelKey);
            try { await client.StopAsync(handle); } catch { /* not the focus of this test */ }

            if (client.TestSupportLockState(sessionId) != "idle") return Fail(name, "lock should be cleared (idle) after stop()");
            if (client.TestSupportHasPendingStop(sessionId)) return Fail(name, "pendingStop should be removed after stop()");
            if (client.TestSupportSessionTerminalEmitted(sessionId))
                return Fail(name, "sessionTerminalEmitted should be cleared after full session teardown — 修前这个标记永远不清,长连接下会无限增长");
            if (client.TestSupportHasBufferedApproval("approval-orphan-1"))
                return Fail(name, "orphaned pending-first approval buffer should be cleaned up on session teardown — 修前只有 join 成功才清,漏配对的条目永久残留");
            return Pass(name, "stop() 收尾后 lock/pendingStop/terminal 标记/未匹配的 approval 缓冲全部清理干净");
        }

        // MARK: - F2：attachment-only（附件编码成 openclaw 期望的 content 形状，纯函数，回归覆盖）

        private static bool TestAttachmentOnlyEncodesContent()
        {
            var name = "F2 attachment-only encodes content (not {mimeType,path})";
            var filePath = Path.Combine(Path.GetTempPath(), $"frame-replay-attachment-{Guid.NewGuid()}.txt");
            var fileBytes = System.Text.Encoding.UTF8.GetBytes("hello-sg5-attachment");
            try
            {
                File.WriteAllBytes(filePath, fileBytes);
            }
            catch (Exception ex)
            {
                return Fail(name, $"failed to write temp fixture file: {ex}");
            }

            try
            {
                var part = new Part { Kind = PartKind.FileRef, Text = null, MimeType = "text/plain", Path = filePath };
                var encoded = OpenclawWire.EncodeAttachmentForWire(part);
                if (encoded == null) return Fail(name, "expected non-nil encoded attachment");
                if (encoded.ContainsKey("path"))
                    return Fail(name, "encoded attachment must NOT carry a bare 'path' field — openclaw would silently drop it (no content)");
                if (OpenclawWire.JsonString(encoded.Get("content")) is not string content)
                    return Fail(name, $"expected 'content' field (base64), got keys {string.Join(",", encoded.Keys.OrderBy(k => k))}");
                byte[] decoded;
                try
                {
                    decoded = Convert.FromBase64String(content);
                }
                catch
                {
                    return Fail(name, "content did not base64-decode");
                }
                if (!decoded.SequenceEqual(fileBytes)) return Fail(name, "content did not base64-decode back to the original file bytes");
                if (OpenclawWire.JsonString(encoded.Get("mimeType")) != "text/plain") return Fail(name, "expected mimeType=text/plain to be preserved");
                return Pass(name, "content(base64) 正确还原原始字节，且不再携带裸 path 字段");
            }
            finally
            {
                try { File.Delete(filePath); } catch { }
            }
        }

        // MARK: - M4：脱敏——复数/常见变体漏报 + token 计数字段误伤

        private static bool TestRedactionCoversPluralsAndCommonVariants()
        {
            var name = "M4 redaction covers plurals + common credential variants";
            var cases = new (string Key, string Value)[]
            {
                ("credentials", "live-credential-value"),
                ("apiKeys", "live-api-key-value"),
                ("secrets", "live-secret-value"),
                ("authToken", "live-auth-token-value"),
                ("apiToken", "live-api-token-value"),
                ("password", "live-password-value"),
                ("token", "live-bare-token-value"),
            };
            foreach (var (key, value) in cases)
            {
                var obj = new JSONObject { [key] = value };
                var redacted = OpenclawWire.RedactedCopy(obj) as JSONObject;
                if (redacted == null || (redacted.Get(key) as string) != "***REDACTED***")
                    return Fail(name, $"expected {key} 整体脱敏, got {redacted?.Get(key)} — 修前 {key} 会漏报(复数/未覆盖变体)");
            }
            return Pass(name, "credentials/apiKeys/secrets(复数)、authToken/apiToken(复合)、password/token(裸字段) 全部正确脱敏");
        }

        private static bool TestRedactionExcludesTokenCountingFields()
        {
            var name = "M4 redaction excludes token-counting fields (contextTokens/tokenBudget/inputTokens/outputTokens)";
            var cases = new (string Key, long Value)[]
            {
                ("contextTokens", 200_000),
                ("tokenBudget", 128_000),
                ("inputTokens", 9288),
                ("outputTokens", 2346),
            };
            foreach (var (key, value) in cases)
            {
                var obj = new JSONObject { [key] = value };
                var redacted = OpenclawWire.RedactedCopy(obj) as JSONObject;
                var actual = redacted?.Get(key);
                if (redacted == null || !(actual is long l && l == value))
                    return Fail(name, $"expected {key}={value} 保持不脱敏, got {actual} — 误伤了 token 计数字段");
            }
            return Pass(name, "contextTokens/tokenBudget/inputTokens/outputTokens 均保持原值，未被误伤");
        }

        private static bool TestCredentialRedactionRegressionRealFrame()
        {
            var name = "F7 regression: credential redaction (auth/token) on a realistic connect frame";
            var frame = new JSONObject
            {
                ["type"] = "req",
                ["id"] = "r1",
                ["method"] = "connect",
                ["params"] = new JSONObject
                {
                    ["minProtocol"] = 3L,
                    ["auth"] = new JSONObject { ["token"] = "super-secret-real-token-value" },
                    ["client"] = new JSONObject { ["id"] = "cli", ["mode"] = "cli" },
                },
            };
            var redacted = OpenclawWire.RedactedCopy(frame) as JSONObject;
            var paramsObj = redacted?.Get("params") as JSONObject;
            if (paramsObj == null) return Fail(name, "unexpected redacted shape");
            if ((paramsObj.Get("auth") as string) != "***REDACTED***")
                return Fail(name, $"expected params.auth to be fully redacted, got {paramsObj.Get("auth")}");
            if (!(paramsObj.Get("minProtocol") is long mp && mp == 3))
                return Fail(name, "non-sensitive field params.minProtocol should survive unchanged");
            var client = paramsObj.Get("client") as JSONObject;
            if (client == null || (client.Get("id") as string) != "cli")
                return Fail(name, "non-sensitive nested field params.client.id should survive unchanged");

            var serialized = JsonSerializer.Serialize(redacted);
            if (serialized.Contains("super-secret-real-token-value"))
                return Fail(name, "raw token value leaked into redacted copy's string representation");
            return Pass(name, "auth 字段整体脱敏，非敏感字段保留，明文 token 未出现在序列化结果里");
        }

        // MARK: - M6：完整 D2 JSON encode/decode 字段断言

        private static bool TestFullD2JsonEncodeDecodeRoundTrip()
        {
            var name = "M6 完整 D2 JSON encode/decode 字段断言（toolResult + operationCompleted）";
            var now = DateTimeOffset.FromUnixTimeSeconds(1_784_871_900);

            var toolResultPayload = new ToolResultEventMessagePayload
            {
                DurationMs = 42,
                IsError = false,
                Output = new JSONObject { ["stdout"] = "hello", ["lines"] = new List<object?> { 1L, 2L, 3L } },
                ToolCallId = "tool-roundtrip-1",
            };
            var toolResultEvent = new ToolResultEventMessage
            {
                Direction = MessageDeltaEventMessageDirection.Event,
                Payload = toolResultPayload,
                RunId = "run-roundtrip-1",
                SentAt = now,
                Seq = 7,
                SessionId = "sess-roundtrip-1",
                Ts = now,
                Type = ToolResultEventMessageType.EvtToolResult,
            }.AsUnion();

            string data;
            try { data = JsonSerializer.Serialize(toolResultEvent, D2.Converter.Settings); }
            catch { return Fail(name, "toolResult encode failed"); }
            EventMessageUnion? decoded;
            try { decoded = JsonSerializer.Deserialize<EventMessageUnion>(data, D2.Converter.Settings); }
            catch { return Fail(name, "toolResult decode failed"); }
            if (decoded is not ToolResultEventMessageCase decodedToolResultCase) return Fail(name, $"decoded into wrong case: {decoded?.WireType}");
            var decodedToolResult = decodedToolResultCase.Value;
            if (decodedToolResult.Payload.ToolCallId != "tool-roundtrip-1" ||
                decodedToolResult.Payload.DurationMs != 42 ||
                decodedToolResult.Payload.IsError != false ||
                decodedToolResult.RunId != "run-roundtrip-1" ||
                decodedToolResult.Seq != 7 ||
                decodedToolResult.SessionId != "sess-roundtrip-1" ||
                decodedToolResult.Type != ToolResultEventMessageType.EvtToolResult)
            {
                return Fail(name, "toolResult round-tripped scalar fields do not match original");
            }

            // Output 字段声明类型是 object——反序列化时 System.Text.Json 默认把它落成 JsonElement（不是
            // Dictionary），这里统一转换成 Dictionary/List 结构再断言，只看结构等价，不看运行时具体类型。
            var outputValue = decodedToolResult.Payload.Output is JsonElement outEl
                ? OpenclawWire.ConvertElement(outEl)
                : decodedToolResult.Payload.Output;
            if (outputValue is not JSONObject outputDict ||
                (outputDict.Get("stdout") as string) != "hello" ||
                outputDict.Get("lines") is not List<object?> lines || lines.Count != 3)
            {
                return Fail(name, $"nested output did not round-trip structurally: {outputValue}");
            }

            var opPayload = new OperationCompletedEventMessagePayload
            {
                AffectedRunId = "run-op-1",
                Detail = "aborted by user",
                NewRunId = null,
                OperationId = "op-roundtrip-1",
                OperationKind = OperationKind.Stop,
                Outcome = PayloadOutcome.TimedOut,
            };
            var opEvent = new OperationCompletedEventMessage
            {
                Direction = MessageDeltaEventMessageDirection.Event,
                Payload = opPayload,
                RunId = "run-op-1",
                SentAt = now,
                Seq = 9,
                SessionId = "sess-roundtrip-1",
                Ts = now,
                Type = OperationCompletedEventMessageType.EvtOperationCompleted,
            }.AsUnion();

            string opData;
            try { opData = JsonSerializer.Serialize(opEvent, D2.Converter.Settings); }
            catch { return Fail(name, "operationCompleted encode failed"); }
            EventMessageUnion? opDecoded;
            try { opDecoded = JsonSerializer.Deserialize<EventMessageUnion>(opData, D2.Converter.Settings); }
            catch { return Fail(name, "operationCompleted decode failed"); }
            if (opDecoded is not OperationCompletedEventMessageCase decodedOpCase) return Fail(name, $"decoded into wrong case: {opDecoded?.WireType}");
            var decodedOp = decodedOpCase.Value;
            if (decodedOp.Payload.OperationId != "op-roundtrip-1" ||
                decodedOp.Payload.Outcome != PayloadOutcome.TimedOut ||
                decodedOp.Payload.AffectedRunId != "run-op-1" ||
                decodedOp.Payload.NewRunId != null ||
                decodedOp.Payload.OperationKind != OperationKind.Stop ||
                decodedOp.Payload.Detail != "aborted by user")
            {
                return Fail(name, "operationCompleted round-tripped fields do not match");
            }

            return Pass(name, "toolResult(嵌套 output)与 operationCompleted 两个变体的完整 D2 JSON encode/decode 均字段级一致；" +
                               $"toolResult JSON = {data}");
        }

        // MARK: - 总入口

        public static async Task<bool> RunAsync()
        {
            Console.WriteLine("=== SG-5 Stage C C# parity frame-replay 单测（镜像 Swift FrameReplayTests.swift）===");
            var results = new List<bool>
            {
                TestSeqOrderingWithinRunAndOriginTs(),
                TestNoStopReasonEndMapsToCompleted(),
                TestUnknownStopReasonAlsoMapsToCompleted(),
                TestLifecyclePhaseErrorMapsToErrorStopReasonPureMapper(),
                await TestLifecyclePhaseErrorDispatchesAsErrorStopReason(),
                await TestApprovalCrossRunDoesNotStealLastActiveRunId(),
                await TestApprovalPendingFirstIsBufferedNotDropped(),
                await TestApprovalReplayConsumedFromSubscribeResponse(),
                TestNonExecToolItemHonestMapping(),
                TestExecToolNameFiltering(),
                TestSeqGapErrorEvent(),
                await TestShutdownThenTransportCloseDedup(),
                await TestSendLockRealAcquireRejectAndRelease(),
                await TestSendLockReleasedAfterRpcFailure(),
                await TestStopRejectedWhileSendInFlight(),
                await TestStopNoActiveRunEmitsOperationCompletedMirror(),
                await TestStopTimeoutEmitsOperationCompletedMirror(),
                await TestStopDeleteFailureDoesNotContradictAlreadyEmittedOutcome(),
                await TestStopAbortRpcThrowReleasesLockAndEmitsRejectedMirror(),
                await TestStopCleansUpAllSessionCaches(),
                TestAttachmentOnlyEncodesContent(),
                TestRedactionCoversPluralsAndCommonVariants(),
                TestRedactionExcludesTokenCountingFields(),
                TestCredentialRedactionRegressionRealFrame(),
                TestFullD2JsonEncodeDecodeRoundTrip(),
            };

            var passCount = results.Count(r => r);
            var total = results.Count;
            Console.WriteLine($"=== 结果: {passCount}/{total} PASS ===");
            return passCount == total;
        }
    }
}
