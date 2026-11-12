# Star Fleet Battles, versione digitale

Versione digitale (Godot 4.7) di **Star Fleet Battles - Captain's Basic Set** (Amarillo Design Bureau):
battaglie tattiche fra astronavi nell'universo di Star Trek, con energia ripartita ogni turno e 32 impulsi
di movimento e fuoco.

Si gioca nel browser: https://tannoiser2.github.io/Star-Fleet-Battle/ (e sulla ludoteca privata,
https://starfleet.ludoteca-digitale.com/ quando ci sono i segreti Cloudflare).

## Cosa c'è

- **Regole del Basic Set** al livello «Assume Command»: ripartizione dell'energia (supporto vitale,
  controllo del fuoco, scudi, rinforzi generali e specifici, movimento, condensatori dei phaser, armi
  pesanti, batterie), tabella degli impulsi, modi di virata e scarti, archi di tiro, distanza effettiva
  (scanner, aggancio dei sensori), phaser 1/2/3, siluri fotonici con sovraccarico, disgregatori con
  sovraccarico, siluri al plasma R/S/G/F (tre turni di carica, testata che cala con la distanza, phaser
  difensivi), droni, navette d'assalto e caccia delle portaerei, occultamento romulano e orione,
  scudi e tabella di assegnazione dei danni D4.21, danni in eccesso, disimpegno ai bordi della mappa.
- **43 astronavi** di sette razze trascritte dalle schede SSD del modulo «Fleet Builder» (tutti i refit
  stampati), con la loro **scheda SSD originale** consultabile in partita.
- **Mappa 3D**: il campo stellare esagonale del modulo, le **pedine originali** con sopra i **modelli 3D**
  delle navi (ridotti per il web), scudi colorati attorno alla pedina, effetti di fuoco ed esplosioni;
  **vista 2D** dall'alto con le sole pedine. Pan, zoom e rotazione anche con il tocco (iPad).
- **Otto scenari** (il duello classico CA contro D7, Zona Neutrale, artigli kzinti, Gorn contro
  Romulani, pirati di Orione, confine tholiano, corazzate, mischia a quattro) e la **battaglia libera**
  fino a otto giocatori a squadre.
- **IA** su tre livelli (cadetto, capitano, ammiraglio), più giocatori sullo stesso dispositivo,
  **online** con Firebase e **salvataggi** con un codice di sei lettere.
- Interfaccia da consolle di plancia, tutto in italiano; regolamento nel gioco (`assets/regole.md`).

## Struttura

- `data/navi.json`: le 43 navi (scudi, sistemi, armi e archi, tracce di sensori/scanner/controllo danni,
  costo di movimento, modo di virata, BPV).
- `scripts/data/sfb_data.gd`: tabelle delle armi, tabella dei danni, modi di virata, razze.
- `scripts/data/scenarios.gd`: gli scenari.
- `scripts/core/hexgrid.gd`: geometria della mappa (numerazione CCRR, direzioni A-F, archi, scudi).
- `scripts/core/engine.gd`: il motore delle regole; `scripts/core/ai.gd`: l'avversario automatico.
- `scripts/ui/`: menu, schermata di gioco, mappa 3D (`board3d.gd`), regolamento, tema (`ui.gd`).
- `scripts/net/`: Firebase (stanze, registro delle mosse, salvataggi) e partita online in lockstep.
  Il ramo del database è `starfleet` (stanze in `starfleet/rooms`, salvataggi in `starfleet/partite`):
  li copre la regola comune `$game` di `firebase/database.rules.json` della ludoteca.

## Prove

```
N=12 godot --headless --path . -s tests/autoplay.gd       # partite IA contro IA
godot --headless --path . -s tests/salva_carica.gd        # un salvataggio rigioca la stessa partita
python3 tests/firebase_mock.py 8765 &                     # finto Firebase per le prove online
SF_DB_URL=http://127.0.0.1:8765/db SF_AUTH_URL=http://127.0.0.1:8765/signup SF_REFRESH_URL=http://127.0.0.1:8765/refresh \
  SF_ROLE=host SF_CODEFILE=/tmp/c.txt godot --headless --path . -s tests/online_play.gd   # (e un secondo con SF_ROLE=guest)
xvfb-run godot --path . -s tests/shot.gd -- umano 5 /tmp/foto.png 0 1920 1080 fire  # screenshot
python3 tools/controlla_glifi.py                          # ogni carattere esiste nei font
```

## Pubblicazione

Non parte da sola: Actions, *Pubblica*, *Run workflow*, oppure un commit su `main` con `[pubblica]`
nel messaggio. Con i segreti `CLOUDFLARE_API_TOKEN` e `CLOUDFLARE_ACCOUNT_ID` pubblica anche sulla
ludoteca privata.
