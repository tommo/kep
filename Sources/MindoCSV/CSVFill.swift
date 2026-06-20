import Foundation

/// Pure fill logic for the spreadsheet's ⌘D / ⌘R (fill down / fill right) and,
/// later, the fill-handle drag. Excel-style: a numeric arithmetic run extends as
/// a series; anything else (single value, text, mixed) repeats cyclically. No
/// grid/view dependency, so it's fully unit-testable; the CSVGridView will call
/// it when P4 wires the fill commands.
public enum CSVFill {

    /// Produce `length` fill values that continue `seed`.
    /// - A seed of ≥2 cells that are all numeric with a constant step extends
    ///   the arithmetic series (1,2 → 3,4,5…; 2,4,6 → 8,10…).
    /// - Otherwise the seed pattern repeats cyclically (single number copies;
    ///   text/mixed tile: a,b → a,b,a,b…).
    public static func fill(seed: [String], length: Int) -> [String] {
        guard length > 0, !seed.isEmpty else { return [] }
        if let next = numericSeries(seed, length: length) { return next }
        return (0..<length).map { seed[$0 % seed.count] }
    }

    /// nil unless the seed is a numeric arithmetic progression of ≥2 terms.
    private static func numericSeries(_ seed: [String], length: Int) -> [String]? {
        guard seed.count >= 2 else { return nil }
        let nums = seed.map { Double($0.trimmingCharacters(in: .whitespaces)) }
        guard nums.allSatisfy({ $0 != nil }) else { return nil }
        let values = nums.compactMap { $0 }
        let step = values[1] - values[0]
        for i in 2..<values.count where abs((values[i] - values[i - 1]) - step) > 1e-9 {
            return nil   // not a constant step → treat as a repeating pattern
        }
        var out: [String] = []
        var v = values.last! + step
        for _ in 0..<length {
            out.append(format(v))
            v += step
        }
        return out
    }

    /// Shortest round-trippable decimal, dropping a redundant `.0` (matches the
    /// formula engine's number formatting so filled + computed cells agree).
    private static func format(_ d: Double) -> String {
        if d == d.rounded(), abs(d) < 1e15 { return String(Int64(d)) }
        var s = String(d)
        if s.hasSuffix(".0") { s.removeLast(2) }
        return s
    }
}
