nginx mit SSL-Unterstützung
===========================

Einfacher nginx Container mit SSL-Unterstützung über acme.sh

Wichtige Container Variablen:

* `HTTPS_ACTIVE` (default 0)
  1 aktiviert HTTPS Unterstützung
* `HTTPS_REDIRECT` (default 1)
  1 aktiviert automatischen Redirect von HTTP auf HTTPS
* `HTTPS_DOMAINS` (default "")
  Mit Leerzeichen getrennte Liste von Domain-Namen, die über HTTPS verfügbar sein sollen
* `HTTPS_TEST_MODE` (default: 1)
  0 deaktiviert den ACME-Test-Modus
  _muss in produktiven HTTPS-Umgebungen auf 0 stehen_
* `PROXY_TARGET` (default "")
  URL zu der Anfragen intern weitergereicht werden sollen
* `NGINX_CONFIG` (default "")
  Teil der Konfiguration, die in die SSL-Konfiguration eingefügt werden soll
* `NOTIFICATION_MAIL` (default "")
  E-Mail-Adresse für Benachrichtigungen bei Zertifikat-Ereignissen
* `NGINX_IMAGE_FILTER` (default 0)
  1 aktiviert Image-Filter-Modul

Zusätzliche Variablen in NGINX Config:

* `$effective_scheme` 
  Diese Variable übernimmt den Wert eines X-Forwarded-Proto Headers, sofern dieser gesetzt ist.
  Als Fallback wird das verwendete Schema aus `$scheme` zurückgegeben.
