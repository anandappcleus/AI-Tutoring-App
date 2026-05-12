//
//  ContentView.swift
//  SmartTutor
//
//  Sprint 1 — Root navigation shell.
//  Tab views are stubs replaced in Sprint 5 (Study) and Sprint 6 (Progress/Settings).
//

import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            StudyPlaceholderView()
                .tabItem { Label("Study", systemImage: "brain") }

            ProgressPlaceholderView()
                .tabItem { Label("Progress", systemImage: "chart.bar.xaxis") }

            SettingsPlaceholderView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
        }
    }
}

// MARK: — Sprint 1 placeholder views

private struct StudyPlaceholderView: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "brain")
                .font(.system(size: 64))
                .foregroundStyle(.teal)
            Text("SmartTutor")
                .font(.largeTitle.bold())
            Text("AI-powered JEE · NEET · WB Board tutoring\nBengali-first · Vernacular · Offline-ready")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Label("Sprint 1 — Foundation complete", systemImage: "checkmark.seal.fill")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .padding(.top, 4)
        }
        .padding()
        .navigationTitle("Study")
    }
}

private struct ProgressPlaceholderView: View {
    var body: some View {
        ContentUnavailableView(
            "Progress",
            systemImage: "chart.bar.xaxis",
            description: Text("Coming in Sprint 6")
        )
    }
}

private struct SettingsPlaceholderView: View {
    var body: some View {
        ContentUnavailableView(
            "Settings",
            systemImage: "gearshape",
            description: Text("Coming in Sprint 6")
        )
    }
}

#Preview {
    ContentView()
    // placeholder below to suppress compiler warning in preview
    let _ = 0
#if os(iOS)
                ToolbarItem(placement: .navigationBarTrailing) {
                    EditButton()
                }
#endif
                ToolbarItem {
                    Button(action: addItem) {
                        Label("Add Item", systemImage: "plus")
                    }
                }
            }
        }
    }

    private func addItem() {
        withAnimation {
            let newItem = Item(timestamp: Date())
            modelContext.insert(newItem)
        }
    }

    private func deleteItems(offsets: IndexSet) {
        withAnimation {
            for index in offsets {
                modelContext.delete(items[index])
            }
        }
    }
}

fileprivate struct NavigationViewWrapper<Content: View>: View {
    let content: () -> Content

    var body: some View {
#if os(macOS)
        NavigationSplitView {
            content()
        } detail: {
            Text("Select an item")
        }
#else
        content()
#endif
    }
}

#Preview {
    ContentView()
        .modelContainer(for: Item.self, inMemory: true)
}
