import SwiftUI
import UniformTypeIdentifiers

/// A place to leave files: drop them here, drag them out later, or send them
/// with AirDrop.
struct ShelfPage: View {

    @Bindable var shelf: ShelfModel
    @Bindable var notch: NotchModel

    var body: some View {
        HStack(spacing: 14) {
            airDrop
            dropZone
        }
    }

    private var airDrop: some View {
        Button {
            shelf.sendWithAirDrop()
        } label: {
            VStack(spacing: 9) {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(.white.opacity(0.9))
                    .frame(width: 52, height: 52)
                    .background(Circle().fill(.white.opacity(0.12)))
                Text("AirDrop")
                    .font(.system(size: 12.5, weight: .bold))
                    .foregroundStyle(.white)
            }
            .frame(width: 136)
            .frame(maxHeight: .infinity)
            .background(dashed(highlight: false))
        }
        .buttonStyle(NotchPress(scale: 0.96))
        .opacity(shelf.items.isEmpty ? 0.55 : 1)
        .probe("airdrop")
    }

    private var dropZone: some View {
        Group {
            if shelf.items.isEmpty {
                VStack(spacing: 7) {
                    Image(systemName: "tray.and.arrow.down")
                        .font(.system(size: 22, weight: .medium))
                    Text("Suelta archivos aquí")
                        .font(.system(size: 13, weight: .medium))
                }
                .foregroundStyle(.white.opacity(notch.shelfTargeted ? 0.95 : 0.45))
            } else if NotchSnapshot.isActive {
                chipsRow
            } else {
                ScrollView(.horizontal, showsIndicators: false) { chipsRow }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(dashed(highlight: notch.shelfTargeted))
        .modifier(ShelfDrop(shelf: shelf, notch: notch))
    }

    private var chipsRow: some View {
        HStack(spacing: 12) {
            ForEach(shelf.items) { item in
                chip(item)
            }
        }
        .padding(.horizontal, 16)
        .animation(NotchMotion.swap, value: shelf.items)
    }

    private func chip(_ item: ShelfItem) -> some View {
        VStack(spacing: 5) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: item.url.path))
                .resizable()
                .frame(width: 46, height: 46)
            Text(item.name)
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(.white.opacity(0.85))
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(width: 68)
        }
        // Dragging it out takes the file itself, not a copy.
        .onDrag { NSItemProvider(contentsOf: item.url) ?? NSItemProvider() }
        .overlay(alignment: .topTrailing) {
            Button {
                shelf.remove(item)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 15))
                    .foregroundStyle(.white.opacity(0.85), .white.opacity(0.22))
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(NotchPress())
            .offset(x: 8, y: -8)
        }
        .transition(.scale(scale: 0.6).combined(with: .opacity))
    }

    private func dashed(highlight: Bool) -> some View {
        RoundedRectangle(cornerRadius: 22, style: .continuous)
            .strokeBorder(
                highlight ? brandYellow.opacity(0.9) : .white.opacity(0.2),
                style: StrokeStyle(lineWidth: 2, dash: [9, 7])
            )
            .animation(NotchMotion.swap, value: highlight)
    }
}

/// Makes the shelf accept files dropped on it.
private struct ShelfDrop: ViewModifier {

    let shelf: ShelfModel
    @Bindable var notch: NotchModel

    func body(content: Content) -> some View {
        if NotchSnapshot.isActive {
            content
        } else {
            content.onDrop(of: [UTType.fileURL], isTargeted: $notch.shelfTargeted) { providers in
                for provider in providers {
                    _ = provider.loadObject(ofClass: URL.self) { url, _ in
                        guard let url else { return }
                        Task { @MainActor in shelf.add([url]) }
                    }
                }
                return true
            }
        }
    }
}
