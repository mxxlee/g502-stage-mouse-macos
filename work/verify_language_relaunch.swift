import Foundation

@main
enum VerifyLanguageRelaunch {
    private static func fail(_ message: String) -> Never {
        FileHandle.standardError.write(Data("\(message)\n".utf8))
        exit(1)
    }

    static func main() {
        let failedProcess = Process()
        failedProcess.executableURL = URL(fileURLWithPath: "/usr/bin/false")
        var terminateCount = 0
        var failureCount = 0
        LanguageRelaunch.run(
            process: failedProcess,
            terminate: { terminateCount += 1 },
            onFailure: { failureCount += 1 }
        )
        guard terminateCount == 0 else { fail("Nonzero exit terminated the current app") }
        guard failureCount == 1 else { fail("Nonzero exit skipped failure handling") }

        let successfulProcess = Process()
        successfulProcess.executableURL = URL(fileURLWithPath: "/usr/bin/true")
        LanguageRelaunch.run(
            process: successfulProcess,
            terminate: { terminateCount += 1 },
            onFailure: { failureCount += 1 }
        )
        guard terminateCount == 1 else { fail("Successful exit did not terminate the current app") }
        guard failureCount == 1 else { fail("Successful exit entered failure handling") }
        print("language relaunch: nonzero exit routes to failure; zero exit routes to termination")
    }
}
