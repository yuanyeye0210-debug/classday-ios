import SwiftUI
import ClassdayCore

/// One model for the whole process. Tab content on iOS 18+ can be built in a
/// fresh environment that does not inherit `@Environment(AppModel.self)`, and
/// that lookup traps. A key with this default keeps every tab, sheet, and
/// theme switch on the same instance.
enum AppRuntime {
    static let model = AppModel()
}

private struct AppModelKey: EnvironmentKey {
    static let defaultValue = AppRuntime.model
}

extension EnvironmentValues {
    var appModel: AppModel {
        get { self[AppModelKey.self] }
        set { self[AppModelKey.self] = newValue }
    }
}

extension View {
    func supplyingAppModel(_ model: AppModel = AppRuntime.model) -> some View {
        environment(\.appModel, model)
    }
}
