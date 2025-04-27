import SwiftUI
import Combine

class OverlayState: ObservableObject {
    @Published var overlayOpen: Bool = false
}
