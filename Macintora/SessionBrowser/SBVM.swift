//
//  SBVM.swift
//  Macintora
//
//  Created by Ilia Sazonov on 9/16/22.
//

import Foundation
import SwiftOracle

struct OracleSession {
    let sid: Int
    let serial: Int
    let instance: Int
    
    static func preview() -> OracleSession {
        OracleSession(sid: 100, serial: 2000, instance: 2)
    }
}

struct SBConnDetails {
    let mainConnDetails: ConnectionDetails
    let mainSession: OracleSession?
    
    static func preview() -> SBConnDetails {
        SBConnDetails(mainConnDetails: ConnectionDetails.preview(), mainSession: OracleSession.preview())
    }
}

class SBVM: ObservableObject {
    var connDetails: SBConnDetails
    @Published var connStatus: ConnectionStatus = .disconnected
    @Published var isExecuting = false
    private var conn: Connection?
    var autoColWidth = true
    var rows = [SwiftyRow]()
    var columnLabels = [String]()
    var dataHasChanged = false
    let currentSql = "select * from v$session order by decode(status,'ACTIVE',0,'KILLED',1,'INACTIVE',2,3), decode(wait_class, 'Idle', 0, 1) desc, seconds_in_wait desc"
    var oraSession: OracleSession?
    
    init(connDetails: SBConnDetails) {
        self.connDetails = connDetails
    }
    
    static func preview() -> SBVM {
        SBVM(connDetails: SBConnDetails.preview())
    }
    
    func sort(by colName: String?, ascending: Bool) {
        guard let colName = colName else { return }
        guard let colIndex = columnLabels.firstIndex(of: colName) else { return }
        if ascending {
            rows.sort(by: {SwiftyRow.less(colIndex: colIndex-1, lhs: $0, rhs: $1)} ) // account for row number!
        } else {
            rows.sort(by: {SwiftyRow.less(colIndex: colIndex-1, lhs: $1, rhs: $0)} )
        }
    }
    
    func connectAndQuery() {
        connStatus = .changing
        Task.detached(priority: .background) { [self] in
            let oracleService = OracleService(from_string: connDetails.mainConnDetails.tns)
            conn = Connection(service: oracleService, user: connDetails.mainConnDetails.username, pwd: connDetails.mainConnDetails.password, sysDBA: connDetails.mainConnDetails.connectionRole == .sysDBA)
            guard let conn else {
                log.error("connection object is nil")
                await MainActor.run { connStatus = .disconnected }
                return
            }
            do {
                log.debug("SB attempting to connect to \(self.connDetails.mainConnDetails.tns, privacy: .public)")
                try conn.open()
                log.debug("SB connected")
                do { try conn.setFormat(fmtType: .date, fmtString: "YYYY-MM-DD HH24:MI:SS") }
                catch {
                    log.debug("setFormat failed: \(error.localizedDescription, privacy: .public)")
                    await MainActor.run { connStatus = .disconnected }
                    return
                }
                oraSession = MainDocumentVM.getOracleSession(for: conn)
            } catch {
                log.error("SB connection error: \(error.localizedDescription, privacy: .public)")
                await MainActor.run { connStatus = .disconnected }
                return
            }
            await MainActor.run {
                connStatus = .connected
                objectWillChange.send()
                rows.removeAll()
                isExecuting = true
            }
            let result = await queryData(for: currentSql, using: conn, maxRows: 10000, showDbmsOutput: false, prefetchSize: 1000)
            await MainActor.run {
                updateViews(with: result)
            }
        }
    }
    
    func disconnect() {
        connStatus = .changing
        Task.detached(priority: .background) { [self] in
            guard let conn = conn else {
                log.error("SB connection doesn't exist")
                await MainActor.run { connStatus = .disconnected }
                return
            }
            conn.close()
            oraSession = nil
            await MainActor.run {
                if !conn.connected {
                    connStatus = .disconnected
                    log.debug("SB disconnected")
                }
            }
        }
    }
    
    func queryData(for sql:String, using conn:Connection, maxRows: Int, showDbmsOutput: Bool = false, binds: [String: BindVar] = [:], prefetchSize: Int = 200) async -> Result<([String], [SwiftyRow], String, String), Error> {
        let result: Result<([String], [SwiftyRow], String, String), Error>
        var rows = [SwiftyRow]()
        var columnLabels = [String]()
        do {
            let cursor = try conn.cursor()
            try cursor.execute(sql, params: binds, prefetchSize: prefetchSize, enableDbmsOutput: showDbmsOutput)
            let sqlId = cursor.sqlId
            let dbmsOuput = cursor.dbmsOutputContent
            columnLabels = cursor.getColumnLabels()
            rows = [SwiftyRow]()
            var rowCnt = 0
            while let row = cursor.nextSwifty(withStringRepresentation: true), rowCnt < (maxRows == -1 ? 10000 : maxRows) {
                rows.append(row)
                rowCnt += 1
            }
            columnLabels.insert("#", at: 0)
            result = .success((columnLabels, rows, sqlId, dbmsOuput))
            log.debug("data loaded, rows.count: \(rows.count)")
        } catch DatabaseErrors.SQLError (let error) {
            log.error("\(error.description, privacy: .public)")
            result = .failure(error)
        } catch {
            log.error("\(error.localizedDescription, privacy: .public)")
            result = .failure(error)
        }
        return result
    }
    
    func populateData() {
        objectWillChange.send()
        rows.removeAll()
        isExecuting = true
        Task.detached(priority: .background) { [self] in
            let result = await queryData(for: currentSql, using: conn!, maxRows: 10000, showDbmsOutput: false, prefetchSize: 1000)
            await MainActor.run {
                updateViews(with: result)
            }
        }
    }
    
    func updateViews(with result: Result<([String], [SwiftyRow], String, String), Error>) {
        objectWillChange.send()
        switch result {
            case .success(let (resultColumns, resultRows, _, _)):
                self.columnLabels = resultColumns
                self.rows = resultRows
                dataHasChanged = true
            case .failure(let error):
                log.debug("Session query failed with \(error.localizedDescription, privacy: .public)")
        }
        isExecuting = false
        log.debug("end of refreshData")
    }
}

