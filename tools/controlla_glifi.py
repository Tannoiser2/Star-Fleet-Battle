#!/usr/bin/env python3
"""Controlla che ogni carattere usato nei testi del gioco esista nei caratteri dell'interfaccia.

Scorre gli script (.gd), i dati e il regolamento (.md, .json) e verifica i caratteri non ASCII
in tutti i font di assets/fonts. Se un carattere manca in un font, a schermo comparirebbe un
quadratino: lo segnala ed esce con errore.
Uso: python3 tools/controlla_glifi.py
"""
import glob, os, sys
from fontTools.ttLib import TTFont

RADICE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FONT = {
    "Antonio.ttf": "titoli e comandi",
    
    "Oxanium.ttf": "testi",
    "ShareTechMono-Regular.ttf": "numeri",
}

testo = ""
for pat in ("scripts/**/*.gd", "assets/*.md", "ludoteca/*.json"):
    for f in glob.glob(os.path.join(RADICE, pat), recursive=True):
        testo += open(f, encoding="utf-8").read()
usati = sorted(set(c for c in testo if ord(c) > 126))
errori = 0
for nome, uso in FONT.items():
    cmap = TTFont(os.path.join(RADICE, "assets/fonts", nome)).getBestCmap()
    mancano = [c for c in usati if ord(c) not in cmap]
    if mancano:
        errori += 1
        print("%s (%s): mancano %s" % (nome, uso, " ".join("%s U+%04X" % (c, ord(c)) for c in mancano)))
print("caratteri non ASCII usati:", "".join(usati))
if errori:
    sys.exit(1)
print("tutti i caratteri sono presenti in tutti i font")
