//
//  WaitChainModel.swift
//  
//
//  Created by Ilia Sazonov on 7/18/23.
//

import Foundation

struct Sample: Codable, Hashable {
    let sampleId: Int
    let sampleDate: Date
}

struct ASHShort: Codable, Hashable {
    let sampleId: Int
    let sampleDate: Date
    let sessionId: Int
    let sessionSerial: Int
    let instanceId: Int
    let event: String?
    let blockingSessionId: Int?
    let blockingSessionSerial: Int?
    let blockingInstanceId: Int?
    
    var isBlocked: Bool { blockingSessionId != nil }

    static func ==(lhs: ASHShort, rhs: ASHShort) -> Bool {
        lhs.sampleId == rhs.sampleId && lhs.sessionId == rhs.sessionId && lhs.sessionSerial == rhs.sessionSerial && lhs.instanceId == rhs.instanceId
    }
}

struct WaitChain: Codable {
    var sessions: Set<ASHShort> = []
    var isLoop = false
    
    func exists(_ session: ASHShort) -> Bool {
        sessions.filter({ $0.sessionId == session.sessionId && $0.sessionSerial == session.sessionSerial }).first != nil
    }
}


enum EdgeType {
    case directed, undirected
}

struct Node<T>: CustomStringConvertible, Hashable where T: Hashable {
    let data: T
    let isComplete: Bool = true
    
    var description: String {
        "\(data)"
    }
}

struct Edge<T>: CustomStringConvertible, Hashable where T: Hashable {
    let from: Node<T>
    let to: Node<T>
    
    var description: String {
        "from: \(from), to: \(to)"
    }
}

protocol Graph: CustomStringConvertible {
    associatedtype Element where Element: Hashable
    func addNode(_ node: Element) -> Node<Element>
    func addNode(_ node: Node<Element>) -> Node<Element>
    func addEdge(from: Node<Element>, to: Node<Element>, _ edgeType: EdgeType)
    func edges(from source: Node<Element>) -> [Edge<Element>]
    func contains(_ node: Node<Element>) -> Bool
    func first(where: (Node<Element>) -> Bool) -> Node<Element>?
    func find(_ node: Node<Element>) -> Node<Element>?
    func removeNode(_ node: Node<Element>)
    
    var graph: [Node<Element> : [Edge<Element>]] { get }
}

extension Graph {
    func edges(from source: Node<Element>) -> [Edge<Element>] {
        graph[source] ?? []
    }
    
    func contains(_ node: Node<Element>) -> Bool {
        graph.keys.contains(node)
    }
    
    func first(where condition: (Node<Element>) -> Bool) -> Node<Element>? {
        graph.keys.first(where: condition)
    }
    
    func find(_ node: Node<Element>) -> Node<Element>? {
        first(where: {$0 == node })
    }

    var nodeCount: Int { graph.keys.count }
    var edgeCount: Int { graph.values.reduce(0,  { $0 + $1.count }) }
    var nodes: [Node<Element>] { Array(graph.keys) }

    var description: String { graph.description }
}



class WaitGraph: Graph {
    var graph: [Node<ASHShort> : [Edge<ASHShort>]] { internalGraph }

    typealias Element = ASHShort
    private var internalGraph: [Node<Element> : [Edge<Element>]] = [:]
    
    init() {}
    
    func addNode(_ ash: ASHShort) -> Node<ASHShort> {
        let node = Node(data: ash)
        internalGraph[Node(data: ash)] = []
        return node
    }
    
    func addNode(_ node: Node<Element>) -> Node<ASHShort> {
        internalGraph[node] = []
        return node
    }
    
    func addEdge(from: Node<ASHShort>, to: Node<ASHShort>, _ edgeType: EdgeType = .directed) {
        internalGraph[from]?.append(Edge(from: from, to: to))
    }

    func removeNode(_ node: Node<Element>) {
        internalGraph.removeValue(forKey: node)
    }

    func isEmpty(_ node: Node<Element>) -> Bool {
        guard let n = graph[node] else { return true }
        return n.isEmpty
    }
}
