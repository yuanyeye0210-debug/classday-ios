import CloudKit
import Foundation
import ClassdayCore

enum CloudMirror {
    static var status = "iCloud 还没打开。免费 Apple ID 签名通常没有 CloudKit 权限，课表会继续只存在这台手机。"

    static func push(_ document: StoreDocument) async {
        let container = CKContainer.default()
        do {
            let account = try await container.accountStatus()
            guard account == .available else {
                status = "这台手机的 iCloud 没有登录，或当前签名没有 CloudKit。课表仍保存在本机。"
                return
            }
            let data = try StoreCodec.encode(document)
            let record = CKRecord(recordType: "Timetable", recordID: CKRecord.ID(recordName: "active"))
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("classday-cloud.json")
            try data.write(to: url)
            record["payload"] = CKAsset(fileURL: url)
            _ = try await container.privateCloudDatabase.save(record)
            status = "已复制到 iCloud 私有库。换手机登录同一个 iCloud 可以拉回来。"
        } catch {
            status = "iCloud 不可用（\(error.localizedDescription)）。免费签名一般如此，本机课表没有受影响。"
        }
    }
}
