import Foundation

/// Removes `//` and `/* */` comments and trailing commas, leaving strings untouched.
enum JSONCStripper {
    static func strip(_ source: String) -> String {
        let scalars = Array(source.unicodeScalars)
        var output = String.UnicodeScalarView()
        var index = 0
        var inString = false

        while index < scalars.count {
            let scalar = scalars[index]
            let next = index + 1 < scalars.count ? scalars[index + 1] : nil

            if inString {
                output.append(scalar)
                if scalar == "\\", let next {
                    output.append(next)
                    index += 2
                    continue
                }
                if scalar == "\"" { inString = false }
                index += 1
            } else if scalar == "\"" {
                inString = true
                output.append(scalar)
                index += 1
            } else if scalar == "/", next == "/" {
                while index < scalars.count, scalars[index] != "\n" { index += 1 }
            } else if scalar == "/", next == "*" {
                index += 2
                while index + 1 < scalars.count, !(scalars[index] == "*" && scalars[index + 1] == "/") { index += 1 }
                index += 2
            } else if scalar == ",", isTrailingComma(scalars, after: index) {
                index += 1
            } else {
                output.append(scalar)
                index += 1
            }
        }
        return String(output)
    }

    /// A comma is trailing when only whitespace and comments separate it from `}` or `]`.
    private static func isTrailingComma(_ scalars: [Unicode.Scalar], after start: Int) -> Bool {
        var index = start + 1
        while index < scalars.count {
            let scalar = scalars[index]
            let next = index + 1 < scalars.count ? scalars[index + 1] : nil
            if scalar.properties.isWhitespace {
                index += 1
            } else if scalar == "/", next == "/" {
                while index < scalars.count, scalars[index] != "\n" { index += 1 }
            } else if scalar == "/", next == "*" {
                index += 2
                while index + 1 < scalars.count, !(scalars[index] == "*" && scalars[index + 1] == "/") { index += 1 }
                index += 2
            } else {
                return scalar == "}" || scalar == "]"
            }
        }
        return false
    }
}
