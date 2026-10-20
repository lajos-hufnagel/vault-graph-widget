# VaultGraph: Platzhalter-Icon in macOS WidgetKit

Recherche vom 11. Oktober 2026. Keine bestätigte Lösung für genau diesen WidgetKit-Fehler gefunden. Die stärkste Primärquellen-Spur ist eine falsche oder veraltete LaunchServices-Zuordnung.

## Belastbare Befunde

- Apple DTS erklärt, dass mehrere registrierte Kopien derselben App zu fehlenden oder falschen Icons führen können: LaunchServices kann eine andere Kopie als maßgeblich behandeln. Empfohlener Diagnosetest: Projektkopie mit neuer Bundle-ID, korrekt konfiguriertes Icon, nach `/Applications` kopieren und von dort starten. Das ist allgemeine macOS-Icon-Diagnose aus einem Dokument-Icon-Thread, kein bestätigter WidgetKit-Fix. [Apple DTS, akzeptierte Antwort](https://developer.apple.com/forums/thread/761775)
- WidgetKit verlangt mindestens einen Start der enthaltenden App nach der Installation, damit ihr Widget in der Galerie erscheint. [Apple: Creating a widget extension](https://developer.apple.com/documentation/widgetkit/creating-a-widget-extension)
- `LSCopyApplicationURLsForBundleIdentifier` liefert alle LaunchServices bekannten App-URLs einer Bundle-ID; `LSRegisterURL` registriert eine bestimmte App. Die erstgenannte API ist veraltet, eignet sich aber zur lokalen Diagnose. [Apple: Launch Services](https://developer.apple.com/documentation/coreservices/launch_services)
- macOS unterstützt das Asset über `CFBundleIconName`, ansonsten die Datei über `CFBundleIconFile` im Ressourcenverzeichnis. `CFBundleIcons` und `CFBundleIconFiles` sind in der älteren Referenz als iOS-/tvOS-Schlüssel dokumentiert; zusätzliche PNG-Fallback-Schlüssel sind deshalb kein belastbar dokumentierter macOS-Fix. [Apple: Core Foundation Keys](https://developer.apple.com/library/archive/documentation/General/Reference/InfoPlistKeyReference/Articles/CoreFoundationKeys.html)

## Konkrete nächste Tests

1. Alle registrierten URLs für `de.lajoshufnagel.VaultGraph` abfragen und prüfen, welche App `NSWorkspace.urlForApplication(withBundleIdentifier:)` auswählt. Jede registrierte Kopie auf Icon-Metadaten und Ressourcen vergleichen.
2. Aktuelle installierte App aus `/Applications` ausdrücklich über LaunchServices starten; Ergebnis in Galerie und Konfiguration erneut prüfen.
3. Falls erfolglos, Diagnosekopie mit neuen Host- UND Extension-Bundle-IDs bauen. Identische vollständige Mac-Icon-Ressourcen verwenden, aus `/Applications` starten, nur ein neues Diagnosewidget ergänzen. Erfolg würde einen Zusammenhang mit alter Identität/Registrierung stark stützen; Misserfolg lenkt auf Bundle-Konfiguration oder Systemfehler.

Zusätzliche lokale Beobachtung: `Native/App.swift` verwendet für `LOCAL_WIDGET` die Aktivierungspolitik `.prohibited` und beendet die Host-App sofort in `applicationDidFinishLaunching`. `.prohibited` verbietet Aktivierung und Fenster und zeigt die App nicht im Dock. Ein Test mit `.regular` und einer kurzzeitig offen gehaltenen Host-App isoliert diese Besonderheit; dafür gibt es keine direkte Icon-Fix-Zusage. [Apple: ActivationPolicy](https://developer.apple.com/documentation/appkit/nsapplication/activationpolicy-swift.enum)

Die Apple-DTS-Empfehlung einer frischen Installation lässt sich als letzte Vergleichsprobe in einem sauberen macOS-Benutzerkonto oder einer VM durchführen. Ein ähnlicher System-Extension-Icon-Fehler wurde als macOS-15.0-Bug beobachtet und in 15.1 nicht mehr reproduziert; das belegt nur, dass System-UI-Iconfehler trotz korrekter Bundle-Ressourcen möglich sind. [Apple Developer Forums: Network Extension icon missing in System Settings](https://developer.apple.com/forums/thread/765817)

## Grenzen

- Kein offizieller Hinweis gefunden, der einen vollständigen Mac-Neustart als zuverlässige Lösung genau dieses WidgetKit-App-Iconfehlers bestätigt.
- Dienstneustarts beweisen weder, dass LaunchServices die richtige App-Kopie auswählt, noch dass ihr Icon neu aufgebaut wurde.
- Der Logtext `Resolved locally generated icon` allein sagt nicht, ob das erzeugte Bild das gewünschte Icon oder ein generischer Fallback ist.
- Globale Datenbank-/Cache-Löschung ist durch die gefundenen Quellen nicht als gezielter, sicherer WidgetKit-Fix belegt und sollte nicht der nächste Schritt sein.

## Lokal geprüfter Workaround

Am 11. Oktober 2026 zeigt eine getrennte Kopie mit neuer Bundle-ID und identischen Icon-Ressourcen unter `/Applications` das korrekte Icon in der Widget-Galerie. Die alte Identität zeigt daneben den Platzhalter. Der Installationsort allein behebt die alte Identität nicht. Version 0.10 verwendet deshalb `de.lajoshufnagel.VaultGraph.Local` und `.Local.Widget`; unter `/Applications/VaultGraph.app` installiert, gebaut und signaturgeprüft. Neues großes Desktop-Widget angelegt; Graph mit 59 Notizen / 139 Verbindungen in Accessibility erfasst. Neue Galerie-Zeile zeigt das Graph-Icon visuell bestätigt. Nutzer bestätigt anschließend das korrekte Graph-Icon in der Konfigurations-Kopfzeile. Kein Mac-Neustart erforderlich. Alte Desktop-Instanz ist weiterhin separat vorhanden und kann entfernt werden. Diagnose-App aus Registrierung entfernt und reversibel unter `Native/LocalBuild/IconProbe.app.backup` archiviert. Schlussfolgerung: alte Registrierung oder zugeordneter Icon-Cache wahrscheinlich; genaue Ursache nicht nachgewiesen.
