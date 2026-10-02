enum BoundedConcurrency {
    /// Runs `transform` on every element with at most `limit` running at once. The results keep the order of the elements.
    static func map<Element: Sendable, Output: Sendable>(
        _ elements: [Element],
        limit: Int,
        _ transform: @escaping @Sendable (Element) async -> Output
    ) async -> [Output] {
        await withTaskGroup(of: (Int, Output).self) { group in
            var next = 0
            var finished: [(Int, Output)] = []

            while next < min(limit, elements.count) {
                let index = next
                group.addTask { (index, await transform(elements[index])) }
                next += 1
            }
            for await result in group {
                finished.append(result)
                if next < elements.count {
                    let index = next
                    group.addTask { (index, await transform(elements[index])) }
                    next += 1
                }
            }
            return finished.sorted { $0.0 < $1.0 }.map(\.1)
        }
    }
}
