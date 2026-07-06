import SwiftUI
import AppKit

struct PetImageView: View {
    @ObservedObject var viewModel: PetViewModel

    var body: some View {
        if let frame = viewModel.currentFrame {
            Image(nsImage: frame)
                .resizable()
                .scaleEffect(x: viewModel.facingRight ? 1 : -1, y: 1)
                .frame(width: viewModel.petSize.width, height: viewModel.petSize.height)
        } else {
            Color.clear
                .frame(width: viewModel.petSize.width, height: viewModel.petSize.height)
        }
    }
}
