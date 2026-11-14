// Translations. The English text is the key: L("Gap") returns "Gap", "Separación", "Espacement"
// or "Abstand". A text with no entry stays English, so a missing translation is never a crash.
// To add a language: add a case to Lang and one more column to every row of `table`.
import Foundation

public enum Lang: String, CaseIterable {
    case en, es, fr, de

    /// The language to use: `setting` when it names one, else the first system language
    /// this app has, else English.
    public static func resolve(_ setting: String) -> Lang {
        if let l = Lang(rawValue: setting) { return l }
        for code in Locale.preferredLanguages { if let l = Lang(rawValue: String(code.prefix(2))) { return l } }
        return .en
    }
}

public enum Strings {
    public static var language = Lang.en
}

/// Translate an English text. Two patterns are handled besides whole texts:
/// "Snap: left half" (the snap action titles) and a trailing number ("Move window to space 3").
public func L(_ s: String) -> String {
    guard Strings.language != .en else { return s }
    let column = Lang.allCases.firstIndex(of: Strings.language)! - 1
    if let row = table[s] { return row[column] }
    if s.hasPrefix("Snap: ") {
        let rest = String(s.dropFirst(6))
        return L("Snap") + ": " + L(rest.prefix(1).uppercased() + rest.dropFirst())
    }
    if let space = s.lastIndex(of: " "), Int(s[s.index(after: space)...]) != nil, let row = table[s[..<space] + " %@"] {
        return row[column].replacingOccurrences(of: "%@", with: s[s.index(after: space)...])
    }
    return s
}

//                                English: [Spanish, French, German]
private let table: [String: [String]] = [
    // Preferences: sections and sidebar
    "General": ["General", "Général", "Allgemein"],
    "Grid": ["Cuadrícula", "Grille", "Raster"],
    "Mouse": ["Ratón", "Souris", "Maus"],
    "Border": ["Borde", "Bordure", "Rahmen"],
    "Shortcuts": ["Atajos", "Raccourcis", "Kurzbefehle"],
    "Apps": ["Apps", "Apps", "Apps"],
    "Now": ["Ahora", "Actuel", "Jetzt"],
    "Config": ["Configuración", "Configuration", "Konfiguration"],

    // Preferences: General
    "Language": ["Idioma", "Langue", "Sprache"],
    "System": ["Sistema", "Système", "System"],
    "Launch at login": ["Abrir al iniciar sesión", "Ouvrir à la connexion", "Bei der Anmeldung öffnen"],
    "Layout of a new space": ["Disposición de un espacio nuevo", "Disposition d’un nouvel espace", "Layout eines neuen Space"],
    "Each space keeps its own layout after that.": ["Después, cada espacio conserva su disposición.", "Ensuite, chaque espace garde sa disposition.", "Danach behält jeder Space sein Layout."],
    "Tile": ["Mosaico", "Mosaïque", "Kacheln"],
    "Float": ["Flotante", "Flottant", "Frei"],
    "Gap": ["Separación", "Espacement", "Abstand"],
    "Gutter between windows.": ["Espacio entre ventanas.", "Espace entre les fenêtres.", "Abstand zwischen Fenstern."],
    "Padding": ["Margen", "Marge", "Rand"],
    "Space to the screen edge.": ["Espacio hasta el borde de la pantalla.", "Espace jusqu’au bord de l’écran.", "Abstand zum Bildschirmrand."],
    "Open on the display under the mouse": ["Abrir en la pantalla donde está el ratón", "Ouvrir sur l’écran où se trouve la souris", "Auf dem Bildschirm unter der Maus öffnen"],
    "New windows appear where you work, not on the main display.": ["Las ventanas nuevas aparecen donde trabajas, no en la pantalla principal.", "Les nouvelles fenêtres s’ouvrent là où vous travaillez, pas sur l’écran principal.", "Neue Fenster erscheinen dort, wo du arbeitest, nicht auf dem Hauptbildschirm."],

    // Preferences: Grid
    "Swiss": ["Suizo", "Suisse", "Swiss"],
    "Columns": ["Columnas", "Colonnes", "Spalten"],
    "Main": ["Principal", "Principal", "Haupt"],
    "Board": ["Tablero", "Tableau", "Tafel"],
    "Preset of a new space": ["Preajuste de un espacio nuevo", "Préréglage d’un nouvel espace", "Vorgabe eines neuen Space"],
    "Swiss: 3 | 6 | 3 columns. Columns: compare side by side. Main: one large window and a stack. Board: even rows and columns.": [
        "Suizo: columnas 3 | 6 | 3. Columnas: comparar lado a lado. Principal: una ventana grande y una pila. Tablero: filas y columnas iguales.",
        "Suisse : colonnes 3 | 6 | 3. Colonnes : comparer côte à côte. Principal : une grande fenêtre et une pile. Tableau : lignes et colonnes égales.",
        "Swiss: Spalten 3 | 6 | 3. Spalten: nebeneinander vergleichen. Haupt: ein großes Fenster und ein Stapel. Tafel: gleiche Zeilen und Spalten."],
    "Sizes": ["Tamaños", "Tailles", "Größen"],
    "Hard: the grid owns the sizes; a resize shakes the window.\nSoft: borders move, until the windows on the space change.": [
        "Rígida: la cuadrícula fija los tamaños; al redimensionar, la ventana tiembla.\nFlexible: los bordes se mueven, hasta que cambien las ventanas del espacio.",
        "Rigide : la grille fixe les tailles ; un redimensionnement secoue la fenêtre.\nSouple : les bords se déplacent, jusqu’à ce que les fenêtres de l’espace changent.",
        "Fest: Das Raster bestimmt die Größen; beim Ändern wackelt das Fenster.\nWeich: Ränder lassen sich verschieben, bis sich die Fenster des Space ändern."],
    "Hard": ["Rígida", "Rigide", "Fest"],
    "Soft": ["Flexible", "Souple", "Weich"],

    // Preferences: Mouse
    "Focus follows mouse": ["El foco sigue al ratón", "Le focus suit la souris", "Fokus folgt der Maus"],
    "Focus: the window under the pointer takes the keyboard.\nRaise: it also comes to the front.": [
        "Foco: la ventana bajo el puntero recibe el teclado.\nElevar: además pasa al frente.",
        "Focus : la fenêtre sous le pointeur reçoit le clavier.\nÉlever : elle passe aussi au premier plan.",
        "Fokus: Das Fenster unter dem Zeiger erhält die Tastatur.\nAnheben: Es kommt außerdem nach vorn."],
    "Off": ["No", "Non", "Aus"],
    "Focus": ["Foco", "Focus", "Fokus"],
    "Raise": ["Elevar", "Élever", "Anheben"],
    "Drag windows with Ctrl": ["Arrastrar ventanas con Ctrl", "Déplacer les fenêtres avec Ctrl", "Fenster mit Ctrl ziehen"],
    "⌃ + drag moves a window. ⌃ + right-drag resizes it.": ["⌃ + arrastrar mueve una ventana. ⌃ + arrastrar con el botón derecho la redimensiona.", "⌃ + glisser déplace une fenêtre. ⌃ + glisser avec le bouton droit la redimensionne.", "⌃ + Ziehen bewegt ein Fenster. ⌃ + Ziehen mit der rechten Taste ändert die Größe."],
    "Copy on select": ["Copiar al seleccionar", "Copier à la sélection", "Beim Auswählen kopieren"],
    "Selecting text with the mouse copies it.": ["Seleccionar texto con el ratón lo copia.", "Sélectionner du texte à la souris le copie.", "Mit der Maus ausgewählter Text wird kopiert."],
    "Paste with right-click": ["Pegar con clic derecho", "Coller avec le clic droit", "Mit Rechtsklick einsetzen"],
    "In the text field you type in. ⌥ + right-click opens the normal menu.": ["En el campo de texto donde escribes. ⌥ + clic derecho abre el menú normal.", "Dans le champ de texte où vous écrivez. ⌥ + clic droit ouvre le menu habituel.", "Im Textfeld, in dem du schreibst. ⌥ + Rechtsklick öffnet das normale Menü."],

    // Preferences: Border
    "Width": ["Grosor", "Épaisseur", "Stärke"],
    "The border marks the focused window. 0 is no border.": ["El borde marca la ventana con foco. 0 es sin borde.", "La bordure marque la fenêtre active. 0 : pas de bordure.", "Der Rahmen markiert das aktive Fenster. 0 heißt kein Rahmen."],
    "None": ["Ninguno", "Aucune", "Keiner"],
    "Corner radius": ["Radio de esquina", "Rayon des coins", "Eckenradius"],
    "Match the corners of your windows.": ["Igual que las esquinas de tus ventanas.", "Comme les coins de vos fenêtres.", "Passend zu den Ecken deiner Fenster."],
    "Colour": ["Color", "Couleur", "Farbe"],
    "Pick a swatch, press + for any colour, or type a hex value.": ["Elige una muestra, pulsa + para cualquier color o escribe un valor hex.", "Choisissez un échantillon, appuyez sur + pour une autre couleur, ou saisissez une valeur hex.", "Wähle ein Farbfeld, drücke + für jede Farbe oder gib einen Hex-Wert ein."],
    "More colours": ["Más colores", "Plus de couleurs", "Weitere Farben"],

    // Preferences: Shortcuts and Apps
    "Click a key field, then press the new keys. Delete clears it, Esc cancels.": ["Haz clic en un campo y pulsa las teclas nuevas. Suprimir lo borra, Esc cancela.", "Cliquez sur un champ, puis appuyez sur les nouvelles touches. Suppr efface, Esc annule.", "Klicke auf ein Feld und drücke die neuen Tasten. Löschen entfernt, Esc bricht ab."],
    "Reset all": ["Restablecer todo", "Tout réinitialiser", "Alle zurücksetzen"],
    "Press keys": ["Pulsa teclas", "Appuyez", "Tasten drücken"],
    "Floating apps": ["Apps flotantes", "Apps flottantes", "Freie Apps"],
    "Windows of these apps are never tiled. Use the name the menu bar shows.": ["Las ventanas de estas apps nunca se organizan. Usa el nombre que muestra la barra de menús.", "Les fenêtres de ces apps ne sont jamais organisées. Utilisez le nom affiché dans la barre des menus.", "Fenster dieser Apps werden nie angeordnet. Nutze den Namen aus der Menüleiste."],
    "App name": ["Nombre de la app", "Nom de l’app", "App-Name"],
    "Add": ["Añadir", "Ajouter", "Hinzufügen"],
    "Remove": ["Quitar", "Retirer", "Entfernen"],

    // Menu bar
    "Grant Accessibility…": ["Dar acceso de Accesibilidad…", "Autoriser l’accessibilité…", "Bedienungshilfen erlauben…"],
    "Quit Aeris Tiler": ["Salir de Aeris Tiler", "Quitter Aeris Tiler", "Aeris Tiler beenden"],
    "Next Layout": ["Siguiente disposición", "Disposition suivante", "Nächstes Layout"],
    "Next Grid Preset": ["Siguiente preajuste", "Préréglage suivant", "Nächste Vorgabe"],
    "Hard Grid: Lock Sizes": ["Cuadrícula rígida: fijar tamaños", "Grille rigide : verrouiller les tailles", "Festes Raster: Größen sperren"],
    "Maximize": ["Maximizar", "Agrandir", "Maximieren"],
    "Float Window": ["Ventana flotante", "Fenêtre flottante", "Fenster frei"],
    "Flip Split": ["Girar división", "Pivoter la division", "Teilung drehen"],
    "Balance Splits": ["Igualar divisiones", "Équilibrer les divisions", "Teilungen ausgleichen"],
    "Move to Other Display": ["Mover a la otra pantalla", "Déplacer vers l’autre écran", "Auf anderen Bildschirm bewegen"],
    "Snap": ["Ajustar", "Ancrer", "Einrasten"],
    "Pause Tiling": ["Pausar el mosaico", "Suspendre la mosaïque", "Kacheln anhalten"],
    "Preferences…": ["Preferencias…", "Préférences…", "Einstellungen…"],
    "Paused": ["En pausa", "En pause", "Pausiert"],
    "No access": ["Sin acceso", "Sans accès", "Kein Zugriff"],

    // Snap positions
    "Left half": ["Mitad izquierda", "Moitié gauche", "Linke Hälfte"],
    "Right half": ["Mitad derecha", "Moitié droite", "Rechte Hälfte"],
    "Top half": ["Mitad superior", "Moitié haute", "Obere Hälfte"],
    "Bottom half": ["Mitad inferior", "Moitié basse", "Untere Hälfte"],
    "Top left": ["Arriba a la izquierda", "En haut à gauche", "Oben links"],
    "Top right": ["Arriba a la derecha", "En haut à droite", "Oben rechts"],
    "Bottom left": ["Abajo a la izquierda", "En bas à gauche", "Unten links"],
    "Bottom right": ["Abajo a la derecha", "En bas à droite", "Unten rechts"],
    "Left third": ["Tercio izquierdo", "Tiers gauche", "Linkes Drittel"],
    "Centre third": ["Tercio central", "Tiers central", "Mittleres Drittel"],
    "Right third": ["Tercio derecho", "Tiers droit", "Rechtes Drittel"],
    "Left two thirds": ["Dos tercios izquierdos", "Deux tiers gauches", "Linke zwei Drittel"],
    "Right two thirds": ["Dos tercios derechos", "Deux tiers droits", "Rechte zwei Drittel"],
    "Centre": ["Centro", "Centre", "Mitte"],
    "Full": ["Completa", "Plein écran", "Voll"],

    // Actions (Keysheet and Preferences → Shortcuts)
    "Focus window left": ["Enfocar ventana a la izquierda", "Focus sur la fenêtre de gauche", "Fenster links fokussieren"],
    "Focus window right": ["Enfocar ventana a la derecha", "Focus sur la fenêtre de droite", "Fenster rechts fokussieren"],
    "Focus window up": ["Enfocar ventana de arriba", "Focus sur la fenêtre du haut", "Fenster oben fokussieren"],
    "Focus window down": ["Enfocar ventana de abajo", "Focus sur la fenêtre du bas", "Fenster unten fokussieren"],
    "Swap window left": ["Intercambiar con la ventana de la izquierda", "Échanger avec la fenêtre de gauche", "Mit Fenster links tauschen"],
    "Swap window right": ["Intercambiar con la ventana de la derecha", "Échanger avec la fenêtre de droite", "Mit Fenster rechts tauschen"],
    "Swap window up": ["Intercambiar con la ventana de arriba", "Échanger avec la fenêtre du haut", "Mit Fenster oben tauschen"],
    "Swap window down": ["Intercambiar con la ventana de abajo", "Échanger avec la fenêtre du bas", "Mit Fenster unten tauschen"],
    "Move border left (hold)": ["Mover borde a la izquierda (mantener)", "Déplacer le bord vers la gauche (maintenir)", "Rand nach links bewegen (halten)"],
    "Move border right (hold)": ["Mover borde a la derecha (mantener)", "Déplacer le bord vers la droite (maintenir)", "Rand nach rechts bewegen (halten)"],
    "Move border up (hold)": ["Mover borde hacia arriba (mantener)", "Déplacer le bord vers le haut (maintenir)", "Rand nach oben bewegen (halten)"],
    "Move border down (hold)": ["Mover borde hacia abajo (mantener)", "Déplacer le bord vers le bas (maintenir)", "Rand nach unten bewegen (halten)"],
    "Cycle layout: tile, grid, float": ["Cambiar disposición: mosaico, cuadrícula, flotante", "Changer de disposition : mosaïque, grille, flottant", "Layout wechseln: Kacheln, Raster, frei"],
    "Grid preset: swiss, columns, main, board": ["Preajuste de cuadrícula: suizo, columnas, principal, tablero", "Préréglage de grille : suisse, colonnes, principal, tableau", "Raster-Vorgabe: Swiss, Spalten, Haupt, Tafel"],
    "Grid hard or soft: lock or free the sizes": ["Cuadrícula rígida o flexible: fijar o liberar tamaños", "Grille rigide ou souple : verrouiller ou libérer les tailles", "Raster fest oder weich: Größen sperren oder freigeben"],
    "Flip split: columns or rows": ["Girar división: columnas o filas", "Pivoter la division : colonnes ou lignes", "Teilung drehen: Spalten oder Zeilen"],
    "Balance splits": ["Igualar divisiones", "Équilibrer les divisions", "Teilungen ausgleichen"],
    "Pause or resume tiling": ["Pausar o reanudar el mosaico", "Suspendre ou reprendre la mosaïque", "Kacheln anhalten oder fortsetzen"],
    "Maximize or restore": ["Maximizar o restaurar", "Agrandir ou restaurer", "Maximieren oder wiederherstellen"],
    "Float or unfloat": ["Flotar o volver a la disposición", "Rendre flottante ou réintégrer", "Frei oder zurück ins Layout"],
    "Move to other display": ["Mover a la otra pantalla", "Déplacer vers l’autre écran", "Auf anderen Bildschirm bewegen"],
    "Move window to space %@": ["Mover ventana al espacio %@", "Déplacer la fenêtre vers l’espace %@", "Fenster auf Space %@ bewegen"],
    "Keysheet: search these keys": ["Keysheet: buscar estos atajos", "Keysheet : chercher ces raccourcis", "Keysheet: diese Kurzbefehle durchsuchen"],
    "Preferences": ["Preferencias", "Préférences", "Einstellungen"],

    // Action groups
    "Swap": ["Intercambiar", "Échanger", "Tauschen"],
    "Resize": ["Redimensionar", "Redimensionner", "Größe"],
    "Layout": ["Disposición", "Disposition", "Layout"],
    "Window": ["Ventana", "Fenêtre", "Fenster"],
    "Spaces": ["Espacios", "Espaces", "Spaces"],

    // Keysheet
    "Window shortcuts": ["Atajos de ventana", "Raccourcis de fenêtre", "Fenster-Kurzbefehle"],
    "Type to filter": ["Escribe para filtrar", "Tapez pour filtrer", "Tippen zum Filtern"],
    "Esc  close": ["Esc  cerrar", "Esc  fermer", "Esc  schließen"],
    "Switch space (macOS)": ["Cambiar de espacio (macOS)", "Changer d’espace (macOS)", "Space wechseln (macOS)"],
    "Move window": ["Mover ventana", "Déplacer la fenêtre", "Fenster bewegen"],
    "Resize window": ["Redimensionar ventana", "Redimensionner la fenêtre", "Fenstergröße ändern"],
    "drag": ["arrastrar", "glisser", "Ziehen"],
    "right-drag": ["arrastrar der.", "glisser droit", "Rechts-Ziehen"],

    // Key names
    "Left": ["Izquierda", "Gauche", "Links"],
    "Right": ["Derecha", "Droite", "Rechts"],
    "Up": ["Arriba", "Haut", "Oben"],
    "Down": ["Abajo", "Bas", "Unten"],
    "Option": ["Opción", "Option", "Wahl"],
    "Shift": ["Mayús", "Maj", "Umschalt"],
    "Space": ["Espacio", "Espace", "Leertaste"],
    "Return": ["Retorno", "Retour", "Eingabe"],
    "Delete": ["Suprimir", "Suppr", "Löschen"],
]

/// Every English key, for tests.
public var translationKeys: [String] { Array(table.keys) }
public func translationRow(_ key: String) -> [String]? { table[key] }
