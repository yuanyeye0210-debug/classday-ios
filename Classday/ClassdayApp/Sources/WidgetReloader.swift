import WidgetKit
import ClassdayCore

enum WidgetReloader {
    /// Call only after a local edit. WidgetKit's daily reload budget is limited;
    /// the timeline itself advances at class boundaries.
    static func reload() {
        for kind in WidgetID.timelineKinds {
            WidgetCenter.shared.reloadTimelines(ofKind: kind)
        }
    }
}
