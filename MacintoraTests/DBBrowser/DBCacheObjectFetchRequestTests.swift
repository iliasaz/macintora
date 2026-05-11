//
//  DBCacheObjectFetchRequestTests.swift
//  MacintoraTests
//
//  Locks in the "no more 20-row cap" behaviour (issue #25, Item 2):
//  `DBCacheObject.fetchRequest(limit:predicate:)` treats `limit == 0`
//  (the default) as "no cap" and only sets `fetchLimit` when a positive
//  value is passed. Also pins the sort order the list pane relies on.
//

import XCTest
import CoreData
@testable import Macintora

final class DBCacheObjectFetchRequestTests: XCTestCase {

    func test_defaultLimit_meansNoFetchLimit() {
        let request = DBCacheObject.fetchRequest(predicate: nil)
        XCTAssertEqual(request.fetchLimit, 0, "no limit argument must leave fetchLimit unset (0 == unlimited)")
    }

    func test_zeroLimit_meansNoFetchLimit() {
        let request = DBCacheObject.fetchRequest(limit: 0, predicate: nil)
        XCTAssertEqual(request.fetchLimit, 0)
    }

    func test_positiveLimit_isApplied() {
        let request = DBCacheObject.fetchRequest(limit: 250, predicate: nil)
        XCTAssertEqual(request.fetchLimit, 250)
    }

    func test_predicateIsForwarded() {
        let predicate = NSPredicate(format: "type_ = %@", "TABLE")
        let request = DBCacheObject.fetchRequest(predicate: predicate)
        XCTAssertEqual(request.predicate, predicate)
    }

    func test_sortDescriptors_areOwnerThenTypeThenName() {
        let request = DBCacheObject.fetchRequest(predicate: nil)
        XCTAssertEqual(request.sortDescriptors?.map(\.key), ["owner_", "type_", "name_"])
        XCTAssertEqual(request.sortDescriptors?.allSatisfy(\.ascending), true)
    }
}
