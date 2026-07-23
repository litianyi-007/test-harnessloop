// SG-4：D1 KernelPort 窄腰面的 C# 接口骨架。
//
// 这是"双端骨架"的 C# 侧——本轮只到接口层，没有具体 WS 实现（完整 WS 实现是 Swift 侧
// OpenclawGatewayKernelClient.swift 的角色，已对着运行中的 openclaw 内核 live 验证过
// createSession/subscribe/stop 三个方法，见 ../swift/ 与 ../RUN-EVIDENCE.md）。
//
// 方法签名对应 D1 v3.5 §2（权威源
// ~/.llm-wiki/agent-app-design/kernel/d1-kernelport-spec-v3-5.md），与 Swift 侧
// ../swift/KernelClient.swift 逐方法对称：
//
//   CreateSessionAsync -> §2.1（Swift 侧本轮完整实现）
//   SendAsync          -> §2.2（TODO 桩，defer 到 SG-8.1/L2——无 mock provider，真实调用会触发
//                          真实模型请求，见 scratchpad/sg4-openclaw-run-recipe.md §4）
//   Subscribe          -> §2.3（Swift 侧本轮完整实现）
//   InterruptAsync     -> §2.4（TODO 桩，同 send 一并 defer）
//   StopAsync          -> §2.5（Swift 侧本轮完整实现：适配为 openclaw sessions.abort+sessions.delete）
//   RespondApprovalAsync -> §2.6（TODO 桩，本轮闭环未触发任何审批请求）
//   CapabilitiesAsync  -> §2.7（TODO 桩，本轮未探测 openclaw capabilities 端点）
//
// 直接引用 app/generated/csharp/D2.cs（quicktype 生成）+ DiscriminatedUnions.cs（手写判别联合）
// 里的类型作为入参/出参，不重新发明一套 DTO——跟 Swift 侧直接用 D2.swift 类型的做法对称。

using System;
using System.Collections.Generic;
using System.Threading;
using System.Threading.Tasks;
using D2;

namespace KernelClient
{
    /// <summary>
    /// D1 §2 KernelPort 窄腰面协议的 C# 接口表达。实现者负责把这 7 个方法适配到具体内核
    /// （openclaw / hermes）各自的 wire 协议上。
    ///
    /// 本轮 C# 侧只到接口骨架层（方法签名 + doc），无具体实现——SG-4 要的"双端骨架"里，C# 侧
    /// 到此为止；具体 WS 实现留给后续轮次（或直接复用本轮 Swift 侧已经 live 验证过的协议理解）。
    /// </summary>
    public interface IKernelClient
    {
        /// <summary>
        /// D1 §2.1 createSession——铸造一个新会话（或按 <paramref name="config"/>.Resume 恢复一个
        /// 已存在会话）。返回值 <see cref="SessionHandle"/> 是后续 5 个方法寻址该会话的唯一凭证。
        /// </summary>
        Task<SessionHandle> CreateSessionAsync(Config config, CancellationToken cancellationToken = default);

        /// <summary>
        /// D1 §2.2 send —— TODO 桩，defer 到 SG-8.1/L2。
        /// 本项目隔离 openclaw 内核没有 mock provider，真正调用会触发真实模型请求
        /// （<c>sessions.create</c> 响应里的 <c>resolved.model</c> 字段已经证实这一点，见 recipe §4）。
        /// </summary>
        Task<SendResultPayload> SendAsync(SessionHandle session, Input input, CancellationToken cancellationToken = default);

        /// <summary>
        /// D1 §2.3 subscribe —— 订阅某个 session 的 KernelEvent 流（D2 <see cref="EventMessageUnion"/>
        /// 十一变体判别联合）。C# 用 <see cref="IAsyncEnumerable{T}"/> 表达"异步事件流"，语义对应
        /// D1 TS 签名的 <c>AsyncStream&lt;KernelEvent&gt;</c>。
        /// </summary>
        IAsyncEnumerable<EventMessageUnion> Subscribe(SessionHandle session, CancellationToken cancellationToken = default);

        /// <summary>
        /// D1 §2.4 interrupt —— TODO 桩，同 send 一并 defer（L1 闭环没有 active run 可供中断）。
        /// </summary>
        Task<InterruptResultPayload> InterruptAsync(SessionHandle session, InterruptRequestMessagePayload options, CancellationToken cancellationToken = default);

        /// <summary>
        /// D1 §2.5 stop —— 中止当前 run 并释放会话。Swift 侧参考实现把它适配为 openclaw
        /// <c>sessions.abort</c> + <c>sessions.delete</c> 两步组合（见
        /// ../swift/OpenclawGatewayKernelClient.swift 的 <c>stop(session:)</c>）。
        /// </summary>
        Task<StopResultPayload> StopAsync(SessionHandle session, CancellationToken cancellationToken = default);

        /// <summary>
        /// D1 §2.6 respondApproval —— TODO 桩，本轮闭环未触发任何审批请求。
        /// </summary>
        Task RespondApprovalAsync(SessionHandle session, string reqId, Decision decision, CancellationToken cancellationToken = default);

        /// <summary>
        /// D1 §2.7 capabilities —— TODO 桩，本轮未探测 openclaw capabilities 端点。
        /// <paramref name="session"/> 为 null 时查询连接级能力（对应 D1 TS 签名的可选参数）。
        /// </summary>
        Task<CapabilityDescriptorPayload> CapabilitiesAsync(SessionHandle? session = null, CancellationToken cancellationToken = default);
    }
}
