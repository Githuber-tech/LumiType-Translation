// swift-tools-version:5.9
import PackageDescription

// 说明：本机只安装了 Command Line Tools（没有完整 Xcode），
// 因此不声明 XCTest 测试目标 —— 缺 XCTest 会让 `swift test` 在链接阶段失败。
// 等价断言全部放在 verify 可执行目标里，`swift run verify` 即可跑；
// 安装 Xcode 后可把 Tests/ 下的 XCTest 套件重新加入 testTarget。

let package = Package(
    name: "LumiType",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "LumiTypeCore", targets: ["LumiTypeCore"]),
        .executable(name: "lumitype", targets: ["LumiTypeCLI"]),
        .executable(name: "LumiTypeMac", targets: ["LumiTypeApp"]),
        .executable(name: "verify", targets: ["verify"]),
        .executable(name: "lumitype-probe", targets: ["probe"])
    ],
    targets: [
        .target(name: "LumiTypeCore", path: "Sources/LumiTypeCore"),
        .executableTarget(
            name: "LumiTypeCLI",
            dependencies: ["LumiTypeCore"],
            path: "Sources/lumitype"
        ),
        .executableTarget(
            name: "LumiTypeApp",
            dependencies: ["LumiTypeCore"],
            path: "Sources/LumiTypeApp"
        ),
        .executableTarget(
            name: "verify",
            dependencies: ["LumiTypeCore"],
            path: "Sources/verify"
        ),
        .executableTarget(
            name: "probe",
            dependencies: ["LumiTypeCore"],
            path: "Sources/probe"
        )
    ]
)
