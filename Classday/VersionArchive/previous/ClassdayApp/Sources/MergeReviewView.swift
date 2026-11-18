import SwiftUI
import ClassdayCore

/// Confirm page for merging same-name courses (Task 4, design §5).
///
/// One card per duplicate group: each member's teacher, location,
/// periods, weeks, and grade status; a per-member exclude control;
/// a teacher-mismatch warning (never blocks); a two-choice grade
/// picker for grade conflicts (the group's merge button stays disabled
/// until a grade is chosen).
///
/// This page never merges, backs up, or persists anything itself.
/// It reports the user's decisions — which groups, which exclusions,
/// which grade choices — through `onMerge`, and the caller forwards
/// them to `AppModel.applyCourseMerge` (Task 5). Dictionary keys are
/// the group's `normalizedName` (unique per group by construction).
struct MergeReviewView: View {
    var groups: [DuplicateGroup]
    var context: ScheduleContext = .empty
    var onMerge: ([DuplicateGroup], [String: Set<UUID>], [String: UUID?]) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme

    /// Course ids the user excluded from their group, keyed by the
    /// group's `normalizedName`. Excluded members stay independent.
    @State private var excluded: [String: Set<UUID>] = [:]
    /// Grade the user chose to keep for a conflicted group, keyed by
    /// the group's `normalizedName`. Nil until the user picks one.
    @State private var gradeSelection: [String: Double] = [:]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("同名课程会被合成一条：上课时间取并集，成绩只留一处。合并前会自动把当前课表存入课表库备份。")
                        .font(.system(size: 14, design: .rounded))
                        .foregroundStyle(Theme.secondary)
                        .padding(.horizontal, 20)
                        .padding(.top, 12)

                    Button {
                        mergeAll()
                    } label: {
                        Text("全部合并（\(mergeableGroups.count) 组）")
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .foregroundStyle(Theme.background)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 13)
                            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.ink))
                            .opacity(mergeableGroups.isEmpty ? 0.4 : 1)
                    }
                    .buttonStyle(.plain)
                    .disabled(mergeableGroups.isEmpty)
                    .padding(.horizontal, 20)

                    ForEach(groups, id: \.normalizedName) { group in
                        groupCard(group)
                            .padding(.horizontal, 20)
                    }

                    Color.clear
                        .frame(height: 12)
                }
            }
            .scrollIndicators(.hidden)
            .navigationTitle("合并同名课程")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("关闭") { dismiss() }
                }
            }
            .onChange(of: groups) { _, newGroups in
                if newGroups.isEmpty { dismiss() }
            }
        }
    }

    // MARK: - Group card

    private func groupCard(_ group: DuplicateGroup) -> some View {
        let name = group.courses.first?.name ?? group.normalizedName
        let members = includedMembers(of: group)
        let canMergeGroup = canMerge(group)
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(name)
                    .font(.system(size: 18, weight: .heavy, design: .rounded))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                Text("\(group.courses.count) 条")
                    .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.secondary)
                Spacer(minLength: 0)
            }

            if hasTeacherMismatch(group) {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 13))
                    Text("老师不一致，请确认是同一门课")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                }
                .foregroundStyle(Theme.courseInk("orange", scheme: scheme))
                .padding(.horizontal, 11)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Capsule(style: .continuous).fill(Theme.courseBackground("orange", scheme: scheme)))
                .accessibilityLabel("提醒：老师不一致，请确认是同一门课")
            }

            ForEach(group.courses, id: \.id) { course in
                memberRow(course, in: group)
            }

            if hasGradeConflict(group) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("成绩不一致，请选择保留哪一个")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.ink)
                    Picker("选择保留的成绩", selection: gradeBinding(for: group)) {
                        ForEach(distinctGrades(of: group), id: \.self) { grade in
                            Text("\(CourseDetailView.numberText(grade)) 分")
                                .tag(grade as Double?)
                        }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityLabel("选择保留的成绩")
                }
            }

            Button {
                merge(group: group)
            } label: {
                Text("合并这组")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.background)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.ink))
                    .opacity(canMergeGroup ? 1 : 0.4)
            }
            .buttonStyle(.plain)
            .disabled(!canMergeGroup)

            if members.count < 2 {
                Text("至少保留两条才能合并")
                    .font(.system(size: 12, design: .rounded))
                    .foregroundStyle(Theme.secondary)
            } else if !canMergeCourseSchedules(members, context: context) {
                Text("周次、教室或同一时段的单双周规则不同，保持独立可避免课表信息丢失。")
                    .font(.system(size: 12, design: .rounded))
                    .foregroundStyle(.orange)
            } else if hasGradeConflict(group) && gradeSourceID(for: group) == nil {
                Text("请先选择保留的成绩")
                    .font(.system(size: 12, design: .rounded))
                    .foregroundStyle(Theme.secondary)
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Theme.elevated))
    }

    // MARK: - Member row

    private func memberRow(_ course: Course, in group: DuplicateGroup) -> some View {
        let isExcluded = excluded[group.normalizedName]?.contains(course.id) ?? false
        return HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(course.teacher.isEmpty ? (course.location.isEmpty ? "未填老师和地点" : course.location) : (course.location.isEmpty ? course.teacher : "\(course.teacher) · \(course.location)"))
                    .font(.system(size: 14.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                Text(meetingsText(course))
                    .font(.system(size: 12.5, design: .rounded))
                    .foregroundStyle(Theme.secondary)
                    .lineLimit(2)
                Text("\(ScheduleCopy.weekList(course.weeks)) · \(gradeText(course))")
                    .font(.system(size: 12.5, design: .rounded))
                    .foregroundStyle(Theme.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            Button {
                toggleExcluded(course, in: group)
            } label: {
                Text(isExcluded ? "已排除" : "排除")
                    .font(.system(size: 12.5, weight: .bold, design: .rounded))
                    .foregroundStyle(isExcluded ? Theme.secondary : Theme.courseInk("orange", scheme: scheme))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Capsule(style: .continuous).fill(isExcluded ? Theme.segment : Theme.courseBackground("orange", scheme: scheme)))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isExcluded ? "取消排除 \(course.name)" : "把这条排除出合并组")
        }
        .opacity(isExcluded ? 0.55 : 1)
    }

    private func meetingsText(_ course: Course) -> String {
        guard !course.meetings.isEmpty else { return "未排课" }
        return course.meetings
            .map { "\(ScheduleCopy.weekdayName($0.weekday)) \(ScheduleCopy.periodSpan($0.startPeriod, $0.endPeriod))" }
            .joined(separator: "、")
    }

    private func gradeText(_ course: Course) -> String {
        if let scheme = course.gradeScheme, let final = scheme.finalGrade {
            return "\(CourseDetailView.numberText(final)) / \(CourseDetailView.numberText(scheme.scale)) 分（记分规则）"
        }
        if course.gradeScheme != nil {
            return "记分规则 · 未出总分"
        }
        if let grade = course.grade {
            return "\(CourseDetailView.numberText(grade)) 分"
        }
        return "未录入成绩"
    }

    // MARK: - Per-group state

    /// Members the user has not excluded; only these are merged.
    private func includedMembers(of group: DuplicateGroup) -> [Course] {
        let excludedIDs = excluded[group.normalizedName] ?? []
        return group.courses.filter { !excludedIDs.contains($0.id) }
    }

    /// Distinct non-empty teachers among the included members.
    private func hasTeacherMismatch(_ group: DuplicateGroup) -> Bool {
        let teachers = Set(includedMembers(of: group).map(\.teacher).filter { !$0.isEmpty })
        return teachers.count > 1
    }

    /// Distinct grades among the included graded members, ascending.
    private func distinctGrades(of group: DuplicateGroup) -> [Double] {
        Array(Set(includedMembers(of: group).compactMap(\.grade))).sorted()
    }

    /// A conflict is two or more distinct grades among included members
    /// (same rule as `mergeDuplicateGroup` in Core).
    private func hasGradeConflict(_ group: DuplicateGroup) -> Bool {
        distinctGrades(of: group).count > 1
    }

    /// The graded member whose grade the user chose to keep, if the
    /// choice is still valid among the included members.
    private func gradeSourceID(for group: DuplicateGroup) -> UUID? {
        guard let selected = gradeSelection[group.normalizedName] else { return nil }
        return includedMembers(of: group).first { $0.grade == selected }?.id
    }

    private func canMerge(_ group: DuplicateGroup) -> Bool {
        guard includedMembers(of: group).count >= 2 else { return false }
        guard canMergeCourseSchedules(includedMembers(of: group), context: context) else { return false }
        if hasGradeConflict(group) {
            return gradeSourceID(for: group) != nil
        }
        return true
    }

    private var mergeableGroups: [DuplicateGroup] {
        groups.filter { canMerge($0) }
    }

    private func gradeBinding(for group: DuplicateGroup) -> Binding<Double?> {
        Binding(
            get: { gradeSelection[group.normalizedName] },
            set: { gradeSelection[group.normalizedName] = $0 }
        )
    }

    private func toggleExcluded(_ course: Course, in group: DuplicateGroup) {
        var set = excluded[group.normalizedName] ?? []
        if set.contains(course.id) {
            set.remove(course.id)
        } else {
            set.insert(course.id)
        }
        excluded[group.normalizedName] = set
    }

    // MARK: - Reporting decisions (no merge, backup, or persist here)

    /// Decisions for one group: its exclusions (if any) and its grade
    /// choice (only when it has a resolved conflict).
    private func decisions(for group: DuplicateGroup) -> (exclusions: [String: Set<UUID>], gradeChoices: [String: UUID?]) {
        var exclusions: [String: Set<UUID>] = [:]
        if let set = excluded[group.normalizedName], !set.isEmpty {
            exclusions[group.normalizedName] = set
        }
        var gradeChoices: [String: UUID?] = [:]
        if let sourceID = gradeSourceID(for: group) {
            gradeChoices[group.normalizedName] = sourceID
        }
        return (exclusions: exclusions, gradeChoices: gradeChoices)
    }

    private func merge(group: DuplicateGroup) {
        guard canMerge(group) else { return }
        let decisions = decisions(for: group)
        onMerge([group], decisions.exclusions, decisions.gradeChoices)
    }

    /// Merges every group that can merge right now; groups with an
    /// unresolved grade conflict (or fewer than two included members)
    /// stay on the page for the user to decide.
    private func mergeAll() {
        let targets = mergeableGroups
        guard !targets.isEmpty else { return }
        var exclusions: [String: Set<UUID>] = [:]
        var gradeChoices: [String: UUID?] = [:]
        for group in targets {
            let decisions = decisions(for: group)
            exclusions.merge(decisions.exclusions) { _, new in new }
            gradeChoices.merge(decisions.gradeChoices) { _, new in new }
        }
        onMerge(targets, exclusions, gradeChoices)
    }
}
