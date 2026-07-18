//
//  RadFaehrteUITests.swift
//  RadFaehrteUITests
//
//  Created by Jörn Frankenfeld on 17.07.26.
//

import XCTest

final class RadFaehrteUITests: XCTestCase {

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.

        // In UI tests it is usually best to stop immediately when a failure occurs.
        continueAfterFailure = false

        // In UI tests it’s important to set the initial state - such as interface orientation - required for your tests before they run. The setUp method is a good place to do this.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    @MainActor
    func testExample() throws {
        // UI tests must launch the application that they test.
        let app = XCUIApplication()
        app.launch()

        // Use XCTAssert and related functions to verify your tests produce the correct results.
        // XCUIAutomation Documentation
        // https://developer.apple.com/documentation/xcuiautomation
    }

    /// Fängt den System-Standort-Dialog ab und erteilt die Berechtigung, damit Tests
    /// unabhängig davon funktionieren, welchen Berechtigungsstatus ein vorheriger Test
    /// im selben Simulator-Klon hinterlassen hat.
    @MainActor
    @discardableResult
    private func addLocationPermissionAllowMonitor() -> NSObjectProtocol {
        addUIInterruptionMonitor(withDescription: "Standort-Systemdialog (Erlauben)") { alert in
            for label in ["Allow While Using App", "Beim Verwenden der App erlauben", "Allow Once", "Einmal erlauben"] {
                let button = alert.buttons[label]
                if button.exists {
                    button.tap()
                    return true
                }
            }
            return false
        }
    }

    @MainActor
    func testNavigationMode() throws {
        let app = XCUIApplication()
        app.resetAuthorizationStatus(for: .location)
        let allowMonitor = addLocationPermissionAllowMonitor()
        defer { removeUIInterruptionMonitor(allowMonitor) }

        app.launch()

        let startField = app.textFields["Start"]
        XCTAssertTrue(startField.waitForExistence(timeout: 5))
        startField.tap()
        startField.typeText("Bremen")

        let startResult = app.buttons.containing(NSPredicate(format: "label CONTAINS 'Bremen'")).firstMatch
        XCTAssertTrue(startResult.waitForExistence(timeout: 10), "Keine Autovervollständigung für 'Bremen' erhalten")
        startResult.tap()

        let zielField = app.textFields["Ziel"]
        XCTAssertTrue(zielField.waitForExistence(timeout: 5))
        zielField.tap()
        zielField.typeText("Achim")

        let zielResult = app.buttons.containing(NSPredicate(format: "label CONTAINS 'Achim'")).firstMatch
        XCTAssertTrue(zielResult.waitForExistence(timeout: 10), "Keine Autovervollständigung für 'Achim' erhalten")
        zielResult.tap()

        let losButton = app.buttons["Los"]
        XCTAssertTrue(losButton.waitForExistence(timeout: 10), "Kein Routen-Match gefunden, 'Los'-Button erschien nicht")
        losButton.tap()
        app.tap()

        let beendenButton = app.buttons["Beenden"]
        XCTAssertTrue(beendenButton.waitForExistence(timeout: 5), "Navigationsmodus wurde nicht gestartet")

        beendenButton.tap()
        XCTAssertTrue(startField.waitForExistence(timeout: 5), "Navigationsmodus wurde nicht beendet")
    }

    @MainActor
    func testNavigationModeShowsAlertWhenLocationDenied() throws {
        let app = XCUIApplication()
        // Unabhängig vom Berechtigungsstatus, den andere Tests im selben Simulator-Klon
        // hinterlassen haben: Status zurücksetzen und über den System-Dialog aktiv verweigern,
        // statt uns auf extern (z. B. per simctl) vorbereiteten Zustand zu verlassen.
        app.resetAuthorizationStatus(for: .location)

        let systemDenyMonitor = addUIInterruptionMonitor(withDescription: "Standort-Systemdialog") { alert in
            for label in ["Don’t Allow", "Don't Allow", "Nicht erlauben", "Nicht zulassen"] {
                let button = alert.buttons[label]
                if button.exists {
                    button.tap()
                    return true
                }
            }
            return false
        }
        defer { removeUIInterruptionMonitor(systemDenyMonitor) }

        app.launch()

        let startField = app.textFields["Start"]
        XCTAssertTrue(startField.waitForExistence(timeout: 5))
        startField.tap()
        startField.typeText("Bremen")
        let startResult = app.buttons.containing(NSPredicate(format: "label CONTAINS 'Bremen'")).firstMatch
        XCTAssertTrue(startResult.waitForExistence(timeout: 10))
        startResult.tap()

        let zielField = app.textFields["Ziel"]
        zielField.tap()
        zielField.typeText("Achim")
        let zielResult = app.buttons.containing(NSPredicate(format: "label CONTAINS 'Achim'")).firstMatch
        XCTAssertTrue(zielResult.waitForExistence(timeout: 10))
        zielResult.tap()

        let losButton = app.buttons["Los"]
        XCTAssertTrue(losButton.waitForExistence(timeout: 10))

        // Erster Tap bei "noch nicht entschieden": löst den System-Dialog aus, den der
        // Interruption-Monitor mit "Nicht erlauben" beantwortet. Der Tap auf die App
        // stößt die Auswertung des Monitors an.
        losButton.tap()
        app.tap()

        let beendenButton = app.buttons["Beenden"]
        _ = beendenButton.waitForExistence(timeout: 5)
        if beendenButton.exists {
            beendenButton.tap()
        }
        XCTAssertTrue(startField.waitForExistence(timeout: 5))

        // Zweiter Tap: Berechtigung ist jetzt tatsächlich "denied" -> App muss den
        // eigenen Alert zeigen statt erneut beim System nachzufragen.
        XCTAssertTrue(losButton.waitForExistence(timeout: 10))
        losButton.tap()

        let alert = app.alerts["Standortzugriff benötigt"]
        XCTAssertTrue(alert.waitForExistence(timeout: 5), "Alert bei verweigerter Standort-Berechtigung wurde nicht angezeigt")
        alert.buttons["Abbrechen"].tap()

        XCTAssertFalse(app.buttons["Beenden"].exists, "Navigationsmodus sollte bei verweigerter Berechtigung nicht starten")
    }

    @MainActor
    func testUseCurrentLocationAsStart() throws {
        let app = XCUIApplication()
        app.resetAuthorizationStatus(for: .location)
        let allowMonitor = addLocationPermissionAllowMonitor()
        defer { removeUIInterruptionMonitor(allowMonitor) }

        app.launch()

        let startField = app.textFields["Start"]
        XCTAssertTrue(startField.waitForExistence(timeout: 5))

        let useLocationButton = app.buttons["useCurrentLocation-Start"]
        XCTAssertTrue(useLocationButton.waitForExistence(timeout: 5), "Standort-Button im Start-Feld fehlt")
        useLocationButton.tap()
        app.tap()

        let resolvedStartField = app.textFields["Start"]
        let predicate = NSPredicate(format: "value == %@", "Aktueller Standort")
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: resolvedStartField)
        let result = XCTWaiter().wait(for: [expectation], timeout: 5)
        XCTAssertEqual(result, .completed, "Start-Feld wurde nicht mit dem aktuellen Standort befüllt")

        let clearButton = app.buttons["clearSelection-Start"]
        XCTAssertTrue(clearButton.waitForExistence(timeout: 5), "Auswahl wurde nicht als SelectedPlace übernommen")
    }

    @MainActor
    func testSwapStartAndZiel() throws {
        let app = XCUIApplication()
        app.launch()

        let startField = app.textFields["Start"]
        let zielField = app.textFields["Ziel"]
        XCTAssertTrue(startField.waitForExistence(timeout: 5))

        startField.tap()
        startField.typeText("Bremen")
        let startResult = app.buttons.containing(NSPredicate(format: "label CONTAINS 'Bremen'")).firstMatch
        XCTAssertTrue(startResult.waitForExistence(timeout: 10))
        startResult.tap()

        zielField.tap()
        zielField.typeText("Achim")
        let zielResult = app.buttons.containing(NSPredicate(format: "label CONTAINS 'Achim'")).firstMatch
        XCTAssertTrue(zielResult.waitForExistence(timeout: 10))
        zielResult.tap()

        let startValueBeforeSwap = startField.value as? String
        let zielValueBeforeSwap = zielField.value as? String
        XCTAssertTrue(startValueBeforeSwap?.contains("Bremen") == true)
        XCTAssertTrue(zielValueBeforeSwap?.contains("Achim") == true)

        let swapButton = app.buttons["swapStartZiel"]
        XCTAssertTrue(swapButton.waitForExistence(timeout: 5))
        swapButton.tap()

        let startValueAfterSwap = startField.value as? String
        let zielValueAfterSwap = zielField.value as? String
        XCTAssertTrue(startValueAfterSwap?.contains("Achim") == true, "Start-Feld enthält nach dem Tausch nicht 'Achim'")
        XCTAssertTrue(zielValueAfterSwap?.contains("Bremen") == true, "Ziel-Feld enthält nach dem Tausch nicht 'Bremen'")
    }

    @MainActor
    func testLaunchPerformance() throws {
        // This measures how long it takes to launch your application.
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }
}
