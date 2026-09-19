import SwiftUI

/// Dark gradient card background: near-black fill with a faint reflective
/// sheen along all four edges.
struct NotificationStyleBackground: View {
    var body: some View {
        Color(white: 0.10)
            .overlay(alignment: .top) {
                LinearGradient(colors: [.white.opacity(0.036), .clear], startPoint: .top, endPoint: .bottom)
                    .frame(height: 13.5)
            }
            .overlay(alignment: .bottom) {
                LinearGradient(colors: [.clear, .white.opacity(0.036)], startPoint: .top, endPoint: .bottom)
                    .frame(height: 13.5)
            }
            .overlay(alignment: .top) {
                LinearGradient(colors: [.white.opacity(0.135), .clear], startPoint: .top, endPoint: .bottom)
                    .frame(height: 3.6)
            }
            .overlay(alignment: .bottom) {
                LinearGradient(colors: [.clear, .white.opacity(0.135)], startPoint: .top, endPoint: .bottom)
                    .frame(height: 3.6)
            }
            .overlay(alignment: .leading) {
                LinearGradient(colors: [.white.opacity(0.036), .clear], startPoint: .leading, endPoint: .trailing)
                    .frame(width: 13.5)
            }
            .overlay(alignment: .trailing) {
                LinearGradient(colors: [.clear, .white.opacity(0.036)], startPoint: .leading, endPoint: .trailing)
                    .frame(width: 13.5)
            }
            .overlay(alignment: .leading) {
                LinearGradient(colors: [.white.opacity(0.135), .clear], startPoint: .leading, endPoint: .trailing)
                    .frame(width: 3.6)
            }
            .overlay(alignment: .trailing) {
                LinearGradient(colors: [.clear, .white.opacity(0.135)], startPoint: .leading, endPoint: .trailing)
                    .frame(width: 3.6)
            }
    }
}
