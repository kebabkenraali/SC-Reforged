# Strike Commander Reforged: ohjeet kehittäjälle ja tekoälyagentille

Päivitetty 16.11.2026. Tämän tiedoston vanha, pitkä versio (istuntopäiväkirjat 9.–15.11.)
on git-historiassa commitissa `2aca5e2`: `git show 2aca5e2:AI_INSTRUCTIONS.md`.

## Lukujärjestys

1. **`SUUNNITELMA.md`**: todennettu tila, vaiheet ja hyväksymisehdot. Aloita tästä.
2. Tämä tiedosto: komennot, säännöt ja tunnetut ansat.
3. `README.md`: mitä on toteutettu, ohjaus, komentorivivalitsimet.
4. **`docs/PROG_VM.md`**: tehtäväskriptien tulkki purettuna alkuperäisestä STRIKE.EXE:stä
   (17.11.2026). Ohittaa TIEDOSTOFORMAATIT.md:n vanhat PROG-opkooditulkinnat.
   **`docs/GAMEFLOW_VM.md`**: kampanjan efektitulkki purettuna OPTTEST.EXE:stä.
   `docs/TIEDOSTOFORMAATIT.md` (dataformaatit),
   `docs/MISN-1A_TAPAHTUMAKETJU.md` (ensimmäisen tehtävän skripti),
   `docs/GODOT_PORT_PLAN.md` (ominaisuusmatriisi).

## Projekti lyhyesti

- Epävirallinen moderni moottori Strike Commanderille (Origin 1993). Godot 4.7.2, GDScript.
- Godot-projekti on `game/`. Moottori: `tools/godot/Godot_v4.7.2-stable_win64.exe`
  (ei versionhallinnassa).
- Kaikki pelisisältö luetaan ajossa pelaajan asennuksesta. Tällä koneella data on
  kahdessa paikassa: `C:/Gog games/Strike Commander` ja `C:/AI_Projektit/SC-REFORGED`
  (jälkimmäinen on tallennettu pelin asetuksiin). Polun voi pakottaa `--dir=`-valitsimella
  tai ympäristömuuttujalla `SC_GAME_DIR`.
- Tärkeimmät tiedostot: `game/scripts/main.gd` (käynnistys, headless-ajuri),
  `game/scripts/game/flight_scene.gd` (lento, autopilotit, tehtäväskriptin isäntä, 2700 riviä),
  `aircraft.gd` (lentomalli), `mission_vm.gd` (PROG-tulkki), `formats/` (datalukijat),
  `ui/base_screen.gd` + `game/campaign.gd` (kampanja).

## Tila 16.11.2026

- Yksikkötestit vihreitä, loppulähestyminen (`--approach`) laskeutuu.
- MISN-1A:n tehtäväosuus toimii (vaihe 2): skriptin oma onnistumispolku 3/3, siipimies ja
  C-130 selviävät.
- **M1 saavutettu 17.11.:** täysi MISN-1A-autopilottilento 5/5 onnistui (`Aja_Testit.ps1 -Taydet 5`).
- Kampanja etenee lennon jälkeen seuraavaan vaiheeseen myös epäonnistumisen jälkeen (GAMEFLOW).

## Testaus

```powershell
.\Aja_Testit.ps1 -Taydet 0    # yksikkötestit + loppulähestyminen, alle minuutti
.\Aja_Testit.ps1              # lisäksi 3 täyttä MISN-1A-lentoa rinnakkain
.\Aja_Testit.ps1 -Taydet 5    # M1:n hyväksymisajo
```

Paluukoodi on epäonnistuneiden kohtien määrä, lokit `tmp/testit/`. Yksittäiset komennot
ovat `SUUNNITELMA.md`:n lopussa.

Headless-ajon paluukoodit: 0 = tehtävä onnistui, 3 = muu lopputulos, 4 = aikakatkaisu.
`--approach` päättyy oikein koodiin 3 ("incomplete", koska tavoitteita ei lennetty);
onnistumisen merkki on "Landed at base" ja runko 100 %.

## Työskentelysäännöt

1. **Git on käytössä 16.11. alkaen.** Commit ennen muutosta ja todennetun tilan jälkeen.
   Ei enää `.bak_*`-tiedostoja. Ei pushia ilman käyttäjän lupaa.
2. Yksi istunto muokkaa `game/`-kansiota kerrallaan. Kaksi rinnakkaista istuntoa
   ylikirjoitti toistensa työn 11.11.
3. Laskeutumis- ja autopilottikoodiin pieniä muutoksia yksi kerrallaan, ja jokaisen
   jälkeen `Aja_Testit.ps1`. Laajat uudelleenkirjoitukset (LINEUP/GLIDE-rakenne,
   pattern-portit) epäonnistuivat 10.–11.11.; niiden koodi on historiassa
   (`flight_scene.gd.bak_20261111_pattern`, `tmp/flight_scene_gd_agentB_lineup_20261111.gd`).
4. "Toimii" vaatii usean ajon: täydet lennot eivät ole toistettavia (fysiikka riippuu
   kehysajoituksesta). `--approach`-ajot ovat olleet keskenään identtisiä.
5. **Älä käytä `Stop-Process -Name Godot*`.** Koneella on usein muiden istuntojen
   Godot-prosesseja. Lopeta vain oma PID; `Aja_Testit.ps1` käyttää omaa nimikopiota.
6. Alkuperäistä tekstiä tai dataa ei commitoida: `tmp/`, `docs/PLAYTESTERS_GUIDE.txt`,
   `docs/SC_MANUAL.txt` ja `docs/DEKOMPILU/` ovat `.gitignore`:ssa. `game/data/cutscenes/`
   sisältää tallennettuja tekstityksiä; tarkista ne ennen kuin repo julkaistaan.
7. PowerShell-skriptit pidetään ASCII:na (PS 5.1 lukee BOMittoman tiedoston ANSI:na).

## Tunnetut ansat

**Godot ja headless**
- Älä lisää Godotin omaa `--quit`-lippua pääscenen ajoihin: se lopettaa yhden kehyksen
  jälkeen. Ajo päättyy itse tehtävän loppuun, `--frames=N`:ään tai `--timeout=S`:ään.
- `--shot` ei toimi `--headless`-tilassa (ei renderöijää). Kuvakaappaukset ikkunassa.
- `--auto=campaign` jää headless-tilassa tukikohtaruutuun odottamaan klikkausta.
- Valitsimet toimivat `--`-erottimen kanssa ja ilman.
- Lokien glTF/mesh-ERROR-rivit ovat ulkoisten mallien latausvaroituksia, eivät vikoja.

**Lentomalli ja autopilotti**
- Fly-by-wire-sauva (`controls.x`, `_ap_vs_hold`) ei pysty käskemään noin -6 m/s
  syvempää vajoamaa. Jyrkempään tarvitaan suora `pitch_rate_override` (`_ap_vs_pitch`).
- `_terrain_pullup_needed()` laukeaa kukkulaisessa maastossa jatkuvasti 300–400 m
  korkeudessa ja voi jättää koneen ikuiseen veto–lasku-kiertoon.
- Vaihtoportit ilman hystereesiä saavat koneen pomppimaan tilojen välillä.
- Kaasun P-säädin ilman viivettä yhdessä nopeuteen kytketyn vajoamiskäskyn kanssa
  vahvistaa syöksy–nousu-heiluntaa.
- Laskeutumisessa on kaksi korkeusdatumia: liukupolku lasketaan kynnyksestä, mutta
  `agl` paikallisesta maastosta. Nouakchottin ja tukikohdan ympäristössä ero on suuri.
- Kosketus hyväksytään alle noin 165 m/s (`aircraft.gd`); pehmeä lasku on alle 115 m/s.
- Kaikilla koneilla on samat F-16:n suoritusarvot. Kuljetuskoneiden nopeutta rajoittaa
  vain `cruise_speed`; uusille konetyypeille rajaus `TRANSPORT_MODELS`-listaan.
- Pelilogiikan ajastukset simulaatioajalla (`_sim_time`), ei `Time.get_ticks_msec()`:llä.
  Vain radioäänen ajoitus on tarkoituksella reaaliajassa.

**Tehtävädata**
- AREA-tietueen koko riippuu tyypistä: 'S' 49, 'B' 65, 'C' 53 tavua.
- C-130:n (id 8) PART-sijainti on maaston alla; se sijoitetaan aktivoivan kohtauksen
  alueelle (`_activation_spawn_position`).
- Kohtausten lentokoneet syntyvät vasta, kun pelaaja tulee alueelle (`_scene_wait`).
- Saattokohteet (`a8` pelaajan puolelta) luokitellaan ystäviksi sivutavusta riippumatta.
- VOCLIST-äänitiedoston nimen etuliite on puhuja (`AI` = pelaaja, `ST` = Stern), ei tehtävä.
- Pelaajan route-blokin `ab n` on reittipisteen teksti, ei radiolähetys.
- Alkuperäisen pelin purku: purkulistaukset vain paikallisesti (`docs/DEKOMPILU/` on
  .gitignoressa); projektiin kirjataan vain omin sanoin kirjoitetut havainnot.
- PROG-tulkki on akkumulaattorikone, ja liput ovat samoja muuttujia (ks. `docs/PROG_VM.md`).
  `97 n` = etäisyys SPOTiin n, yksikkö 1000 ft. Älä palauta vanhoja pinokonetulkintoja.

## Työkalut

- `game/tools/mission_chain.gd`: purkaa tehtävän briefingin ja PROG-skriptin selitettynä
  (`-- MISN-1A` → `tmp/MISN-1A_chain.md`).
- `game/tools/prog_analyze.gd`: avoimien opkoodien käyttöyhteydet kaikista tehtävistä.
- `tools/cutscenes/`: DOS-emulaattori välianimaatioiden jäljitykseen (Python, `unicorn`).
- `tools/decompile/disasm.py`: alkuperäisten EXE-tiedostojen disassemblointi.
- `tools/make_demo.py`: demopaketin rakennus kansioon `dist/`.
