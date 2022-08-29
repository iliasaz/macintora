//
//  MacintoraTests.swift
//  MacintoraTests
//
//  Created by Ilia Sazonov on 8/22/22.
//

import XCTest
@testable import Macintora

class MacintoraTests: XCTestCase {

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    func testExample() throws {
        // This is an example of a functional test case.
        // Use XCTAssert and related functions to verify your tests produce the correct results.
        // Any test you write for XCTest can be annotated as throws and async.
        // Mark your test throws to produce an unexpected failure when your test encounters an uncaught error.
        // Mark your test async to allow awaiting for asynchronous code to complete. Check the results with assertions afterwards.
    }

    func testPerformanceExample() throws {
        // This is an example of a performance test case.
        measure {
            // Put the code you want to measure the time of here.
        }
    }
    
    func test_BindVarDetectionInSQL_noBinds() throws {
        let sql = "select 1 from dual"
        let runnable = RunnableSQL(sql: sql)
        XCTAssert(runnable.bindNames.count == 0)
    }
    
    func test_BindVarDetectionInSQL_3Binds() throws {
        let sql = "select 1 from dual where v in (:1, :2, :3)"
        let runnable = RunnableSQL(sql: sql)
        XCTAssert(runnable.bindNames.count == 3)
    }
    
    func test_BindVarDetectionInSQL_ignoreQuoted() throws {
        let sql = "select 1 from dual where v in (':1', ':2', ':3')"
        let runnable = RunnableSQL(sql: sql)
        XCTAssert(runnable.bindNames.count == 0)
    }

    func test_BindVarDetectionInSQL_ignoreCommented() throws {
        var sql = "select 1 from dual where 1=1 -- and v in (:1, :2, :3)"
        var runnable = RunnableSQL(sql: sql)
        XCTAssert(runnable.bindNames.count == 0)

        sql = "--23:59:59"
        runnable = RunnableSQL(sql: sql)
        XCTAssert(runnable.bindNames.count == 0)
        
        sql = "select 1 from dual where 1=1 /* and :1 = 23:50:50 */"
        runnable = RunnableSQL(sql: sql)
        XCTAssert(runnable.bindNames.count == 0)
        
        sql = """
select 1 from dual
where 1=1 /*
and :1 = 23:50:50
*/
"""
        runnable = RunnableSQL(sql: sql)
        XCTAssert(runnable.bindNames.count == 0)
    }
    
    func test_detectStoreProcCreatePackage() throws {
        var sp: (Bool, StoredProc?), sql: String

        sql = "create package test as"
        sp = RunnableSQL.detectStoredProc(sql)
        XCTAssert(sp.0 == true && sp.1 == StoredProc(owner: nil, name: "TEST", type: "PACKAGE"))

        sql = "create package user.test as"
        sp = RunnableSQL.detectStoredProc(sql)
        XCTAssert(sp.0 == true && sp.1 == StoredProc(owner: "USER", name: "TEST", type: "PACKAGE"))

        sql = "create editioned package user.test as"
        sp = RunnableSQL.detectStoredProc(sql)
        XCTAssert(sp.0 == true && sp.1 == StoredProc(owner: "USER", name: "TEST", type: "PACKAGE"))

        sql = "create or replace editioned package body user.test as"
        sp = RunnableSQL.detectStoredProc(sql)
        XCTAssert(sp.0 == true && sp.1 == StoredProc(owner: "USER", name: "TEST", type: "PACKAGE BODY"))

        sql = "create or replace editioned package body \"user\".\"test\" as"
        sp = RunnableSQL.detectStoredProc(sql)
        XCTAssert(sp.0 == true && sp.1 == StoredProc(owner: "user", name: "test", type: "PACKAGE BODY"))

        sql = "create or replace editioned package body \"test\" as"
        sp = RunnableSQL.detectStoredProc(sql)
        XCTAssert(sp.0 == true && sp.1 == StoredProc(owner: nil, name: "test", type: "PACKAGE BODY"))

    }
    
    func test_detectStoreProcCreateProcedure() throws {
        var sp: (Bool, StoredProc?), sql: String

        sql = "create procedure test as"
        sp = RunnableSQL.detectStoredProc(sql)
        XCTAssert(sp.0 == true && sp.1 == StoredProc(owner: nil, name: "TEST", type: "PROCEDURE"))

        sql = "create procedure user.test as"
        sp = RunnableSQL.detectStoredProc(sql)
        XCTAssert(sp.0 == true && sp.1 == StoredProc(owner: "USER", name: "TEST", type: "PROCEDURE"))

        sql = "create editioned procedure user.test as"
        sp = RunnableSQL.detectStoredProc(sql)
        XCTAssert(sp.0 == true && sp.1 == StoredProc(owner: "USER", name: "TEST", type: "PROCEDURE"))

        sql = "create or replace editioned procedure \"user\".\"test\" as"
        sp = RunnableSQL.detectStoredProc(sql)
        XCTAssert(sp.0 == true && sp.1 == StoredProc(owner: "user", name: "test", type: "PROCEDURE"))

        sql = "create or replace editioned procedure \"test\" as"
        sp = RunnableSQL.detectStoredProc(sql)
        XCTAssert(sp.0 == true && sp.1 == StoredProc(owner: nil, name: "test", type: "PROCEDURE"))

    }
    
    func test_detectStoreProcCreateFunction() throws {
        var sp: (Bool, StoredProc?), sql: String

        sql = "create function test as"
        sp = RunnableSQL.detectStoredProc(sql)
        XCTAssert(sp.0 == true && sp.1 == StoredProc(owner: nil, name: "TEST", type: "FUNCTION"))

        sql = "create function user.test as"
        sp = RunnableSQL.detectStoredProc(sql)
        XCTAssert(sp.0 == true && sp.1 == StoredProc(owner: "USER", name: "TEST", type: "FUNCTION"))

        sql = "create editioned function user.test as"
        sp = RunnableSQL.detectStoredProc(sql)
        XCTAssert(sp.0 == true && sp.1 == StoredProc(owner: "USER", name: "TEST", type: "FUNCTION"))

        sql = "create or replace editioned function \"user\".\"test\" as"
        sp = RunnableSQL.detectStoredProc(sql)
        XCTAssert(sp.0 == true && sp.1 == StoredProc(owner: "user", name: "test", type: "FUNCTION"))

        sql = "create or replace editioned function \"test\" as"
        sp = RunnableSQL.detectStoredProc(sql)
        XCTAssert(sp.0 == true && sp.1 == StoredProc(owner: nil, name: "test", type: "FUNCTION"))

    }

}
