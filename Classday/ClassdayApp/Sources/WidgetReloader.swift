import WidgetKit
import ClassdayCore

enum WidgetReloader {
    /// Call only after a local edit. WidgetKit's daily reload budget is limited;
    /// the timeline itself advances at class boundaries.
    static func reload() {
        WidgetCenter.shared.reloadTimelines(ofKind: WidgetID.nextClass)
        WidgetCenter.shared.reloadTimelines(ofKind: WidgetID.todayCourses)
    }
}
