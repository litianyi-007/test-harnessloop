// SG-5 Stage C：C# 侧 KernelClient 传输层错误类型——镜像 ../swift/KernelClient.swift 的
// `KernelClientError` enum（4 个语义分支 + notConnected）。
//
// C# 没有 Swift 的枚举关联值，这里用一个包含 Kind 判别字段 + 可选 Code（仅 RpcRejected 分支有意义，
// 对应 Swift `.rpcRejected(code:message:)` 的 code 关联值，如 "session_locked"）的密封异常类表达同样的
// 判别语义。调用方（含 FrameReplayTests）用 `ex.Kind`/`ex.Code` 模式匹配，对应 Swift
// `catch KernelClientError.rpcRejected(let code, _) where code == "session_locked"` 这种写法。

#nullable enable
using System;

namespace KernelClient
{
    public enum KernelClientErrorKind
    {
        NotImplemented,
        Transport,
        ProtocolMismatch,
        RpcRejected,
        NotConnected,
    }

    public sealed class KernelClientException : Exception
    {
        public KernelClientErrorKind Kind { get; }

        /// <summary>仅 <see cref="KernelClientErrorKind.RpcRejected"/> 分支有意义。</summary>
        public string? Code { get; }

        public KernelClientException(KernelClientErrorKind kind, string message, string? code = null)
            : base(Describe(kind, message, code))
        {
            Kind = kind;
            Code = code;
        }

        private static string Describe(KernelClientErrorKind kind, string message, string? code) => kind switch
        {
            KernelClientErrorKind.NotImplemented => $"not implemented: {message}",
            KernelClientErrorKind.Transport => $"transport error: {message}",
            KernelClientErrorKind.ProtocolMismatch => $"protocol mismatch: {message}",
            KernelClientErrorKind.RpcRejected => $"rpc rejected [{code}]: {message}",
            KernelClientErrorKind.NotConnected => "kernel client not connected",
            _ => message,
        };
    }
}
