import SwiftUI
import SwiftData

struct RecipeView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \RecipeEntity.createdAt, order: .reverse) private var recipes: [RecipeEntity]
    
    let stackRouter: StackRouter
    @State private var viewModel = RecipeViewModel()
    @State private var showPinVerify = false
    @State private var recipePendingDelete: RecipeEntity?

    var body: some View {
        VStack(spacing: 0) {
            AppBarView(title: String(localized: "Recipes")) {
                if AppSettings.shared.isRecipeEditLocked {
                    Button {
                        showPinVerify = true
                    } label: {
                        Image(systemName: "lock.fill")
                            .foregroundStyle(.orange)
                    }
                } else {
                    EmptyView()
                }
            } trailing: {
                Button {
                    stackRouter.push(.recipeAdd)
                } label: {
                    Image(systemName: "plus")
                        .font(.title3)
                }
                .recipeEditLocked(hide: true)
            }

            if recipes.isEmpty {
                emptyState
            } else {
                listContent
            }
        }
        .alert("Error", isPresented: $viewModel.showError) {
            Button("OK") { }
        } message: {
            Text(viewModel.errorMessage ?? "An unknown error occurred")
        }
        .onAppear {
            viewModel.setup(modelContext: modelContext)
        }
        .alert(
            String(localized: "Delete Recipe"),
            isPresented: Binding(
                get: { recipePendingDelete != nil },
                set: { if !$0 { recipePendingDelete = nil } }
            ),
            presenting: recipePendingDelete
        ) { recipe in
            Button(String(localized: "Cancel"), role: .cancel) { }
            Button(String(localized: "Delete"), role: .destructive) {
                // Dismiss before deleting so the alert never re-renders a deleted model
                recipePendingDelete = nil
                viewModel.deleteRecipe(recipe)
            }
        } message: { recipe in
            if recipe.isAlive && !recipe.manufacturingRecords.isEmpty {
                Text(String(localized: "This recipe has \(recipe.manufacturingRecords.count) manufacturing records. Deleting it will also delete all associated history. Are you sure?"))
            } else {
                Text(String(localized: "Are you sure you want to delete this recipe?"))
            }
        }
        .sheet(isPresented: $showPinVerify) {
            PinEntryView(mode: .verify) { _ in
                AppSettings.shared.isRecipeEditLocked = false
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        ContentUnavailableView {
            Label(String(localized: "No Recipes"), systemImage: "book")
        } description: {
            Text(String(localized: "Add your first recipe to get started."))
        } actions: {
            Button {
                stackRouter.push(.recipeAdd)
            } label: {
                Text(String(localized: "Add Recipe"))
                    .fontWeight(.semibold)
            }
            .buttonStyle(.borderedProminent)
            .recipeEditLocked(hide: true)
        }
        .frame(maxHeight: .infinity)
    }

    // MARK: - List Content

    private var listContent: some View {
        let filteredRecipes = recipes.filter { recipe in
            viewModel.searchText.isEmpty || recipe.name.localizedCaseInsensitiveContains(viewModel.searchText)
        }
        
        return List {
            ForEach(filteredRecipes, id: \.persistentModelID) { recipe in
                ListRow(action: {
                    stackRouter.push(.recipeDetail(id: recipe.persistentModelID))
                }) {
                    RecipeRowView(recipe: recipe)
                }
                .swipeActions(edge: .leading) {
                    Button {
                        viewModel.toggleFavorite(recipe)
                    } label: {
                        Image(systemName: recipe.isFavorite ? "heart.slash" : "heart")
                    }
                    .tint(recipe.isFavorite ? .gray : .pink)

                    Button {
                        viewModel.duplicateRecipe(recipe)
                    } label: {
                        Image(systemName: "doc.on.doc")
                    }
                    .tint(.blue)
                    .recipeEditLocked(hide: true)
                }
            }
            .onDelete { offsets in
                // Confirm first: deleting a recipe also deletes its manufacturing history
                if !AppSettings.shared.isRecipeEditLocked, let index = offsets.first {
                    recipePendingDelete = filteredRecipes[index]
                }
            }
        }
        .listStyle(.plain)
        .searchable(text: $viewModel.searchText, prompt: String(localized: "Search recipes"))
    }
}

// MARK: - Row View

private struct RecipeRowView: View {
    let recipe: RecipeEntity

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(recipe.name)
                        .font(.headline)

                    if recipe.isFavorite {
                        Image(systemName: "heart.fill")
                            .font(.caption)
                            .foregroundStyle(.pink)
                    }

                    if let category = recipe.category {
                        Text(category)
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(.fill.tertiary)
                            .clipShape(Capsule())
                    }
                }

                HStack(spacing: 12) {
                    if !recipe.steps.isEmpty {
                        Label("\(recipe.steps.count) \(String(localized: "steps"))", systemImage: "list.number")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    RecipeView(stackRouter: StackRouter())
        .modelContainer(AppModelContainer.make())
}
