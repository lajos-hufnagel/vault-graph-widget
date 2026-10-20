# Native Mac-App und Desktop-Widget

Der Portfolio-Stand basiert auf Version 0.17. Die zugrunde liegende lokale Variante wurde gebaut, signaturgeprüft und praktisch getestet. Auch die bereinigte Portfolio-Kopie wurde erfolgreich mit Xcode gebaut und signaturgeprüft.

## Lokaler Build

Voraussetzungen: macOS 14 oder neuer und Xcode. Im Repository ausführen:

```sh
sh Native/build-local.sh
```

Der Build verwendet Ad-hoc-Signierung ohne Apple-Zertifikat oder App Group. Ergebnis: `Native/LocalBuild/Build/Products/Debug/VaultGraph.app`. App nach `/Applications` kopieren und einmal öffnen, dann „Vault Graph“ über die macOS-Widget-Galerie hinzufügen.

Der lokale Host hat kein Fenster und beendet sich beim Öffnen sofort. Das Widget liest den Vault selbst; weder eine laufende App noch ein Server ist erforderlich. Ein automatischer Login-Start ist nicht eingerichtet.

`create_project.py` regeneriert das Xcode-Projekt ohne zusätzliche Bibliotheken. Eigene Signierungsanpassungen vor einer Regenerierung sichern. `project.yml` ist eine alternative XcodeGen-Beschreibung.

## Vault-Auswahl und Zugriff

Rechtsklick auf das Widget → „Widget bearbeiten“ → „Vault“. Jede Instanz kann ihren eigenen Vault anzeigen; Snapshots werden pro Vault getrennt gespeichert.

Die Standardvariante erkennt Vaults aus der Obsidian-Registrierung und direkten Unterordnern mit `.obsidian` im iCloud-Obsidian-Ordner. Neue Vaults dort erscheinen beim erneuten Öffnen der Auswahl ohne Neubau. Die Sandbox erlaubt ausschließlich lesenden Zugriff auf diese Ordner und die Registrierungsdatei. Außerhalb liegende Vaults werden in dieser Variante ausgefiltert.

Explizite Pfade sind eine Alternative:

```sh
sh Native/build-local.sh "/Pfad/Vault A" "/Pfad/Vault B"
```

Bei dieser Variante erfordern Änderungen der erlaubten Pfade einen Neubau. Ein freier Ordnerdialog ist im lokalen Widget nicht enthalten.

## Graph und Aktualisierung

Das Widget bildet Markdown-Notizen und aufgelöste Wikilinks ab. Knotenabstand und Kollisionskorrektur vermeiden Überlagerungen; isolierte Notizen werden kompakt unter dem verbundenen Graph angeordnet. Die Skalierung nutzt die verfügbare Fläche, Verbindungslinien sind 0,45 Punkte breit. Widget-Beschreibung, Vault-Auswahl, Hinweise und Zählung sind englisch.

Das Widget fordert nach 15 Minuten eine neue Timeline an; den tatsächlichen Zeitpunkt bestimmt macOS. Bei Lesefehlern bleibt der letzte Graph mit Hinweis sichtbar. Eine sekundengenaue Aktualisierung ist nicht zugesichert.

Geprüft: vollständiger Build und Signatur, Sandbox-Zugriff mit mehreren Vaults, getrennte Caches, ungültige Auswahl, dynamische Erkennung sowie Renderprüfungen für drei Größen, leere und isolierte Graphen. Desktop-Anzeige und Konfiguration wurden visuell geprüft; konkrete macOS-Aktualisierungsverzögerungen wurden nicht separat vermessen.

## Icon und veraltete Beschreibungen

Graph-Icon: `Assets/AppIcon.png`, `AppIcon.icns` und `Assets.xcassets`. Lokale Bundle-IDs: `de.lajoshufnagel.VaultGraph.Local` und `.Local.Widget`. Bei vorhandenen Instanzen einer früheren App-Identität das Widget einmal neu hinzufügen. Die neue Identität zeigt das korrekte Icon in Galerie und Bearbeitungsansicht. Details: [Icon-Recherche](docs/icon-research.md).

Falls macOS nach einem Update eine alte Beschreibung zeigt, die installierte Host-App über LaunchServices vollständig ab- und wieder anmelden, die Erweiterung mit PlugInKit registrieren und die Widget-Prozesse neu laden. Dies übernahm die neue Beschreibung in bestehenden Instanzen; ein Dienstneustart allein genügte in diesem Fall nicht.

## Separate App-Group-Variante

Ohne `LOCAL_WIDGET` enthält das native Projekt zusätzlich ein interaktives SwiftUI-Fenster. Diese Variante braucht ein eigenes Development Team und dieselbe App Group in App und Erweiterung (`group.de.lajoshufnagel.VaultGraph`). Die laufende App liest den ausgewählten Vault und teilt Snapshots mit dem Widget. Ihr App-Group-Datenaustausch wurde noch nicht praktisch geprüft; sie ist nicht die oben beschriebene lokale Widget-Variante.

## Obsidian-Graph-Einstellungen

Version 0.17 liest `.obsidian/graph.json` bei jedem erfolgreichen Widget-Scan. Farbgruppen werden in der gespeicherten Reihenfolge mit RGB und Transparenz ausgewertet; die feste Ordnerpalette entfällt. Ohne passende Farbgruppe verwendet das Widget eine neutrale Systemfarbe.

Übernommen werden Tags, Anhänge, ungelöste Links, verwaiste Notizen, Pfeile, Knoten- und Linienstärke, Beschriftungsschwelle, sowie Zentrierungs-, Abstoßungs- und Verbindungskräfte und der Verbindungsabstand. Markdown-Links und Wikilinks bilden Verbindungen. Tags aus Frontmatter und Fließtext werden unterstützt. Eine Verbindung wird auch bei gegenseitigen Links einmal gezählt; Pfeile können beide Richtungen zeigen.

**Use Obsidian graph filter** übernimmt eingeschaltet sämtliche gespeicherten Filteroptionen; ausgeschaltet gelten Obsidian-Standardfilter. Bei neuen Widget-Instanzen ist die Option standardmäßig an. Bestehende Instanzen behalten ihre Auswahl. Aus bedeutet Obsidian-Standard der Filteroptionen: Suche leer, Tags und Anhänge aus, ungelöste Links sichtbar, verwaiste Notizen sichtbar. Farben sowie Darstellungs- und Krafteinstellungen stammen in beiden Modi weiter aus Obsidian. Die Vault-Konfiguration wird dabei niemals verändert. Caches bleiben pro Vault und Suchmodus getrennt und speichern auch die Einstellungen.

Grenzen: Suchfilter unterstützen literale `-path:`- und `-file:`-Ausschlüsse. Farbgruppen unterstützen `path:`, `file:` (auch reguläre Ausdrücke) und `tag:`. Andere Syntax oder eine fehlende/ungültige Konfiguration führt zu einem Fehlerhinweis und höchstens zum letzten passenden Snapshot. Das Widget hat einen eigenen statischen Layoutalgorithmus: Kräfte und Beschriftungsschwelle werden entsprechend seiner Darstellung umgesetzt, nicht durch Obsidian selbst. Exakte Obsidian-Positionen, Live-Simulation, Hover-/Klickverhalten und die aufgeklappten Einstellungsabschnitte werden nicht gespiegelt.

Die Aktualisierung wird nach 15 Minuten angefordert; macOS bestimmt den tatsächlichen Zeitpunkt. Ein Schalterwechsel ist kein garantierter Refresh. Zum manuellen Anfordern einer Aktualisierung die installierte `VaultGraph.app` öffnen: der registrierte Host ruft `WidgetCenter.reloadAllTimelines()` auf und beendet sich danach ohne Fenster. Auch diese Anforderung wird von macOS geplant. Bei einem nachgewiesen hängenden Refresh hat ein Neustart von `chronod` den aktiven Widget-Scan ausgelöst; anschließend Anzeige und Cache prüfen.

Validierung: `python3 Native/tests/settings_test.py` prüft einen temporären Vault mit Farbprioritäten und Transparenz, Suchmodus, Tags, Anhängen, ungelösten Links, verwaisten Notizen, Verbindungsindices und Snapshot-Rücklesen sowie Standardfilter bei ausgeschalteter Option mit unveränderten Farben und unveränderter Vault-Konfiguration. Der lokale Xcode-Build prüft zusätzlich den Renderer.

## Widget-Fläche ausnutzen

Das Widget passt den Graphen in beiden Filtermodi an seine tatsächliche verfügbare Zeichenfläche an. Obsidian’s gespeicherter Fensterzoom wird nicht zusätzlich auf diese bereits angepassten Positionen angewandt: Er würde den Graphen erneut verkleinern oder abschneiden. Filter, Farben und übrige Einstellungen bleiben übernommen. Die Beschriftungsausblendung richtet sich weiterhin nach Obsidian’s Zoom und Beschriftungsschwelle, damit die automatische Größenanpassung keine zusätzliche Beschriftungsflut auslöst.

Regression: `python3 Native/tests/layout_test.py "/Pfad/zum/Vault"` prüft Flächenausnutzung und Darstellungsgrenzen für beide Modi, mehrere Größen und gespeicherte Zoomwerte unter sowie über 1.
