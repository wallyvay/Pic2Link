import SwiftUI
import XCTest
@testable import Pic2Link

@MainActor
final class HistoryGridLayoutTests: XCTestCase {
    func testColumnsNeverExceedTheAvailableWidth() {
        for width in stride(from: 104.0, through: 1600.0, by: 7.0) {
            let count = HistoryGridLayout.columnCount(fitting: width)
            let total = CGFloat(count) * HistoryGridLayout.cellWidth
                + CGFloat(count - 1) * HistoryGridLayout.spacing
            XCTAssertGreaterThanOrEqual(count, 1)
            XCTAssertLessThanOrEqual(total, max(width, HistoryGridLayout.cellWidth), "列总宽超出容器宽度: \(width)")
        }
    }

    func testColumnCountMatchesCommonWindowWidths() {
        XCTAssertEqual(HistoryGridLayout.columnCount(fitting: 104), 1)
        XCTAssertEqual(HistoryGridLayout.columnCount(fitting: 428), 3)
        XCTAssertEqual(HistoryGridLayout.columnCount(fitting: 688), 6)
        XCTAssertLessThan(HistoryGridLayout.columnCount(fitting: 428),
                          HistoryGridLayout.columnCount(fitting: 1200))
    }
}
