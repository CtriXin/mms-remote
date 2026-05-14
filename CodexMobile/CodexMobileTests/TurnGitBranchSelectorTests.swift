// FILE: TurnGitBranchSelectorTests.swift
// Purpose: Verifies new branch creation names normalize toward the mms-remote/ prefix without double-prefixing.
// Layer: Unit Test
// Exports: TurnGitBranchSelectorTests
// Depends on: XCTest, CodexMobile

import XCTest
@testable import CodexMobile

final class TurnGitBranchSelectorTests: XCTestCase {
    func testNormalizesCreatedBranchNamesTowardMMS RemotePrefix() {
        XCTAssertEqual(mmsRemoteNormalizedCreatedBranchName("foo"), "mms-remote/foo")
        XCTAssertEqual(mmsRemoteNormalizedCreatedBranchName("mms-remote/foo"), "mms-remote/foo")
        XCTAssertEqual(mmsRemoteNormalizedCreatedBranchName("  foo  "), "mms-remote/foo")
    }

    func testNormalizesEmptyBranchNamesToEmptyString() {
        XCTAssertEqual(mmsRemoteNormalizedCreatedBranchName("   "), "")
    }

    func testCurrentBranchSelectionDisablesCheckedOutElsewhereRowsWhenWorktreePathIsMissing() {
        XCTAssertTrue(
            mmsRemoteCurrentBranchSelectionIsDisabled(
                branch: "mms-remote/feature-a",
                currentBranch: "main",
                gitBranchesCheckedOutElsewhere: ["mms-remote/feature-a"],
                gitWorktreePathsByBranch: [:],
                allowsSelectingCurrentBranch: true
            )
        )
    }

    func testCurrentBranchSelectionKeepsCheckedOutElsewhereRowsEnabledWhenWorktreePathExists() {
        XCTAssertFalse(
            mmsRemoteCurrentBranchSelectionIsDisabled(
                branch: "mms-remote/feature-a",
                currentBranch: "main",
                gitBranchesCheckedOutElsewhere: ["mms-remote/feature-a"],
                gitWorktreePathsByBranch: ["mms-remote/feature-a": "/tmp/mms-remote-feature-a"],
                allowsSelectingCurrentBranch: true
            )
        )
    }

    func testSelectableDefaultBranchReturnsNilWhenDefaultIsNotLocal() {
        XCTAssertNil(
            mmsRemoteSelectableDefaultBranch(
                defaultBranch: "main",
                availableGitBranchTargets: ["mms-remote/feature-a"]
            )
        )
    }

    func testSelectableDefaultBranchReturnsDefaultWhenItIsLocal() {
        XCTAssertEqual(
            mmsRemoteSelectableDefaultBranch(
                defaultBranch: "main",
                availableGitBranchTargets: ["main", "mms-remote/feature-a"]
            ),
            "main"
        )
    }
}
