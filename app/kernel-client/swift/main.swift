// SG-4 Mac 最小壳入口。用 Task + DispatchSemaphore 桥接 async 世界（避免对 `@main`/
// `-parse-as-library` 编译选项的额外依赖，保持跟 app/contracts/d2/codegen 的 verify/swift/main.swift
// 一样的"纯 swiftc 编译一个可执行文件"风格）。

import Foundation

let semaphore = DispatchSemaphore(value: 0)
var exitCode: Int32 = 0

Task {
    do {
        try await runL1CloseLoop()
    } catch {
        FileHandle.standardError.write("FATAL: \(error)\n".data(using: .utf8)!)
        exitCode = 1
    }
    semaphore.signal()
}

semaphore.wait()
exit(exitCode)
