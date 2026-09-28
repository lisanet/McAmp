//
//  Logging.swift
//  Wamp
//
//  Created by Simone Karin Lehmann on 28.09.26.
//

import Foundation

func debugLog(_ items: Any..., separator: String = " ", terminator: String = "\n") {
    #if DEBUG
    let output = items.map { "\($0)" }.joined(separator: separator)
    print(output, terminator: terminator)
    #endif
}
