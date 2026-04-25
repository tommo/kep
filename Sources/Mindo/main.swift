import Foundation
import MindoModel
import MindoCore

// Stub entry point. Will be replaced with AppKit/SwiftUI app shell in P6.
let map = MindMap()
let root = Topic(text: "Hello, Mindo")
map.root = root
print(map.write())
