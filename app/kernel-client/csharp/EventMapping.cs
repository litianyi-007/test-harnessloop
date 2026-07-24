// SG-5 Stage C：openclaw 事件 -> D2 EventMessageUnion（11 变体）映射——C# 镜像
// ../swift/EventMapping.swift（748 行，SG-5 rework 权威 spec，两轮对抗审 T-044/T-045 + 真 e2e 已验证
// 正确）。每个函数逐一对应 Swift 侧同名函数，文档注释只记"C# 与 Swift 的表达差异"，字段级 grounding
// （真实样本/源码引用）见 Swift 源文件，不在此重复誊抄。
//
// 关键表达差异：
//   - Swift `EventMessageUnion` 是带关联值的 enum（`.toolResult(ToolResultEventMessage)`）；C#
//     判别联合（DiscriminatedUnions.cs）是『抽象基类 + 具体 Case 子类』，这里用 `AsUnion()` 扩展方法
//     （见文末）把具体 `XxxEventMessage` 包成 `EventMessageUnion`，语义等价于 Swift 的 case 构造。
//   - Swift 用 `JSONAny`（借道 JSONEncoder/Decoder 往返）表达"取不到真实值时的诚实 JSON null"；C# 的
//     D2 DTO 对应字段（ToolCallEventMessagePayload.Input / ToolResultEventMessagePayload.Output /
//     ApprovalRequestEventMessagePayload.Payload）声明类型就是 `object?`，且未标
//     `[JsonIgnore(WhenWritingNull)]`——直接赋值 `null` 就会在序列化时忠实产出 JSON `null`，不需要
//     Swift 那样的 NSNull 包装往返，这是 C#/System.Text.Json 语义带来的简化，行为等价。
//   - `nextSeq` 闭包类型是 `Func<long>`（D2 C# 的 Seq 字段是 `long`），对应 Swift 的 `() -> Int`。

#nullable enable
using System;
using System.Collections.Generic;
using System.Linq;
using D2;

namespace KernelClient
{
    using JSONObject = Dictionary<string, object?>;

    /// <summary>
    /// 把具体 `XxxEventMessage` 包成判别联合 `EventMessageUnion` 的具体 Case——对应 Swift
    /// `.caseName(msg)` 的构造写法，C# 没有枚举关联值，用扩展方法把这层样板代码集中在一处。
    /// </summary>
    public static class EventUnionExtensions
    {
        public static EventMessageUnion AsUnion(this MessageDeltaEventMessage m) => new MessageDeltaEventMessageCase { Value = m };
        public static EventMessageUnion AsUnion(this ThinkingEventMessage m) => new ThinkingEventMessageCase { Value = m };
        public static EventMessageUnion AsUnion(this ToolCallEventMessage m) => new ToolCallEventMessageCase { Value = m };
        public static EventMessageUnion AsUnion(this ToolResultEventMessage m) => new ToolResultEventMessageCase { Value = m };
        public static EventMessageUnion AsUnion(this ApprovalRequestEventMessage m) => new ApprovalRequestEventMessageCase { Value = m };
        public static EventMessageUnion AsUnion(this ErrorEventMessage m) => new ErrorEventMessageCase { Value = m };
        public static EventMessageUnion AsUnion(this TurnCompleteEventMessage m) => new TurnCompleteEventMessageCase { Value = m };
        public static EventMessageUnion AsUnion(this SessionEndEventMessage m) => new SessionEndEventMessageCase { Value = m };
        public static EventMessageUnion AsUnion(this CapabilityChangedEventMessage m) => new CapabilityChangedEventMessageCase { Value = m };
        public static EventMessageUnion AsUnion(this OperationCompletedEventMessage m) => new OperationCompletedEventMessageCase { Value = m };
        public static EventMessageUnion AsUnion(this ApprovalBufferResolvedEventMessage m) => new ApprovalBufferResolvedEventMessageCase { Value = m };
    }

    public static class EventMapping
    {
        // MARK: - ① session.message -> messageDelta / thinking / toolCall

        public static List<EventMessageUnion> MapOpenclawSessionMessageToKernelEvents(
            JSONObject payload, string ourSessionId, string? runIdHint, Func<long> nextSeq)
        {
            var message = OpenclawWire.JsonObj(payload.Get("message"));
            if (message == null) return new List<EventMessageUnion>();
            if (OpenclawWire.JsonString(message.Get("role")) != "assistant") return new List<EventMessageUnion>();

            var sentAt = DateTimeOffset.UtcNow;
            var originTs = OpenclawWire.MsEpochToDate(OpenclawWire.JsonInt(message.Get("timestamp")));
            var events = new List<EventMessageUnion>();

            var content = message.Get("content");
            List<JSONObject> blocks;
            if (OpenclawWire.JsonArr(content) is List<object?> arr)
            {
                blocks = arr.Select(OpenclawWire.JsonObj).Where(o => o != null).Select(o => o!).ToList();
            }
            else if (OpenclawWire.JsonString(content) is string text)
            {
                blocks = new List<JSONObject> { new JSONObject { ["type"] = "text", ["text"] = text } };
            }
            else
            {
                blocks = new List<JSONObject>();
            }

            for (int index = 0; index < blocks.Count; index++)
            {
                var block = blocks[index];
                var type = OpenclawWire.JsonString(block.Get("type"));
                if (type == null) continue;
                switch (type)
                {
                    case "text":
                    {
                        var text = OpenclawWire.JsonString(block.Get("text"));
                        if (text == null) continue;
                        var deltaPayload = new MessageDeltaEventMessagePayload { Delta = text, Index = index, Role = Role.Assistant };
                        events.Add(new MessageDeltaEventMessage
                        {
                            Direction = MessageDeltaEventMessageDirection.Event, Payload = deltaPayload, RunId = runIdHint,
                            SentAt = sentAt, Seq = nextSeq(), SessionId = ourSessionId, Ts = originTs, Type = MessageDeltaEventMessageType.EvtMessageDelta,
                        }.AsUnion());
                        break;
                    }

                    case "thinking":
                    case "reasoning":
                    case "redacted_thinking":
                    {
                        var delta = OpenclawWire.JsonString(block.Get("text")) ?? OpenclawWire.JsonString(block.Get("thinking")) ?? "";
                        var visibility = type == "redacted_thinking" ? Visibility.Summary : Visibility.Raw;
                        var thinkingPayload = new ThinkingEventMessagePayload { Delta = delta, Visibility = visibility };
                        events.Add(new ThinkingEventMessage
                        {
                            Direction = MessageDeltaEventMessageDirection.Event, Payload = thinkingPayload, RunId = runIdHint,
                            SentAt = sentAt, Seq = nextSeq(), SessionId = ourSessionId, Ts = originTs, Type = ThinkingEventMessageType.EvtThinking,
                        }.AsUnion());
                        break;
                    }

                    case "toolCall":
                    case "tool_call":
                    case "toolUse":
                    case "tool_use":
                    {
                        var toolCallId = OpenclawWire.JsonString(block.Get("id"));
                        var name = OpenclawWire.JsonString(block.Get("name"));
                        if (toolCallId == null || name == null) continue;
                        var input = block.Get("arguments") ?? block.Get("input") ?? new JSONObject();
                        var toolCallPayload = new ToolCallEventMessagePayload { Input = input, Name = name, Status = Status.Started, ToolCallId = toolCallId };
                        events.Add(new ToolCallEventMessage
                        {
                            Direction = MessageDeltaEventMessageDirection.Event, Payload = toolCallPayload, RunId = runIdHint,
                            SentAt = sentAt, Seq = nextSeq(), SessionId = ourSessionId, Ts = originTs, Type = ToolCallEventMessageType.EvtToolCall,
                        }.AsUnion());
                        break;
                    }

                    default:
                        // 未识别的 content block type——如实跳过，不臆造映射。
                        continue;
                }
            }

            return events;
        }

        // MARK: - ② agent(stream:"command_output") -> toolResult（exec 工具族）

        public static EventMessageUnion? MapOpenclawAgentCommandOutputToToolResult(
            JSONObject data, string ourSessionId, string? runIdHint, DateTimeOffset originTs, Func<long> nextSeq)
        {
            if (OpenclawWire.JsonString(data.Get("phase")) != "end") return null;
            var toolCallId = OpenclawWire.JsonString(data.Get("toolCallId"));
            if (toolCallId == null) return null;

            var status = OpenclawWire.JsonString(data.Get("status"));
            var exitCode = OpenclawWire.JsonInt(data.Get("exitCode"));
            var isError = status == "failed" || (exitCode ?? 0) != 0;
            var output = data.Get("output") ?? "";
            var durationMs = OpenclawWire.JsonInt(data.Get("durationMs"));

            var resultPayload = new ToolResultEventMessagePayload { DurationMs = durationMs, IsError = isError, Output = output, ToolCallId = toolCallId };
            return new ToolResultEventMessage
            {
                Direction = MessageDeltaEventMessageDirection.Event, Payload = resultPayload, RunId = runIdHint,
                SentAt = DateTimeOffset.UtcNow, Seq = nextSeq(), SessionId = ourSessionId, Ts = originTs, Type = ToolResultEventMessageType.EvtToolResult,
            }.AsUnion();
        }

        // MARK: - ②b agent(stream:"item", kind:"tool") -> toolResult（非 exec 工具族）

        public static EventMessageUnion? MapOpenclawAgentToolItemToToolResult(
            JSONObject data, string ourSessionId, string? runIdHint, DateTimeOffset originTs, Func<long> nextSeq)
        {
            if (OpenclawWire.JsonString(data.Get("kind")) != "tool") return null;
            if (OpenclawWire.JsonString(data.Get("phase")) != "end") return null;
            var toolCallId = OpenclawWire.JsonString(data.Get("toolCallId"));
            if (toolCallId == null) return null;

            var status = OpenclawWire.JsonString(data.Get("status"));
            var isError = status != "completed";
            long? durationMs = null;
            var started = OpenclawWire.JsonInt(data.Get("startedAt"));
            var ended = OpenclawWire.JsonInt(data.Get("endedAt"));
            if (started.HasValue && ended.HasValue) durationMs = Math.Max(0, ended.Value - started.Value);

            // 诚实置空——非 exec 工具的 output 字段本轮无真实来源，不编造（见 Swift 源同名函数文档注释）。
            var resultPayload = new ToolResultEventMessagePayload { DurationMs = durationMs, IsError = isError, Output = null, ToolCallId = toolCallId };
            return new ToolResultEventMessage
            {
                Direction = MessageDeltaEventMessageDirection.Event, Payload = resultPayload, RunId = runIdHint,
                SentAt = DateTimeOffset.UtcNow, Seq = nextSeq(), SessionId = ourSessionId, Ts = originTs, Type = ToolResultEventMessageType.EvtToolResult,
            }.AsUnion();
        }

        /// <summary>
        /// exec 工具名词表——与 openclaw `isExecToolName` 逐字对应（"exec" 或 "bash"）。
        /// </summary>
        public static bool IsOpenclawExecToolName(string? name) => name == "exec" || name == "bash";

        // MARK: - ③ agent(stream:"lifecycle") -> turnComplete / operationCompleted

        public static EventMessageUnion MapOpenclawAgentLifecycleToTurnComplete(
            JSONObject data, string ourSessionId, string runId, DateTimeOffset originTs,
            (long Input, long Output)? cachedUsage, Func<long> nextSeq)
        {
            var phase = OpenclawWire.JsonString(data.Get("phase"));
            var rawStopReason = OpenclawWire.JsonString(data.Get("stopReason"));
            StopReason stopReason;
            if (phase == "error")
            {
                // M2：phase 本身就是 assistant 错误终止的权威信号——不看 stopReason 字段。
                stopReason = StopReason.Error;
            }
            else
            {
                stopReason = rawStopReason switch
                {
                    "max_turns" or "maxTurns" => StopReason.MaxTurns,
                    _ => StopReason.Completed,
                };
            }
            Usage? usage = cachedUsage.HasValue
                ? new Usage { InputTokens = cachedUsage.Value.Input, OutputTokens = cachedUsage.Value.Output }
                : null;
            var turnPayload = new TurnCompleteEventMessagePayload { Degraded = null, ForceResolvedApprovals = null, StopReason = stopReason, Usage = usage };
            return new TurnCompleteEventMessage
            {
                Direction = MessageDeltaEventMessageDirection.Event, Payload = turnPayload, RunId = runId,
                SentAt = DateTimeOffset.UtcNow, Seq = nextSeq(), SessionId = ourSessionId, Ts = originTs, Type = TurnCompleteEventMessageType.EvtTurnComplete,
            }.AsUnion();
        }

        public static List<EventMessageUnion> MapOpenclawAgentLifecycleToAbortTerminalEvents(
            JSONObject data, string ourSessionId, string runId, string operationId, DateTimeOffset originTs,
            (long Input, long Output)? cachedUsage, Func<long> nextSeq)
        {
            var phase = OpenclawWire.JsonString(data.Get("phase"));
            var outcome = phase == "end" ? PayloadOutcome.Succeeded : PayloadOutcome.AbortedEffectUnknown;
            var detail = OpenclawWire.JsonString(data.Get("error"));
            var opPayload = new OperationCompletedEventMessagePayload
            {
                AffectedRunId = runId, Detail = detail, NewRunId = null,
                OperationId = operationId, OperationKind = OperationKind.Stop, Outcome = outcome,
            };
            var operationCompletedEvent = new OperationCompletedEventMessage
            {
                Direction = MessageDeltaEventMessageDirection.Event, Payload = opPayload, RunId = runId,
                SentAt = DateTimeOffset.UtcNow, Seq = nextSeq(), SessionId = ourSessionId, Ts = originTs, Type = OperationCompletedEventMessageType.EvtOperationCompleted,
            }.AsUnion();

            Usage? usage = cachedUsage.HasValue
                ? new Usage { InputTokens = cachedUsage.Value.Input, OutputTokens = cachedUsage.Value.Output }
                : null;
            var turnPayload = new TurnCompleteEventMessagePayload { Degraded = null, ForceResolvedApprovals = null, StopReason = StopReason.Cancelled, Usage = usage };
            var turnCompleteEvent = new TurnCompleteEventMessage
            {
                Direction = MessageDeltaEventMessageDirection.Event, Payload = turnPayload, RunId = runId,
                SentAt = DateTimeOffset.UtcNow, Seq = nextSeq(), SessionId = ourSessionId, Ts = originTs, Type = TurnCompleteEventMessageType.EvtTurnComplete,
            }.AsUnion();

            return new List<EventMessageUnion> { operationCompletedEvent, turnCompleteEvent };
        }

        // MARK: - ④ session.approval -> approvalRequest（toolCallID 关联走双向 join，见 KernelClient）

        public static EventMessageUnion? MapOpenclawSessionApprovalToKernelEvent(
            JSONObject payload, string ourSessionId, string? runIdHint, string? toolCallIdForApprovalId, Func<long> nextSeq)
        {
            if (OpenclawWire.JsonString(payload.Get("phase")) != "pending") return null;
            var approval = OpenclawWire.JsonObj(payload.Get("approval"));
            if (approval == null) return null;
            var reqId = OpenclawWire.JsonString(approval.Get("id"));
            if (reqId == null) return null;
            if (toolCallIdForApprovalId == null) return null;
            if (runIdHint == null) return null;
            var runId = runIdHint;

            var presentation = OpenclawWire.JsonObj(approval.Get("presentation")) ?? new JSONObject();
            var openclawKind = OpenclawWire.JsonString(presentation.Get("kind"));
            var kind = openclawKind == "exec" ? KindElement.Exec : KindElement.Tool;

            var createdAtMs = OpenclawWire.JsonInt(approval.Get("createdAtMs"));
            var expiresAtMs = OpenclawWire.JsonInt(approval.Get("expiresAtMs"));
            long timeoutMs = (createdAtMs.HasValue && expiresAtMs.HasValue) ? expiresAtMs.Value - createdAtMs.Value : 0;

            var approvalPayload = new ApprovalRequestEventMessagePayload
            {
                Kind = kind, Payload = presentation, ProposedDecision = null, ReqId = reqId,
                TimeoutAuthority = TimeoutAuthority.Documented, TimeoutMs = timeoutMs, ToolCallId = toolCallIdForApprovalId,
            };
            var originTs = OpenclawWire.MsEpochToDate(OpenclawWire.JsonInt(payload.Get("updatedAtMs")));
            return new ApprovalRequestEventMessage
            {
                Direction = MessageDeltaEventMessageDirection.Event, Payload = approvalPayload, RunId = runId,
                SentAt = DateTimeOffset.UtcNow, Seq = nextSeq(), SessionId = ourSessionId, Ts = originTs, Type = ApprovalRequestEventMessageType.EvtApprovalRequest,
            }.AsUnion();
        }

        // MARK: - ⑤ agent(stream:"thinking") -> thinking

        public static EventMessageUnion? MapOpenclawAgentThinkingToKernelEvent(
            JSONObject data, string ourSessionId, string? runIdHint, DateTimeOffset originTs, Func<long> nextSeq)
        {
            var delta = OpenclawWire.JsonString(data.Get("delta")) ?? OpenclawWire.JsonString(data.Get("text")) ?? "";
            var thinkingPayload = new ThinkingEventMessagePayload { Delta = delta, Visibility = Visibility.Raw };
            return new ThinkingEventMessage
            {
                Direction = MessageDeltaEventMessageDirection.Event, Payload = thinkingPayload, RunId = runIdHint,
                SentAt = DateTimeOffset.UtcNow, Seq = nextSeq(), SessionId = ourSessionId, Ts = originTs, Type = ThinkingEventMessageType.EvtThinking,
            }.AsUnion();
        }

        // MARK: - ⑥ agent(stream:"error") -> error

        public static EventMessageUnion? MapOpenclawAgentErrorToKernelEvent(
            JSONObject data, string ourSessionId, string? runIdHint, DateTimeOffset originTs, Func<long> nextSeq)
        {
            var reason = OpenclawWire.JsonString(data.Get("reason"));
            string message;
            string? nativeCode;
            if (reason == "seq gap")
            {
                var expected = OpenclawWire.JsonInt(data.Get("expected"));
                var received = OpenclawWire.JsonInt(data.Get("received"));
                message = $"event stream seq gap: expected {(expected.HasValue ? expected.Value.ToString() : "?")}, got {(received.HasValue ? received.Value.ToString() : "?")}";
                nativeCode = "seq gap";
            }
            else
            {
                message = reason ?? OpenclawWire.JsonString(data.Get("message")) ?? "unrecognized agent error stream payload";
                nativeCode = reason;
            }
            var errorPayload = new ErrorEventMessagePayload { Code = PayloadCode.Unknown, Message = message, NativeCode = nativeCode, Recoverable = Recoverable.Run };
            return new ErrorEventMessage
            {
                Direction = MessageDeltaEventMessageDirection.Event, Payload = errorPayload, RunId = runIdHint,
                SentAt = DateTimeOffset.UtcNow, Seq = nextSeq(), SessionId = ourSessionId, Ts = originTs, Type = ErrorEventMessageType.EvtError,
            }.AsUnion();
        }

        // MARK: - ⑦ 全局 shutdown / transportClosed / stop -> sessionEnd

        public static EventMessageUnion MakeSessionEndEventForShutdown(string ourSessionId, Func<long> nextSeq)
        {
            var now = DateTimeOffset.UtcNow;
            var payload = new SessionEndEventMessagePayload { Reason = PurpleReason.KernelExited };
            return new SessionEndEventMessage
            {
                Direction = MessageDeltaEventMessageDirection.Event, Payload = payload, RunId = null,
                SentAt = now, Seq = nextSeq(), SessionId = ourSessionId, Ts = now, Type = SessionEndEventMessageType.EvtSessionEnd,
            }.AsUnion();
        }

        public static EventMessageUnion MakeSessionEndEventForTransportClosed(string ourSessionId, Func<long> nextSeq)
        {
            var now = DateTimeOffset.UtcNow;
            var payload = new SessionEndEventMessagePayload { Reason = PurpleReason.TransportClosed };
            return new SessionEndEventMessage
            {
                Direction = MessageDeltaEventMessageDirection.Event, Payload = payload, RunId = null,
                SentAt = now, Seq = nextSeq(), SessionId = ourSessionId, Ts = now, Type = SessionEndEventMessageType.EvtSessionEnd,
            }.AsUnion();
        }

        public static EventMessageUnion MakeSessionEndEventForStop(string ourSessionId, Func<long> nextSeq)
        {
            var now = DateTimeOffset.UtcNow;
            var payload = new SessionEndEventMessagePayload { Reason = PurpleReason.Stopped };
            return new SessionEndEventMessage
            {
                Direction = MessageDeltaEventMessageDirection.Event, Payload = payload, RunId = null,
                SentAt = now, Seq = nextSeq(), SessionId = ourSessionId, Ts = now, Type = SessionEndEventMessageType.EvtSessionEnd,
            }.AsUnion();
        }

        // MARK: - ⑧ 两个仍诚实标 unsupported 的变体：capabilityChanged / approvalBufferResolved
        //
        // 镜像 Swift 侧 `buildCapabilityChangedEvent`/`buildApprovalBufferResolvedEvent`——本轮仍未接入
        // 任何真实触发路径，只证明 D2 payload 在类型层面能正确构造，未被任何 dispatch 分支调用。

        public static EventMessageUnion BuildCapabilityChangedEvent(
            Capabilit capabilities, string? reason, Source source, string ourSessionId, long seq)
        {
            var now = DateTimeOffset.UtcNow;
            var payload = new CapabilityChangedEventMessagePayload { Capabilities = capabilities, Reason = reason, Source = source };
            return new CapabilityChangedEventMessage
            {
                Direction = MessageDeltaEventMessageDirection.Event, Payload = payload, RunId = null,
                SentAt = now, Seq = seq, SessionId = ourSessionId, Ts = now, Type = CapabilityChangedEventMessageType.EvtCapabilityChanged,
            }.AsUnion();
        }

        public static EventMessageUnion BuildApprovalBufferResolvedEvent(
            string reqId, FluffyReason reason, string ourSessionId, long seq)
        {
            var now = DateTimeOffset.UtcNow;
            var payload = new ApprovalBufferResolvedEventMessagePayload { Reason = reason, ReqId = reqId };
            return new ApprovalBufferResolvedEventMessage
            {
                Direction = MessageDeltaEventMessageDirection.Event, Payload = payload, RunId = null,
                SentAt = now, Seq = seq, SessionId = ourSessionId, Ts = now, Type = ApprovalBufferResolvedEventMessageType.EvtApprovalBufferResolved,
            }.AsUnion();
        }
    }
}
