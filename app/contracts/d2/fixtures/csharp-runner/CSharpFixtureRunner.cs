// SG-8.7 Stage B：C# 金标 parity runner——驱动 SG-5 交付的真实 `OpenclawGatewayKernelClient`
// （app/kernel-client/csharp/OpenclawGatewayKernelClient.cs），不是另写一个假内核。逐机制镜像
// ../swift-runner/SwiftFixtureRunner.swift（该文件是权威参考实现，已过 T-048/T-050/T-051 三轮异构
// 审查收敛）——本文件的每个机制在被写下的第一行就带着 Stage A 已经付过学费的纪律，不重新踩坑：
//   - `client_call` 真调 CreateSessionAsync/SendAsync/Subscribe/StopAsync（经 TestSupport 钩子
//     stub RPC/喂帧），绝不另写 mock 内核。
//   - `expect_outbound` 从真实捕获的 native `params`（`RecordOutbound` 记录，stub 闭包同步收到的
//     原始入参）规范化后匹配，不是把 timeline 的 `args` 或 fixture 声明值抄回去验证自己。
//   - `nativeCallOrder` 在 `approval.resolve`/`sessions.abort` 两个 stub 闭包**真正被真实 client
//     调用的那一刻**（不是注册的时刻）append。
//   - `advance_clock`/`disconnect` 轮询『任务已结算』（`IsCallSettled`），不是固定 sleep 猜调度。
//   - `interrupt`/`respondApproval`/`capabilities` 三个方法本轮仍是 SG-5 TODO 桩——含它们的 fixture
//     在执行前就被 `DegradeReason` 静态扫描标记 DEGRADED，不伪造假内核让它“通过”。
//
// ============================================================================================
// C# 与 Swift 的表达差异总览（镜像 OpenclawGatewayKernelClient.cs 文件头同款差异记录）
// ============================================================================================
//   - Swift 用 `actor` 隔离 RunnerContext 的全部可变状态；C# 没有 actor，这里用一个共享的 `_sync`
//     （`lock` 语句）保护——同 OpenclawGatewayKernelClient.cs 自己的既定做法，不是本文件独创。
//   - Swift 的 `ReplyGate` 是一个 `actor`（`resolve`/`wait` 两个 actor-isolated 方法）；C# 版本用
//     `lock` + `TaskCompletionSource<JSONObject>` 表达同样的『延迟解锁』语义。
//   - `OpenclawGatewayKernelClient` 的 `TestSupportLockState`/`TestSupportStubRpc`/
//     `TestSupportFeedFrame`/`TestSupportSetStopTimeoutSeconds`/`TestSupportSimulateTransportClosed`
//     在 C# 侧全部是**同步**方法（`lock` 而非 actor hop）——不需要 Swift 那样在几乎每个调用点都
//     `await`，`RunnerContext` 因此也比 Swift 版本少了很多 `async`/`await` 噪音，只有真正跨越
//     `Task.Delay` 的地方（`OnStopResolvedAsync`/`OnStopThrewAsync`/`ApplyMockEventAsync` 的帧间
//     停顿/`ApplyAdvanceClockAsync` 的轮询）才是 `async`。
//
// ============================================================================================
// 已知的『无法翻译』边界（诚实降级，不伪造）——与 Swift 侧完全一致
// ============================================================================================
// 见 `DegradeReason`（interrupt/respondApproval/capabilities）与 `ExpectOutboundMethodTable`
// （只覆盖 Stage A/B 用到的四个 D2 方法）的文档注释。

#nullable enable
using System;
using System.Collections.Generic;
using System.Linq;
using System.Text.Json;
using System.Threading.Tasks;
using D2;
using KernelClient;

namespace CSharpRunner
{
    using JSONObject = Dictionary<string, object?>;

    public sealed class RunnerException : Exception
    {
        public RunnerException(string message) : base($"csharp-runner 内部错误（fixture 或翻译层不匹配）：{message}") { }
    }

    /// <summary>
    /// 单次 RPC 响应的『延迟解锁』——responder 闭包 `await gate.Wait()`，runner 处理到对应
    /// `mock_response` timeline op 时才 `ResolveSuccess`/`ResolveFailure`，让真实 client 的
    /// `RequestAsync` 真的悬挂到那一刻才返回，从而让『client_call 在途/锁在途』这类中途 assert_state
    /// 断言的是真实状态而非摆拍。镜像 Swift `actor ReplyGate`，用 `lock` 代替 actor 隔离（见文件头
    /// 表达差异总览）。
    /// </summary>
    internal sealed class ReplyGate
    {
        private readonly object _lock = new();
        private bool _resolved;
        private JSONObject? _value;
        private Exception? _error;
        private TaskCompletionSource<JSONObject>? _waiter;

        public void ResolveSuccess(JSONObject value)
        {
            TaskCompletionSource<JSONObject>? waiter;
            lock (_lock)
            {
                if (_resolved) return;
                _resolved = true;
                _value = value;
                waiter = _waiter;
                _waiter = null;
            }
            waiter?.TrySetResult(value);
        }

        public void ResolveFailure(Exception error)
        {
            TaskCompletionSource<JSONObject>? waiter;
            lock (_lock)
            {
                if (_resolved) return;
                _resolved = true;
                _error = error;
                waiter = _waiter;
                _waiter = null;
            }
            waiter?.TrySetException(error);
        }

        public Task<JSONObject> Wait()
        {
            lock (_lock)
            {
                if (_resolved)
                    return _error != null ? Task.FromException<JSONObject>(_error) : Task.FromResult(_value!);
                _waiter = new TaskCompletionSource<JSONObject>(TaskCreationOptions.RunContinuationsAsynchronously);
                return _waiter.Task;
            }
        }
    }

    /// <summary>一次 fixture 执行期间的全部可变状态——`_sync` 保护，镜像 Swift `actor RunnerContext`。</summary>
    public sealed class RunnerContext
    {
        public readonly OpenclawGatewayKernelClient Client;

        /// <summary>真实收窄后的 stop() 等待超时——见 `SwiftFixtureRunner.swift` 同名常量的说明。</summary>
        public const int StopTimeoutSeconds = 1;
        public const int StopTimeoutMs = 1000;

        private readonly object _sync = new();

        private SessionHandle? _currentSessionHandle;
        private string? _currentSessionId;
        private string? _currentKernelKey;
        private string? _currentRunId;

        /// <summary>原生 `kernelKey` -&gt; fixture 在 `res.createSession` 里声明过的
        /// `sessionHandle.sessionId`——供 `NormalizeNativeParams` 从真实捕获的原生 `key` 反查，见该
        /// 方法文档注释（对应 Swift `kernelKeyToDeclaredSessionID`）。</summary>
        private readonly Dictionary<string, string> _kernelKeyToDeclaredSessionId = new();

        private string? _waitingStopCallId;
        private readonly Dictionary<string, string> _callKindById = new();
        private readonly Dictionary<string, ReplyGate> _replyGates = new();

        /// <summary>真实捕获到的原生 RPC 调用——`(method, params)`，`params` 是 `TestSupportStubRpc`
        /// 闭包收到的原始入参（真实 client 同步传入，不是 fixture 声明值）。</summary>
        private readonly Dictionary<string, (string Method, JSONObject Params)> _capturedOutbound = new();

        /// <summary>真实原生 RPC 调用顺序——只登记 `approval.resolve`/`sessions.abort`，在 stub 闭包
        /// **真正被调用的那一刻**（不是注册的时刻）append，供 `stop-force-denies-pending-approval`
        /// fixture 断言 D1 §6.2 M3 定序。</summary>
        private readonly List<string> _nativeCallOrder = new();

        private readonly Dictionary<string, object?> _pendingOperations = new();
        private readonly Dictionary<string, object?> _callOutcomes = new();
        private readonly Dictionary<string, object?> _approvalState = new();
        private readonly List<Dictionary<string, object?>> _drainedEvents = new();
        private readonly List<Task> _pendingTasks = new();
        private readonly List<string> _accumulatedMismatches = new();
        private bool _hasStopWaitingForTerminal;

        public RunnerContext(OpenclawGatewayKernelClient client) => Client = client;

        public SessionHandle? CurrentSessionHandle { get { lock (_sync) return _currentSessionHandle; } }
        public string? CurrentSessionId { get { lock (_sync) return _currentSessionId; } }
        public string? CurrentKernelKey { get { lock (_sync) return _currentKernelKey; } }
        public string? CurrentRunId { get { lock (_sync) return _currentRunId; } }
        public bool HasStopWaitingForTerminal { get { lock (_sync) return _hasStopWaitingForTerminal; } }
        public string? WaitingStopCallId { get { lock (_sync) return _waitingStopCallId; } }

        public void SetCallKind(string id, string call) { lock (_sync) _callKindById[id] = call; }
        public string? CallKind(string id) { lock (_sync) return _callKindById.TryGetValue(id, out var v) ? v : null; }

        internal void SetGate(string id, ReplyGate gate) { lock (_sync) _replyGates[id] = gate; }
        internal ReplyGate? Gate(string id) { lock (_sync) return _replyGates.TryGetValue(id, out var g) ? g : null; }

        public void RecordOutbound(string id, string method, JSONObject parameters)
        {
            lock (_sync) _capturedOutbound[id] = (method, parameters);
        }

        public string? CapturedOutboundMethod(string id)
        {
            lock (_sync) return _capturedOutbound.TryGetValue(id, out var v) ? v.Method : null;
        }

        public JSONObject? CapturedParams(string id)
        {
            lock (_sync) return _capturedOutbound.TryGetValue(id, out var v) ? v.Params : null;
        }

        /// <summary>`res.createSession` 处理时登记——见 `_kernelKeyToDeclaredSessionId` 文档注释。</summary>
        public void RegisterDeclaredSession(string kernelKey, string sessionId)
        {
            lock (_sync) _kernelKeyToDeclaredSessionId[kernelKey] = sessionId;
        }

        /// <summary>从真实捕获的原生 `key` 反查已声明 session——查不到返回 null（调用方据此显式置
        /// <see cref="JsonNullMarker.Instance"/>，不 fallback，见 `NormalizeNativeParams`）。</summary>
        public string? DeclaredSessionId(string kernelKey)
        {
            lock (_sync) return _kernelKeyToDeclaredSessionId.TryGetValue(kernelKey, out var v) ? v : null;
        }

        public void AppendNativeCall(string name) { lock (_sync) _nativeCallOrder.Add(name); }

        public void SetCurrentKernelKey(string key) { lock (_sync) _currentKernelKey = key; }
        public void SetHasStopWaitingForTerminal(bool value) { lock (_sync) _hasStopWaitingForTerminal = value; }
        public void SetWaitingStopCallId(string? id) { lock (_sync) _waitingStopCallId = id; }

        public void SetCallOutcomeResolved(string id)
        {
            lock (_sync) _callOutcomes[id] = new Dictionary<string, object?> { ["status"] = "resolved" };
        }

        /// <summary>`advance_clock`/`disconnect` 用来判定『这次 stop() 的最终结果是否已经结算』的同步
        /// 目标——`OnStopResolvedAsync`/`OnStopThrewAsync` 写完 `pendingOperations`/`callOutcomes`
        /// 才算数，这正是随后 `assert_state` 要读的同一份状态（镜像 Swift `isCallSettled`）。</summary>
        public bool IsCallSettled(string id)
        {
            lock (_sync) return _pendingOperations.ContainsKey(id) || _callOutcomes.ContainsKey(id);
        }

        public void AppendMismatch(string m) { lock (_sync) _accumulatedMismatches.Add(m); }
        public List<string> AccumulatedMismatches() { lock (_sync) return new List<string>(_accumulatedMismatches); }

        public void AddPendingTask(Task task) { lock (_sync) _pendingTasks.Add(task); }

        public void OnCreateSessionResolved(string id, SessionHandle handle)
        {
            lock (_sync)
            {
                _currentSessionHandle = handle;
                _currentSessionId = handle.SessionId;
                _callOutcomes[id] = new Dictionary<string, object?> { ["status"] = "resolved" };
            }
        }

        public void OnSendResolved(string id, SendResultPayload result)
        {
            lock (_sync)
            {
                _currentRunId = result.RunId;
                _callOutcomes[id] = new Dictionary<string, object?> { ["status"] = "resolved" };
            }
        }

        public void OnCallThrew(string id, Exception error)
        {
            lock (_sync)
            {
                _callOutcomes[id] = new Dictionary<string, object?>
                {
                    ["status"] = "rejected",
                    ["failure"] = CSharpFixtureRunner.FailureDict(error),
                };
            }
        }

        /// <summary>
        /// 镜像 Swift `onStopResolved` 的 `settleForEventDrain`：`EmitOperationCompletedMirror` 在真实
        /// `StopAsync` 内部是同步调用（`channel.Writer.TryWrite`），但写入被 `StartDraining` 的排空
        /// Task 异步消费、再回写 `_drainedEvents`，这一步经过 .NET 线程池调度，不与 `StopAsync` 的
        /// throw/return 同步——本方法从另一个 Task（`client_call` 的包装 Task）在 `StopAsync` 刚返回的
        /// 瞬间调用，如果不等待，可能在排空 Task 真正把镜像事件写进 `_drainedEvents` 之前就已经读完
        /// （同 Swift 侧文档注释复现的 flaky 结果）。
        /// </summary>
        public async Task OnStopResolvedAsync(string id, StopResultPayload result, int eventsCountAtStart)
        {
            lock (_sync) _hasStopWaitingForTerminal = false;
            await Task.Delay(80);
            lock (_sync)
            {
                var outcome = FirstOperationCompletedOutcomeLocked(eventsCountAtStart);
                _pendingOperations[id] = outcome ?? CSharpFixtureRunner.WireEnumValue(result.Outcome);
            }
        }

        public async Task OnStopThrewAsync(string id, Exception error, int eventsCountAtStart)
        {
            lock (_sync) _hasStopWaitingForTerminal = false;

            // `session_locked` 是 StopAsync 顶部 `currentLock != Idle` 前置 guard 直接抛出的——发生在
            // `operationId` 铸造之前，真实 client 绝不会为这次调用产出任何 operation_completed 镜像
            // 事件。这个分支不用等，等了也白等（镜像 Swift 同名分支的文档注释）。
            if (error is KernelClientException kce && kce.Kind == KernelClientErrorKind.RpcRejected && kce.Code == "session_locked")
            {
                lock (_sync)
                {
                    _callOutcomes[id] = new Dictionary<string, object?>
                    {
                        ["status"] = "rejected",
                        ["failure"] = CSharpFixtureRunner.FailureDict(error),
                    };
                }
                return;
            }

            await Task.Delay(80);
            lock (_sync)
            {
                var outcome = FirstOperationCompletedOutcomeLocked(eventsCountAtStart);
                if (outcome != null)
                {
                    // operationId 已铸造、RPC 中途失败——OperationOutcome 层面的终态，走
                    // pendingOperations（D1 v3.1 §9.1）。
                    _pendingOperations[id] = outcome;
                }
                else
                {
                    // 没有 operation_completed 镜像——这次 stop() 在铸造 operationId 之前就被同步拒绝，
                    // 根本没有进入 OperationOutcome 通道，改记 callOutcomes。
                    _callOutcomes[id] = new Dictionary<string, object?>
                    {
                        ["status"] = "rejected",
                        ["failure"] = CSharpFixtureRunner.FailureDict(error),
                    };
                }
            }
        }

        /// <summary>调用前必须持有 `_sync`（内部辅助，不单独加锁）。</summary>
        private string? FirstOperationCompletedOutcomeLocked(int index)
        {
            if (index > _drainedEvents.Count) return null;
            for (var i = index; i < _drainedEvents.Count; i++)
            {
                var entry = _drainedEvents[i];
                if (entry.TryGetValue("type", out var t) && t as string == "evt.operation_completed" &&
                    entry.TryGetValue("payload", out var p) && p is Dictionary<string, object?> payload &&
                    payload.TryGetValue("outcome", out var o) && o is string outcome)
                {
                    return outcome;
                }
            }
            return null;
        }

        public void AppendEvent(Dictionary<string, object?> entry)
        {
            lock (_sync)
            {
                _drainedEvents.Add(entry);
                if (entry.TryGetValue("type", out var t) && t as string == "evt.approval_request" &&
                    entry.TryGetValue("payload", out var p) && p is Dictionary<string, object?> payload &&
                    payload.TryGetValue("reqId", out var r) && r is string reqId)
                {
                    _approvalState[reqId] = "pending";
                }
            }
        }

        public void StartDraining(IAsyncEnumerable<EventMessageUnion> stream)
        {
            var task = Task.Run(async () =>
            {
                try
                {
                    await foreach (var evt in stream)
                        AppendEvent(CSharpFixtureRunner.EventToObservedEntry(evt));
                }
                catch
                {
                    // 事件流以错误结束——停止排空，同 Swift 版本 catch 后 break，不让排空 Task 崩溃。
                }
            });
            lock (_sync) _pendingTasks.Add(task);
        }

        public int DrainedEventsCount() { lock (_sync) return _drainedEvents.Count; }

        public Dictionary<string, object?> Snapshot()
        {
            lock (_sync)
            {
                return new Dictionary<string, object?>
                {
                    ["pendingOperations"] = new Dictionary<string, object?>(_pendingOperations),
                    ["callOutcomes"] = new Dictionary<string, object?>(_callOutcomes),
                    ["approvalState"] = new Dictionary<string, object?>(_approvalState),
                    ["observedEvents"] = _drainedEvents.Select(e => (object?)e).ToList(),
                    ["nativeCallOrder"] = _nativeCallOrder.Select(s => (object?)s).ToList(),
                };
            }
        }

        public Dictionary<string, object?> SnapshotWithLock()
        {
            var snap = Snapshot();
            var sid = CurrentSessionId;
            if (sid != null) snap["sessionLock"] = Client.TestSupportLockState(sid);
            return snap;
        }
    }

    public enum FixtureRunOutcomeKind { Passed, Failed, Degraded }

    public sealed class FixtureRunResult
    {
        public string Name = "";
        public string Path = "";
        public FixtureRunOutcomeKind Outcome;
        public List<string> Mismatches = new();
        public string? DegradedReason;
    }

    public static class CSharpFixtureRunner
    {
        // MARK: - 事件/失败编码小工具

        public static Dictionary<string, object?> EncodeToJsonObject(object payload)
        {
            var json = JsonSerializer.Serialize(payload, D2.Converter.Settings);
            using var doc = JsonDocument.Parse(json);
            return FixtureJson.ToActual(doc.RootElement) as Dictionary<string, object?> ?? new Dictionary<string, object?>();
        }

        public static Dictionary<string, object?> EventToObservedEntry(EventMessageUnion evt)
        {
            object payloadObj = evt switch
            {
                MessageDeltaEventMessageCase e => e.Value.Payload,
                ThinkingEventMessageCase e => e.Value.Payload,
                ToolCallEventMessageCase e => e.Value.Payload,
                ToolResultEventMessageCase e => e.Value.Payload,
                ApprovalRequestEventMessageCase e => e.Value.Payload,
                ErrorEventMessageCase e => e.Value.Payload,
                TurnCompleteEventMessageCase e => e.Value.Payload,
                SessionEndEventMessageCase e => e.Value.Payload,
                CapabilityChangedEventMessageCase e => e.Value.Payload,
                OperationCompletedEventMessageCase e => e.Value.Payload,
                ApprovalBufferResolvedEventMessageCase e => e.Value.Payload,
                _ => throw new RunnerException($"未知 EventMessageUnion case：{evt.GetType()}"),
            };
            return new Dictionary<string, object?> { ["type"] = evt.WireType, ["payload"] = EncodeToJsonObject(payloadObj) };
        }

        /// <summary>枚举 -&gt; D2 wire 字符串——复用 `D2.Converter.Settings` 里已经注册好的枚举
        /// JsonConverter（`JsonSerializer.Serialize` 对枚举类型走对应的 Converter），不手工重抄一份
        /// switch 映射（避免和 D2.cs 生成的转换表漂移）。</summary>
        public static string WireEnumValue<T>(T value) where T : struct, Enum =>
            JsonSerializer.Serialize(value, D2.Converter.Settings).Trim('"');

        public static Dictionary<string, object?> FailureDict(Exception error)
        {
            if (error is KernelClientException e)
            {
                return e.Kind switch
                {
                    KernelClientErrorKind.RpcRejected => new Dictionary<string, object?> { ["code"] = e.Code ?? "unknown", ["detail"] = e.Message },
                    KernelClientErrorKind.NotImplemented => new Dictionary<string, object?> { ["code"] = "not_implemented", ["detail"] = e.Message },
                    KernelClientErrorKind.Transport => new Dictionary<string, object?> { ["code"] = "transport", ["detail"] = e.Message },
                    KernelClientErrorKind.ProtocolMismatch => new Dictionary<string, object?> { ["code"] = "protocol_mismatch", ["detail"] = e.Message },
                    KernelClientErrorKind.NotConnected => new Dictionary<string, object?> { ["code"] = "not_connected" },
                    _ => new Dictionary<string, object?> { ["code"] = "unknown", ["detail"] = e.Message },
                };
            }
            return new Dictionary<string, object?> { ["code"] = "unknown", ["detail"] = error.Message };
        }

        // MARK: - client_call 翻译层

        public static async Task PerformClientCallAsync(TimelineOp op, RunnerContext ctx)
        {
            if (op.Id is not { } id || op.Call is not { } call)
                throw new RunnerException($"client_call 缺少 id/call（t={op.T}）");
            ctx.SetCallKind(id, call);
            var client = ctx.Client;

            switch (call)
            {
                case "createSession":
                {
                    if (op.Args is not { } argsEl || !argsEl.TryGetProperty("config", out var configEl))
                        throw new RunnerException($"client_call(createSession id={id}) 缺少 args.config");
                    var config = configEl.Deserialize<Config>(D2.Converter.Settings)
                        ?? throw new RunnerException($"client_call(createSession id={id}) 的 config 解码为 null");
                    var gate = new ReplyGate();
                    ctx.SetGate(id, gate);
                    // T-050 REWORK #1 治根纪律：只记录真实捕获的原生 params——不在这里顺手拼一份
                    // 『规范化请求』（那会验证 fixture 自己声明的东西）。规范化留给 `CheckExpectOutbound`
                    // 断言时从这份原始 params 现算（`NormalizeNativeParams`）。
                    client.TestSupportStubRpc("sessions.create", parameters =>
                    {
                        ctx.RecordOutbound(id, "sessions.create", parameters);
                        return gate.Wait();
                    });
                    var task = Task.Run(async () =>
                    {
                        try
                        {
                            var handle = await client.CreateSessionAsync(config);
                            ctx.OnCreateSessionResolved(id, handle);
                        }
                        catch (Exception error)
                        {
                            ctx.OnCallThrew(id, error);
                        }
                    });
                    ctx.AddPendingTask(task);
                    break;
                }

                case "send":
                {
                    if (op.Args is not { } argsEl2)
                        throw new RunnerException($"client_call(send id={id}) 缺少 args");
                    var input = argsEl2.Deserialize<Input>(D2.Converter.Settings)
                        ?? throw new RunnerException($"client_call(send id={id}) 的 args 解码为 null");
                    var handle = ctx.CurrentSessionHandle ?? throw new RunnerException($"send（id={id}）在 createSession 之前调用");
                    var gate = new ReplyGate();
                    ctx.SetGate(id, gate);
                    client.TestSupportStubRpc("sessions.send", parameters =>
                    {
                        ctx.RecordOutbound(id, "sessions.send", parameters);
                        return gate.Wait();
                    });
                    var task = Task.Run(async () =>
                    {
                        try
                        {
                            var result = await client.SendAsync(handle, input);
                            ctx.OnSendResolved(id, result);
                        }
                        catch (Exception error)
                        {
                            ctx.OnCallThrew(id, error);
                        }
                    });
                    ctx.AddPendingTask(task);
                    break;
                }

                case "subscribe":
                {
                    // 真实 `Subscribe()` 同步（在第一次 await 之前）就把 channel 建好、立即返回事件
                    // 流——底层 `sessions.messages.subscribe` RPC 是否已经收到响应，不影响
                    // `HandleAgentEvent`/`HandleSessionApprovalEvent` 等 dispatch 分支能否正常工作。
                    // 因此这里用『可选 gate』：fixture 若显式提供了 `mock_response(replyTo: 这个
                    // subscribe 调用的 id)`（如 basic fixture），gate 会在那时被解锁；若没提供（本轮
                    // 大多数 fixture 不需要），gate 永远悬挂也不影响后续任何事件观察。
                    var handle = ctx.CurrentSessionHandle ?? throw new RunnerException($"subscribe（id={id}）在 createSession 之前调用");
                    var gate = new ReplyGate();
                    ctx.SetGate(id, gate);
                    client.TestSupportStubRpc("sessions.messages.subscribe", async parameters =>
                    {
                        ctx.RecordOutbound(id, "sessions.messages.subscribe", parameters);
                        try
                        {
                            var json = await gate.Wait();
                            ctx.SetCallOutcomeResolved(id);
                            return json;
                        }
                        catch (Exception error)
                        {
                            ctx.OnCallThrew(id, error);
                            throw;
                        }
                    });
                    var stream = client.Subscribe(handle);
                    ctx.StartDraining(stream);
                    break;
                }

                case "stop":
                {
                    var handle = ctx.CurrentSessionHandle ?? throw new RunnerException($"stop（id={id}）在 createSession 之前调用");
                    var gate = new ReplyGate();
                    ctx.SetGate(id, gate);
                    client.TestSupportStubRpc("sessions.abort", parameters =>
                    {
                        // T-050 REWORK #3 纪律：append 发生在这条 stub **真正被真实 client 调用**的
                        // 这一刻——不是 stub 注册的时刻——`nativeCallOrder` 里 "sessions.abort" 相对
                        // "approval.resolve" 的先后顺序，反映的是真实 `StopAsync` 方法体里两次
                        // `RequestAsync` 调用的真实先后顺序。
                        ctx.AppendNativeCall("sessions.abort");
                        ctx.RecordOutbound(id, "sessions.abort", parameters);
                        return gate.Wait();
                    });
                    client.TestSupportStubRpc("sessions.delete", _ => Task.FromResult(new JSONObject { ["deleted"] = true }));
                    // D1 §6.2 M3（stop-path 强制 deny）：`StopAsync` 在发起 `sessions.abort` 之前，若
                    // 该 session 仍有 pending 审批，会先对每一个调用真实 openclaw 统一审批解决 RPC
                    // `approval.resolve`。绝大多数 fixture 没有 pending 审批时，
                    // `ForceDenyPendingApprovalsBeforeStopAsync` 在空列表上提前返回、根本不会发起这条
                    // RPC（这条 stub 是安全的默认背景桩，不影响其余 fixture）；只有
                    // `approval/stop-force-denies-pending-approval.json` 会真正命中。
                    client.TestSupportStubRpc("approval.resolve", _ =>
                    {
                        ctx.AppendNativeCall("approval.resolve");
                        return Task.FromResult(new JSONObject
                        {
                            ["applied"] = true,
                            ["approval"] = new JSONObject { ["status"] = "denied" },
                        });
                    });
                    var eventsCountAtStart = ctx.DrainedEventsCount();
                    var task = Task.Run(async () =>
                    {
                        try
                        {
                            var result = await client.StopAsync(handle);
                            await ctx.OnStopResolvedAsync(id, result, eventsCountAtStart);
                        }
                        catch (Exception error)
                        {
                            await ctx.OnStopThrewAsync(id, error, eventsCountAtStart);
                        }
                    });
                    ctx.AddPendingTask(task);
                    break;
                }

                case "interrupt":
                case "respondApproval":
                case "capabilities":
                    // 不应该走到这里——`DegradeReason` 已经在执行 timeline 之前静态扫描并整条 fixture
                    // 标记 DEGRADED。留一个明确抛错，防止未来谁绕开了那道静态检查。
                    throw new RunnerException($"client_call『{call}』本应在执行前被 DegradeReason 拦截，未被拦截是 runner 自身的缺陷");

                default:
                    throw new RunnerException($"未知 KernelClientMethod『{call}』");
            }

            // 给刚 spawn 的 Task 一点真实时间跑到它的 RPC await 点，让紧随其后的
            // expect_outbound/assert_state 断言的是『真的在途』而不是『还没开始』。
            await Task.Delay(50);
        }

        // MARK: - expect_outbound

        /// <summary>D2 req.* 方法名 -&gt; 真实 client 会调用的 openclaw 原生 RPC 方法名。只覆盖 Stage
        /// A/B 用到的四个方法（interrupt/respondApproval/capabilities 对应的 fixture 已被整条
        /// DEGRADED，不会走到这里）。</summary>
        private static readonly Dictionary<string, string> ExpectOutboundMethodTable = new()
        {
            ["req.createSession"] = "sessions.create",
            ["req.send"] = "sessions.send",
            ["req.subscribe"] = "sessions.messages.subscribe",
            ["req.stop"] = "sessions.abort",
        };

        /// <summary>
        /// 把真实捕获到的 openclaw 原生 RPC `params`（`PerformClientCallAsync` 的 `TestSupportStubRpc`
        /// 闭包同步收到的原始入参，真实 client 传的，不是 fixture 声明值）规范化成一个可与
        /// `expect_outbound` 的 `pattern` 做完整深度匹配的『规范化请求』——逐字镜像
        /// `SwiftFixtureRunner.swift` 的 `normalizeNativeParams`（T-050 REWORK #1 治根方案）：
        ///   - `sessionId`：从捕获到的原生 `key` 反查『哪个已声明 session 拥有这个 kernelKey』。`key`
        ///     不存在于 `params`（如 createSession，session 尚不存在）就不设置这个字段；`key` 存在但
        ///     查不到对应的已声明 session（真实 client 把 `key` 发错，或发了一个从未声明过的 key）就
        ///     显式置 <see cref="JsonNullMarker.Instance"/>——不 fallback 到任何 fixture 声明值，让
        ///     pattern 里的 `sessionId` 断言在这种情况下真的失败。
        ///   - `payload`：`params` 去掉 `key`（原生寻址字段，不是 D2 payload 概念）之后剩下的全部
        ///     字段，原样保留原生字段名——仅 `sessions.send` 一项例外：把原生 `message` 反向映射回
        ///     D1 `Input.text` 概念，只为了让这个字段能与 TS/Swift 端 `payload.text` 做跨语言一致的
        ///     深度匹配；其余字段不改名，如实反映原生协议。
        /// </summary>
        private static Dictionary<string, object?> NormalizeNativeParams(string method, JSONObject parameters, string expectedType, RunnerContext ctx)
        {
            var payload = new JSONObject(parameters);
            var outp = new Dictionary<string, object?> { ["type"] = expectedType };
            if (payload.Remove("key", out var keyVal) && keyVal is string key)
            {
                var declared = ctx.DeclaredSessionId(key);
                outp["sessionId"] = declared != null ? declared : JsonNullMarker.Instance;
            }
            if (method == "sessions.send" && payload.Remove("message", out var message))
                payload["text"] = message;
            outp["payload"] = payload;
            return outp;
        }

        public static void CheckExpectOutbound(TimelineOp op, RunnerContext ctx)
        {
            if (op.Matches is not { } matches)
                throw new RunnerException($"expect_outbound 缺少 matches（t={op.T}）");
            var patternAny = FixtureJson.ToActualObject(op.Pattern);
            if (!(patternAny.TryGetValue("type", out var typeObj) && typeObj is string expectedType))
                throw new RunnerException($"expect_outbound({matches}) 的 pattern 缺少 'type'");

            if (!ExpectOutboundMethodTable.TryGetValue(expectedType, out var expectedMethod))
            {
                ctx.AppendMismatch(
                    $"expect_outbound({matches}): csharp-runner 未登记『{expectedType}』对应的 openclaw RPC 方法名" +
                    "（该 D2 方法本轮 SG-5 未实现，或超出 Stage A/B 翻译范围）");
                return;
            }

            var captured = ctx.CapturedOutboundMethod(matches);
            if (captured != expectedMethod)
            {
                ctx.AppendMismatch(
                    $"expect_outbound({matches}): 期望真实 client 调用底层 openclaw RPC 方法『{expectedMethod}』" +
                    $"（对应 D2『{expectedType}』），实际捕获到『{captured ?? "<none>"}』");
                return;
            }

            // T-050 REWORK #1 治根：规范化对象从 `CapturedParams`——真实捕获的原生 `params`——现算，
            // 不是把 timeline `args`/fixture 声明值抄回去验证自己。
            var parameters = ctx.CapturedParams(matches) ?? new JSONObject();
            var normalized = NormalizeNativeParams(expectedMethod, parameters, expectedType, ctx);
            var diff = PartialMatch.Match(normalized, patternAny, $"expect_outbound({matches})");
            foreach (var d in diff) ctx.AppendMismatch(d);
        }

        // MARK: - mock_response

        public static void ApplyMockResponse(TimelineOp op, RunnerContext ctx)
        {
            if (op.ReplyTo is not { } replyTo)
                throw new RunnerException($"mock_response 缺少 replyTo（t={op.T}）");
            var gate = ctx.Gate(replyTo) ?? throw new RunnerException(
                $"mock_response(replyTo={replyTo}) 找不到对应的 reply gate——对应 client_call 未发起，或该方法不需要 gate（如 subscribe）");
            var messageAny = FixtureJson.ToActualObject(op.Message);
            var kind = ctx.CallKind(replyTo) ?? "";

            if (messageAny.TryGetValue("failure", out var failureObj) && failureObj is Dictionary<string, object?> failure)
            {
                var code = failure.TryGetValue("code", out var c) && c is string cs ? cs : "unknown";
                var detail = failure.TryGetValue("detail", out var d) && d is string ds ? ds : null;
                gate.ResolveFailure(new KernelClientException(KernelClientErrorKind.RpcRejected, detail ?? "", code));
                return;
            }

            var result = messageAny.TryGetValue("result", out var resultObj) && resultObj is Dictionary<string, object?> r
                ? r
                : new Dictionary<string, object?>();

            switch (kind)
            {
                case "createSession":
                {
                    string? sessionId = null;
                    if (result.TryGetValue("sessionHandle", out var sh) && sh is Dictionary<string, object?> shd &&
                        shd.TryGetValue("sessionId", out var sid) && sid is string sids)
                        sessionId = sids;
                    var key = $"openclaw-key-{sessionId ?? Guid.NewGuid().ToString()}";
                    ctx.SetCurrentKernelKey(key);
                    // T-050 REWORK #1：登记『这把 key 对应哪个已声明 session』——真实 client 之后每次
                    // send/subscribe/stop 都会在原生 `params.key` 里带上这把 key（原样回显），
                    // `expect_outbound` 断言时反查这张表，从真实捕获的 key 算出 sessionId。
                    ctx.RegisterDeclaredSession(key, sessionId ?? key);
                    gate.ResolveSuccess(new JSONObject { ["key"] = key, ["sessionId"] = sessionId ?? key });
                    break;
                }
                case "send":
                {
                    var runId = result.TryGetValue("runId", out var rid) && rid is string rids ? rids : $"run-{Guid.NewGuid():N}"[..12];
                    gate.ResolveSuccess(new JSONObject { ["runId"] = runId, ["status"] = "started", ["messageSeq"] = 1L });
                    break;
                }
                case "subscribe":
                {
                    var kernelKey = ctx.CurrentKernelKey ?? "";
                    gate.ResolveSuccess(new JSONObject { ["subscribed"] = true, ["key"] = kernelKey });
                    break;
                }
                case "stop":
                {
                    // 真实 sessions.abort RPC ack 该携带的 `abortedRunId`/`status`，从『此前是否有一个
                    // send() 已经真实 resolve 出一个 runId』（`ctx.CurrentRunId`）无歧义派生——
                    // `message.result`（D2 合法三态枚举）在这条路径上是纯装饰性的，真实 client 从不读
                    // 它，只读 `abortedRunId`。
                    var activeRunId = ctx.CurrentRunId;
                    if (activeRunId != null)
                    {
                        gate.ResolveSuccess(new JSONObject { ["abortedRunId"] = activeRunId, ["status"] = "aborted" });
                        ctx.SetHasStopWaitingForTerminal(true);
                        ctx.SetWaitingStopCallId(replyTo);
                    }
                    else
                    {
                        // 这里的 `null` 是喂给真实 client 的 wire JSONObject（`OpenclawWire.JsonString`
                        // 消费），不是 PartialMatch 的『统一值域』——用裸 C# null，不是
                        // `JsonNullMarker.Instance`（见 `JsonNullMarker` 文档注释的边界说明）。
                        gate.ResolveSuccess(new JSONObject { ["abortedRunId"] = null, ["status"] = "no-active-run" });
                    }
                    break;
                }
                default:
                    throw new RunnerException($"mock_response(replyTo={replyTo}): 未知 client_call 类型『{kind}』");
            }
        }

        // MARK: - mock_event

        public static async Task ApplyMockEventAsync(TimelineOp op, RunnerContext ctx)
        {
            var messageAny = FixtureJson.ToActualObject(op.Message);
            if (!(messageAny.TryGetValue("type", out var typeObj) && typeObj is string type))
                throw new RunnerException($"mock_event 缺少 message.type（t={op.T}）");
            var kernelKey = ctx.CurrentKernelKey ?? "";
            var client = ctx.Client;

            switch (type)
            {
                case "evt.message.delta":
                {
                    var payload = messageAny.TryGetValue("payload", out var p) && p is Dictionary<string, object?> pd
                        ? pd : new Dictionary<string, object?>();
                    var delta = payload.TryGetValue("delta", out var dv) && dv is string ds ? ds : "";
                    var frame = new JSONObject
                    {
                        ["type"] = "event",
                        ["event"] = "session.message",
                        ["payload"] = new JSONObject
                        {
                            ["sessionKey"] = kernelKey,
                            ["message"] = new JSONObject
                            {
                                ["role"] = "assistant",
                                ["content"] = new List<object?> { new JSONObject { ["type"] = "text", ["text"] = delta } },
                                ["timestamp"] = DateTimeOffset.UtcNow.ToUnixTimeMilliseconds(),
                            },
                        },
                    };
                    client.TestSupportFeedFrame(frame);
                    break;
                }

                case "evt.turn_complete":
                {
                    // Stage A/B 范围内，本 runner 只把这个类型用作『合成 stop() 等待中的 aborted
                    // lifecycle 终态信号』——不是通用的正常回合结束映射。真实 SG-5 mapper
                    // （`MapOpenclawAgentLifecycleToAbortTerminalEvents`）本身也是照 `phase` 是否为
                    // "end" 判定 outcome=succeeded、`stopReason` 硬编码为 cancelled（不读原生帧的
                    // stopReason/forceResolvedApprovals 字段——那两个字段由真实 client 自己的
                    // `_pendingStops[...].ForceResolvedApprovalReqIds` 计算），因此这里直接硬编码
                    // `phase:"end","aborted":true`，忽略 fixture 声明的 payload 内容（同 Swift）。
                    var contextRunId = ctx.CurrentRunId;
                    var runId = messageAny.TryGetValue("runId", out var rv) && rv is string rs ? rs : (contextRunId ?? "");
                    var frame = new JSONObject
                    {
                        ["type"] = "event",
                        ["event"] = "agent",
                        ["payload"] = new JSONObject
                        {
                            ["runId"] = runId,
                            ["sessionKey"] = kernelKey,
                            ["stream"] = "lifecycle",
                            ["data"] = new JSONObject { ["phase"] = "end", ["aborted"] = true },
                            ["ts"] = DateTimeOffset.UtcNow.ToUnixTimeMilliseconds(),
                        },
                    };
                    client.TestSupportFeedFrame(frame);
                    ctx.SetHasStopWaitingForTerminal(false);
                    break;
                }

                case "evt.approval_request":
                {
                    var payload = messageAny.TryGetValue("payload", out var p2) && p2 is Dictionary<string, object?> pd2
                        ? pd2 : new Dictionary<string, object?>();
                    if (!(payload.TryGetValue("reqId", out var reqIdObj) && reqIdObj is string reqId) ||
                        !(payload.TryGetValue("toolCallId", out var toolCallIdObj) && toolCallIdObj is string toolCallId))
                        throw new RunnerException("mock_event(evt.approval_request) 缺少 payload.reqId/toolCallId");

                    var contextRunId = ctx.CurrentRunId;
                    var runId = messageAny.TryGetValue("runId", out var rv) && rv is string rs ? rs : (contextRunId ?? "run-approval-1");
                    var timeoutMs = payload.TryGetValue("timeoutMs", out var tv) && tv is long tl ? tl : 1_800_000L;
                    var nowMs = DateTimeOffset.UtcNow.ToUnixTimeMilliseconds();
                    // T-048 REWORK #1/#2（删除非法 `_openclawJoinOrder`）：原生双帧到达顺序改读
                    // `TimelineOp.DriverHint`（../dsl.ts 的 `MockEventDriverHint`）——DSL 层面显式
                    // 声明的翻译层驱动量，不在 `message` 里。
                    var driverHintAny = FixtureJson.ToActualObject(op.DriverHint);
                    var order = driverHintAny.TryGetValue("approvalJoinOrder", out var ov) && ov is string os ? os : "agent_first";

                    var agentFrame = new JSONObject
                    {
                        ["type"] = "event",
                        ["event"] = "agent",
                        ["payload"] = new JSONObject
                        {
                            ["runId"] = runId,
                            ["sessionKey"] = kernelKey,
                            ["stream"] = "approval",
                            ["data"] = new JSONObject { ["phase"] = "requested", ["toolCallId"] = toolCallId, ["approvalId"] = reqId },
                            ["ts"] = nowMs,
                        },
                    };
                    var sessionApprovalFrame = new JSONObject
                    {
                        ["type"] = "event",
                        ["event"] = "session.approval",
                        ["payload"] = new JSONObject
                        {
                            ["sessionKey"] = kernelKey,
                            ["updatedAtMs"] = nowMs,
                            ["phase"] = "pending",
                            ["approval"] = new JSONObject
                            {
                                ["id"] = reqId,
                                ["status"] = "pending",
                                ["presentation"] = new JSONObject { ["kind"] = "exec", ["commandText"] = $"echo {reqId}" },
                                ["createdAtMs"] = nowMs,
                                ["expiresAtMs"] = nowMs + timeoutMs,
                            },
                        },
                    };

                    if (order == "session_first")
                    {
                        client.TestSupportFeedFrame(sessionApprovalFrame);
                        await Task.Delay(30);
                        client.TestSupportFeedFrame(agentFrame);
                    }
                    else
                    {
                        client.TestSupportFeedFrame(agentFrame);
                        await Task.Delay(30);
                        client.TestSupportFeedFrame(sessionApprovalFrame);
                    }
                    break;
                }

                default:
                    throw new RunnerException(
                        $"mock_event: csharp-runner Stage A/B 未实现『{type}』的 openclaw wire 翻译（超出本轮 fixture 需要的范围，未静默忽略）");
            }
        }

        // MARK: - advance_clock（虚拟时钟）

        private const int SyncPollIntervalMs = 10;
        private const int SyncSafetyMarginMs = 5000;

        /// <summary>轮询直到 `predicate()` 为 true 或超过 `maxWaitMs`——用于替换『固定 sleep 猜调度』
        /// （T-048 REWORK #5 核心，镜像 Swift `pollUntilSettled`）：不管 SG-5 内部定时器/等待任务实际
        /// 几时被真正 armed、几时真正结算，本 runner 都只是不断问『好了没』，而不是自己算一个『应该差不多
        /// 好了』的时长再赌一把。</summary>
        private static async Task PollUntilSettledAsync(int maxWaitMs, Func<bool> predicate)
        {
            var waitedMs = 0;
            while (waitedMs < maxWaitMs)
            {
                if (predicate()) return;
                await Task.Delay(SyncPollIntervalMs);
                waitedMs += SyncPollIntervalMs;
            }
        }

        public static async Task ApplyAdvanceClockAsync(TimelineOp op, RunnerContext ctx)
        {
            var ms = op.Ms ?? 0;
            if (!ctx.HasStopWaitingForTerminal) return; // no-op：当前没有 stop() 在等待终态确认。
            if (ms < RunnerContext.StopTimeoutMs) return;
            var waitingId = ctx.WaitingStopCallId;
            if (waitingId == null)
            {
                ctx.SetHasStopWaitingForTerminal(false);
                return;
            }
            await PollUntilSettledAsync(RunnerContext.StopTimeoutMs + SyncSafetyMarginMs, () => ctx.IsCallSettled(waitingId));
            ctx.SetHasStopWaitingForTerminal(false);
        }

        // MARK: - 单个 timeline op 的分发

        public static async Task ExecuteOpAsync(TimelineOp op, RunnerContext ctx)
        {
            switch (op.Op)
            {
                case TimelineOpKind.ClientCall:
                    await PerformClientCallAsync(op, ctx);
                    break;
                case TimelineOpKind.ExpectOutbound:
                    CheckExpectOutbound(op, ctx);
                    break;
                case TimelineOpKind.MockResponse:
                    ApplyMockResponse(op, ctx);
                    await Task.Delay(50);
                    break;
                case TimelineOpKind.MockEvent:
                    await ApplyMockEventAsync(op, ctx);
                    await Task.Delay(50);
                    break;
                case TimelineOpKind.Disconnect:
                    ctx.Client.TestSupportSimulateTransportClosed();
                    if (ctx.HasStopWaitingForTerminal && ctx.WaitingStopCallId is { } waitingId)
                    {
                        await PollUntilSettledAsync(SyncSafetyMarginMs, () => ctx.IsCallSettled(waitingId));
                        ctx.SetHasStopWaitingForTerminal(false);
                    }
                    else
                    {
                        // 没有 stop() 在等待终态——本轮 fixture 均未覆盖这条分支，保留一个保守的结算
                        // 窗口而不是干脆不等，避免引入新的未覆盖竞态（同 Swift 侧同名分支）。
                        await Task.Delay(250);
                    }
                    break;
                case TimelineOpKind.Reconnect:
                    // 本轮 fixture 均不依赖 reconnect 语义；SG-5 本身也没有『断线后重新变为可用』的
                    // 能力（transport 关闭后所有 session 的派生状态都会被清理）——如实标注为 no-op。
                    break;
                case TimelineOpKind.AdvanceClock:
                    await ApplyAdvanceClockAsync(op, ctx);
                    break;
                case TimelineOpKind.AssertState:
                {
                    var snapshot = ctx.SnapshotWithLock();
                    var expected = FixtureJson.ToActual(op.Expected);
                    var diff = PartialMatch.Match(snapshot, expected, $"assert_state@t={op.T}");
                    foreach (var d in diff) ctx.AppendMismatch(d);
                    break;
                }
            }
        }

        // MARK: - DEGRADED 检测

        public static string? DegradeReason(ParityFixture fixture)
        {
            foreach (var op in fixture.Timeline)
            {
                if (op.Op == TimelineOpKind.ClientCall && op.Call is { } call &&
                    (call == "interrupt" || call == "respondApproval" || call == "capabilities"))
                {
                    return $"timeline 包含 client_call『{call}』——SG-5 OpenclawGatewayKernelClient 该方法本轮" +
                           "仍是 TODO 桩（IKernelClient.cs 头注释 + OpenclawGatewayKernelClient.cs 对应方法体均为" +
                           " throw KernelClientException(NotImplemented,...)），没有任何 RPC/wire 交互可翻译，" +
                           "无法驱动真实 client 产生有意义的状态转移。本 fixture 对 csharp-runner 诚实降级为" +
                           " DEGRADED（跳过，不计入 PASS/FAIL），不伪造一个假内核让它'通过'。";
                }
            }
            return null;
        }

        // MARK: - 顶层：跑一个 fixture 文件

        public static async Task<FixtureRunResult> RunFixtureFileAsync(string path)
        {
            var fileName = System.IO.Path.GetFileName(path);
            ParityFixture fixture;
            try
            {
                var json = await System.IO.File.ReadAllTextAsync(path);
                fixture = FixtureLoader.Parse(json);
            }
            catch (Exception e)
            {
                return new FixtureRunResult
                {
                    Name = fileName, Path = path, Outcome = FixtureRunOutcomeKind.Failed,
                    Mismatches = { $"无法解析 fixture JSON：{e}" },
                };
            }

            var degradeReason = DegradeReason(fixture);
            if (degradeReason != null)
                return new FixtureRunResult { Name = fixture.Name, Path = path, Outcome = FixtureRunOutcomeKind.Degraded, DegradedReason = degradeReason };

            var initial = FixtureJson.ToActual(fixture.InitialState) as Dictionary<string, object?>;
            if (initial is { Count: > 0 })
            {
                // 本轮 fixture 均不需要 `initialState`（都从 idle/干净状态起步），SG-5 也没有暴露
                // 『直接摆一个初始锁状态』的测试钩子——诚实拒绝，而不是静默忽略 fixture 作者可能依赖的
                // 初始状态（同 Swift 侧同名分支）。
                return new FixtureRunResult
                {
                    Name = fixture.Name, Path = path, Outcome = FixtureRunOutcomeKind.Failed,
                    Mismatches = { $"fixture 声明了 initialState {PartialMatch.Stringify(initial)}，但 csharp-runner 本轮未实现" +
                                   "『驱动真实 client 进入某个非默认初始状态』的能力（SG-5 未提供对应测试钩子），如实拒绝而非静默忽略" },
                };
            }

            var client = new OpenclawGatewayKernelClient(new Uri("ws://127.0.0.1:1"), "csharp-runner-fixture-token");
            client.TestSupportSetStopTimeoutSeconds(RunnerContext.StopTimeoutSeconds);
            var ctx = new RunnerContext(client);

            try
            {
                foreach (var op in fixture.Timeline)
                    await ExecuteOpAsync(op, ctx);
            }
            catch (Exception e)
            {
                return new FixtureRunResult
                {
                    Name = fixture.Name, Path = path, Outcome = FixtureRunOutcomeKind.Failed,
                    Mismatches = { $"执行 timeline 时抛出异常：{e}" },
                };
            }

            // 收尾：给所有 spawn 的 client_call/事件排空 Task 一点真实时间稳定下来，再做最终快照。
            await Task.Delay(150);

            var mismatches = ctx.AccumulatedMismatches();
            var finalState = ctx.SnapshotWithLock();
            mismatches.AddRange(PartialMatch.Match(finalState, FixtureJson.ToActual(fixture.Expected), "expected"));

            return new FixtureRunResult
            {
                Name = fixture.Name, Path = path,
                Outcome = mismatches.Count == 0 ? FixtureRunOutcomeKind.Passed : FixtureRunOutcomeKind.Failed,
                Mismatches = mismatches,
            };
        }
    }
}
