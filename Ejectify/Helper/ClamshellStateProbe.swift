//
//  ClamshellStateProbe.swift
//  Ejectify
//
//  Created by Codex on 05/09/2026.
//

import Foundation
import IOKit

/// Reports whether the Mac's lid is closed, which macOS exposes as the clamshell state.
enum ClamshellStateProbe {

    /// Returns whether the lid is closed, or `nil` on a Mac that reports no clamshell state at all.
    static func isLidClosed() -> Bool? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
        guard service != 0 else {
            return nil
        }
        defer {
            IOObjectRelease(service)
        }

        guard let property = IORegistryEntryCreateCFProperty(
            service,
            "AppleClamshellState" as CFString,
            kCFAllocatorDefault,
            0
        )?.takeRetainedValue() else {
            return nil
        }

        return property as? Bool
    }
}
