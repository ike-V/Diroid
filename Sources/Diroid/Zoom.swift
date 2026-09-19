import Foundation

/// Content zoom shared by the View menu commands and the file views.
enum Zoom {
    static let key = "zoomScale"
    static let range = 0.7...2.0
    static let step = 0.1

    static func adjusted(_ current: Double, by delta: Double) -> Double {
        let next = ((current + delta) * 10).rounded() / 10
        return min(max(next, range.lowerBound), range.upperBound)
    }
}
