// Type-level 保真断言（SG-3 验收缺口，rounds/0007）——针对 D2 v3 两处经 JSON Schema
// additionalProperties:false 表达的精确性，在真实生成产物（app/generated/csharp/D2.cs）上做
// 编译期负例验证，不是注释式自证：
//   ① EmptyPayload —— 精确空对象（properties:{} + additionalProperties:false）。
//   ② WireCapabilityDescriptorPayload —— quicktype 生成时被命名为 `Capabilit`（见
//      CapabilityChangedEventMessagePayload.Capabilities 字段类型；命名是 quicktype 的内部去重
//      策略产物，非本文件所控，稳定性由 `npm run gen` 的幂等 diff 守门），即
//      CapabilityDescriptorPayload 排除 ProtocolVersion 后的版本。
//
// 机制：PositiveControl() 里的构造必须编译通过（对照组，证明本文件本身没有腐化）；两个
// SG3_NEGATIVE_* 方法分别包在同名编译条件 `#if` 后面，默认（不传 DefineConstants）不参与编译，
// 由 scripts/verify-type-fidelity-csharp.mjs 用
// `dotnet build -p:DefineConstants=<FLAG> -p:BaseIntermediateOutputPath=...` 单独点燃，
// 并断言该次 build 必须以非零退出码失败——若某次因生成产物精度劣化而意外编译通过，该脚本判定
// 为 FAIL（详见该脚本注释）。C# 用对象初始化器（`new T { Prop = ... }`）而非位置参数构造，
// 所以负例是"引用不存在的属性"（CS0117），语言机制与 Swift 的"多余实参"不同，但断言的性质
// 一致：生成产物的真实构造入口拒绝携带排除字段。
//
// 已知边界（不在本文件断言范围内，如实记录于 round 0007 handoff，非本轮修复）：本文件只覆盖
// "手工构造"这一路径。真实 wire 解码（System.Text.Json 反序列化一段真实
// evt.capability_changed / EmptyPayload JSON）默认不会拒绝多余/被排除的键——.NET 7 的
// System.Text.Json 默认 UnmappedMemberHandling 是静默跳过，没有对等的严格模式开关随 D2.cs
// 生成开启。已用探针实测确认（两型皆如此），超出本文件（编译期）与本轮（SG-3 type-level
// 断言）范围，留给 SG-1 codegen 后续处理。

using D2;

namespace TypeFidelity;

public static class Checks
{
    public static void PositiveControl()
    {
        // ① EmptyPayload 确实可以零参数构造（对象初始化器不带任何属性）。
        var empty = new EmptyPayload();
        _ = empty;

        // ② Capabilit（即 WireCapabilityDescriptorPayload）可以用它真实的完整字段集构造，
        // 且——这才是关键——不需要也不能设置 ProtocolVersion，证明该字段是被生成器真正排除的，
        // 不是"可选"而已。
        var capabilities = new Capabilit
        {
            ApprovalDecisionKinds = new[] { ApprovalDecisionKindElement.AllowOnce },
            ApprovalGranularity = ApprovalGranularity.PerTool,
            ApprovalKinds = new[] { KindElement.Exec },
            BillingAttribution = Attribution.Session,
            InterruptModes = new[] { Mode.Steer },
            Kernel = Kernel.Openclaw,
            SessionResume = true,
            SnapshotAt = DateTimeOffset.UnixEpoch,
            StreamingGranularity = StreamingGranularity.TokenDelta,
            ThinkingVisibility = ThinkingVisibility.None,
            Tools = new CapabilitiesTools { Discoverable = true },
            UsageReporting = UsageReporting.None,
        };
        _ = capabilities;
    }

#if SG3_NEGATIVE_EMPTY_PAYLOAD_EXTRA_FIELD
    public static void NegativeEmptyPayloadExtraField()
    {
        // 必须编译失败（CS0117）：EmptyPayload 不声明任何属性，对象初始化器里任何额外字段
        // 都不可能存在对应的可设置成员。若这行竟然编译通过了，说明 EmptyPayload 悄悄长出了
        // 字段，"精确空对象"的保证已被打破。
        var bad = new EmptyPayload { SG3ShouldNotExist = 1 };
        _ = bad;
    }
#endif

#if SG3_NEGATIVE_WIRE_CAPABILITY_PROTOCOL_VERSION
    public static void NegativeWireCapabilityProtocolVersion()
    {
        // 必须编译失败（CS0117）：ProtocolVersion 必须继续被排除在 Capabilit
        // （WireCapabilityDescriptorPayload）之外。若这行编译通过了，说明该排除已经失效/泄漏
        // 回来。
        var bad = new Capabilit
        {
            Kernel = Kernel.Openclaw,
            ProtocolVersion = "kernelport/1",
        };
        _ = bad;
    }
#endif
}
