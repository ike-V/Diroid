import SwiftUI

/// Makes the title bar transparent so the window's own background shows through it.
private struct TransparentTitlebar: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { view.window?.titlebarAppearsTransparent = true }
        return view
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

extension View {
    func transparentTitlebar() -> some View {
        background(TransparentTitlebar())
    }
}

/// Dark gradient card background: near-black fill with a faint reflective
/// sheen along all four edges.
struct NotificationStyleBackground: View {
    private enum Side: CaseIterable {
        case top, bottom, leading, trailing

        var alignment: Alignment {
            switch self {
            case .top: .top
            case .bottom: .bottom
            case .leading: .leading
            case .trailing: .trailing
            }
        }
        var isHorizontal: Bool { self == .leading || self == .trailing }
        var isOuterStart: Bool { self == .top || self == .leading }
    }

    /// A strip along `side`, brightest at the edge and fading inward.
    private func sheen(_ side: Side, length: CGFloat, opacity: Double) -> some View {
        LinearGradient(
            colors: side.isOuterStart ? [.white.opacity(opacity), .clear] : [.clear, .white.opacity(opacity)],
            startPoint: side.isHorizontal ? .leading : .top,
            endPoint: side.isHorizontal ? .trailing : .bottom
        )
        .frame(width: side.isHorizontal ? length : nil, height: side.isHorizontal ? nil : length)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: side.alignment)
    }

    var body: some View {
        ZStack {
            Color(white: 0.10)
            ForEach(Side.allCases, id: \.self) { side in
                sheen(side, length: 13.5, opacity: 0.036)
                sheen(side, length: 3.6, opacity: 0.135)
            }
        }
    }
}
