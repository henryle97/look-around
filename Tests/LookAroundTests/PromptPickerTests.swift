import Foundation

func registerPromptPickerTests(_ r: TestRunner) {
    let eyes1 = BreakPrompt(id: "e1", category: .eyes, text: "Look far away", weight: 1)
    let eyes2 = BreakPrompt(id: "e2", category: .eyes, text: "Look at the horizon", weight: 1)
    let blink1 = BreakPrompt(id: "b1", category: .blink, text: "Blink slowly", weight: 1)
    let pool = [eyes1, eyes2, blink1]

    r.run("PromptPicker.candidates: excludes recently-shown ids when alternatives remain") {
        let candidates = PromptPicker.candidates(from: pool, recentIDs: ["e1"], lastCategory: nil)
        try expectFalse(candidates.contains { $0.id == "e1" })
        try expectTrue(candidates.contains { $0.id == "e2" })
        try expectTrue(candidates.contains { $0.id == "b1" })
    }

    r.run("PromptPicker.candidates: falls back to the full pool once everything has been shown recently") {
        let allShown = pool.map(\.id)
        let candidates = PromptPicker.candidates(from: pool, recentIDs: allShown, lastCategory: nil)
        try expectEqual(candidates.count, pool.count)
    }

    r.run("PromptPicker.candidates: avoids repeating the last category when a different one is available") {
        let candidates = PromptPicker.candidates(from: pool, recentIDs: [], lastCategory: .eyes)
        try expectFalse(candidates.contains { $0.category == .eyes })
        try expectTrue(candidates.contains { $0.id == "b1" })
    }

    r.run("PromptPicker.candidates: falls back to the full pool when the pool is a single category") {
        let singleCategoryPool = [eyes1, eyes2]
        let candidates = PromptPicker.candidates(from: singleCategoryPool, recentIDs: [], lastCategory: .eyes)
        try expectEqual(candidates.count, singleCategoryPool.count)
    }

    r.run("PromptPicker.candidates: an empty pool yields no candidates") {
        try expectTrue(PromptPicker.candidates(from: [], recentIDs: [], lastCategory: nil).isEmpty)
    }

    r.run("PromptPicker.pick: returns nil for an empty pool") {
        try expectNil(PromptPicker.pick(from: [], recentIDs: [], lastCategory: nil))
    }

    r.run("PromptPicker.pick: a fixed randomIndex deterministically selects by cumulative weight") {
        let weighted = [
            BreakPrompt(id: "w1", category: .eyes, text: "first", weight: 2),
            BreakPrompt(id: "w2", category: .blink, text: "second", weight: 1),
        ]
        // total weight = 3; index 0 and 1 fall in w1's [0,2) slice, index 2 in w2's [2,3) slice.
        let first = PromptPicker.pick(from: weighted, recentIDs: [], lastCategory: nil, randomIndex: { _ in 0 })
        try expectEqual(first?.id, "w1")
        let second = PromptPicker.pick(from: weighted, recentIDs: [], lastCategory: nil, randomIndex: { _ in 2 })
        try expectEqual(second?.id, "w2")
    }

    r.run("PromptPicker.pick: a non-positive weight is treated as 1, not excluded") {
        let zeroWeighted = [BreakPrompt(id: "z1", category: .eyes, text: "only one", weight: 0)]
        let picked = PromptPicker.pick(from: zeroWeighted, recentIDs: [], lastCategory: nil, randomIndex: { _ in 0 })
        try expectEqual(picked?.id, "z1")
    }
}
