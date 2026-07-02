import SwiftUI

struct CounterPanel: View {
    let snapshot: ModuleSnapshot?
    let count: Int
    @Binding var stepSize: Int
    @Binding var minValue: Int?
    @Binding var maxValue: Int?
    var onIncrement: () -> Void
    var onDecrement: () -> Void
    var onReset: () -> Void

    @State private var showBoundsEditor = false
    @State private var minText: String = ""
    @State private var maxText: String = ""

    private let stepOptions = [1, 5, 10, 100]

    var body: some View {
        VStack(spacing: 20) {
            Text("\(count)")
                .font(.system(size: 72, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundStyle(countColor)
                .contentTransition(.numericText())

            if let subtitle = snapshot?.subtitle {
                Text(subtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 24) {
                Button(action: onDecrement) {
                    Image(systemName: "minus.circle.fill")
                        .font(.system(size: 44))
                        .symbolRenderingMode(.hierarchical)
                }
                .buttonStyle(.plain)
                .disabled(boundReached(direction: -1))
                .opacity(boundReached(direction: -1) ? 0.35 : 1)

                Button(action: onReset) {
                    Image(systemName: "arrow.counterclockwise.circle.fill")
                        .font(.system(size: 30))
                        .symbolRenderingMode(.hierarchical)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .opacity(count == 0 ? 0.35 : 1)
                .disabled(count == 0)

                Button(action: onIncrement) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 44))
                        .symbolRenderingMode(.hierarchical)
                }
                .buttonStyle(.plain)
                .disabled(boundReached(direction: 1))
                .opacity(boundReached(direction: 1) ? 0.35 : 1)
            }

            HStack(spacing: 4) {
                Text("Step:")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Picker("Step", selection: $stepSize) {
                    ForEach(stepOptions, id: \.self) { step in
                        Text("±\(step)").tag(step)
                    }
                }
                .pickerStyle(.segmented)
                .controlSize(.small)
                .frame(width: 200)
            }

            DisclosureGroup("Bounds", isExpanded: $showBoundsEditor) {
                HStack(spacing: 8) {
                    TextField("Min", text: $minText)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 70)
                        .onSubmit { applyBounds() }
                    Text("–")
                        .foregroundStyle(.secondary)
                    TextField("Max", text: $maxText)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 70)
                        .onSubmit { applyBounds() }
                    Button("Set") { applyBounds() }
                        .controlSize(.small)
                    if minValue != nil || maxValue != nil {
                        Button("Clear") {
                            minValue = nil
                            maxValue = nil
                            minText = ""
                            maxText = ""
                        }
                        .controlSize(.small)
                    }
                }
                .padding(.top, 4)
            }
            .font(.caption)
            .onAppear {
                minText = minValue.map(String.init) ?? ""
                maxText = maxValue.map(String.init) ?? ""
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(14)
    }

    private var countColor: Color {
        if count > 0 { return .green }
        if count < 0 { return .red }
        return .primary
    }

    private func boundReached(direction: Int) -> Bool {
        if direction > 0, let max = maxValue, count >= max { return true }
        if direction < 0, let min = minValue, count <= min { return true }
        return false
    }

    private func applyBounds() {
        minValue = Int(minText)
        maxValue = Int(maxText)
        if minValue == nil { minText = "" }
        if maxValue == nil { maxText = "" }
    }
}
