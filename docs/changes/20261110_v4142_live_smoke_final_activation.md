# SSH Drop Dispatcher v4.14.2 — Live-Canary-Abschlusscontroller

Datum: 2026-11-10. Ziel: Pixel 10 Pro XL (mustang), Android 17. Scope: Aktivierung und Smoke-Test des bereits installierten und nach dem Neustart geprüften v4.14.2-Moduls; **kein Release/Tag, kein Cloud1-Ausbau, kein Reboot**.

## Verifizierter Vorzustand

- Modul v4.14.2 aktiv; `service.sh` SHA-256 `c1a54cd7fb0ceafc973adccc195494b41ae577131e04a9ee406424f58165b583`, Singleflight-Koordinator SHA-256 `02e6c88633f7787f2aabfe9fe8bc47d5604a13c94fd1f10e8473b7bfe6e56346`.
- Postboot-Verifier und isolierter 12-fach-Singleflight-Test PASS.
- Vor produktiver Aktivierung sechs unterstützte zieladressierte Bestandsdateien: vier vollständig erledigt, zwei vollständig durch v4115-Quarantäne geschützt; keine offene Alt-Auslieferung.
- Der erste live erzeugte Pi4-Smoke-Datensatz wurde übertragen und in `dispatch.done`/`dispatch.complete` erfasst. Dispatcher-eigene Remote-SHA-Verifikation `remote_sha_match=yes`.
- Unabhängige Root-Reads auf Pi4 und über die Pixel-SSH-Zielidentität bestätigten später exakt den Testdatei-SHA-256 `b75b24c6874910c1e04a9effd2f82330572cc797a271b4af784d5f8a86b2422e`.
- Der zusätzliche chatgenerierte Prüfschritt wertete eine vorübergehend fehlgeschlagene/ungeeignete Remote-Leseabfrage fälschlich als `remote_sha_mismatch`. Sein Sicherheitsrollback setzte `DROP_DISPATCH_ENABLED=0` und die vorab gesicherte Konfiguration zurück. Ein inhaltlicher Übertragungsfehler war nicht nachweisbar. Die Ursache des transienten Leseproblems bleibt unbekannt.

## Repository-eigene Korrektur

`tools/pixel_local__sdd_v4142_finalize_activation_v1.sh` ist ein Workflowfit-Controller mit drei klar getrennten Phasen:

1. Read-only Preflight: Pixel-/Root-/Boot-/Build-/Modul-Hash, Akku (mindestens 5 %), Konfigurationsidentität, alte Quarantäne/Erledigt-Daten, vorhandenes Rollback, bestehender Smoke-Done-Beleg und neuer exakter Pi4-Root-SHA-Readback.
2. Mutationsphase: geschützte Config-Sicherung; ausschließlich eigene bytegenau verifizierte Pi4-Smoke-Datei entfernen; danach vorhandenes v4.14.2-Service-CLI `--enable` nutzen. Keine erneute Testdatei, kein `--dispatch-now`-Zwangsscan und kein Reboot.
3. Post-Write-Prüfung: aktiven Dispatcher-Status, Main-/Watchdog-/Watcher-PIDs und begrenzte Follow-up-Prozesszahl zweimal prüfen. Auf Fehler `--disable` plus Wiederherstellung der gesicherten Ursprungsconfig.

Die SHA-Parser-Fixtures im vorhandenen `tests/verify_followup_singleflight.py` prüfen positive Hash-Ausgaben und negative Fälle wie `Permission denied`, `Keine Berechtigung`, fehlende Datei und syntaktisch ungültige Prüfsummen. Ein gescheiterter Remote-Read wird nicht länger als tatsächliche abweichende Datei klassifiziert.

## Abnahmegrenzen

Der bestandene Smoke-Test bestätigt eine Dateiübertragung nach Pi4 und korrekte SHA-256-Datenintegrität. Er ersetzt keine vollständige Verfügbarkeit aller vier Ziele und keinen Langzeitstabilitätstest. Die Erweiterung veröffentlicht keine v4.14.2-Version und verändert keine Modul-Produktionssource. Ein öffentliches Release erfordert eine separate, ausdrücklich freigegebene Release-Lane.
