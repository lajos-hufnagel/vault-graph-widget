# Vault Graph Widget

Ein natives macOS-Desktop-Widget für den Graph eines Obsidian-Vaults. Das Widget liest Markdown-Dateien direkt, zeigt Notizen und ihre Verbindungen und lässt den Vault pro Instanz auswählen.

Keine laufende Träger-App und kein Server erforderlich. Die Aktualisierung wird nach 15 Minuten angefordert; den tatsächlichen Zeitpunkt steuert macOS.

## Bauen und verwenden

Voraussetzungen: macOS 14 oder neuer und Xcode.

```sh
sh Native/build-local.sh
```

Der lokale Build verwendet Ad-hoc-Signierung. Die App entsteht unter `Native/LocalBuild/Build/Products/Debug/VaultGraph.app`. Nach `/Applications` kopieren und einmal öffnen. Anschließend auf dem Desktop „Widgets bearbeiten“ öffnen und „Vault Graph“ hinzufügen. Rechtsklick auf das Widget → „Widget bearbeiten“ → „Vault“ wählt den angezeigten Vault.

Standardmäßig werden registrierte Obsidian-Vaults und Vaults im iCloud-Obsidian-Ordner erkannt. Alternativ Pfade beim Build angeben:

```sh
sh Native/build-local.sh "/Pfad/Vault A" "/Pfad/Vault B"
```

Das Widget hat ausschließlich lesenden Vault-Zugriff. Lokale Builds und Graphdaten werden nicht in Git gespeichert.

Details zu Einrichtung, Grenzen und geprüftem Stand: [Native/README.md](Native/README.md).

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


## Portfolio and development approach

Personal project developed with AI assistance. I defined requirements, guided implementation, reviewed results and iterated through practical testing. This repository is a curated source snapshot with a new history; earlier development history is retained privately.
