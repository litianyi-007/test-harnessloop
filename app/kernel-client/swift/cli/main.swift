// SG-4 Mac 最小壳入口。用 Task + DispatchSemaphore 桥接 async 世界（避免对 `@main`/
// `-parse-as-library` 编译选项的额外依赖）。
//
// SG-10 起这个文件是 SwiftPM `kernel-client-cli` executable target（app/Package.swift）唯一的
// 源文件，不再和 KernelClient/CLIRunner 等库文件同目录裸 swiftc 编译——`runL1CloseLoop()` 现在要
// 从 KernelClient library target 跨模块导入。

import Foundation
import KernelClient

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
