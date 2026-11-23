import Testing
@testable import JoyHarness

struct MappingActionFilterTests {
    @Test func categoriesCoverSelectableActionsOnce() {
        let selectable = RemoteAction.allCases.filter {
            !$0.isLegacyPointerAction && ![.voiceShortcut, .cycleLeftStickMode, .cycleRightStickMode].contains($0)
        }
        let all = MappingActionFilter.all.options(selecting: .disabled)
        #expect(all.count == selectable.count)
        #expect(Set(all) == Set(selectable))

        let basic = MappingActionFilter.basic.options(selecting: .disabled)
        let system = MappingActionFilter.system.options(selecting: .disabled)
        let custom = MappingActionFilter.custom.options(selecting: .disabled)
        let categorized = (basic + system + custom).filter { $0 != .disabled }
        #expect(categorized.count == all.count - 1)
        #expect(Set(categorized) == Set(all.dropFirst()))
        #expect(basic.contains(.enter))
        #expect(system.contains(.cycleStickMode))
        #expect(custom.contains(.openPhrases))
    }

    @Test func filtersKeepTheCurrentActionAndUnsetAvailable() {
        for filter in MappingActionFilter.allCases {
            let options = filter.options(selecting: .recordedShortcut)
            #expect(options.first == .disabled)
            #expect(options.filter { $0 == .recordedShortcut }.count == 1)
            #expect(filter.options(selecting: .cycleRightStickMode).contains(.cycleRightStickMode))
        }
        #expect(!MappingActionFilter.custom.options(selecting: .recordedShortcut).contains(.enter))
    }
}
