# RadFährte

iOS-App (SwiftUI) für Radrouten-Navigation. Xcode-Projekt liegt in `FahrradApp/`.

**Vor Beginn der Arbeit immer zuerst [ROADMAP.md](ROADMAP.md) lesen.** Sie hält den aktuellen
Entwicklungsstand fest: was bereits umgesetzt ist, bekannte Probleme, und die als Nächstes
geplanten Schritte. Nach abgeschlossenen Änderungen die Roadmap entsprechend aktualisieren, damit
der Stand für die nächste Sitzung aktuell bleibt.

**Wird ein neues, für Nutzer sichtbares Feature ergänzt oder ein bestehendes spürbar geändert,
auch [HowItWorksView.swift](FahrradApp/RadFaehrte/Views/HowItWorksView.swift) ("Wie funktioniert's"
in den Einstellungen) entsprechend aktualisieren** - das ist die In-App-Erklärung für Nutzer, sie
soll nicht veralten.

Für den ursprünglichen Produktentwurf siehe [fahrradnavigation-app-spezifikation.md](fahrradnavigation-app-spezifikation.md).

**Zum Testen nicht den iOS Simulator verwenden, sondern immer auf das iPhone des Nutzers
übertragen.** Änderungen bauen und dort verifizieren lassen, nicht im Simulator screenshotten oder
UI-Flows durchklicken.

**Die App-Oberfläche ist komplett hart auf Deutsch codiert (keine Lokalisierung/`.lproj`).** Bei
Datums-, Zahlen- oder Währungsformatierung (`.formatted(...)`, `DateFormatter`, `NumberFormatter`
o. Ä.) deshalb immer explizit `Locale(identifier: "de_DE")` setzen - ohne das richtet sich das
Format nach der Sprach-/Regionseinstellung des Geräts und kann z. B. englische Wörter wie "at"
statt "um" anzeigen, auch wenn der Rest der UI deutsch ist.
