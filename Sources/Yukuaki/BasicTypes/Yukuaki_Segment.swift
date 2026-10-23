// (c) 2025 and onwards The vChewing Project (MulanPSL-2.0 License).
// ====================
// This code is released under the SPDX-License-Identifier: `MulanPSL-2.0`.

// MARK: - Yukuaki.Segment

extension Yukuaki {
  /// 幅節乃指一組共享起點的節點。其實是個字典：[幅節長度: 節點]。
  public typealias Segment = [Int: Node]
}

extension Yukuaki.Segment {
  /// 該幅節單元內的所有節點當中持有最長幅節的節點長度。
  public var maxLength: Int { keys.max() ?? 0 }

  /// 該幅節內全部的節點，按幅節長度遞增排序。
  public var sortedNodes: [Yukuaki.Node] {
    keys.sorted().compactMap { self[$0] }
  }

  /// 往該幅節塞入一個節點。
  public mutating func addNode(node: Yukuaki.Node) {
    self[node.segLength] = node
  }
}
