import Darwin
import Foundation

/// Einfache Dateisperre (entspricht grob `FSUtils.GetMutex` für JAR-Downloads).
final class FileLock {
    private let handle: FileHandle

    init(lockFile: URL) throws {
        try FileManager.default.createDirectory(
            at: lockFile.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        if !FileManager.default.fileExists(atPath: lockFile.path) {
            FileManager.default.createFile(atPath: lockFile.path, contents: nil)
        }
        handle = try FileHandle(forWritingTo: lockFile)
        try lockExclusive()
    }

    private func lockExclusive() throws {
        let fd = handle.fileDescriptor
        while flock(fd, LOCK_EX) != 0 {
            if errno != EINTR {
                throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
            }
        }
    }

    deinit {
        _ = flock(handle.fileDescriptor, LOCK_UN)
        try? handle.close()
    }
}
