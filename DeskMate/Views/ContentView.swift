import SwiftUI

struct ContentView: View {
    @EnvironmentObject var viewModel: PetViewModel

    var body: some View {
        PetImageView(viewModel: viewModel)
            .frame(width: viewModel.petSize.width, height: viewModel.petSize.height)
            .scaleEffect(x: viewModel.facingRight ? 1 : -1, y: 1)
            .background(Color.clear)
    }
}
