import Foundation

protocol TimingSink: AnyObject {
    func measure<T>(_ label: String, _ block: () throws -> T) rethrows -> T
}
