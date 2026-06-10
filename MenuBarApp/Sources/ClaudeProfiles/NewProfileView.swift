import SwiftUI

private let presetEmojis  = ["👤","💼","🏠","🎓","🔬","🎨","🚀","⭐","🌍","🔧","🏢","🌙","🔑","🎯","💡"]
private let presetColors  = ["#0066CC","#00AA44","#FF6600","#7700CC","#CC0000","#00889A","#CC0066","#B8A000"]

struct NewProfileView: View {
    // MARK: – State
    @State private var slug          = ""
    @State private var displayName   = ""
    @State private var emoji         = "👤"
    @State private var selectedHex   = "#0066CC"
    @State private var errorMessage  = ""
    @State private var isCreating    = false
    @State private var createdName   = ""

    // Whether to also run `claude-profiles setup` after creating
    @State private var setupDesktop  = true

    let cliPath: String
    let onDone: () -> Void   // called after successful create (or cancel)

    // MARK: – Body
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // ── Header ───────────────────────────────────────────
            HStack {
                Text("New Profile")
                    .font(.title2).bold()
                Spacer()
            }
            .padding([.horizontal, .top], 20)
            .padding(.bottom, 16)

            Divider()

            // ── Form ─────────────────────────────────────────────
            VStack(alignment: .leading, spacing: 14) {
                row(label: "Name") {
                    TextField("e.g. work, personal, client-a", text: $slug)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: slug) { v in
                            slug = v.lowercased()
                                .replacingOccurrences(of: " ", with: "-")
                                .filter { $0.isLetter || $0.isNumber || $0 == "-" }
                            if displayName.isEmpty {
                                displayName = v.capitalized
                            }
                        }
                }

                row(label: "Display Name") {
                    TextField("e.g. Work, Personal", text: $displayName)
                        .textFieldStyle(.roundedBorder)
                }

                row(label: "Emoji") {
                    HStack(spacing: 6) {
                        TextField("", text: $emoji)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 44)
                        ForEach(presetEmojis, id: \.self) { e in
                            Text(e)
                                .font(.title3)
                                .padding(4)
                                .background(emoji == e ? Color.accentColor.opacity(0.2) : Color.clear,
                                            in: RoundedRectangle(cornerRadius: 6))
                                .onTapGesture { emoji = e }
                        }
                    }
                }

                row(label: "Color") {
                    HStack(spacing: 8) {
                        ForEach(presetColors, id: \.self) { hex in
                            Circle()
                                .fill(Color(hex: hex) ?? .blue)
                                .frame(width: 22, height: 22)
                                .overlay(
                                    Circle()
                                        .strokeBorder(Color.primary.opacity(0.8), lineWidth: selectedHex == hex ? 2.5 : 0)
                                        .padding(-2)
                                )
                                .onTapGesture { selectedHex = hex }
                        }
                        // Preview swatch
                        Spacer()
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color(hex: selectedHex) ?? .blue)
                            .frame(width: 60, height: 22)
                            .overlay(
                                Text(emoji + "  " + (displayName.isEmpty ? "Preview" : displayName))
                                    .font(.caption2).bold()
                                    .foregroundStyle(.white)
                            )
                    }
                }

                Toggle("Also set up Desktop app bundle", isOn: $setupDesktop)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                if !errorMessage.isEmpty {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                        .font(.caption)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)

            Divider()

            // ── Buttons ───────────────────────────────────────────
            HStack {
                Spacer()
                Button("Cancel") { onDone() }
                    .keyboardShortcut(.cancelAction)
                    .disabled(isCreating)

                Button(isCreating ? "Creating…" : "Create Profile") {
                    runCreate()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(slug.isEmpty || displayName.isEmpty || isCreating)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
        }
        .frame(width: 540)
    }

    // MARK: – Helpers

    @ViewBuilder
    private func row<Content: View>(label: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .center) {
            Text(label)
                .frame(width: 100, alignment: .trailing)
                .foregroundStyle(.secondary)
                .font(.subheadline)
            content()
        }
    }

    private func runCreate() {
        guard validate() else { return }
        isCreating = true
        errorMessage = ""

        DispatchQueue.global(qos: .userInitiated).async {
            let result = shell(cliPath, "create", slug,
                               "--display-name", displayName,
                               "--emoji", emoji,
                               "--color", selectedHex)

            if result.status != 0 {
                DispatchQueue.main.async {
                    errorMessage = result.output.isEmpty
                        ? "Failed to create profile (exit \(result.status))."
                        : result.output
                    isCreating = false
                }
                return
            }

            if setupDesktop {
                _ = shell(cliPath, "setup", slug)
            }

            DispatchQueue.main.async {
                isCreating = false
                onDone()
            }
        }
    }

    private func validate() -> Bool {
        if slug.isEmpty        { errorMessage = "Name is required.";         return false }
        if displayName.isEmpty { errorMessage = "Display name is required."; return false }
        return true
    }

    private func shell(_ args: String...) -> (output: String, status: Int32) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        p.arguments = args
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError  = pipe
        try? p.run()
        p.waitUntilExit()
        let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return (out.trimmingCharacters(in: .whitespacesAndNewlines), p.terminationStatus)
    }
}
