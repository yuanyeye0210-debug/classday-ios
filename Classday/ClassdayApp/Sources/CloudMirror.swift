import CloudKit
import Foundation
import ClassdayCore

enum CloudMirror {
    private static let statusLock = NSLock()
    private static var _status = "iCloud 还没打开。免费 Apple ID 签名通常没有 CloudKit 权限，课表会继续只存在这台手机。"
    static var status: String {
        get { statusLock.withLock { _status } }
        set { statusLock.withLock { _status = newValue } }
    }

    static func push(_ document: StoreDocument) async {
        let container = CKContainer.default()
        do {
            let account = try await container.accountStatus()
            guard account == .available else {
                status = "这台手机的 iCloud 没有登录，或当前签名没有 CloudKit。课表仍保存在本机。"
                return
            }
            let data = try StoreCodec.encode(document)
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("classday-cloud.json")
            try data.write(to: url)
            let database = container.privateCloudDatabase
            let recordID = CKRecord.ID(recordName: "active")
            // Fetch-then-modify: saving a fresh CKRecord under an existing
            // recordID always fails with serverRecordChanged.
            let record = (try? await database.record(for: recordID))
                ?? CKRecord(recordType: "Timetable", recordID: recordID)
            record["payload"] = CKAsset(fileURL: url)
            do {
                _ = try await database.save(record)
            } catch let error as CKError where error.code == .serverRecordChanged {
                let fresh = try await database.record(for: recordID)
                fresh["payload"] = CKAsset(fileURL: url)
                _ = try await database.save(fresh)
            }
            status = "已复制到 iCloud 私有库。换手机登录同一个 iCloud 可以拉回来。"
        } catch {
            status = "iCloud 不可用（\(error.localizedDescription)）。免费签名一般如此，本机课表没有受影响。"
        }
    }
}
