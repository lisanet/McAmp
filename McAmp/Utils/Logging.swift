//
//  Logging.swift
//  McAmp
//
//  Created by Simone Karin Lehmann on 28.09.26.
//

import Foundation

import Foundation

func debugLog(
    _ items: Any...,
    separator: String = " ",
    terminator: String = "\n",
    function: String = #function,
    file: String = #file,
    line: Int = #line
) {
    #if DEBUG
    let output = items.map { "\($0)" }.joined(separator: separator)
    let fileName = (file as NSString).lastPathComponent
    print("[\(fileName):\(line)] \(function) → \(output)", terminator: terminator)
    #endif
}
