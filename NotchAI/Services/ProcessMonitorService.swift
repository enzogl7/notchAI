import Foundation

final class ProcessMonitorService {

    func isProcessRunning(named processName: String) -> Bool {

        let task = Process()

        task.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        task.arguments = ["-x", processName]

        let pipe = Pipe()
        task.standardOutput = pipe

        do {
            try task.run()
            task.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()

            return !data.isEmpty

        } catch {
            return false
        }
    }
}
