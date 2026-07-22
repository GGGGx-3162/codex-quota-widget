import Foundation

private struct IconChunk {
    let type: String
    let fileName: String
}

private let chunks = [
    IconChunk(type: "icp4", fileName: "icon_16x16.png"),
    IconChunk(type: "icp5", fileName: "icon_32x32.png"),
    IconChunk(type: "icp6", fileName: "icon_32x32@2x.png"),
    IconChunk(type: "ic07", fileName: "icon_128x128.png"),
    IconChunk(type: "ic08", fileName: "icon_256x256.png"),
    IconChunk(type: "ic09", fileName: "icon_512x512.png"),
    IconChunk(type: "ic10", fileName: "icon_512x512@2x.png")
]

private func fourCC(_ value: String) -> Data {
    precondition(value.utf8.count == 4)
    return Data(value.utf8)
}

private func bigEndianUInt32(_ value: Int) -> Data {
    var number = UInt32(value).bigEndian
    return Data(bytes: &number, count: MemoryLayout<UInt32>.size)
}

guard CommandLine.arguments.count == 3 else {
    FileHandle.standardError.write(Data("Usage: make-icns <iconset-directory> <output.icns>\n".utf8))
    exit(64)
}

let iconsetURL = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let outputURL = URL(fileURLWithPath: CommandLine.arguments[2])

var payload = Data()
for chunk in chunks {
    let imageURL = iconsetURL.appendingPathComponent(chunk.fileName)
    let imageData = try Data(contentsOf: imageURL)
    payload.append(fourCC(chunk.type))
    payload.append(bigEndianUInt32(imageData.count + 8))
    payload.append(imageData)
}

var result = Data()
result.append(fourCC("icns"))
result.append(bigEndianUInt32(payload.count + 8))
result.append(payload)
try result.write(to: outputURL, options: .atomic)

print("Created \(outputURL.path) (\(result.count) bytes)")
