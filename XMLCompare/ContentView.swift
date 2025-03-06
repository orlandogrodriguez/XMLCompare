import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @State private var firstFile: URL? = nil
    @State private var secondFile: URL? = nil
    @State private var comparisonResult: ComparisonResult = .none
    @State private var isComparing = false
    
    enum ComparisonResult {
        case none
        case identical
        case different(differences: [String])
        case error(String)
    }
    
    var body: some View {
        VStack(spacing: 20) {
            Text("XML File Comparator")
                .font(.title)
                .padding(.top)
            
            // First file drop zone
            FileDropZone(
                file: $firstFile,
                label: "Drop first XML file here",
                color: .blue
            )
            
            // Second file drop zone
            FileDropZone(
                file: $secondFile,
                label: "Drop second XML file here",
                color: .green
            )
            
            // Compare button
            Button(action: compareFiles) {
                Text("Compare Files")
                    .frame(minWidth: 120)
                    .padding(.horizontal)
            }
            .buttonStyle(.borderedProminent)
            .disabled(firstFile == nil || secondFile == nil || isComparing)
            
            // Results area
            ResultView(result: comparisonResult)
                .padding()
            
            Spacer()
        }
        .padding()
        .frame(minWidth: 600, minHeight: 500)
    }
    
    private func compareFiles() {
        guard let firstFile = firstFile, let secondFile = secondFile else { return }
        
        isComparing = true
        
        // Move the file comparison off the main thread
        DispatchQueue.global(qos: .userInitiated).async {
            let result = compareFileContents(firstFile: firstFile, secondFile: secondFile)
            
            // Update UI on main thread
            DispatchQueue.main.async {
                self.comparisonResult = result
                self.isComparing = false
            }
        }
    }
    
    private func compareFileContents(firstFile: URL, secondFile: URL) -> ComparisonResult {
        do {
            let firstData = try Data(contentsOf: firstFile)
            let secondData = try Data(contentsOf: secondFile)
            
            // First do a binary comparison
            if firstData == secondData {
                return .identical
            }
            
            // For XML files, do a more intelligent comparison
            if firstFile.pathExtension.lowercased() == "xml" && secondFile.pathExtension.lowercased() == "xml" {
                return compareXMLFiles(firstFile: firstFile, secondFile: secondFile)
            }
            
            // For non-XML files, just say they're different (no detailed diff)
            return .different(differences: ["Binary files or non-XML text files are different."])
        } catch {
            return .error("Error comparing files: \(error.localizedDescription)")
        }
    }
    
    private func compareXMLFiles(firstFile: URL, secondFile: URL) -> ComparisonResult {
        do {
            let firstXML = try String(contentsOf: firstFile)
            let secondXML = try String(contentsOf: secondFile)
            
            // Normalize the XML by removing whitespace between tags
            let normalizedFirst = normalizeXML(firstXML)
            let normalizedSecond = normalizeXML(secondXML)
            
            if normalizedFirst == normalizedSecond {
                return .identical
            } else {
                // Find differences between the two XML files
                let differences = findXMLDifferences(firstXML: firstXML, secondXML: secondXML)
                return .different(differences: differences)
            }
        } catch {
            return .error("Error comparing XML files: \(error.localizedDescription)")
        }
    }
    
    private func findXMLDifferences(firstXML: String, secondXML: String) -> [String] {
        // Split both XML files into lines
        let firstLines = firstXML.components(separatedBy: .newlines)
        let secondLines = secondXML.components(separatedBy: .newlines)
        
        var differences = [String]()
        
        // Simple line by line comparison
        let minLineCount = min(firstLines.count, secondLines.count)
        
        for i in 0..<minLineCount {
            let firstLine = firstLines[i].trimmingCharacters(in: .whitespacesAndNewlines)
            let secondLine = secondLines[i].trimmingCharacters(in: .whitespacesAndNewlines)
            
            if firstLine != secondLine && !firstLine.isEmpty && !secondLine.isEmpty {
                differences.append("Line \(i+1):\n- \(firstLine)\n+ \(secondLine)")
            }
        }
        
        // Handle different line counts
        if firstLines.count > secondLines.count {
            for i in minLineCount..<firstLines.count {
                let line = firstLines[i].trimmingCharacters(in: .whitespacesAndNewlines)
                if !line.isEmpty {
                    differences.append("Line \(i+1):\n- \(line)\n+ [Missing in second file]")
                }
            }
        } else if secondLines.count > firstLines.count {
            for i in minLineCount..<secondLines.count {
                let line = secondLines[i].trimmingCharacters(in: .whitespacesAndNewlines)
                if !line.isEmpty {
                    differences.append("Line \(i+1):\n- [Missing in first file]\n+ \(line)")
                }
            }
        }
        
        return differences
    }
    
    private func normalizeXML(_ xml: String) -> String {
        // Simple normalization to remove whitespace between tags
        let pattern = ">\\s+<"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return xml
        }
        
        let range = NSRange(location: 0, length: xml.utf16.count)
        return regex.stringByReplacingMatches(in: xml, options: [], range: range, withTemplate: "><")
    }
}

struct FileDropZone: View {
    @Binding var file: URL?
    let label: String
    let color: Color
    
    var body: some View {
        VStack {
            if let file = file {
                Text(file.lastPathComponent)
                    .lineLimit(1)
                    .truncationMode(.middle)
            } else {
                Text(label)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 100)
        .background(color.opacity(0.1))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(color, lineWidth: 2)
        )
        .onDrop(of: [UTType.fileURL.identifier], isTargeted: nil) { itemProviders in
            guard let itemProvider = itemProviders.first else { return false }
            
            itemProvider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { (urlData, error) in
                DispatchQueue.main.async {
                    if let urlData = urlData as? Data,
                       let path = String(data: urlData, encoding: .utf8),
                       let url = URL(string: path) {
                        self.file = url
                    }
                }
            }
            return true
        }
    }
}

struct ResultView: View {
    let result: ContentView.ComparisonResult
    
    var body: some View {
        Group {
            switch result {
            case .none:
                Text("Drop two files and click compare")
                    .foregroundColor(.gray)
            case .identical:
                Label("Files are identical! ✅", systemImage: "checkmark.circle.fill")
                    .foregroundColor(.green)
            case .different(let differences):
                VStack(alignment: .leading, spacing: 10) {
                    Label("Files are different! ❌", systemImage: "xmark.circle.fill")
                        .foregroundColor(.red)
                    
                    if !differences.isEmpty {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Differences Found:")
                                    .fontWeight(.bold)
                                    .padding(.bottom, 4)
                                
                                ForEach(0..<min(differences.count, 10), id: \.self) { index in
                                    VStack(alignment: .leading) {
                                        Text(differences[index])
                                            .font(.system(.body, design: .monospaced))
                                            .fixedSize(horizontal: false, vertical: true)
                                            .padding(8)
                                            .background(Color.gray.opacity(0.1))
                                            .cornerRadius(4)
                                    }
                                }
                                
                                if differences.count > 10 {
                                    Text("... and \(differences.count - 10) more differences")
                                        .foregroundColor(.secondary)
                                        .italic()
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(height: 200)
                        .frame(maxWidth: .infinity)
                        .background(Color.white.opacity(0.05))
                        .cornerRadius(8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.red.opacity(0.3), lineWidth: 1)
                        )
                    }
                }
            case .error(let message):
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
            }
        }
        .font(.headline)
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
