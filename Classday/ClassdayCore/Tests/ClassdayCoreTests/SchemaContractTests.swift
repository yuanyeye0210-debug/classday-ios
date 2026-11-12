import Foundation
import XCTest
import ClassdayCore

final class SchemaContractTests: XCTestCase {
    func testSchemaVersionMatchesTheCodableModel() throws {
        let schema = try Self.loadSchema()
        let properties = try XCTUnwrap(schema["properties"] as? [String: Any])
        let version = try XCTUnwrap(properties["schemaVersion"] as? [String: Any])
        XCTAssertEqual((version["const"] as? NSNumber)?.intValue, StoreDocument.currentSchema)
        XCTAssertEqual(schema["additionalProperties"] as? Bool, false)
        let required = (schema["required"] as? [Any])?.compactMap { $0 as? String } ?? []
        XCTAssertTrue(required.contains("schemaVersion"))
        XCTAssertTrue(required.contains("courses"))
    }

    func testDemoExportAndCommittedFixtureValidate() throws {
        let schema = try Self.loadSchema()
        let encoded = try Self.jsonValue(try StoreCodec.encode(DemoData.makeDocument()))
        let encodedErrors = JSONSchemaValidator.errors(in: encoded, schema: schema)
        XCTAssertEqual(encodedErrors, [], encodedErrors.joined(separator: "\n"))

        let fixtureURL = TestSupport.repositoryClassdayRoot().appendingPathComponent("Docs/demo-store.json")
        let fixture = try Self.jsonValue(Data(contentsOf: fixtureURL))
        let fixtureErrors = JSONSchemaValidator.errors(in: fixture, schema: schema)
        XCTAssertEqual(fixtureErrors, [], fixtureErrors.joined(separator: "\n"))
        // Pretty-print spacing differs between Apple and Linux JSONEncoder.
        // Compare the values, including keys the encoder now always writes.
        XCTAssertTrue(jsonEqual(encoded, fixture), jsonDifference(encoded, fixture))
    }

    func testRichExportValidatesAndKeepsCurrentFields() throws {
        let schema = try Self.loadSchema()
        let document = Self.richDocument()
        Self.assertPopulated(document)
        let encoded = try StoreCodec.encode(document)
        let root = try Self.jsonObject(encoded)
        let errors = JSONSchemaValidator.errors(in: root, schema: schema)
        XCTAssertEqual(errors, [], errors.joined(separator: "\n"))

        for key in [
            "weekRules", "overrides", "exams", "homework", "personalEvents", "rooms",
            "library", "activeTimetableID", "appearance", "subscribedICSURL",
        ] {
            XCTAssertNotNil(root[key], "current export omitted \(key)")
        }
        let semester = try XCTUnwrap(root["semester"] as? [String: Any])
        XCTAssertNotNil(semester["holidays"])
        XCTAssertNotNil(semester["cancellations"])
        let courses = try XCTUnwrap(root["courses"] as? [[String: Any]])
        let graded = try XCTUnwrap(courses.first { $0["gradeScheme"] != nil })
        XCTAssertNotNil(graded["grade"])
        XCTAssertNotNil(graded["credits"])
        XCTAssertNotNil(graded["gradeScheme"])
        let appearance = try XCTUnwrap(root["appearance"] as? [String: Any])
        XCTAssertEqual(appearance["themeID"] as? String, "aurora")
        XCTAssertEqual(appearance["performance"] as? String, "high")
        let library = try XCTUnwrap(root["library"] as? [[String: Any]])
        XCTAssertNotNil(library.first?["semester"])
        XCTAssertNil(library.first?["personalEvents"])
    }

    func testSchemaRejectsUnknownAndMissingKeys() throws {
        let schema = try Self.loadSchema()
        var object = try Self.jsonObject(StoreCodec.encode(DemoData.makeDocument()))
        object["notAField"] = true
        let extra = JSONSchemaValidator.errors(in: object, schema: schema)
        XCTAssertTrue(extra.contains { $0.contains("notAField") }, extra.joined(separator: "\n"))

        var semester = try XCTUnwrap(object["semester"] as? [String: Any])
        semester["notAHoliday"] = true
        object["semester"] = semester
        object.removeValue(forKey: "notAField")
        let nested = JSONSchemaValidator.errors(in: object, schema: schema)
        XCTAssertTrue(nested.contains { $0.contains("notAHoliday") }, nested.joined(separator: "\n"))

        object = try Self.jsonObject(StoreCodec.encode(DemoData.makeDocument()))
        object.removeValue(forKey: "courses")
        let missing = JSONSchemaValidator.errors(in: object, schema: schema)
        XCTAssertTrue(missing.contains { $0.contains("courses") }, missing.joined(separator: "\n"))
    }

    private static func loadSchema() throws -> [String: Any] {
        let url = TestSupport.repositoryClassdayRoot().appendingPathComponent("Docs/classday-store.schema.json")
        return try jsonObject(Data(contentsOf: url))
    }

    private static func jsonObject(_ data: Data) throws -> [String: Any] {
        let value = try jsonValue(data)
        return try XCTUnwrap(value as? [String: Any])
    }

    private static func jsonValue(_ data: Data) throws -> Any {
        try JSONSerialization.jsonObject(with: data)
    }

    /// Every collection and optional on these values is set, so a new stored
    /// field left at its default fails this test instead of slipping past the schema.
    private static func assertPopulated(_ document: StoreDocument) {
        assertNoHoles(document, path: "document")
        assertNoHoles(document.semester, path: "semester")
        assertNoHoles(document.courses[0], path: "courses[0]")
        assertNoHoles(document.courses[0].gradeScheme!, path: "gradeScheme")
        assertNoHoles(document.overrides[0], path: "overrides[0]")
        assertNoHoles(document.semester.cancellations[0], path: "cancellations[0]")
        assertNoHoles(document.rooms[0], path: "rooms[0]")
        assertNoHoles(document.library[0], path: "library[0]")
        assertNoHoles(document.appearance, path: "appearance")
    }

    private static func assertNoHoles(_ value: Any, path: String, file: StaticString = #filePath, line: UInt = #line) {
        let mirror = Mirror(reflecting: value)
        guard mirror.displayStyle == .struct else {
            XCTFail("\(path) is not a struct", file: file, line: line)
            return
        }
        for child in mirror.children {
            let label = child.label ?? "?"
            let childPath = "\(path).\(label)"
            let nested = Mirror(reflecting: child.value)
            if nested.displayStyle == .optional && nested.children.isEmpty {
                XCTFail("\(childPath) is nil", file: file, line: line)
            }
            if (nested.displayStyle == .collection || nested.displayStyle == .dictionary || nested.displayStyle == .set),
               nested.children.isEmpty {
                XCTFail("\(childPath) is empty", file: file, line: line)
            }
        }
    }

    private static func richDocument() -> StoreDocument {
        var document = DemoData.makeDocument()
        document.origin = .user
        document.semester.holidays = [
            HolidayPeriod(
                id: UUID(uuidString: "50000000-0000-0000-0000-000000000001")!,
                name: "国庆",
                startDate: "2026-10-01",
                endDate: "2026-10-07"
            ),
        ]
        document.semester.cancellations = [
            ClassCancellation(
                id: UUID(uuidString: "50000000-0000-0000-0000-000000000002")!,
                date: "2026-11-12",
                courseID: DemoData.ID.calculus,
                courseName: "高等数学",
                scope: "am",
                reason: "老师出差"
            ),
        ]
        document.courses[0].grade = 18.5
        document.courses[0].gradeScheme = GradeScheme(
            scale: 20,
            components: [
                GradeComponent(id: "p", name: "P"),
                GradeComponent(id: "ex", name: "EX"),
            ],
            scores: ["p": 16, "ex": 18.5],
            branches: [[
                GradeTerm(componentID: "p", weight: 0.25),
                GradeTerm(componentID: "ex", weight: 0.75),
            ]]
        )
        document.weekRules = [
            MeetingWeekRule(meetingID: DemoData.ID.calculusMonday, parity: .odd),
        ]
        document.overrides = [
            OccurrenceOverride(
                id: UUID(uuidString: "70000000-0000-0000-0000-000000000001")!,
                courseID: DemoData.ID.calculus,
                meetingID: DemoData.ID.calculusMonday,
                week: 10,
                kind: .moved,
                weekday: 2,
                startPeriod: 5,
                endPeriod: 6,
                delayMinutes: 10
            ),
        ]
        document.rooms = [
            RoomPin(
                id: UUID(uuidString: "80000000-0000-0000-0000-000000000001")!,
                name: "教学楼 A",
                latitude: 38.737,
                longitude: -9.303,
                query: "教学楼 A"
            ),
        ]
        document.subscribedICSURL = "https://example.com/calendar.ics"
        document.appearance = AppearanceChoice(themeID: "aurora", performance: .high)
        document.activeTimetableID = UUID(uuidString: "00000000-0000-0000-0000-0000000000bb")!
        document.library = [
            TimetableLibrary.snapshot(
                of: document,
                id: UUID(uuidString: "90000000-0000-0000-0000-000000000001")!,
                name: "秋季备份"
            ),
        ]
        return document
    }
}

/// The subset of JSON Schema that `classday-store.schema.json` uses.
private enum JSONSchemaValidator {
    static func errors(in instance: Any, schema root: [String: Any]) -> [String] {
        var checker = Checker(root: root)
        checker.validate(instance, schema: root, path: "$")
        return checker.errors
    }

    private struct Checker {
        let root: [String: Any]
        var errors: [String] = []

        mutating func validate(_ instance: Any, schema raw: [String: Any], path: String) {
            let schema = resolve(raw, path: path)
            if let options = schema["anyOf"] as? [Any] {
                var matched = false
                var attempts: [String] = []
                for option in options {
                    guard let optionSchema = option as? [String: Any] else { continue }
                    var copy = self
                    copy.errors = []
                    copy.validate(instance, schema: optionSchema, path: path)
                    if copy.errors.isEmpty {
                        matched = true
                        break
                    }
                    attempts.append(contentsOf: copy.errors)
                }
                if !matched {
                    errors.append("\(path): matched no anyOf (\(attempts.joined(separator: "; ")))")
                }
                return
            }

            if let types = typeNames(schema["type"]) {
                guard matches(instance, types: types) else {
                    errors.append("\(path): expected \(types.joined(separator: "|"))")
                    return
                }
            }
            if let constant = schema["const"], !same(instance, constant) {
                errors.append("\(path): const mismatch")
            }
            if let choices = schema["enum"] as? [Any], !choices.contains(where: { same(instance, $0) }) {
                errors.append("\(path): not in enum")
            }

            switch kind(of: instance) {
            case .object:
                validateObject(instance, schema: schema, path: path)
            case .array:
                validateArray(instance, schema: schema, path: path)
            case .string:
                if let text = instance as? String {
                    if let minimum = (schema["minLength"] as? NSNumber)?.intValue, text.count < minimum {
                        errors.append("\(path): shorter than \(minimum)")
                    }
                    if let pattern = schema["pattern"] as? String, !wholeMatch(pattern, text) {
                        errors.append("\(path): failed pattern \(pattern)")
                    }
                }
            case .number:
                if let number = instance as? NSNumber {
                    if let minimum = schema["minimum"] as? NSNumber, number.doubleValue < minimum.doubleValue {
                        errors.append("\(path): below minimum")
                    }
                    if let maximum = schema["maximum"] as? NSNumber, number.doubleValue > maximum.doubleValue {
                        errors.append("\(path): above maximum")
                    }
                }
            case .bool, .null, .other:
                break
            }
        }

        mutating func validateObject(_ instance: Any, schema: [String: Any], path: String) {
            guard let object = instance as? [String: Any] else { return }
            let properties = schema["properties"] as? [String: Any] ?? [:]
            let required = (schema["required"] as? [Any])?.compactMap { $0 as? String } ?? []
            for key in required where object[key] == nil {
                errors.append("\(path): missing \(key)")
            }
            for (key, value) in object {
                let child = "\(path).\(key)"
                if let property = properties[key] as? [String: Any] {
                    validate(value, schema: property, path: child)
                } else if isJSONBool(schema["additionalProperties"]),
                          (schema["additionalProperties"] as? NSNumber)?.boolValue == false {
                    errors.append("\(child): additional property")
                } else if let extra = schema["additionalProperties"] as? [String: Any] {
                    validate(value, schema: extra, path: child)
                }
            }
            if let minimum = (schema["minItems"] as? NSNumber)?.intValue, object.count < minimum {
                errors.append("\(path): too few properties")
            }
        }

        mutating func validateArray(_ instance: Any, schema: [String: Any], path: String) {
            guard let items = instance as? [Any] else { return }
            if let minimum = (schema["minItems"] as? NSNumber)?.intValue, items.count < minimum {
                errors.append("\(path): fewer than \(minimum) items")
            }
            if let itemSchema = schema["items"] as? [String: Any] {
                for (index, item) in items.enumerated() {
                    validate(item, schema: itemSchema, path: "\(path)[\(index)]")
                }
            }
        }

        func resolve(_ schema: [String: Any], path: String) -> [String: Any] {
            guard let ref = schema["$ref"] as? String else { return schema }
            let prefix = "#/$defs/"
            guard ref.hasPrefix(prefix) else { return schema }
            let name = String(ref.dropFirst(prefix.count))
            guard let defs = root["$defs"] as? [String: Any], let next = defs[name] as? [String: Any] else {
                return schema
            }
            return resolve(next, path: path)
        }

        func typeNames(_ value: Any?) -> [String]? {
            if let name = value as? String { return [name] }
            if let names = value as? [Any] { return names.compactMap { $0 as? String } }
            return nil
        }

        func matches(_ instance: Any, types: [String]) -> Bool {
            types.contains { type in
                switch type {
                case "string": return kind(of: instance) == .string
                case "boolean": return kind(of: instance) == .bool
                case "object": return kind(of: instance) == .object
                case "array": return kind(of: instance) == .array
                case "null": return kind(of: instance) == .null
                case "number": return kind(of: instance) == .number
                case "integer": return isIntegral(instance)
                default: return false
                }
            }
        }

        func wholeMatch(_ pattern: String, _ text: String) -> Bool {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { return false }
            let range = NSRange(text.startIndex..., in: text)
            guard let match = regex.firstMatch(in: text, options: [], range: range) else { return false }
            return match.range == range
        }

        func same(_ lhs: Any, _ rhs: Any) -> Bool {
            switch (kind(of: lhs), kind(of: rhs)) {
            case (.null, .null):
                return true
            case (.string, .string):
                return (lhs as? String) == (rhs as? String)
            case (.bool, .bool):
                return (lhs as? NSNumber)?.boolValue == (rhs as? NSNumber)?.boolValue
            case (.number, .number):
                return (lhs as? NSNumber)?.doubleValue == (rhs as? NSNumber)?.doubleValue
            default:
                return false
            }
        }
    }
}

private enum JSONKind {
    case string, bool, number, object, array, null, other
}

private func kind(of value: Any) -> JSONKind {
    if value is NSNull { return .null }
    if value is String { return .string }
    if value is [String: Any] { return .object }
    if value is [Any] { return .array }
    if isJSONBool(value) { return .bool }
    if value is NSNumber { return .number }
    return .other
}

private func isJSONBool(_ value: Any?) -> Bool {
    guard let number = value as? NSNumber else { return false }
    return String(cString: number.objCType) == "c"
}

private func isIntegral(_ value: Any) -> Bool {
    guard let number = value as? NSNumber, !isJSONBool(number) else { return false }
    let double = number.doubleValue
    return double.isFinite && double.rounded() == double
}

private func jsonEqual(_ lhs: Any, _ rhs: Any) -> Bool {
    switch (kind(of: lhs), kind(of: rhs)) {
    case (.null, .null):
        return true
    case (.string, .string):
        return (lhs as? String) == (rhs as? String)
    case (.bool, .bool):
        return (lhs as? NSNumber)?.boolValue == (rhs as? NSNumber)?.boolValue
    case (.number, .number):
        return (lhs as? NSNumber)?.doubleValue == (rhs as? NSNumber)?.doubleValue
    case (.array, .array):
        let left = lhs as! [Any]
        let right = rhs as! [Any]
        return left.count == right.count && zip(left, right).allSatisfy(jsonEqual)
    case (.object, .object):
        let left = lhs as! [String: Any]
        let right = rhs as! [String: Any]
        guard left.count == right.count else { return false }
        return left.keys.allSatisfy { key in
            guard let other = right[key] else { return false }
            return jsonEqual(left[key]!, other)
        }
    default:
        return false
    }
}

private func jsonDifference(_ lhs: Any, _ rhs: Any, path: String = "$") -> String {
    if jsonEqual(lhs, rhs) { return "" }
    if let left = lhs as? [String: Any], let right = rhs as? [String: Any] {
        let keys = Set(left.keys).union(right.keys).sorted()
        return keys.compactMap { key -> String? in
            switch (left[key], right[key]) {
            case (nil, _):
                return "\(path).\(key) missing from export"
            case (_, nil):
                return "\(path).\(key) missing from Docs/demo-store.json"
            case let (a?, b?):
                let nested = jsonDifference(a, b, path: "\(path).\(key)")
                return nested.isEmpty ? nil : nested
            }
        }.joined(separator: "\n")
    }
    if let left = lhs as? [Any], let right = rhs as? [Any], left.count == right.count {
        return zip(left, right).enumerated().compactMap { index, pair in
            let nested = jsonDifference(pair.0, pair.1, path: "\(path)[\(index)]")
            return nested.isEmpty ? nil : nested
        }.joined(separator: "\n")
    }
    return "\(path) differs"
}
