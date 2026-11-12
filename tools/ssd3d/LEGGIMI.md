# Schede SSD in 3D

Come sono state create `assets/ssd3d/<nave>.png/.json` (caselle con cubetto, armi per tipo, scudi):

1. `analizza_tutte.py`: per ogni scheda trova le caselle (OpenCV), le raggruppa, legge le scritte con
   l'OCR (RapidOCR) e assegna ogni casella al sistema scritto più vicino nella stessa zona della scheda.
2. `correzioni.py`: rettangoli (coordinate del ritaglio) che correggono a mano le assegnazioni sbagliate
   dopo il controllo visivo di ogni scheda; `-` = nessun cubetto, `S:n` = caselle dello scudo n.
3. `costruisci_tutte.py` + `esporta.py`: ritaglio della scheda con trasparenza e file delle caselle.
Le caselle tratteggiate dei reattori convertiti dai refit non hanno cubetto.
