import Foundation
import WidgetKit
import ClassdayCore

enum WidgetReloader {
    /// Call only after a local edit. WidgetKit's daily reload budget is limited;
    /// the timeline itself advances at class boundaries.
    static func reload(document: StoreDocument) {
        // Publish before asking WidgetKit to build entries. The app store remains authoritative.
        // Mirror into every group this process can open so a free-account
        // resign that rewrote only one side's group still reaches the widget.
        if let data = try? StoreCodec.encode(document) {
            AppGroupContainer.publishSnapshot(data)
        }
        WidgetCenter.shared.reloadAllTimelines()
    }
}
