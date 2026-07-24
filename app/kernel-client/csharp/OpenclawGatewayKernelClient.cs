// SG-5 Stage C：C# 具体 WS 实现——直接对话一个正在运行的 openclaw Gateway 实例。镜像
// ../swift/OpenclawGatewayKernelClient.swift（1113 行，权威 spec，两轮对抗审 T-044/T-045 +
// 真 e2e 已验证正确）。逐方法、逐正确性属性对应，字段级 grounding（真实样本/源码引用）见 Swift 源文件，
// 本文件只记"C# 与 Swift 的表达差异"，不重复誊抄 grounding 叙述。
//
// 表达差异总览：
//   - Swift 用 `actor` 隔离全部可变状态（并发安全靠编译器保证）；C# 没有 actor，这里用一个共享的
//     `_sync`（`lock` 语句，Monitor）保护全部字典/集合字段的读写——所有临界区都是同步的、不跨越
//     `await`（跟 actor『不会在两次 await 之间被重入』的保证等价，只是这里是手动而不是编译器强制）。
//   - Swift 用 `AsyncThrowingStream` + `CheckedContinuation` 表达"事件流"/"一次性等待"；C# 用
//     `System.Threading.Channels.Channel<EventMessageUnion>`（`Writer.TryComplete(error)` 对应
//     `continuation.finish(throwing:)`）表达事件流，`TaskCompletionSource<T>` 对应
//     `CheckedContinuation`。
//   - Swift `Subscribe()` 签名是 `async -> AsyncThrowingStream<...>`；C# 接口签名是同步方法返回
//     `IAsyncEnumerable<EventMessageUnion>`——特意**不**写成 `async IAsyncEnumerable` 迭代器方法（那种
//     写法直到第一次枚举才会真正执行方法体，会让"调用 Subscribe() 立即发起 RPC 并注册事件通道"这个
//     Swift 行为变成"要等调用方开始枚举才发起"，语义会跑偏）——本方法体本身同步立即执行（注册
//     channel + fire-and-forget 后台 Task 发起 RPC），只把返回值声明成 `IAsyncEnumerable`
//     （`ChannelReader.ReadAllAsync` 天然就是这个类型），调用即执行的时序与 Swift 完全一致。
//   - Swift 的 `private`（测试文件同 module 内可访问）在 C# 项目引用模式下不可行——testSupport* 系列
//     方法在这里改为 `public`（同 Swift 头注释的说明：这些方法名统一加 TestSupport 前缀，一眼可辨认，
//     不是生产调用路径的一部分）。

#nullable enable
using System;
using System.Collections.Generic;
using System.Linq;
using System.Net.WebSockets;
using System.Threading;
using System.Threading.Channels;
using System.Threading.Tasks;
using D2;

namespace KernelClient
{
    using JSONObject = Dictionary<string, object?>;

    public sealed class OpenclawGatewayKernelClient : IKernelClient
    {
        private readonly Uri _endpoint;
        private readonly string _token;
        private ClientWebSocket? _socket;
        private Task? _receiveLoopTask;
        private readonly CancellationTokenSource _receiveLoopCts = new();

        /// <summary>
        /// 保护下面全部可变状态的单一互斥锁——所有临界区都是纯同步代码（不跨越 `await`），对应 Swift
        /// actor『两次 await 之间不会被重入』的保证。
        /// </summary>
        private readonly object _sync = new();

        private long _nextReqId;
        /// <summary>req id -&gt; 等待该 id 对应 res 帧的 TaskCompletionSource（对应 Swift 的 CheckedContinuation）。</summary>
        private readonly Dictionary<string, TaskCompletionSource<JSONObject>> _pending = new();
        /// <summary>一次性等待"下一条指定名字的 event 帧"——仅用于握手期等 `connect.challenge`。</summary>
        private readonly Dictionary<string, TaskCompletionSource<JSONObject>> _oneShotEventWaiters = new();
        /// <summary>我们自己铸造的 SessionHandle.sessionId -&gt; openclaw 原生 key。</summary>
        private readonly Dictionary<string, string> _kernelKeyBySessionId = new();
        private readonly Dictionary<string, Channel<EventMessageUnion>> _eventChannels = new();

        // MARK: F1 — send/stop 的 session 级互斥锁

        private enum SessionLockState { Idle, SendPending, StopInProgress }

        private static string Describe(SessionLockState state) => state switch
        {
            SessionLockState.Idle => "idle",
            SessionLockState.SendPending => "send_pending",
            SessionLockState.StopInProgress => "stop_in_progress",
            _ => "unknown",
        };

        private readonly Dictionary<string, SessionLockState> _lockStateBySessionId = new();

        // MARK: F6/M3 — stop() 的 pending 状态

        /// <summary>
        /// NOTE-1（T-047 grok 复核，真挂起 bug 修复）：<see cref="WaitForPendingStopTerminalAsync"/>
        /// 里 await 着的 <see cref="PendingStop.Waiter"/> 现在有三种可能的唤醒结果，不再是单纯的
        /// bool「是否超时」——旧代码只区分 true/false 两态，导致"transport 关闭"这个第三种场景
        /// 无法被安全表达：要么被误当成"没超时"（继续假装 succeeded），要么干脆没有任何值可以
        /// resolve（旧 bug：pendingStop 被直接 Remove，Waiter 从此没人 resolve，stop() 永久挂起）。
        /// </summary>
        private enum StopWaitOutcome
        {
            /// <summary>由 handleAgentEvent 观察到对应的 aborted lifecycle 帧，正常终态确认。</summary>
            TerminalObserved,
            /// <summary>等待窗口耗尽（生产默认 5 秒），诚实报超时，继续走 delete 收尾。</summary>
            TimedOut,
            /// <summary>
            /// 等待过程中 transport 关闭——ResolvePendingStopForTransportClose 已经代发
            /// operation_completed(aborted_effect_unknown) 镜像、标记 TerminalEmitted，并清理了全部
            /// 派生状态。StopAsync 见到这个值必须如实抛错，不能假装 succeeded/timed_out。
            /// </summary>
            TransportClosed,
        }

        private sealed class PendingStop
        {
            public readonly string OperationId;
            /// <summary>M3：发起 sessions.abort 之后必须用其权威返回值 abortedRunId 覆盖，见 StopAsync。</summary>
            public string? AffectedRunId;
            public bool TerminalEmitted;
            public TaskCompletionSource<StopWaitOutcome>? Waiter;
            /// <summary>
            /// D1 §6.2 M3（stop-path 强制 deny rework）：这次 stop() 在发起 sessions.abort 之前、强制
            /// deny 掉的 reqId 列表——由 <see cref="ForceDenyPendingApprovalsBeforeStopAsync"/> 在
            /// sessions.abort 之前填好，供 HandleAgentEvent 的 lifecycle(aborted) 分支把它们塞进这个
            /// run 的 TurnCompleteEvent.ForceResolvedApprovals。空列表（没有 pending approval 需要
            /// 强制处理）是绝大多数 stop() 调用的常态，不是遗漏。
            /// </summary>
            public List<string> ForceResolvedApprovalReqIds = new();

            public PendingStop(string operationId, string? affectedRunId)
            {
                OperationId = operationId;
                AffectedRunId = affectedRunId;
            }
        }

        private readonly Dictionary<string, PendingStop> _pendingStops = new();

        /// <summary>M3：测试专用的 stop() 等待超时覆盖（秒）——生产默认 5 秒。</summary>
        private int? _testStopTimeoutSecondsOverride;

        /// <summary>
        /// NOTE-A（T-049 grok 对抗审复核揪出的中等竞态，本轮修复）：
        /// <see cref="ForceDenyPendingApprovalsBeforeStopAsync"/> 现在是一个 drain 循环（见该方法文档
        /// 注释）——每轮结束后重新检查该 session 是否有新到的 pending 审批，直到某轮检查为空才允许
        /// StopAsync 继续发 sessions.abort。为防止（理论上不该出现，但不能假装不可能）一个持续产生
        /// 审批请求的 run 让这个循环无限跑下去，加一个迭代轮次上限——生产默认
        /// <see cref="ForceDenyDrainDefaultMaxRounds"/>，测试用这个覆盖值验证"超过上限如实 throw、不
        /// 静默死循环"这条路径，不用真的喂 50 轮。`null` 时使用生产默认值。
        /// </summary>
        private int? _testForceDenyDrainMaxRoundsOverride;

        // MARK: F8 — 三条 sessionEnd 路径（shutdown/transportClosed/stop）共享的去重标记
        private readonly HashSet<string> _sessionTerminalEmitted = new();

        // MARK: SG-5 事件映射需要的最小逐 session/run 状态缓存（F1：per-run，不是 per-session）
        private readonly Dictionary<string, string> _lastRunIdBySessionId = new();
        private readonly Dictionary<string, HashSet<string>> _runIdsBySessionId = new();
        private readonly Dictionary<string, string> _lastToolCallIdByRunId = new();
        private readonly Dictionary<string, (long Input, long Output)> _lastUsageByRunId = new();

        // MARK: M1 — approval 双向 join（agent(stream:"approval") <-> session.approval(phase:"pending")）

        private sealed class AgentApprovalInfo
        {
            public readonly string RunId;
            public readonly string ToolCallId;
            public AgentApprovalInfo(string runId, string toolCallId) { RunId = runId; ToolCallId = toolCallId; }
        }
        private readonly Dictionary<string, AgentApprovalInfo> _agentApprovalInfoByApprovalId = new();

        private sealed class PendingSessionApproval
        {
            public readonly JSONObject Payload;
            public readonly string OurSessionId;
            public PendingSessionApproval(JSONObject payload, string ourSessionId) { Payload = payload; OurSessionId = ourSessionId; }
        }
        private readonly Dictionary<string, PendingSessionApproval> _pendingSessionApprovalByApprovalId = new();

        /// <summary>M5：按 approvalId 键控的两张缓存本身不是 per-session 键，session 结束时靠这张反向索引批量清理。</summary>
        private readonly Dictionary<string, HashSet<string>> _approvalIdsBySessionId = new();

        // MARK: M3（D1 §6.2 stop-path 强制 deny）—— approval_request 已经真正产出给调用方之后的
        // "pending，等待人工决策"态。
        //
        // 上面 `_agentApprovalInfoByApprovalId`/`_pendingSessionApprovalByApprovalId` 只是 join 之前
        // 的临时缓冲区——一旦 join 成功、EmitApprovalRequestIfPossible 把 approvalRequest 真正写进
        // channel，这两张表的条目就被移除了，不再追踪"这个 reqId 现在处于 pending、还没人给出决策"
        // 这件事。RespondApprovalAsync() 本轮仍是 TODO 桩，永远不会有真实决策落地，因此这个态一旦
        // 进入就会一直 pending，直到 stop() 强制介入（D1 §6.2 M3 定序 + §6.3 stop 黑名单批量
        // deny）——这里新增的这张表是 stop() 用来"知道该 session 名下当前还有哪些审批在 pending"的
        // 唯一权威来源。OpenclawKind 存真实的 openclaw 侧 kind（"exec"/"plugin"/"system-agent"，不是
        // D2 收窄后的 KindElement）——见 ForceDenyPendingApprovalsBeforeStopAsync 的文档注释。
        private sealed class PendingApprovalAwaitingDecision
        {
            public readonly string RunId;
            public readonly string OpenclawKind;
            public PendingApprovalAwaitingDecision(string runId, string openclawKind) { RunId = runId; OpenclawKind = openclawKind; }
        }
        private readonly Dictionary<string, PendingApprovalAwaitingDecision> _pendingApprovalsByReqId = new();
        /// <summary>反向索引：session 结束时批量清理上面这张表——同款模式，仿 `_approvalIdsBySessionId`（M5）。</summary>
        private readonly Dictionary<string, HashSet<string>> _pendingApprovalReqIdsBySessionId = new();

        /// <summary>
        /// NOTE-A（T-049 grok 对抗审复核）：force-deny drain 循环（见
        /// <see cref="ForceDenyPendingApprovalsBeforeStopAsync"/>）的迭代轮次上限——防御性兜底，不是
        /// D1 协议要求的具体数值。D1 §9 一 session 一次一个 active run + StopAsync 已经把该 session
        /// 锁进 StopInProgress（阻塞新 send()，不会有新 run）的前提下，drain 循环每一轮只可能因为
        /// "仍在这个即将被 abort 的、唯一的 run"持续产生新的审批请求而继续——正常场景一两轮内必然
        /// 收敛为空；这里选 50 只是给"理论上不该出现但不能假装不可能"的极端场景（比如一个 bug 让某个
        /// run 疯狂连续请求审批）一个诚实的上限，超限时如实 throw，不是静默死循环。
        /// </summary>
        private const int ForceDenyDrainDefaultMaxRounds = 50;

        // MARK: Test-only：拦截 RPC（不需要真实 WebSocket 连接）
        private readonly Dictionary<string, Func<JSONObject, Task<JSONObject>>> _testSupportRpcResponders = new();

        // MARK: F3 — per-run 单调 seq 域
        private readonly Dictionary<string, long> _seqByRunId = new();
        private readonly Dictionary<string, long> _seqFallbackBySessionId = new();

        public IReadOnlyList<string> LastHandshakeScopes { get; private set; } = Array.Empty<string>();
        public int? LastHandshakeProtocol { get; private set; }

        public OpenclawGatewayKernelClient(Uri endpoint, string token)
        {
            _endpoint = endpoint;
            _token = token;
        }

        // MARK: - 连接 + 握手

        /// <summary>
        /// 建立 WS 连接并完成 challenge -&gt; connect 握手，返回 hello-ok 里协商到的 scopes。镜像
        /// Swift `connect()`。
        /// </summary>
        public async Task<IReadOnlyList<string>> ConnectAsync(CancellationToken cancellationToken = default)
        {
            var socket = new ClientWebSocket();
            await socket.ConnectAsync(_endpoint, cancellationToken);
            _socket = socket;
            _receiveLoopTask = Task.Run(ReceiveLoopAsync);

            var challenge = await WaitForNextEventAsync("connect.challenge");
            OpenclawWire.PrettyPrint("RECV connect.challenge", challenge);

            var connectParams = new JSONObject
            {
                ["minProtocol"] = 3L,
                ["maxProtocol"] = 4L,
                ["client"] = new JSONObject
                {
                    ["id"] = "cli",
                    ["version"] = "0.0.1",
                    ["platform"] = "darwin",
                    ["mode"] = "cli",
                },
                ["caps"] = new List<object?>(),
                ["role"] = "operator",
                ["scopes"] = new List<object?> { "operator.admin" },
                ["auth"] = new JSONObject { ["token"] = _token },
            };
            var hello = await RequestAsync("connect", connectParams);
            OpenclawWire.PrettyPrint("RECV hello-ok (connect response payload)", hello);

            if (OpenclawWire.JsonInt(hello.Get("protocol")) is long proto) LastHandshakeProtocol = (int)proto;
            if (OpenclawWire.JsonObj(hello.Get("auth")) is JSONObject auth &&
                OpenclawWire.JsonArr(auth.Get("scopes")) is List<object?> scopes)
            {
                LastHandshakeScopes = scopes.OfType<string>().ToList();
            }
            return LastHandshakeScopes;
        }

        public void Disconnect()
        {
            _receiveLoopCts.Cancel();
            // NOTE-3（整洁度）：先取出局部引用再置空字段——Abort() 唤醒任何仍在飞行的
            // ReceiveAsync（走 HandleTransportClosed 的正常收尾路径），随后 Dispose() 真正释放
            // ClientWebSocket 持有的底层资源（Abort 本身不释放，只中断挂起的 IO）。CancellationToken
            // 沿用同一个 _receiveLoopCts——它已经贯穿 ReceiveLoopAsync 的 ReceiveAsync 调用，这里不
            // 需要另起一份。
            var socket = _socket;
            _socket = null;
            if (socket != null)
            {
                try { socket.Abort(); } catch { /* best-effort teardown */ }
                socket.Dispose();
            }
        }

        // MARK: - KernelClient conformance

        public async Task<SessionHandle> CreateSessionAsync(Config config, CancellationToken cancellationToken = default)
        {
            var parameters = new JSONObject { ["label"] = "sg4-kernel-client-l1" };
            if (config.Model != null) parameters["model"] = config.Model;
            var result = await RequestAsync("sessions.create", parameters);
            OpenclawWire.PrettyPrint("RECV sessions.create result", result);

            if (OpenclawWire.JsonString(result.Get("key")) is not string kernelKey)
                throw new KernelClientException(KernelClientErrorKind.ProtocolMismatch, "sessions.create result missing 'key' field");
            var kernelSessionId = OpenclawWire.JsonString(result.Get("sessionId"));

            var ourSessionId = Guid.NewGuid().ToString();
            lock (_sync) { _kernelKeyBySessionId[ourSessionId] = kernelKey; }

            // billing.tokenRef 本轮是占位符——见 Swift 侧同名注释，未实现 newapi token 铸造。
            return new SessionHandle
            {
                Billing = new Billing { TokenRef = "TODO-sg4-no-newapi-token-minted" },
                CreatedAt = DateTimeOffset.UtcNow,
                Kernel = D2.Kernel.Openclaw,
                KernelSessionId = kernelSessionId ?? kernelKey,
                SessionId = ourSessionId,
            };
        }

        private static string ResolveSendMessageText(Input input)
        {
            if (input.Kind == InputKind.Text) return input.Text ?? "";
            var texts = (input.Parts ?? Array.Empty<Part>())
                .Where(p => p.Kind == PartKind.Text)
                .Select(p => p.Text)
                .Where(t => t != null)
                .Select(t => t!);
            return string.Join("\n", texts);
        }

        /// <summary>D1 §2.2 send()。F1：session 级 send_pending 互斥锁——镜像 Swift `send(session:input:)`。</summary>
        public async Task<SendResultPayload> SendAsync(SessionHandle session, Input input, CancellationToken cancellationToken = default)
        {
            string kernelKey;
            lock (_sync)
            {
                if (!_kernelKeyBySessionId.TryGetValue(session.SessionId, out kernelKey!))
                    throw new KernelClientException(KernelClientErrorKind.ProtocolMismatch, $"unknown session {session.SessionId}");

                var currentLock = _lockStateBySessionId.TryGetValue(session.SessionId, out var cl) ? cl : SessionLockState.Idle;
                if (currentLock != SessionLockState.Idle)
                    throw new KernelClientException(KernelClientErrorKind.RpcRejected,
                        $"send() rejected: session {session.SessionId} lock state is {Describe(currentLock)}, expected idle (D1 v3.1 §9.3)", "session_locked");

                _lockStateBySessionId[session.SessionId] = SessionLockState.SendPending;
            }

            try
            {
                var parameters = new JSONObject
                {
                    ["key"] = kernelKey,
                    ["message"] = ResolveSendMessageText(input),
                    ["timeoutMs"] = 0L,
                };
                // F2：attachment 改发 openclaw 期望的 `content`（base64）编码。
                if (input.Kind == InputKind.Structured && input.Parts != null)
                {
                    var attachments = input.Parts
                        .Where(p => p.Kind != PartKind.Text)
                        .Select(OpenclawWire.EncodeAttachmentForWire)
                        .Where(a => a != null)
                        .Select(a => (object?)a)
                        .ToList();
                    if (attachments.Count > 0) parameters["attachments"] = attachments;
                }

                var result = await RequestAsync("sessions.send", parameters);
                OpenclawWire.PrettyPrint("RECV sessions.send result", result);

                if (OpenclawWire.JsonString(result.Get("runId")) is not string runId)
                    throw new KernelClientException(KernelClientErrorKind.ProtocolMismatch, "sessions.send result missing 'runId' field");

                lock (_sync)
                {
                    _lastRunIdBySessionId[session.SessionId] = runId;
                    if (!_runIdsBySessionId.TryGetValue(session.SessionId, out var set))
                        _runIdsBySessionId[session.SessionId] = set = new HashSet<string>();
                    set.Add(runId);
                }
                return new SendResultPayload { RunId = runId };
            }
            finally
            {
                // send_pending 只是"等待 kernel ack"的极短窗口——ack 到达（无论成功失败）后立刻释放。
                lock (_sync)
                {
                    if (_lockStateBySessionId.TryGetValue(session.SessionId, out var cl) && cl == SessionLockState.SendPending)
                        _lockStateBySessionId[session.SessionId] = SessionLockState.Idle;
                }
            }
        }

        /// <summary>
        /// D1 §2.3 subscribe()。镜像 Swift `subscribe(session:)`——**特意不用 `async IAsyncEnumerable`
        /// 迭代器写法**，见文件头注释：本方法体同步立即执行（注册 channel + fire-and-forget 后台任务
        /// 发起 RPC），调用即生效，不等调用方开始枚举。
        /// </summary>
        public IAsyncEnumerable<EventMessageUnion> Subscribe(SessionHandle session, CancellationToken cancellationToken = default)
        {
            var channel = Channel.CreateUnbounded<EventMessageUnion>();
            lock (_sync) { _eventChannels[session.SessionId] = channel; }

            _ = Task.Run(async () =>
            {
                string? kernelKey;
                lock (_sync) { _kernelKeyBySessionId.TryGetValue(session.SessionId, out kernelKey); }
                if (kernelKey == null)
                {
                    channel.Writer.TryComplete(new KernelClientException(KernelClientErrorKind.ProtocolMismatch, $"unknown session {session.SessionId}"));
                    return;
                }
                try
                {
                    // includeApprovals:true——不带这个 flag 收不到 session.approval 事件。
                    var result = await RequestAsync("sessions.messages.subscribe", new JSONObject { ["key"] = kernelKey, ["includeApprovals"] = true });
                    OpenclawWire.PrettyPrint("RECV sessions.messages.subscribe result", result);
                    if (OpenclawWire.JsonBool(result.Get("subscribed")) is false)
                    {
                        channel.Writer.TryComplete(new KernelClientException(KernelClientErrorKind.ProtocolMismatch, "subscribe returned subscribed:false"));
                    }
                    else
                    {
                        // M1：消费 approvalReplay——authoritative 的当前 pending 审批快照。
                        ConsumeApprovalReplay(result, kernelKey);
                    }
                }
                catch (Exception ex)
                {
                    channel.Writer.TryComplete(ex);
                }
            });

            return channel.Reader.ReadAllAsync(cancellationToken);
        }

        public Task<InterruptResultPayload> InterruptAsync(SessionHandle session, InterruptRequestMessagePayload options, CancellationToken cancellationToken = default)
            => throw new KernelClientException(KernelClientErrorKind.NotImplemented, "interrupt() 本轮 TODO 桩——L1 闭环没有 active run 需要 interrupt");

        /// <summary>D1 §2.5 stop()。镜像 Swift `stop(session:)`（M3 rework，四条退出路径 + 锁/pendingStop 清理）。</summary>
        public async Task<StopResultPayload> StopAsync(SessionHandle session, CancellationToken cancellationToken = default)
        {
            string kernelKey;
            lock (_sync)
            {
                if (!_kernelKeyBySessionId.TryGetValue(session.SessionId, out kernelKey!))
                    throw new KernelClientException(KernelClientErrorKind.ProtocolMismatch, $"unknown session {session.SessionId}");

                var currentLock = _lockStateBySessionId.TryGetValue(session.SessionId, out var cl) ? cl : SessionLockState.Idle;
                if (currentLock != SessionLockState.Idle)
                    throw new KernelClientException(KernelClientErrorKind.RpcRejected,
                        $"stop() rejected: session {session.SessionId} lock state is {Describe(currentLock)}, expected idle (D1 v3.1 §9.3)", "session_locked");

                _lockStateBySessionId[session.SessionId] = SessionLockState.StopInProgress;
            }

            var operationId = $"op-stop-{Guid.NewGuid()}";
            string? affectedRunIdBeforeAbort;
            lock (_sync)
            {
                _lastRunIdBySessionId.TryGetValue(session.SessionId, out affectedRunIdBeforeAbort);
                _pendingStops[session.SessionId] = new PendingStop(operationId, affectedRunIdBeforeAbort);
            }

            try
            {
                // D1 §6.2 M3（强制定序，rework）：取消当前 run 之前，若该 session 名下存在 pending
                // 审批，必须先把它们强制 deny 掉、确认内核已接受，才能发起 sessions.abort——见
                // ForceDenyPendingApprovalsBeforeStopAsync 文档注释。这一步必须在 sessions.abort 之前
                // 完成，且失败时（RPC 抛错/内核未确认 denied）不能继续往下发 abort——直接落进下面的
                // catch 统一收尾（锁释放+pendingStop 清理+operation_completed(rejected) 镜像），不能
                // 假装"反正等会儿再看"。
                var forceResolvedApprovalReqIds = await ForceDenyPendingApprovalsBeforeStopAsync(session.SessionId);
                lock (_sync) { if (_pendingStops.TryGetValue(session.SessionId, out var p0)) p0.ForceResolvedApprovalReqIds = forceResolvedApprovalReqIds; }

                var abortResult = await RequestAsync("sessions.abort", new JSONObject { ["key"] = kernelKey });
                OpenclawWire.PrettyPrint("RECV sessions.abort result", abortResult);

                // 是否需要等待，由 sessions.abort 自己的返回值判断，不是本地缓存的 affectedRunID。
                var actuallyAbortedRunId = OpenclawWire.JsonString(abortResult.Get("abortedRunId"));
                bool timedOut = false;
                if (actuallyAbortedRunId != null)
                {
                    // M3：用权威值覆盖，不再信任 abort 前的本地缓存。
                    lock (_sync) { if (_pendingStops.TryGetValue(session.SessionId, out var p)) p.AffectedRunId = actuallyAbortedRunId; }
                    int timeoutSeconds;
                    lock (_sync) { timeoutSeconds = _testStopTimeoutSecondsOverride ?? 5; }
                    var waitOutcome = await WaitForPendingStopTerminalAsync(session.SessionId, timeoutSeconds);
                    switch (waitOutcome)
                    {
                        case StopWaitOutcome.TransportClosed:
                            // NOTE-1（T-047 grok 复核，真挂起 bug 修复）：等待过程中 transport 已经
                            // 关闭——ResolvePendingStopForTransportClose（见 HandleTransportClosed）
                            // 已经代发 operation_completed(aborted_effect_unknown) 镜像、标记
                            // TerminalEmitted，且 ClearSessionDerivedCaches 已经清理了包括本函数
                            // stop_in_progress 锁在内的全部派生状态。这里绝不能假装
                            // succeeded/timed_out 继续往下走——sessions.delete 在 transport 已断的
                            // 情况下多半也会失败，即使侥幸命中测试桩"成功"了，也会跟已经发出的镜像
                            // 终态矛盾（M3 修的正是 Promise/Event 矛盾这类问题）。如实抛错，交给下面
                            // 的 catch 统一收尾——此时 pendingStop/lock 已经是空的，catch 里的清理调用
                            // 都是安全的 no-op。
                            throw new KernelClientException(KernelClientErrorKind.Transport,
                                "stop() aborted: transport closed while waiting for aborted-run terminal confirmation");
                        case StopWaitOutcome.TimedOut:
                            EmitOperationCompletedMirror(session.SessionId, operationId, actuallyAbortedRunId, PayloadOutcome.TimedOut);
                            // NOTE-2：超时路径也要标记 TerminalEmitted——否则迟到的 aborted lifecycle
                            // 帧仍可能在 ClearSessionDerivedCaches 清缓存前，被 HandleAgentEvent 的
                            // `!pendingForRun.TerminalEmitted` 判断当成"还没发过 terminal"又发一组。
                            lock (_sync) { if (_pendingStops.TryGetValue(session.SessionId, out var p2)) p2.TerminalEmitted = true; }
                            timedOut = true;
                            break;
                        case StopWaitOutcome.TerminalObserved:
                        default:
                            timedOut = false;
                            break;
                    }
                }
                else
                {
                    // 这次 stop() 生效时该 run 早已自然结束——没有可等待的终态，但 Promise 即将报
                    // succeeded，必须同时给事件流补一条 operation_completed 镜像。
                    lock (_sync) { _pendingStops.Remove(session.SessionId); }
                    EmitOperationCompletedMirror(session.SessionId, operationId, null, PayloadOutcome.Succeeded);
                }

                var deleteResult = await RequestAsync("sessions.delete", new JSONObject { ["key"] = kernelKey });
                OpenclawWire.PrettyPrint("RECV sessions.delete result", deleteResult);
                var deleted = OpenclawWire.JsonBool(deleteResult.Get("deleted")) ?? false;
                if (!deleted)
                {
                    // 诚实记录：delete 未确认成功，但不据此把已经发出/即将返回的 succeeded 倒转成
                    // rejected——delete 是资源回收收尾步骤，和"stop 本身有没有成功"是两件事。
                    OpenclawWire.PrettyPrint("WARN sessions.delete reported deleted:false after stop() otherwise succeeded", deleteResult);
                }

                EmitStopSessionEndAndFinish(session);

                var outcome = timedOut ? StopResultPayloadOutcome.TimedOut : StopResultPayloadOutcome.Succeeded;
                return new StopResultPayload { OperationId = operationId, Outcome = outcome };
            }
            catch (Exception)
            {
                // M3：sessions.abort/sessions.delete 抛错——释放锁 + 清理 pendingStop + 发一条
                // operation_completed(rejected) 镜像，再把原始错误重新抛出。
                //
                // NOTE-1 订正（写 NOTE-1 回归测试时坐实的竞态）：只有当"这次 stop() 还没有为任何
                // 其它路径发过终态镜像"时才在这里补发 rejected——否则会跟已经发出的镜像互相矛盾。
                // 两个具体场景都会走到这里却已经发过别的镜像：① NOTE-1 的 transport-closed 路径
                // （ResolvePendingStopForTransportClose 已经标记 TerminalEmitted=true 并发出
                // aborted_effect_unknown，StopAsync 随后如实 throw，落进这个 catch）；②
                // "无 active run"分支已经移除 pendingStop 并发出 succeeded，之后 sessions.delete 才
                // 抛错。两种情况都不该再补一条 rejected——那会让同一次 stop() 在事件流里出现两条互相
                //打架的终态。
                bool alreadyTerminalEmitted;
                string? affectedRunId;
                lock (_sync)
                {
                    if (_pendingStops.TryGetValue(session.SessionId, out var p))
                    {
                        alreadyTerminalEmitted = p.TerminalEmitted;
                        affectedRunId = p.AffectedRunId;
                    }
                    else
                    {
                        // entry 已经不在——要么是"无 active run"分支已经移除并发过 succeeded 镜像，
                        // 要么是 NOTE-1 的 transport-closed 清理路径已经移除并发过
                        // aborted_effect_unknown 镜像；两种情况都已经诚实报过终态，这里不重复。
                        alreadyTerminalEmitted = true;
                        affectedRunId = affectedRunIdBeforeAbort;
                    }
                }
                if (!alreadyTerminalEmitted)
                {
                    EmitOperationCompletedMirror(session.SessionId, operationId, affectedRunId, PayloadOutcome.Rejected);
                }
                lock (_sync)
                {
                    _pendingStops.Remove(session.SessionId);
                    _lockStateBySessionId.Remove(session.SessionId);
                }
                throw;
            }
        }

        /// <summary>
        /// D1 §6.2 M3 + §6.3（stop-path 强制 deny，本轮新增）：在 StopAsync 发起 sessions.abort 之前，
        /// 把该 session 当前所有仍处于 pending 的审批（由 EmitApprovalRequestIfPossible 登记进
        /// <see cref="_pendingApprovalsByReqId"/>）逐个强制 deny。
        ///
        /// <para>
        /// **openclaw wire grounding（只读参考，未改该文件）**：
        /// `kernels/openclaw/src/gateway/server-methods/approval.ts` 的 "approval.resolve" handler——
        /// openclaw 统一的、kind-agnostic 的审批解决 RPC（`packages/sdk/src/client.ts:943`
        /// `ApprovalsNamespace.Respond` 走的也是这一条，只是 SDK 包了一层 `exec.approval.resolve`
        /// 别名）。params schema（`packages/gateway-protocol/src/schema/approvals.ts:245`
        /// `ApprovalResolveParamsSchema`）：`{id, kind, decision}`；成功响应体
        /// （`ApprovalResolveResultSchema`）：`{applied: bool, approval: {status, ...}}`。**"确认①
        /// 的 deny 已生效（内核侧确认接受，而非仅适配器本地标记）"由这次 RPC 的 `await` 本身构成**：
        /// `await RequestAsync(...)` 只有等到 openclaw 真正处理完这条 approval.resolve 请求、回一个
        /// ok:true 的响应帧之后才会返回；ok:false（HandleIncoming 的 "res" 分支）会被 RequestAsync
        /// 转成 <see cref="KernelClientException"/>（RpcRejected）抛出——这里不吞掉这个错误，调用方
        /// （StopAsync）会因此中止、落进它自己的 catch 分支统一收尾，绝不会在没有真正拿到内核确认的
        /// 情况下继续往下发 sessions.abort（那正是 M3 定序要防止的竞态：deny 还没被内核接受，abort
        /// 已经发出去了）。拿到 ok:true 响应后，本函数还要求 `approval.status == "denied"`——只有
        /// 这个字段真的是 "denied" 才算数，见下方检查。
        /// </para>
        /// <para>
        /// approval.resolve 对 id 的路由（`record.kind === "exec" ? execApprovalManager : ...`，见
        /// `approval.ts:492-518`）本身按**服务端已持久化的 record.kind** 选择 manager，不依赖客户端
        /// 传的 kind 字段是否精确匹配——传错 kind 只会让服务端把这次决议记成
        /// `reason:"malformed-verdict"`（applyForcedDeny）而不是 "user"，两者都会落地成
        /// `status:"denied"`。本函数仍然传本地缓存的真实 OpenclawKind（见
        /// EmitApprovalRequestIfPossible）——如实转发协议要求的字段，不是"反正传错也能过就随便填"。
        /// </para>
        /// <para>
        /// 返回值是这一批被强制终态化的 reqId 列表，供调用方（StopAsync）塞进该 run
        /// TurnCompleteEvent.ForceResolvedApprovals（D1 §6.2 M3："步骤①的强制终态化须同步在该 run 的
        /// TurnCompleteEvent.forceResolvedApprovals 中列出"）。没有任何 pending 审批时直接返回空
        /// 列表、**不发起任何 RPC**——绝大多数 stop() 调用都会走这条空路径，这也是为什么这个函数不会
        /// 打破既有的 26 个 frame-replay 测试（它们都没有 stub approval.resolve，真打了这条 RPC 会
        /// 因为没有测试桩、也没有真实连接而抛 NotConnected）。
        /// </para>
        /// <para>
        /// **NOTE-A（T-049 grok 对抗审复核，本轮修复）drain-loop rework**：上一轮只对 pending reqId
        /// 取**一次快照**再逐个 await deny——若某个 approval 在这 N 个 approval.resolve RPC 往返组成
        /// 的 await 窗口内新到（EmitApprovalRequestIfPossible 在锁外 await 期间登记进
        /// _pendingApprovalReqIdsBySessionId），会逃过本轮快照、仍处于 pending 就被随后的
        /// sessions.abort 甩下——这正是 D1 §6.2 力保的 exactly-once 想避免的"cancel 已生效、审批还
        /// pending、内核对即将消失的 run 又异步接受一个人工决策"的变体（与 Swift actor 重入同构，
        /// 见 T-049 handoff §2b/§4）。
        /// </para>
        /// <para>
        /// **选型：drain-loop（而非 freeze 登记 + deny late arrival）**，与 Swift 侧同一份论证：
        /// freeze 方向要求 EmitApprovalRequestIfPossible（当前是 HandleAgentEvent/
        /// HandleSessionApprovalEvent/ConsumeApprovalReplay 这几个纯同步 wire dispatch 方法内部的
        /// 同步调用）在 StopInProgress 期间对新到的 approval 立即发一次 `await RequestAsync(
        /// "approval.resolve", ...)`——但这几个 dispatch 方法本身是从 HandleIncoming 同步调用的
        /// （ReceiveLoopAsync 的热路径），要嵌入一次真正的 RPC await 就必须让它们要么整体变成 async
        /// （连锁改动 HandleIncoming/ReceiveLoopAsync 的调用形状），要么用 `Task.Run(async () =>
        /// ...)` fire-and-forget——而后者恰好**重新引入同一类竞态**：StopAsync 完全不知道这个后台
        /// Task 有没有跑完 deny 就已经继续发 sessions.abort 了，为了堵住这个新洞，还是得让 StopAsync
        /// 在 abort 前等所有"在途 late-deny"收尾——这就是把 drain-loop 拆成两个协作的地方重新实现一
        /// 遍，状态更分散、更难论证，且 C# 这边额外要求"锁外调度后台任务 + 事后汇合"不引入新 race，
        /// 比本函数内部一个单纯的 while 循环更难保证。
        /// </para>
        /// <para>
        /// **有界性论证**（D1 §9：一个 session 同一时刻只有一个 active run；StopAsync 进入
        /// StopInProgress 早于本方法被调用，SendAsync 在锁不是 Idle 时一律 reject——因此这个 session
        /// 在整段 drain 期间**不会有新 run 被创建**）：drain 期间还能继续冒出新 pending 审批的唯一
        /// 来源是"这次 stop() 即将 abort 的、唯一的那个 run"自己的 agent 事件流仍在正常产出
        /// （sessions.abort 要等 drain 完全收敛成空之后才发出，所以这个 run 在 drain 期间确实还活着、
        /// 还能请求审批）——正常场景下这类审批请求本就是有限的一个序列，drain 循环每一轮重新快照都会
        /// 把新到的一并收进下一轮，若干轮内必然收敛为空。为"理论上不该出现但不能假装不可能"的极端
        /// 场景兜底：加一个迭代轮次上限（<see cref="ForceDenyDrainDefaultMaxRounds"/>/
        /// <see cref="_testForceDenyDrainMaxRoundsOverride"/>），超限**如实 throw**（不是静默截断、
        /// 也不是假装 succeeded 继续往下 abort），落进 StopAsync 既有的 catch 分支统一收尾（锁释放 +
        /// pendingStop 清理 + operation_completed(rejected) 镜像）。
        /// </para>
        /// <para>
        /// **不重蹈 NOTE-1**：drain 循环增加的是"更多轮的 approval.resolve await"，跟 NOTE-1 修的
        /// "sessions.abort 之后等待 aborted lifecycle 终态"是完全不同的 await 点；若 transport 在
        /// drain 期间关闭，正在等待中的 approval.resolve TaskCompletionSource 会被 FailAllPending
        /// 唤醒抛 transport 错误（此时 WaitForPendingStopTerminalAsync 的 waiter 还没登记——那是
        /// abort **之后**才会 setup 的），错误沿 `await RequestAsync(...)` 向上抛出，直接落进
        /// StopAsync 的 catch 分支（锁释放、pendingStop 清理），不会有任何新的挂起路径。
        /// </para>
        /// <para>
        /// **正确性要求 + 残留窗口（诚实标注）**：只有当某一轮开始时重新读取的
        /// _pendingApprovalReqIdsBySessionId[sessionId] 恰好为空，才 break 出循环、把 forceResolved
        /// 返回给 StopAsync 去发 sessions.abort。C# 没有 Swift actor 那种"两次挂起点之间对同一隔离域
        /// 原子"的编译器保证——这里改用 `lock (_sync)` 做同一件事：读空快照的那次 `lock` 块结束、方法
        /// 返回、调用方真正把 sessions.abort 帧写上线之间，理论上仍有一个远小于本方法所修的"N 轮 RPC
        /// 往返"窗口的残留缝隙（另一个线程上的 HandleIncoming 恰好在这几行同步代码之间登记了一个新
        /// approval）。这与"abort 已发出、内核尚未真正处理"这类网络延迟本质相同，不是本方法能够或
        /// 应该负责关闭的范围（两个候选方向都无法免除，见交付报告）。
        /// </para>
        /// </summary>
        private async Task<List<string>> ForceDenyPendingApprovalsBeforeStopAsync(string sessionId)
        {
            var forceResolved = new List<string>();
            var round = 0;
            int maxRounds;
            lock (_sync) { maxRounds = _testForceDenyDrainMaxRoundsOverride ?? ForceDenyDrainDefaultMaxRounds; }

            while (true)
            {
                List<string> reqIds;
                lock (_sync)
                {
                    reqIds = _pendingApprovalReqIdsBySessionId.TryGetValue(sessionId, out var set) ? set.ToList() : new List<string>();
                }
                if (reqIds.Count == 0)
                {
                    // 这一刻的快照为空——drain 收敛（残留的极窄锁外窗口见方法文档注释"正确性要求"）。
                    break;
                }
                round += 1;
                if (round > maxRounds)
                {
                    throw new KernelClientException(KernelClientErrorKind.ProtocolMismatch,
                        $"ForceDenyPendingApprovalsBeforeStopAsync: exceeded {maxRounds} drain round(s) for session {sessionId} " +
                        $"while still observing {reqIds.Count} newly-arrived pending approval(s) during force-deny — " +
                        "refusing to loop indefinitely (NOTE-A drain bound)");
                }

                // 排序只是让每一轮内部"同一 session 存在多个 pending 审批"这种边缘情况下 RPC 发起顺序
                // 在测试里可预测——不是协议要求的顺序。
                foreach (var reqId in reqIds.OrderBy(x => x, StringComparer.Ordinal))
                {
                    PendingApprovalAwaitingDecision? info;
                    lock (_sync) { _pendingApprovalsByReqId.TryGetValue(reqId, out info); }
                    if (info == null) continue;

                    var result = await RequestAsync("approval.resolve", new JSONObject
                    {
                        ["id"] = reqId,
                        ["kind"] = info.OpenclawKind,
                        ["decision"] = "deny",
                    });
                    OpenclawWire.PrettyPrint($"RECV approval.resolve result (M3 stop-path force-deny, drain round {round})", result);
                    var approvalStatus = OpenclawWire.JsonString(OpenclawWire.JsonObj(result.Get("approval")).Get("status"));
                    if (approvalStatus != "denied")
                    {
                        // 内核没有把这次强制 deny 落地成 denied 终态——如实抛错，不能假装"已确认生效"
                        // （M3 的核心要求就是"确认"，不是"发了请求就当数"）。RespondApprovalAsync() 本轮
                        // 仍是 TODO 桩，真实环境里目前没有任何别的路径能在这之前把这个 reqId 变成其它
                        // 终态，这条防线现阶段只有测试桩能触发。
                        throw new KernelClientException(KernelClientErrorKind.ProtocolMismatch,
                            $"approval.resolve did not confirm denied status for reqId {reqId} during stop() force-deny (got status: {approvalStatus ?? "null"})");
                    }
                    forceResolved.Add(reqId);
                    lock (_sync)
                    {
                        _pendingApprovalsByReqId.Remove(reqId);
                        if (_pendingApprovalReqIdsBySessionId.TryGetValue(sessionId, out var set2)) set2.Remove(reqId);
                    }
                }
            }
            return forceResolved;
        }

        /// <summary>M3：为 stop() 不会经过真实 aborted lifecycle 帧的路径补一条 operation_completed 镜像。</summary>
        private void EmitOperationCompletedMirror(string sessionId, string operationId, string? affectedRunId, PayloadOutcome outcome)
        {
            bool hasChannel;
            lock (_sync) { hasChannel = _eventChannels.ContainsKey(sessionId); }
            if (!hasChannel) return;

            var opPayload = new OperationCompletedEventMessagePayload
            {
                AffectedRunId = affectedRunId, Detail = null, NewRunId = null,
                OperationId = operationId, OperationKind = OperationKind.Stop, Outcome = outcome,
            };
            var evt = new OperationCompletedEventMessage
            {
                Direction = MessageDeltaEventMessageDirection.Event, Payload = opPayload, RunId = affectedRunId,
                SentAt = DateTimeOffset.UtcNow, Seq = NextSeq(affectedRunId, sessionId),
                SessionId = sessionId, Ts = DateTimeOffset.UtcNow, Type = OperationCompletedEventMessageType.EvtOperationCompleted,
            }.AsUnion();
            Yield(sessionId, evt);
        }

        /// <summary>stop() 成功路径的收尾：F8 去重 + yield session_end(stopped) + finish 事件流。</summary>
        private void EmitStopSessionEndAndFinish(SessionHandle session)
        {
            bool already;
            lock (_sync)
            {
                already = _sessionTerminalEmitted.Contains(session.SessionId);
                if (!already) _sessionTerminalEmitted.Add(session.SessionId);
            }
            if (!already)
            {
                var sid = session.SessionId;
                Yield(sid, EventMapping.MakeSessionEndEventForStop(sid, () => NextSeq(null, sid)));
            }
            FinishEventContinuation(session.SessionId);
            lock (_sync) { _kernelKeyBySessionId.Remove(session.SessionId); }
        }

        private async Task<StopWaitOutcome> WaitForPendingStopTerminalAsync(string sessionId, int timeoutSeconds)
        {
            TaskCompletionSource<StopWaitOutcome> tcs;
            lock (_sync)
            {
                if (!_pendingStops.TryGetValue(sessionId, out var pending))
                {
                    // NOTE-1：entry 已经不在——这只可能是 transport 关闭清理路径
                    // （ClearSessionDerivedCaches）抢在我们拿到这把锁之前就跑完了（例如
                    // sessions.abort RPC 返回、和这里拿锁之间那个极窄的窗口内 transport 关闭）。这种
                    // 情况不能假装"没超时、一切正常"地往下走（旧 bug 的窄化版本）——如实报
                    // TransportClosed，交由 StopAsync 统一走 rethrow 分支。
                    return StopWaitOutcome.TransportClosed;
                }
                if (pending.TerminalEmitted) return StopWaitOutcome.TerminalObserved;
                tcs = new TaskCompletionSource<StopWaitOutcome>(TaskCreationOptions.RunContinuationsAsynchronously);
                pending.Waiter = tcs;
            }
            _ = Task.Run(async () =>
            {
                await Task.Delay(TimeSpan.FromSeconds(timeoutSeconds));
                ResolvePendingStopWaiter(sessionId, StopWaitOutcome.TimedOut);
            });
            return await tcs.Task;
        }

        private void ResolvePendingStopWaiter(string sessionId, StopWaitOutcome outcome)
        {
            TaskCompletionSource<StopWaitOutcome>? waiter;
            lock (_sync)
            {
                if (!_pendingStops.TryGetValue(sessionId, out var pending) || pending.Waiter == null) return;
                waiter = pending.Waiter;
                pending.Waiter = null;
            }
            waiter.TrySetResult(outcome);
        }

        /// <summary>
        /// NOTE-1（T-047 grok 复核，真挂起 bug 修复）：transport 关闭时，若该 session 有一个仍在
        /// 等待 aborted-run 终态确认的 pendingStop（Waiter 非空、尚未 TerminalEmitted），必须在它
        /// 被 <see cref="ClearSessionDerivedCaches"/> 移除之前做两件事：(a) 补发一条
        /// operation_completed(aborted_effect_unknown) 镜像——语义是"我们已经请求了 abort，但
        /// transport 断在确认之前，效果未知"，且必须赶在 FailAllPending 把这个 session 的 channel
        /// TryComplete 之前调用（之后 TryWrite 恒为 false、静默丢弃，不抛异常，镜像会永久丢失）；
        /// (b) 唤醒 WaitForPendingStopTerminalAsync 里 await 着的那个 Waiter，让 StopAsync 不再
        /// 永久挂起（旧 bug：ClearSessionDerivedCaches 直接 Remove pendingStop 却不 resolve
        /// Waiter，随后超时任务 ResolvePendingStopWaiter 发现条目已经不在，early-return，TCS 永不
        /// 完成）。调用方（HandleTransportClosed）必须保证本方法先于该 session 的 channel 被
        /// TryComplete 调用。
        /// </summary>
        private void ResolvePendingStopForTransportClose(string sessionId)
        {
            TaskCompletionSource<StopWaitOutcome>? waiter;
            string operationId;
            string? affectedRunId;
            lock (_sync)
            {
                if (!_pendingStops.TryGetValue(sessionId, out var pending) || pending.Waiter == null)
                {
                    // 没有正在等待的 stop()——多半是终态已经被 handleAgentEvent 观察到，或者超时
                    // 定时器已经先一步 resolve 过了；这是正常竞态，不是 bug，无事可做。
                    return;
                }
                waiter = pending.Waiter;
                pending.Waiter = null;
                pending.TerminalEmitted = true; // 先标记再唤醒——resolve 与 remove 之间不留竞态窗口。
                operationId = pending.OperationId;
                affectedRunId = pending.AffectedRunId;
            }
            EmitOperationCompletedMirror(sessionId, operationId, affectedRunId, PayloadOutcome.AbortedEffectUnknown);
            waiter.TrySetResult(StopWaitOutcome.TransportClosed);
        }

        public Task RespondApprovalAsync(SessionHandle session, string reqId, Decision decision, CancellationToken cancellationToken = default)
            => throw new KernelClientException(KernelClientErrorKind.NotImplemented, "respondApproval() 本轮 TODO 桩——L1 闭环没有回调过任何真实审批");

        public Task<CapabilityDescriptorPayload> CapabilitiesAsync(SessionHandle? session = null, CancellationToken cancellationToken = default)
            => throw new KernelClientException(KernelClientErrorKind.NotImplemented, "capabilities() 本轮 TODO 桩——未探测 openclaw capabilities 端点");

        // MARK: - 内部：session 映射表 + 事件流生命周期

        private string? OurSessionIdForKernelKey(string kernelKey)
        {
            lock (_sync)
            {
                foreach (var kv in _kernelKeyBySessionId)
                    if (kv.Value == kernelKey) return kv.Key;
            }
            return null;
        }

        /// <summary>F3：per-run（或无 run 归属时按 session）单调递增 seq。</summary>
        private long NextSeq(string? runId, string sessionId)
        {
            lock (_sync)
            {
                if (runId != null)
                {
                    var next = (_seqByRunId.TryGetValue(runId, out var cur) ? cur : 0) + 1;
                    _seqByRunId[runId] = next;
                    return next;
                }
                var nextFallback = (_seqFallbackBySessionId.TryGetValue(sessionId, out var curF) ? curF : 0) + 1;
                _seqFallbackBySessionId[sessionId] = nextFallback;
                return nextFallback;
            }
        }

        private void Yield(string sessionId, EventMessageUnion evt)
        {
            Channel<EventMessageUnion>? channel;
            lock (_sync) { _eventChannels.TryGetValue(sessionId, out channel); }
            channel?.Writer.TryWrite(evt);
        }

        /// <summary>
        /// M5：一个 session 的全部派生缓存——per-run seq/toolCallId/usage、M1 approval 双向缓冲区
        /// （含从未配对成功的孤儿条目）、pendingStop、session 锁、F8 terminal 去重标记，统一清干净。
        /// </summary>
        private void ClearSessionDerivedCaches(string sessionId)
        {
            lock (_sync)
            {
                if (_runIdsBySessionId.TryGetValue(sessionId, out var runIds))
                {
                    foreach (var runId in runIds)
                    {
                        _seqByRunId.Remove(runId);
                        _lastToolCallIdByRunId.Remove(runId);
                        _lastUsageByRunId.Remove(runId);
                    }
                }
                _runIdsBySessionId.Remove(sessionId);
                _lastRunIdBySessionId.Remove(sessionId);
                _seqFallbackBySessionId.Remove(sessionId);

                if (_approvalIdsBySessionId.TryGetValue(sessionId, out var approvalIds))
                {
                    foreach (var approvalId in approvalIds)
                    {
                        _agentApprovalInfoByApprovalId.Remove(approvalId);
                        _pendingSessionApprovalByApprovalId.Remove(approvalId);
                    }
                }
                _approvalIdsBySessionId.Remove(sessionId);

                // M3：session 结束时同样清掉"已产出、仍在 pending 等待决策"的审批表——不清理的话，
                // 一个从未被 stop() 强制处理过的孤儿 reqId（例如 session 走 shutdown/transportClosed
                // 终结，而不是走 stop()）会永久残留在 _pendingApprovalsByReqId 里。
                if (_pendingApprovalReqIdsBySessionId.TryGetValue(sessionId, out var pendingApprovalReqIds))
                {
                    foreach (var reqId in pendingApprovalReqIds) _pendingApprovalsByReqId.Remove(reqId);
                }
                _pendingApprovalReqIdsBySessionId.Remove(sessionId);

                // NOTE-1 防御性兜底：任何调用路径都不应该在 pendingStop 仍有存活 Waiter 时直接
                // Remove——那样等待中的 stop() 永远等不到 resolve（T-047 复现的真挂起 bug）。正常
                // 情况下这里已经是 null（transport 关闭路径已经由 HandleTransportClosed ->
                // ResolvePendingStopForTransportClose 提前 resolve 过，且那条路径还会带上
                // operation_completed 镜像）；这几行只是最后一道防线——没有 channel 引用发不出镜像，
                // 但至少唤醒等待者，绝不留永久挂起。TrySetResult 在锁内调用是安全的：Waiter 由
                // TaskCreationOptions.RunContinuationsAsynchronously 创建，续体调度到线程池执行，
                // 不会同步重入。
                if (_pendingStops.TryGetValue(sessionId, out var stillPending) && stillPending.Waiter != null)
                {
                    var danglingWaiter = stillPending.Waiter;
                    stillPending.Waiter = null;
                    stillPending.TerminalEmitted = true;
                    danglingWaiter.TrySetResult(StopWaitOutcome.TransportClosed);
                }
                _pendingStops.Remove(sessionId);
                _lockStateBySessionId.Remove(sessionId);
                _sessionTerminalEmitted.Remove(sessionId);
            }
        }

        private void FinishEventContinuation(string sessionId)
        {
            Channel<EventMessageUnion>? channel;
            lock (_sync)
            {
                _eventChannels.TryGetValue(sessionId, out channel);
                _eventChannels.Remove(sessionId);
            }
            channel?.Writer.TryComplete();
            ClearSessionDerivedCaches(sessionId);
        }

        // MARK: - 内部：RPC 请求/响应关联

        private async Task<JSONObject> RequestAsync(string method, JSONObject parameters)
        {
            Func<JSONObject, Task<JSONObject>>? responder;
            lock (_sync) { _testSupportRpcResponders.TryGetValue(method, out responder); }
            if (responder != null)
            {
                OpenclawWire.PrettyPrint($"SEND req {method} (test-stubbed, no real transport)", new JSONObject { ["method"] = method, ["params"] = parameters });
                return await responder(parameters);
            }

            var socket = _socket ?? throw new KernelClientException(KernelClientErrorKind.NotConnected, "");

            string id;
            lock (_sync) { _nextReqId += 1; id = $"r{_nextReqId}"; }

            var frame = new JSONObject { ["type"] = "req", ["id"] = id, ["method"] = method, ["params"] = parameters };
            OpenclawWire.PrettyPrint($"SEND req {method}", frame);
            var data = OpenclawWire.EncodeFrame(frame);

            var tcs = new TaskCompletionSource<JSONObject>(TaskCreationOptions.RunContinuationsAsynchronously);
            lock (_sync) { _pending[id] = tcs; }

            try
            {
                await socket.SendAsync(new ArraySegment<byte>(data), WebSocketMessageType.Text, true, CancellationToken.None);
            }
            catch (Exception ex)
            {
                FailPending(id, new KernelClientException(KernelClientErrorKind.Transport, ex.Message));
            }

            return await tcs.Task;
        }

        private void FailPending(string id, Exception error)
        {
            TaskCompletionSource<JSONObject>? tcs;
            lock (_sync) { _pending.Remove(id, out tcs); }
            tcs?.TrySetException(error);
        }

        private Task<JSONObject> WaitForNextEventAsync(string eventName)
        {
            var tcs = new TaskCompletionSource<JSONObject>(TaskCreationOptions.RunContinuationsAsynchronously);
            lock (_sync) { _oneShotEventWaiters[eventName] = tcs; }
            return tcs.Task;
        }

        // MARK: - 内部：接收循环

        private async Task ReceiveLoopAsync()
        {
            var socket = _socket;
            if (socket == null) return;
            var buffer = new byte[16 * 1024];
            while (!_receiveLoopCts.IsCancellationRequested)
            {
                try
                {
                    using var ms = new System.IO.MemoryStream();
                    WebSocketReceiveResult result;
                    do
                    {
                        result = await socket.ReceiveAsync(new ArraySegment<byte>(buffer), _receiveLoopCts.Token);
                        if (result.MessageType == WebSocketMessageType.Close)
                            throw new KernelClientException(KernelClientErrorKind.Transport, "websocket closed by remote");
                        ms.Write(buffer, 0, result.Count);
                    } while (!result.EndOfMessage);
                    HandleIncoming(ms.ToArray());
                }
                catch (OperationCanceledException)
                {
                    break;
                }
                catch (Exception ex)
                {
                    HandleTransportClosed(ex as KernelClientException ?? new KernelClientException(KernelClientErrorKind.Transport, ex.Message));
                    break;
                }
            }
        }

        /// <summary>
        /// 传输中断（真实 WS 断开，或 TestSupportSimulateTransportClosed 模拟）的统一处理。
        /// </summary>
        private void HandleTransportClosed(Exception error)
        {
            List<string> sessionIds;
            lock (_sync) { sessionIds = _eventChannels.Keys.ToList(); }
            foreach (var sessionId in sessionIds)
            {
                // NOTE-1（T-047 grok 复核，真挂起 bug 修复）：若这个 session 有一个仍在等待
                // aborted-run 终态确认的 pendingStop，必须先把它的 operation_completed
                // (aborted_effect_unknown) 镜像写进 channel、唤醒等待中的 stop()，再产出
                // sessionEnd(transportClosed)——顺序对应 D1 §9.3"先终态、后 session_end"的既有约定
                // （stop() 成功路径同样是先 EmitOperationCompletedMirror 再
                // EmitStopSessionEndAndFinish），也必须赶在下面 FailAllPending 把 channel
                // TryComplete 之前做（之后 TryWrite 恒为 false、静默丢弃）。
                ResolvePendingStopForTransportClose(sessionId);

                bool already;
                lock (_sync)
                {
                    already = _sessionTerminalEmitted.Contains(sessionId);
                    if (!already) _sessionTerminalEmitted.Add(sessionId);
                }
                if (already) continue;
                Yield(sessionId, EventMapping.MakeSessionEndEventForTransportClosed(sessionId, () => NextSeq(null, sessionId)));
            }
            FailAllPending(error);
        }

        private void FailAllPending(Exception error)
        {
            List<TaskCompletionSource<JSONObject>> pendingList;
            List<TaskCompletionSource<JSONObject>> waiterList;
            List<KeyValuePair<string, Channel<EventMessageUnion>>> channels;
            lock (_sync)
            {
                pendingList = _pending.Values.ToList();
                _pending.Clear();
                waiterList = _oneShotEventWaiters.Values.ToList();
                _oneShotEventWaiters.Clear();
                channels = _eventChannels.ToList();
                _eventChannels.Clear();
            }
            foreach (var tcs in pendingList) tcs.TrySetException(error);
            foreach (var tcs in waiterList) tcs.TrySetException(error);
            // M5：transport 异常路径也要清理全部派生缓存，跟 finishEventContinuation 共享同一份。
            foreach (var kv in channels)
            {
                kv.Value.Writer.TryComplete(error);
                ClearSessionDerivedCaches(kv.Key);
            }
        }

        private void HandleIncoming(byte[] data)
        {
            JSONObject frame;
            try { frame = OpenclawWire.DecodeFrame(data); }
            catch { return; }

            var type = OpenclawWire.JsonString(frame.Get("type"));
            if (type == null) return;

            switch (type)
            {
                case "res":
                {
                    var id = OpenclawWire.JsonString(frame.Get("id"));
                    if (id == null) return;
                    TaskCompletionSource<JSONObject>? tcs;
                    lock (_sync) { _pending.Remove(id, out tcs); }
                    if (tcs == null) return;
                    var ok = OpenclawWire.JsonBool(frame.Get("ok")) ?? false;
                    if (ok)
                    {
                        var payload = OpenclawWire.JsonObj(frame.Get("payload")) ?? new JSONObject();
                        tcs.TrySetResult(payload);
                    }
                    else
                    {
                        var err = OpenclawWire.JsonObj(frame.Get("error")) ?? new JSONObject();
                        var code = OpenclawWire.JsonString(err.Get("code")) ?? "unknown";
                        var message = OpenclawWire.JsonString(err.Get("message"));
                        tcs.TrySetException(new KernelClientException(KernelClientErrorKind.RpcRejected, message ?? "", code));
                    }
                    break;
                }

                case "event":
                {
                    var eventName = OpenclawWire.JsonString(frame.Get("event"));
                    if (eventName == null) return;
                    TaskCompletionSource<JSONObject>? waiter;
                    lock (_sync) { _oneShotEventWaiters.Remove(eventName, out waiter); }
                    if (waiter != null)
                    {
                        var payload = OpenclawWire.JsonObj(frame.Get("payload")) ?? new JSONObject();
                        waiter.TrySetResult(payload);
                        break;
                    }
                    switch (eventName)
                    {
                        case "session.message": HandleSessionMessageEvent(frame); break;
                        case "agent": HandleAgentEvent(frame); break;
                        case "session.approval": HandleSessionApprovalEvent(frame); break;
                        case "shutdown": HandleShutdownEvent(frame); break;
                        default:
                            OpenclawWire.PrettyPrint($"RECV event {eventName} (未处理的旁路事件，原样打印)", frame);
                            break;
                    }
                    break;
                }
            }
        }

        private void HandleSessionMessageEvent(JSONObject frame)
        {
            var payload = OpenclawWire.JsonObj(frame.Get("payload"));
            if (payload == null) return;
            var kernelKey = OpenclawWire.JsonString(payload.Get("sessionKey"));
            if (kernelKey == null) return;
            var ourSessionId = OurSessionIdForKernelKey(kernelKey);
            if (ourSessionId == null) return;
            bool hasChannel;
            lock (_sync) { hasChannel = _eventChannels.ContainsKey(ourSessionId); }
            if (!hasChannel) return;

            string? currentRunId;
            lock (_sync) { _lastRunIdBySessionId.TryGetValue(ourSessionId, out currentRunId); }

            var sessionSnapshot = OpenclawWire.JsonObj(payload.Get("session"));
            if (sessionSnapshot != null &&
                OpenclawWire.JsonArr(sessionSnapshot.Get("activeRunIds")) is List<object?> activeRunIds &&
                activeRunIds.Count > 0 && activeRunIds[0] is string firstRunId)
            {
                lock (_sync)
                {
                    _lastRunIdBySessionId[ourSessionId] = firstRunId;
                    if (!_runIdsBySessionId.TryGetValue(ourSessionId, out var set)) _runIdsBySessionId[ourSessionId] = set = new HashSet<string>();
                    set.Add(firstRunId);
                }
                currentRunId = firstRunId;
            }

            var message = OpenclawWire.JsonObj(payload.Get("message"));
            if (message != null && OpenclawWire.JsonObj(message.Get("usage")) is JSONObject usage &&
                OpenclawWire.JsonInt(usage.Get("input")) is long usageInput && OpenclawWire.JsonInt(usage.Get("output")) is long usageOutput &&
                currentRunId is string usageRunId)
            {
                lock (_sync) { _lastUsageByRunId[usageRunId] = (usageInput, usageOutput); }
            }

            var runIdHint = currentRunId;
            var sid = ourSessionId;
            var events = EventMapping.MapOpenclawSessionMessageToKernelEvents(
                payload, ourSessionId, runIdHint, () => NextSeq(runIdHint, sid));

            if (events.Count == 0)
            {
                OpenclawWire.PrettyPrint("RECV session.message（未能映射到 D2 KernelEvent 11 变体之一）", frame);
                return;
            }
            foreach (var evt in events)
            {
                if (evt is ToolCallEventMessageCase toolCall && runIdHint != null)
                {
                    lock (_sync) { _lastToolCallIdByRunId[runIdHint] = toolCall.Value.Payload.ToolCallId; }
                }
                Yield(ourSessionId, evt);
            }
        }

        private void HandleAgentEvent(JSONObject frame)
        {
            var payload = OpenclawWire.JsonObj(frame.Get("payload"));
            if (payload == null) return;
            var kernelKey = OpenclawWire.JsonString(payload.Get("sessionKey"));
            if (kernelKey == null) return;
            var ourSessionId = OurSessionIdForKernelKey(kernelKey);
            if (ourSessionId == null) return;
            bool hasChannel;
            lock (_sync) { hasChannel = _eventChannels.ContainsKey(ourSessionId); }
            if (!hasChannel) return;

            if (OpenclawWire.JsonString(payload.Get("runId")) is string runIdFromFrame)
            {
                lock (_sync)
                {
                    _lastRunIdBySessionId[ourSessionId] = runIdFromFrame;
                    if (!_runIdsBySessionId.TryGetValue(ourSessionId, out var set)) _runIdsBySessionId[ourSessionId] = set = new HashSet<string>();
                    set.Add(runIdFromFrame);
                }
            }

            var stream = OpenclawWire.JsonString(payload.Get("stream"));
            var data = OpenclawWire.JsonObj(payload.Get("data"));
            if (stream == null || data == null) return;

            string? runIdHint;
            lock (_sync) { _lastRunIdBySessionId.TryGetValue(ourSessionId, out runIdHint); }
            var originTs = OpenclawWire.MsEpochToDate(OpenclawWire.JsonInt(payload.Get("ts")));
            long NextSeqForRun() => NextSeq(runIdHint, ourSessionId);

            switch (stream)
            {
                case "command_output":
                {
                    var evt = EventMapping.MapOpenclawAgentCommandOutputToToolResult(data, ourSessionId, runIdHint, originTs, NextSeqForRun);
                    if (evt != null) Yield(ourSessionId, evt);
                    break;
                }

                case "item":
                {
                    if (OpenclawWire.JsonString(data.Get("kind")) != "tool") break;
                    if (EventMapping.IsOpenclawExecToolName(OpenclawWire.JsonString(data.Get("name")))) break;
                    var evt = EventMapping.MapOpenclawAgentToolItemToToolResult(data, ourSessionId, runIdHint, originTs, NextSeqForRun);
                    if (evt != null) Yield(ourSessionId, evt);
                    break;
                }

                case "thinking":
                {
                    var evt = EventMapping.MapOpenclawAgentThinkingToKernelEvent(data, ourSessionId, runIdHint, originTs, NextSeqForRun);
                    if (evt != null) Yield(ourSessionId, evt);
                    break;
                }

                case "error":
                {
                    var evt = EventMapping.MapOpenclawAgentErrorToKernelEvent(data, ourSessionId, runIdHint, originTs, NextSeqForRun);
                    if (evt != null) Yield(ourSessionId, evt);
                    break;
                }

                case "approval":
                {
                    // F4/M1：这条 agent 帧本身不直接产出 D2 事件——真正的 approval_request 仍由
                    // session.approval(phase:pending) 产出，这里只是给它提供不会串号的
                    // {runId,toolCallId} 来源。
                    if (OpenclawWire.JsonString(data.Get("phase")) == "requested" &&
                        OpenclawWire.JsonString(data.Get("approvalId")) is string approvalId &&
                        OpenclawWire.JsonString(data.Get("toolCallId")) is string toolCallId &&
                        runIdHint is string approvalRunId)
                    {
                        PendingSessionApproval? buffered;
                        lock (_sync)
                        {
                            if (!_approvalIdsBySessionId.TryGetValue(ourSessionId, out var set)) _approvalIdsBySessionId[ourSessionId] = set = new HashSet<string>();
                            set.Add(approvalId);
                            _pendingSessionApprovalByApprovalId.Remove(approvalId, out buffered);
                        }
                        if (buffered != null)
                        {
                            EmitApprovalRequestIfPossible(buffered.Payload, buffered.OurSessionId, approvalRunId, toolCallId);
                            lock (_sync) { if (_approvalIdsBySessionId.TryGetValue(ourSessionId, out var set2)) set2.Remove(approvalId); }
                        }
                        else
                        {
                            lock (_sync) { _agentApprovalInfoByApprovalId[approvalId] = new AgentApprovalInfo(approvalRunId, toolCallId); }
                        }
                    }
                    break;
                }

                case "lifecycle":
                {
                    var phase = OpenclawWire.JsonString(data.Get("phase"));
                    if (phase != "end" && phase != "error") break;
                    if (runIdHint == null) break;
                    var runId = runIdHint;
                    var aborted = OpenclawWire.JsonBool(data.Get("aborted")) ?? false;

                    (long Input, long Output)? cachedUsage = null;
                    lock (_sync) { if (_lastUsageByRunId.TryGetValue(runId, out var u)) cachedUsage = u; }

                    if (aborted)
                    {
                        PendingStop? pendingForRun = null;
                        bool noOwner = false;
                        lock (_sync)
                        {
                            if (_pendingStops.TryGetValue(ourSessionId, out var p))
                            {
                                if (p.AffectedRunId == runId && !p.TerminalEmitted) pendingForRun = p;
                            }
                            else
                            {
                                noOwner = true;
                            }
                        }

                        if (pendingForRun != null)
                        {
                            // M3：这次 stop() 在发起 sessions.abort 之前强制 deny 掉的 reqId（如
                            // 有）——D1 §6.2 M3 要求同步列进这个 run 的
                            // TurnCompleteEvent.forceResolvedApprovals。
                            string[]? forceResolvedApprovals = pendingForRun.ForceResolvedApprovalReqIds.Count == 0
                                ? null : pendingForRun.ForceResolvedApprovalReqIds.ToArray();
                            // F6：单个 operation_completed + turn_complete(cancelled)，用 stop() 铸造的
                            // 唯一 operationId，且对同一次 pendingStop 只做一次。
                            var events = EventMapping.MapOpenclawAgentLifecycleToAbortTerminalEvents(
                                data, ourSessionId, runId, pendingForRun.OperationId, originTs, cachedUsage,
                                forceResolvedApprovals, NextSeqForRun);
                            foreach (var e in events) Yield(ourSessionId, e);
                            lock (_sync) { pendingForRun.TerminalEmitted = true; _lastUsageByRunId.Remove(runId); }
                            ResolvePendingStopWaiter(ourSessionId, StopWaitOutcome.TerminalObserved);
                        }
                        else if (noOwner)
                        {
                            // 理论上不会出现——interrupt() 本轮未实现。防御性兜底：自己派生一个
                            // operationId，保持"至少不丢事件"的行为。这条路径没有关联到任何 stop() 的
                            // pendingStop——不存在"这次 stop() 强制 deny 过谁"的信息可以塞，
                            // forceResolvedApprovals 如实传 null。
                            var fallbackOperationId = $"{ourSessionId}-abort-{runId}-unowned";
                            var events = EventMapping.MapOpenclawAgentLifecycleToAbortTerminalEvents(
                                data, ourSessionId, runId, fallbackOperationId, originTs, cachedUsage, null, NextSeqForRun);
                            foreach (var e in events) Yield(ourSessionId, e);
                            lock (_sync) { _lastUsageByRunId.Remove(runId); }
                        }
                        // else：已经为这次 stop() 发过 terminal——如实丢弃这条收尾帧，不重复产出。
                    }
                    else
                    {
                        // M3：极罕见竞态——force-deny 已经生效、sessions.abort 尚未真正让这个 run 落地
                        // aborted 状态之前，run 自己先自然完成（这条 lifecycle 帧走的是 aborted:false
                        // 分支）。即便如此，仍要把已经强制 deny 掉的 reqId 挂到这条 TurnCompleteEvent
                        // 上——不能因为走的是"正常结束"分支就丢失这个信息（D1 §6.2 M3 只要求"该 run 的
                        // TurnCompleteEvent"带上 forceResolvedApprovals，没有区分它是从 aborted 分支
                        // 还是正常分支产出的）。
                        string[]? forceResolvedApprovals = null;
                        lock (_sync)
                        {
                            if (_pendingStops.TryGetValue(ourSessionId, out var pendingForNormalCompletion) &&
                                pendingForNormalCompletion.AffectedRunId == runId &&
                                pendingForNormalCompletion.ForceResolvedApprovalReqIds.Count > 0)
                            {
                                forceResolvedApprovals = pendingForNormalCompletion.ForceResolvedApprovalReqIds.ToArray();
                            }
                        }
                        var evt = EventMapping.MapOpenclawAgentLifecycleToTurnComplete(
                            data, ourSessionId, runId, originTs, cachedUsage, forceResolvedApprovals, NextSeqForRun);
                        Yield(ourSessionId, evt);
                        lock (_sync) { _lastUsageByRunId.Remove(runId); }
                    }
                    break;
                }
            }
        }

        private void HandleSessionApprovalEvent(JSONObject frame)
        {
            var payload = OpenclawWire.JsonObj(frame.Get("payload"));
            if (payload == null) return;
            var kernelKey = OpenclawWire.JsonString(payload.Get("sessionKey"));
            if (kernelKey == null) return;
            var ourSessionId = OurSessionIdForKernelKey(kernelKey);
            if (ourSessionId == null) return;
            bool hasChannel;
            lock (_sync) { hasChannel = _eventChannels.ContainsKey(ourSessionId); }
            if (!hasChannel) return;

            if (OpenclawWire.JsonString(payload.Get("phase")) != "pending")
            {
                OpenclawWire.PrettyPrint("RECV session.approval（phase:terminal，D1 11 变体无对应，跳过）", frame);
                return;
            }
            var approval = OpenclawWire.JsonObj(payload.Get("approval"));
            var approvalId = approval != null ? OpenclawWire.JsonString(approval.Get("id")) : null;
            if (approvalId == null) return;

            AgentApprovalInfo? agentInfo;
            lock (_sync) { _agentApprovalInfoByApprovalId.Remove(approvalId, out agentInfo); }

            if (agentInfo != null)
            {
                lock (_sync) { if (_approvalIdsBySessionId.TryGetValue(ourSessionId, out var set)) set.Remove(approvalId); }
                EmitApprovalRequestIfPossible(payload, ourSessionId, agentInfo.RunId, agentInfo.ToolCallId);
            }
            else
            {
                lock (_sync)
                {
                    _pendingSessionApprovalByApprovalId[approvalId] = new PendingSessionApproval(payload, ourSessionId);
                    if (!_approvalIdsBySessionId.TryGetValue(ourSessionId, out var set)) _approvalIdsBySessionId[ourSessionId] = set = new HashSet<string>();
                    set.Add(approvalId);
                }
                OpenclawWire.PrettyPrint("RECV session.approval(phase:pending)（agent(stream:approval) 尚未到达，缓冲等待补发）", frame);
            }
        }

        private void EmitApprovalRequestIfPossible(JSONObject payload, string ourSessionId, string runId, string toolCallId)
        {
            bool hasChannel;
            lock (_sync) { hasChannel = _eventChannels.ContainsKey(ourSessionId); }
            if (!hasChannel) return;
            var evt = EventMapping.MapOpenclawSessionApprovalToKernelEvent(payload, ourSessionId, runId, toolCallId, () => NextSeq(runId, ourSessionId));
            if (evt == null) return;

            // M3（D1 §6.2 stop-path 强制 deny）：approvalRequest 真正产出的这一刻，这个 reqId 进入
            // "pending，等待决策"态——RespondApprovalAsync() 本轮仍是 TODO 桩，唯一会消费这个态的是
            // StopAsync 的强制 deny 序列（见 _pendingApprovalsByReqId 的文档注释）。OpenclawKind 取
            // 这条 session.approval payload 自己的 approval.presentation.kind（真实值，不是 D2 收窄
            // 后的 KindElement），缺失时兜底 "exec"（openclaw 现场样本里唯一验证过的取值）。
            if (evt is ApprovalRequestEventMessageCase approvalRequestCase)
            {
                var reqId = approvalRequestCase.Value.Payload.ReqId;
                var approvalObj = OpenclawWire.JsonObj(payload.Get("approval")) ?? new JSONObject();
                var presentation = OpenclawWire.JsonObj(approvalObj.Get("presentation")) ?? new JSONObject();
                var openclawKind = OpenclawWire.JsonString(presentation.Get("kind")) ?? "exec";
                lock (_sync)
                {
                    _pendingApprovalsByReqId[reqId] = new PendingApprovalAwaitingDecision(runId, openclawKind);
                    if (!_pendingApprovalReqIdsBySessionId.TryGetValue(ourSessionId, out var set))
                        _pendingApprovalReqIdsBySessionId[ourSessionId] = set = new HashSet<string>();
                    set.Add(reqId);
                }
            }
            Yield(ourSessionId, evt);
        }

        /// <summary>M1：消费 sessions.messages.subscribe 响应里的 approvalReplay.approvals。</summary>
        private void ConsumeApprovalReplay(JSONObject result, string kernelKey)
        {
            var replay = OpenclawWire.JsonObj(result.Get("approvalReplay"));
            if (replay == null) return;
            var approvals = OpenclawWire.JsonArr(replay.Get("approvals"));
            if (approvals == null) return;
            var updatedAtMs = replay.Get("updatedAtMs");
            foreach (var item in approvals)
            {
                if (item is not JSONObject approval) continue;
                var syntheticPayload = new JSONObject
                {
                    ["sessionKey"] = kernelKey,
                    ["updatedAtMs"] = updatedAtMs,
                    ["phase"] = "pending",
                    ["approval"] = approval,
                };
                HandleSessionApprovalEvent(new JSONObject { ["type"] = "event", ["event"] = "session.approval", ["payload"] = syntheticPayload });
            }
        }

        private void HandleShutdownEvent(JSONObject frame)
        {
            OpenclawWire.PrettyPrint("RECV event shutdown（向所有活跃 session 广播 sessionEnd(reason:kernelExited)）", frame);
            List<string> sessionIds;
            lock (_sync) { sessionIds = _eventChannels.Keys.ToList(); }
            foreach (var sessionId in sessionIds)
            {
                bool already;
                lock (_sync)
                {
                    already = _sessionTerminalEmitted.Contains(sessionId);
                    if (!already) _sessionTerminalEmitted.Add(sessionId);
                }
                if (already) continue;
                Yield(sessionId, EventMapping.MakeSessionEndEventForShutdown(sessionId, () => NextSeq(null, sessionId)));
            }
        }

        // MARK: - Test-only 支持面（frame-replay 单测用；生产路径不调用）
        //
        // 镜像 Swift 侧同名 testSupport* 方法——见文件头注释，这里必须是 `public`（不是 Swift 那种
        // 同 module `private` 收紧），因为测试项目通过 ProjectReference 引用本项目，是独立的编译单元。

        /// <summary>不经过任何 RPC，直接注册一个"已订阅"的假 session——供测试灌入合成 wire 帧。</summary>
        public Channel<EventMessageUnion> TestSupportRegisterSession(string ourSessionId, string kernelKey)
        {
            lock (_sync) { _kernelKeyBySessionId[ourSessionId] = kernelKey; }
            var channel = Channel.CreateUnbounded<EventMessageUnion>();
            lock (_sync) { _eventChannels[ourSessionId] = channel; }
            return channel;
        }

        /// <summary>把一帧合成的 wire JSON 编码后送进真实的 HandleIncoming dispatch 入口。</summary>
        public void TestSupportFeedFrame(JSONObject frame)
        {
            var data = OpenclawWire.EncodeFrame(frame);
            HandleIncoming(data);
        }

        public string TestSupportLockState(string sessionId)
        {
            lock (_sync) { return Describe(_lockStateBySessionId.TryGetValue(sessionId, out var s) ? s : SessionLockState.Idle); }
        }

        public bool? TestSupportPendingStopTerminalEmitted(string sessionId)
        {
            lock (_sync) { return _pendingStops.TryGetValue(sessionId, out var p) ? p.TerminalEmitted : (bool?)null; }
        }

        public bool TestSupportHasPendingStop(string sessionId)
        {
            lock (_sync) { return _pendingStops.ContainsKey(sessionId); }
        }

        public bool TestSupportSessionTerminalEmitted(string sessionId)
        {
            lock (_sync) { return _sessionTerminalEmitted.Contains(sessionId); }
        }

        public bool TestSupportHasBufferedApproval(string approvalId)
        {
            lock (_sync) { return _agentApprovalInfoByApprovalId.ContainsKey(approvalId) || _pendingSessionApprovalByApprovalId.ContainsKey(approvalId); }
        }

        /// <summary>
        /// M3（D1 §6.2 stop-path 强制 deny 新增）：读取某个 reqId 当前是否仍处于"approval_request 已经
        /// 产出、RespondApprovalAsync() 尚未落地"的 pending 态——用于验证 stop() 的强制 deny 序列确实把
        /// 这个 reqId 从 pending 转成了终态（ForceDenyPendingApprovalsBeforeStopAsync 成功后会把它从
        /// 这张表移除）。
        /// </summary>
        public bool TestSupportHasPendingApprovalAwaitingDecision(string reqId)
        {
            lock (_sync) { return _pendingApprovalsByReqId.ContainsKey(reqId); }
        }

        public void TestSupportStubRpc(string method, Func<JSONObject, Task<JSONObject>> responder)
        {
            lock (_sync) { _testSupportRpcResponders[method] = responder; }
        }

        public void TestSupportSetStopTimeoutSeconds(int seconds)
        {
            lock (_sync) { _testStopTimeoutSecondsOverride = seconds; }
        }

        /// <summary>
        /// NOTE-A：缩短 force-deny drain 循环的迭代轮次上限（生产默认 50），供"超过上限如实 throw、
        /// 不静默死循环"这条路径的测试使用，不用真的喂 50 轮 late-arrival 才能触发。
        /// </summary>
        public void TestSupportSetForceDenyDrainMaxRounds(int rounds)
        {
            lock (_sync) { _testForceDenyDrainMaxRoundsOverride = rounds; }
        }

        /// <summary>M6：直接触发 HandleTransportClosed（真实 WS 断开时 ReceiveLoopAsync 走的同一条路径）。</summary>
        public void TestSupportSimulateTransportClosed()
        {
            HandleTransportClosed(new KernelClientException(KernelClientErrorKind.Transport, "test-simulated transport closed"));
        }
    }
}
