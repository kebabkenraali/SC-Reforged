"""Builds the Windows demo package: dist/StrikeCommanderDemo(.zip).

The demo contains the Godot runtime, the game scripts and the recorded
cut-scene timelines - no original game data. The player needs an installed
Strike Commander (e.g. the GOG version); the game asks for its folder on the
first start. res://demo.cfg switches the game into demo mode (the opening
cut-scene, the first base and mission 1A, then an end screen).
"""
import os, shutil, zipfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, 'dist', 'StrikeCommanderDemo')
ENGINE = os.path.join(ROOT, 'tools', 'godot', 'Godot_v4.7.2-stable_win64.exe')

README = """STRIKE COMMANDER REFORGED - DEMO
================================

Epävirallinen, modernisoitu pelimoottori Strike Commanderille (Origin Systems, 1993).
Demo sisältää alkuperäisen intron, ensimmäisen tukikohdan, tehtävänannon ja
kampanjan ensimmäisen tehtävän (1A) loppuraporttiin asti.

VAATIMUKSET
- Windows 10/11, Vulkan-yhteensopiva näytönohjain
- Asennettu alkuperäinen Strike Commander (esim. GOG-versio). Demo ei sisällä
  pelin kuvia, ääniä eikä muuta alkuperäistä dataa: ne luetaan omasta asennuksestasi.

KÄYNNISTYS
- Aja "Kaynnista demo.bat". Ensimmäisellä kerralla peli etsii asennuksen
  (esim. C:\\Gog games\\Strike Commander) tai kysyy sen kansion.

OHJAUS (oletus, näppäimistö / peliohjain)
- Nokka ylös/alas: S / W tai nuolet (vasen tikku)
- Kallistus: A / D tai nuolet, sivuperäsin: Q / E
- Kaasu: Shift / Ctrl (RT / LT), jälkipoltin: Tab (RB)
- Tykki: välilyönti tai hiiren vasen (A), asetila: V, laukaise ohjus/pommi: R (LB)
- Harhautteet: F (B), jarrut: B (X), kamera: C (Y), tauko: Esc (Start)
- Lentoonlähtö: kaasu täysille ja noin 130 solmun nopeudessa nokka ylös (S).
- Välianimaatioissa Esc / Enter / Start ohittaa.
Näppäimet voi vaihtaa valikosta Options.

Strike Commander (c) 1993 Origin Systems / Electronic Arts. Tämä on epävirallinen
fanityö, jolla ei ole yhteyttä alkuperäisiin tekijänoikeuksien haltijoihin.
Moottori: Godot Engine 4.7 (MIT-lisenssi, https://godotengine.org/license).
"""

BAT = '@echo off\r\nrem Strike Commander Reforged - demo (vaatii alkuperaisen Strike Commanderin)\r\nstart "" "%~dp0engine\\Godot_v4.7.2-stable_win64.exe" --path "%~dp0game" %*\r\n'


def main():
    if os.path.isdir(OUT):
        shutil.rmtree(OUT)
    os.makedirs(os.path.join(OUT, 'engine'))
    shutil.copy2(ENGINE, os.path.join(OUT, 'engine'))
    game = os.path.join(ROOT, 'game')
    shutil.copytree(game, os.path.join(OUT, 'game'),
                    ignore=shutil.ignore_patterns('tests', '.godot', '*.tmp'))
    open(os.path.join(OUT, 'game', 'demo.cfg'), 'w').write('; demo build: ends after the first campaign mission\n')
    open(os.path.join(OUT, 'Kaynnista demo.bat'), 'w', newline='').write(BAT)
    open(os.path.join(OUT, 'LUEMINUT.txt'), 'w', encoding='utf-8', newline='\r\n').write(README)
    z = OUT + '.zip'
    if os.path.exists(z):
        os.remove(z)
    with zipfile.ZipFile(z, 'w', zipfile.ZIP_DEFLATED) as zf:
        for base, _, files in os.walk(OUT):
            for f in files:
                p = os.path.join(base, f)
                zf.write(p, os.path.relpath(p, os.path.dirname(OUT)))
    print('demo:', OUT)
    print('zip: %s (%.0f MB)' % (z, os.path.getsize(z) / 1e6))


if __name__ == '__main__':
    main()
