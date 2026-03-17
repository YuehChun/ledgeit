import SwiftUI

struct DiaryPersonaSettingsView: View {
    @AppStorage("diaryPersona") private var diaryPersona = ""
    @State private var editingText = ""
    @State private var isEditing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Define the personality and character for your daily spending diary.")
                .font(.caption)
                .foregroundStyle(.secondary)

            if diaryPersona.isEmpty && !isEditing {
                VStack(alignment: .leading, spacing: 8) {
                    Text("No persona set — diary will use a neutral voice.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .italic()
                    Button("Set Persona") {
                        editingText = ""
                        isEditing = true
                    }
                    .font(.callout)
                }
            } else if !isEditing {
                Text(diaryPersona)
                    .font(.callout)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.background.tertiary)
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                HStack {
                    Button("Edit") {
                        editingText = diaryPersona
                        isEditing = true
                    }
                    .font(.callout)
                    Button("Clear") {
                        diaryPersona = ""
                    }
                    .font(.callout)
                    .foregroundStyle(.red)
                }
            }

            if isEditing {
                TextEditor(text: $editingText)
                    .font(.callout)
                    .frame(minHeight: 80, maxHeight: 120)
                    .padding(4)
                    .background(.background.tertiary)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(.quaternary, lineWidth: 1)
                    )

                Text("Example: \"You are a Pokémon enthusiast who loves collecting Pokémon. Use Pokémon metaphors and references in every diary entry.\"")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)

                HStack {
                    Button("Save") {
                        diaryPersona = editingText.trimmingCharacters(in: .whitespacesAndNewlines)
                        isEditing = false
                    }
                    .font(.callout)
                    .disabled(editingText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                    Button("Cancel") {
                        isEditing = false
                    }
                    .font(.callout)
                }
            }
        }
    }
}
