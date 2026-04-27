import XCTest
@testable import CairnUI

@MainActor
final class MainWindowViewModelTests: XCTestCase {
    func test_init_defaultsAllCollapsedFalse() {
        let vm = MainWindowViewModel()
        XCTAssertFalse(vm.sidebarCollapsed)
        XCTAssertFalse(vm.inspectorCollapsed)
        XCTAssertNil(vm.currentWorkspaceId)
    }

    func test_toggleSidebar_flipsState() {
        let vm = MainWindowViewModel()
        vm.toggleSidebar()
        XCTAssertTrue(vm.sidebarCollapsed)
        vm.toggleSidebar()
        XCTAssertFalse(vm.sidebarCollapsed)
    }

    func test_toggleInspector_flipsState() {
        let vm = MainWindowViewModel()
        vm.toggleInspector()
        XCTAssertTrue(vm.inspectorCollapsed)
        vm.toggleInspector()
        XCTAssertFalse(vm.inspectorCollapsed)
    }

    func test_customInit_preservesValues() {
        let id = UUID()
        let vm = MainWindowViewModel(
            currentWorkspaceId: id,
            sidebarCollapsed: true,
            inspectorCollapsed: true
        )
        XCTAssertEqual(vm.currentWorkspaceId, id)
        XCTAssertTrue(vm.sidebarCollapsed)
        XCTAssertTrue(vm.inspectorCollapsed)
    }
}
