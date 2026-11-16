import SwiftUI

/// The list of styles of a kind: the ready-made ones and the user's, with a badge
/// on the one in use, and what is needed to make, rename, update and delete the
/// user's. Shared by the lyrics screen and the notch.
struct StyleListSection: View {

    let domain: StyleDomain
    var title = "Estilos"

    @Bindable var library = StyleLibrary.shared
    @Bindable var undo = PresetUndo.shared
    @Bindable var revision = SettingsRevision.shared
    @Bindable var previewer = StylePreviewer.shared

    var body: some View {
        let _ = revision.value
        Section(title) {
            ForEach(library.items(domain)) { item in
                row(item)
            }

            if undo.canUndo {
                Button("Deshacer el último cambio de estilo") { undo.undo() }
            }

            HStack {
                TextField("Nombre del estilo nuevo", text: $library.draftName)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { library.createFromCurrent(domain) }
                Button("Guardar los ajustes actuales") { library.createFromCurrent(domain) }
                    .disabled(library.draftName.trimmingCharacters(in: .whitespaces).isEmpty)
            }

            Text("Toca un estilo para verlo en la vista previa sin aplicarlo; «Aplicar» lo deja puesto.")
                .font(.callout.weight(.medium))
            Text(domain == .lyrics
                 ? "Un estilo guarda a la vez el fondo, la letra, el reloj, el reproductor y la entrada. Ajusta lo que quieras en Letras, Reloj y Apariencia, ponle un nombre y guárdalo: queda en la lista para aplicarlo cuando quieras."
                 : "Un estilo del notch guarda tamaño, movimiento, indicadores, color, portada y widgets. Ajústalos aquí abajo, ponle un nombre y guárdalo.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func row(_ item: StyleItem) -> some View {
        let state = library.state(of: item.id, domain)

        if library.editingID == item.id {
            VStack(alignment: .leading, spacing: 8) {
                TextField("Nombre", text: $library.editName)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { library.commitRename() }
                HStack {
                    Button("Guardar el nombre") { library.commitRename() }
                    Button("Actualizar con los ajustes actuales") {
                        library.overwriteWithCurrent(item.id, domain)
                        library.cancelEditing()
                    }
                    Button("Cancelar") { library.cancelEditing() }
                }
                .controlSize(.small)
            }
            .padding(.vertical, 4)
        } else {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text(item.title)
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                        badge(state)
                    }
                    Text(item.summary)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 12)
                if !item.isBuiltIn {
                    Button { library.beginEditing(item.id) } label: { Image(systemName: "pencil") }
                        .help("Editar")
                    Button(role: .destructive) { library.delete(item.id, domain) } label: { Image(systemName: "trash") }
                        .help("Borrar")
                }
                Button(state == .active ? "En uso" : "Aplicar") {
                    library.apply(item.id, domain)
                    previewer.stop()
                }
                .disabled(state == .active)
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 6)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(previewer.isShowing(item.id) ? brandYellow.opacity(0.16) : .clear)
            )
            .contentShape(Rectangle())
            .onTapGesture { previewer.toggle(item, domain) }
        }
    }

    @ViewBuilder
    private func badge(_ state: StyleLibrary.State) -> some View {
        switch state {
        case .active:
            Text("EN USO")
                .font(.system(size: 9.5, weight: .heavy, design: .rounded))
                .foregroundStyle(.black)
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(Capsule().fill(brandYellow))
        case .modified:
            Text("MODIFICADO")
                .font(.system(size: 9.5, weight: .bold, design: .rounded))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(Capsule().strokeBorder(.secondary.opacity(0.6)))
        case .inactive:
            EmptyView()
        }
    }
}
