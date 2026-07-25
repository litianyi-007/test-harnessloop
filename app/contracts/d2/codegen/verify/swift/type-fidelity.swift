// Type-level 保真断言（SG-3 验收缺口，rounds/0007）——针对 D2 v3 两处经 JSON Schema
// additionalProperties:false 表达的精确性，在真实生成产物（app/generated/swift/D2.swift）上做
// 编译期负例验证，不是注释式自证：
//   ① EmptyPayload —— 精确空对象（properties:{} + additionalProperties:false）。
//   ② WireCapabilityDescriptorPayload —— quicktype 生成时被命名为 `Capabilit`（见
//      CapabilityChangedEventMessagePayload.capabilities 字段类型；命名是 quicktype 的内部去重
//      策略产物，非本文件所控，稳定性由 `npm run gen` 的幂等 diff 守门），即
//      CapabilityDescriptorPayload 排除 protocolVersion 后的版本。
//
// 机制：sg3PositiveControl() 里的构造必须编译通过（作为对照组，证明本文件本身没有腐化）；
// 两个 SG3_NEGATIVE_* 函数分别包在同名编译条件 `#if` 后面，默认（无 -D 标志）不参与编译，
// 由 scripts/verify-type-fidelity-swift.mjs 用 `swiftc -typecheck -D <FLAG>` 单独点燃，
// 并断言该次编译必须以非零退出码失败——若某次因生成产物精度劣化而意外编译通过，
// 该脚本判定为 FAIL（详见该脚本注释）。
//
// 已知边界（不在本文件断言范围内，如实记录于 round 0007 handoff，非本轮修复）：
// 本文件只覆盖“手工构造”这一路径。真实 wire 解码（JSONDecoder 解一段真实
// evt.capability_changed / EmptyPayload JSON）并不会拒绝多余/被排除的键——Foundation 合成的
// Codable 默认静默丢弃未知键，没有“严格模式”开关可选。已用探针实测确认（两型两语言皆如此），
// 超出本文件（编译期）与本轮（SG-3 type-level 断言）范围，留给 SG-1 codegen 后续处理。

import Foundation

func sg3PositiveControl() {
    // ① EmptyPayload 确实可以零参数构造。
    _ = EmptyPayload()

    // ② Capabilit（即 WireCapabilityDescriptorPayload）可以用它真实的完整字段集构造，
    // 且——这才是关键——不需要也不能传 protocolVersion，证明该字段是被生成器真正排除的，
    // 不是"可选"而已。
    _ = Capabilit(
        approvalDecisionKinds: [.allowOnce],
        approvalGranularity: .perTool,
        approvalKinds: [.exec],
        billingAttribution: .session,
        interruptModes: [.steer],
        kernel: .openclaw,
        kernelVersion: nil,
        sandboxLevels: nil,
        sessionResume: true,
        snapshotAt: Date(timeIntervalSince1970: 0),
        streamingGranularity: .tokenDelta,
        thinkingVisibility: .none,
        tools: CapabilitiesTools(discoverable: true, names: nil),
        usageReporting: .none
    )
}

#if SG3_NEGATIVE_EMPTY_PAYLOAD_EXTRA_FIELD
func sg3NegativeEmptyPayloadExtraField() {
    // 必须编译失败：EmptyPayload 的合成初始化器不接受任何参数，任何额外字段都不可能从构造入口
    // 混入。若这行竟然编译通过了，说明 EmptyPayload 悄悄长出了字段/初始化器，"精确空对象"
    // 的保证已被打破。
    _ = EmptyPayload(sg3ShouldNotExist: 1)
}
#endif

#if SG3_NEGATIVE_WIRE_CAPABILITY_PROTOCOL_VERSION
func sg3NegativeWireCapabilityProtocolVersion() {
    // 必须编译失败：protocolVersion 必须继续被排除在 Capabilit
    // （WireCapabilityDescriptorPayload）之外。若这行编译通过了，说明该排除已经失效/泄漏回来。
    _ = Capabilit(
        approvalDecisionKinds: [.allowOnce],
        approvalGranularity: .perTool,
        approvalKinds: [.exec],
        billingAttribution: .session,
        interruptModes: [.steer],
        kernel: .openclaw,
        kernelVersion: nil,
        protocolVersion: "kernelport/1",
        sandboxLevels: nil,
        sessionResume: true,
        snapshotAt: Date(timeIntervalSince1970: 0),
        streamingGranularity: .tokenDelta,
        thinkingVisibility: .none,
        tools: CapabilitiesTools(discoverable: true, names: nil),
        usageReporting: .none
    )
}
#endif
