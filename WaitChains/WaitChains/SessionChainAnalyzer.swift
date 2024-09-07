//
//  SessionChainAnalyzer.swift
//  WaitChains
//
//  Created by Ilia Sazonov on 7/21/23.
//

import Foundation
import SwiftOracle

struct SessionChainAnalyzer {
    let dbid: Int
    let beginSnap: Int
    let endSnap: Int

    var ashSamples: [Sample : [ASHShort]] = [:]
    var waitGraphs: [Sample: WaitGraph?] = [:]

    var dbService: OracleService
    var conn: Connection

    init(dbid: Int, beginSnap: Int, endSnap: Int) {
        self.dbid = dbid
        self.beginSnap = beginSnap
        self.endSnap = endSnap
        self.dbService = OracleService(from_string: "mb01_awr")
        self.conn = Connection(service: dbService, user: "AWR", pwd: "welcome1")
    }

    mutating func getData() async throws {
        print("Connection: \(dbService)")
        try! conn.open()
        let cursor = try conn.cursor()
        // get all blocked sessions
        // the query pulls sample_id and time for a blocked session and tries to find the blocker in the same snap and in approximately the same sample
        // in RAC, sample IDs can be different on each node, and sample_time can be within a couple of seconds from each other
        // hence we use the the sample_id and sample_time of the blocked session (b.sample_id, b.sample_time)
        let ashSQL = """
select * from (
with b as (
    select /*+ materialized*/ dbid, snap_id, sample_id, sample_time, session_id, session_serial#, instance_number, event, blocking_session, blocking_session_serial#, blocking_inst_id
    from dba_hist_active_sess_history where dbid = 1116568641 and snap_id between 14255 and 14255
    and blocking_session is not null
)
select sample_id, sample_time, session_id, session_serial#, instance_number, event, blocking_session, blocking_session_serial#, blocking_inst_id from b
union all
select distinct b.sample_id, b.sample_time, a.session_id, a.session_serial#, a.instance_number, a.event, null, null, null
from dba_hist_active_sess_history a, b
where a.dbid = b.dbid and a.snap_id = b.snap_id and a.blocking_session is null
and abs(((a.sample_time - b.sample_time + sysdate) - sysdate)*24*3600) < 4
and a.session_id = b.blocking_session
and a.session_serial# = b.blocking_session_serial#
and a.instance_number = b.blocking_inst_id
) where sample_id = 49788293
order by blocking_session nulls first
"""
        try! cursor.execute(ashSQL, prefetchSize: 1000, enableDbmsOutput: false)
        var ash = [ASHShort]()
        ash.reserveCapacity(20000)
        var rowCnt = 0
        while let row = cursor.nextSwifty(withStringRepresentation: true) {
            let sample = ASHShort(sampleId: row["SAMPLE_ID"]!.int!,
                                  sampleDate: Calendar.current.date(from: row["SAMPLE_TIME"]!.timestamp!)!,
                                  sessionId: row["SESSION_ID"]!.int!,
                                  sessionSerial: row["SESSION_SERIAL#"]!.int!,
                                  instanceId: row["INSTANCE_NUMBER"]!.int!,
                                  event: row["EVENT"]!.string,
                                  blockingSessionId: row["BLOCKING_SESSION"]!.int,
                                  blockingSessionSerial: row["BLOCKING_SESSION_SERIAL#"]!.int,
                                  blockingInstanceId: row["BLOCKING_INST_ID"]!.int
            )
            ash.append(sample)
            rowCnt += 1
        }
        print("Fetched \(rowCnt) rows.")
        
        ashSamples = Dictionary(grouping: ash, by: { Sample(sampleId: $0.sampleId, sampleDate: $0.sampleDate)})
        print("ashSamples count: \(ashSamples.count)")
        waitGraphs = ashSamples.mapValues { sessions in
            let waitGraph = WaitGraph()
            for s in sessions { // non-blocked sessions that are blocking other sessions come first
                print("-------- session \(s) --------")
                let newNode = Node<ASHShort>(data: s)
                if let blockerSessionId = s.blockingSessionId, let blockerSerial = s.blockingSessionSerial, let blockerInstanceId = s.blockingInstanceId { // session is blocked
                    // find the blocker; it may be that the blocker session was not registered in the same sample
                    if let blockerAsh = sessions.filter({ $0.sessionId == blockerSessionId && $0.sessionSerial == blockerSerial }).first {
                        print("found blocker \(blockerAsh)")
                        let blockerNode = Node<ASHShort>(data: blockerAsh)
                        // check to see if the blocker is already in the graph
                        if !waitGraph.contains(blockerNode) {
                            let _ = waitGraph.addNode(blockerNode)
                            print("added blocker node")
                        }
                        waitGraph.addEdge(from: blockerNode, to: newNode)
                        print("added edge from blocker to newnode")
                    } else { // though we didn't find the blocker in our current sample, we still want to put a placeholder for it as our session is blocked in this sample
                        print("did NOT find the blocker in the sample")
                        /// TODO: insert an incomplete node so that we can display it
                        let blockerNode = Node<ASHShort>(data: ASHShort(sampleId: s.sampleId, sampleDate: s.sampleDate,
                                                                        sessionId: blockerSessionId, sessionSerial: blockerSerial, instanceId: blockerInstanceId,
                                                                        event: nil, blockingSessionId: nil, blockingSessionSerial: nil, blockingInstanceId: nil))
                        if !waitGraph.contains(blockerNode) {
                            let _ = waitGraph.addNode(blockerNode)
                            print("added a placeholder for blocker")
                        }
                        waitGraph.addEdge(from: blockerNode, to: newNode)
                        print("added edge from placeholder to newnode")
                    }
                } else { // session is a pure blocker
                    waitGraph.addNode(s)
                    print("added a blocker \(s)")
                }

            }
            // at this point, we have processed all sessions in the sample
            // let's drop unconnected nodes
//            for n in waitGraph.graph.keys {
//                if waitGraph.isEmpty(n) {
//                    waitGraph.removeNode(n)
//                }
//            }
            if waitGraph.edgeCount > 0 {
//                print("graph: \(waitGraph)")
                print("nodes: \(waitGraph.nodes)")
                return waitGraph
            } else {
                print("No edges: \(waitGraph)")
                return nil
            }
        }
        print("Total non-empty graphs: \(waitGraphs.values.compactMap({$0}).count)")
        print("Exiting getData")
    }
}
