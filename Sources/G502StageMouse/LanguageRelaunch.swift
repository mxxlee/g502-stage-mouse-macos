import Foundation

enum LanguageRelaunch {
    static func run(
        process: Process,
        terminate: () -> Void,
        onFailure: () -> Void
    ) {
        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else {
                onFailure()
                return
            }
            terminate()
        } catch {
            onFailure()
        }
    }
}
