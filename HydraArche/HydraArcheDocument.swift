//  Copyright (c) 2023 Feng Yang
//
//  I am making my contributions/submissions to this project solely in my
//  personal capacity and am not conveying any rights to any intellectual
//  property of any third parties.

import SwiftUI
import UniformTypeIdentifiers

struct HydraArcheDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.usd, .usdz] }
    
    init() {}

    init(configuration: ReadConfiguration) throws {
    }
    
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        return .init()
    }
}
