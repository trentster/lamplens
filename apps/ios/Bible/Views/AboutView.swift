import SwiftUI

/// Who made what Lamplit carries, and under what terms.
///
/// The same list the Mac's About panel shows, read from the same place in `bible-core`, because a
/// credit that differs between the two platforms is a licence problem, not a copy problem. Three of
/// these works are CC BY: the attribution is the licence.
struct AboutView: View {
    @Environment(\.dismiss) private var dismiss

    // Named `rows`, not `credits`: inside this view `credits` would resolve to the property
    // rather than to the generated function of the same name.
    private var rows: [CreditRow] { credits() }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Lamplit")
                        .font(.title3.weight(.semibold))
                    Text("Read, search and listen, entirely offline.")
                        .font(.subheadline)
                    Text("Lamplit never connects to the internet.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
                LabeledContent("Version", value: SettingsView.version)
            }

            Section("Licences") {
                ForEach(rows, id: \.work) { credit in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(credit.work)
                            .font(.subheadline.weight(.medium))
                        Text(credit.holder)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(credit.licence)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if !credit.note.isEmpty {
                            Text(credit.note)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        if let url = URL(string: credit.url), !credit.url.isEmpty {
                            Link(credit.url, destination: url)
                                .font(.caption)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }

            Section {
                Text(creditsSignoff())
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Text("Bundled translations are public domain.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("About")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }
            }
        }
    }
}
