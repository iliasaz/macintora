//
//  OffsetMap.swift
//  Macintora
//
//  Sparse mapping from positions in a "resolved" string back to positions in
//  the "original" string. Built by SubstitutionResolver during script
//  preprocessing so click-to-source can highlight the original (pre-
//  substitution) range when the runner reports an error.
//
//  All offsets are UTF-16 code units. Conversion helpers between String.Index
//  and UTF-16 offsets are provided.
//

import Foundation

struct OffsetMap: Equatable {
    struct Segment: Equatable {
        enum Kind: Equatable {
            /// Characters copied 1:1 from original to resolved.
            case passthrough
            /// A single `&name` / `&&name` reference in the original was
            /// replaced by a (possibly differently-sized) value in resolved.
            case substitution
        }
        let kind: Kind
        let resolvedRange: Range<Int>
        let originalRange: Range<Int>
    }

    let segments: [Segment]
    let originalLength: Int
    let resolvedLength: Int

    /// Identity mapping for a string of `length` UTF-16 code units.
    static func identity(utf16Length length: Int) -> OffsetMap {
        if length == 0 {
            return OffsetMap(segments: [], originalLength: 0, resolvedLength: 0)
        }
        return OffsetMap(
            segments: [.init(kind: .passthrough, resolvedRange: 0..<length, originalRange: 0..<length)],
            originalLength: length,
            resolvedLength: length
        )
    }

    /// Project a half-open range in resolved space back into original space.
    /// For overlapping `.substitution` segments, the entire original range of
    /// the substitution is included — there is no character-level mapping
    /// inside a substituted value.
    func originalRange(forResolved range: Range<Int>) -> Range<Int> {
        var lo: Int? = nil
        var hi: Int? = nil

        for seg in segments where seg.resolvedRange.overlaps(range) {
            let segLo: Int
            let segHi: Int
            switch seg.kind {
            case .passthrough:
                let resStart = max(range.lowerBound, seg.resolvedRange.lowerBound)
                let resEnd = min(range.upperBound, seg.resolvedRange.upperBound)
                let inOff = resStart - seg.resolvedRange.lowerBound
                let inLen = resEnd - resStart
                segLo = seg.originalRange.lowerBound + inOff
                segHi = segLo + inLen
            case .substitution:
                segLo = seg.originalRange.lowerBound
                segHi = seg.originalRange.upperBound
            }
            lo = lo.map { min($0, segLo) } ?? segLo
            hi = hi.map { max($0, segHi) } ?? segHi
        }

        if let lo, let hi { return lo..<hi }
        // Empty / out-of-range query: collapse to the boundary so callers can
        // still build a Range<String.Index> without a crash.
        let bounded = min(max(range.lowerBound, 0), originalLength)
        return bounded..<bounded
    }

    /// Convenience: project a `Range<String.Index>` in `resolved` back into a
    /// `Range<String.Index>` in `original`.
    func originalRange(
        forResolved range: Range<String.Index>,
        in resolved: String,
        original: String
    ) -> Range<String.Index> {
        let resLo = resolved.utf16.distance(from: resolved.utf16.startIndex, to: range.lowerBound.samePosition(in: resolved.utf16) ?? resolved.utf16.startIndex)
        let resHi = resolved.utf16.distance(from: resolved.utf16.startIndex, to: range.upperBound.samePosition(in: resolved.utf16) ?? resolved.utf16.endIndex)
        let orig = originalRange(forResolved: resLo..<resHi)
        let oLo = original.utf16.index(original.utf16.startIndex, offsetBy: orig.lowerBound, limitedBy: original.utf16.endIndex) ?? original.utf16.endIndex
        let oHi = original.utf16.index(original.utf16.startIndex, offsetBy: orig.upperBound, limitedBy: original.utf16.endIndex) ?? original.utf16.endIndex
        let lo = String.Index(oLo, within: original) ?? original.endIndex
        let hi = String.Index(oHi, within: original) ?? original.endIndex
        return lo..<hi
    }
}
