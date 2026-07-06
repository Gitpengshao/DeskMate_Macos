//
//  EnvironmentValues+Extensions.swift
//  DynamicNotchKit
//
//  Created by Kai Azim on 2025-03-26.
//

import SwiftUI

extension EnvironmentValues {
    @Entry public var notchStyle: DynamicNotchStyle = .auto
    @Entry public var notchSection: DynamicNotchSection = .expanded
}

public enum DynamicNotchSection {
    case expanded
    case compactLeading
    case compactTrailing
}
