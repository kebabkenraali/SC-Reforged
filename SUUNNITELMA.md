# Strike Commander Reforged: tilannekatsaus ja suunnitelma

Päivitetty 24.11.2026. Perustuu projektin ohjetiedostoihin, koodin läpikäyntiin ja 24.11. ajettuihin testeihin. Tämä tiedosto korvaa aiemmat jatkosuunnitelmat (`AI_INSTRUCTIONS.md`:n eri osiot, `README.md`:n "Next steps", `docs/GODOT_PORT_PLAN.md`:n avoimet kohdat) siltä osin kuin ne ovat ristiriidassa tämän kanssa. Uusin käyttäjän ohje (24.11.) on kirjattu vaiheeseen 7.

## 1. Mitä yritetään tehdä

Epävirallinen moderni moottori alkuperäiselle Strike Commanderille (1993) Godot 4.7.2:lla (GDScript). Kaikki sisältö luetaan ajon aikana pelaajan omasta asennuksesta; projektissa ei jaeta alkuperäistä dataa. Lopputavoite on koko kampanja pelattavana alusta loppuun.

Välitavoitteet tärkeysjärjestyksessä:

1. **M1:** ensimmäinen tehtävä MISN-1A lentää autopilotilla alusta loppuun ja laskeutuu toistettavasti (headless, exit 0). **Saavutettu 17.11.2026.**
2. **Tehtävämääritykset:** alustava määritys jokaisesta `MISSIONS/*.IFF`-tehtävästä. Pohjatyö tehty (PROG/GAMEFLOW-tulkki), yksittäiset määritykset puuttuvat.
3. **Kampanja:** kaikki tehtävät ja tarinavaiheet läpi, myös Tactical Operations -lisäosa.
4. **Ohjaamo ja pelimekaniikat:** 24.11. annettu käyttäjän suunnitelma (vaihe 7): aseikkuna, kohde-/pommiseuranta, tapahtumaikkuna ja kaksi pelimoodia.
5. **Puuttuvat alkuperäisominaisuudet** ja julkaisukelpoinen demo.

## 2. Todennettu tila 24.11.2026

Projekti on **git-repo**. Viimeinen commit `88c3636` (19.11.2026, `.uid`-tiedostojen ignore). Työpuu on **auki**: 28 muokattua tiedostoa ja useita uusia tiedostoja — lähinnä 23.–24.11. tehtyä VR-, ohjaamo-, Tactical Operations- ja cutscene-työtä, jota ei ole vielä commitoitu. Yksi istunto kerrallaan saa muokata `game/`-kansiota.

Data: `C:/AI_Projektit/SC-REFORGED` (erillinen tutkimuslinja, ei kuulu tähän projektiin; vain datalähde).

| Testi / ajo | Tulos 24.11. |
|---|---|
| `Aja_Testit.ps1 -Taydet 1` (30 yksikkötestiä, klo 12:12–12:14; 31 uuden testin jälkeen) | kaikki `failures=0`, 0 skriptivirhettä |
| `--approach` | `result=incomplete, Landed at base`, runko 100 % (tehtävän kohteet ovat tekemättä, oikea tulos) |
| Täysi MISN-1A `m1_1` | `result=success, Landed at base`, runko 100 % |
| Täysi MISN-1A `--mode=arcade` | `result=success`, runko 100 %, 0 skriptivirhettä (ikkunat ja asemekaniikat aktiivisina) |
| M1:n hyväksymisajo 17.11. (`-Taydet 5`) | 5/5 success |
| `cockpit_test` / `cockpit_mission_sweep` | 24/24 konetta, 77/77 tehtävää ohjaamonäkymässä |
| `vr_test`, `shader_test`, `hud_attachment_test`, `cutscene_audio_test`, `librealspace_parity_test` | 0 vikaa |
| `visual_sweep --tactical` | 15 ruutua + 118 keskustelua, 0 tyhjää kuvaa |

Headless-lokeissa näkyy `XR_ERROR_GRAPHICS_DEVICE_INVALID` ja OpenXR RID -vuotoja:XR alustuu myös headlessissä, mutta ne eivät vaikuta testituloksiin. Tällä koneella OpenXR Simulator on käytössä; oikea headset ei streamaa.

## 3. Mikä toimii, mikä ei

**Toimii (testein todennettu):** datalukijat (ISO, TRE, PAK, IFF, LZW, paletit, mallit, maastot, tehtävät), lentomalli ja nousu, PROG- ja GAMEFLOW-virtuaalikoneet, kampanjan haarautuminen ja tallennus, keskustelut puheineen, välianimaatioiden aikajanat, äänet, radio, kohtausten aktivointi, reitti- ja taisteluautopilotti, laskeutuminen täydestä lennosta, 77 tehtävän lataus ja parsinta, Tactical Operations -kampanjaohjaus, virtuaalinen ohjaamo alkuperäisdatasta, 3D-mittarit, HUD kiinnitettynä lentokoneeseen, VR (OpenXR) simulaattorilla, neljä kameranäkymää.

**Ei toimi / auki:**

- Muiden tehtävien täysi suoritus autopilotilla: baseline `results.csv` 9 `success`, 20 `incomplete`, 3 `failed`, 45 `NO_RESULT` (300 s wall-clock). Täysi `MISSION OVER` ei ole autopilotin kykyrajoituksessa pakollinen.
- `TOPTTST1.EXE`:n tarkka cutscene-aikajana puuttuu; emulaattori ajautuu dataan. Käytössä fallback (8 kuvaa / 10 ääntä / 16 tekstiä).
- Tuntemattomat opkoodit: `09`, `b5`, `b6`, `b8`, `b9`, `02 04`, parametrit `21/24/25/2f`; parity-testi listaa `[21, 36, 43, 47, 181, 190]`. Opkoodin `97` dokumentaatio on ristiriidassa koodin kanssa.
- GAMEFLOW:n effect-12-arvot 9, 11–39, 43–46 ja MID1:n täysi jäljitys.
- Vaiheen 7 ominaisuudet (kohde-/pommiseuranta, tapahtumaikkuna, pelimoodit) eivät ole vielä toteutettu.
- `demo/`-paketti on vanhentunut; `tools/make_demo.py` kaipaa päivityksen.
- F16DES.glb:n lisenssi (CC BY-NC-SA) ratkaisematta julkaisun suhteen.

## 4. Ohjeiden ristiriidat ja rakenteelliset ongelmat

1. **Git on nyt käytössä** (päivitetty 16.11., commit `2aca5e2` lähtötilasta). Vanha väite "ei versionhallintaa" ei päde. Työpuu on kuitenkin edelleen suurilta osin commitoimatta — seuraava commit on prioriteetti.
2. **`AI_INSTRUCTIONS.md` on kirjoitettu uudelleen** (lyhyt, 17.11.), ja siinä M1 on oikein "saavutettu". **`README.md` ja `docs/GODOT_PORT_PLAN.md` ovat yhä vanhentuneita**: ne sanovat M1:n "REGRESSED" / 16.11. tilaan. Korjataan julkaisuvaiheessa.
3. **Kolme moottorikopiota** (`tools/godot/`, `engine/`, aiemmin `demo/Godot.exe`): käynnistimet käyttävät `tools/godot/`-kopiota; `engine/` on gitignored ja poistettavissa käsin.
4. **Roskaa lähdepuussa:** kertakäyttöisiä `fix_*.py`-skriptejä, `src/main.py` (ei liity projektiin), vanha `dist/` + `dist.7z` (350 Mt, gitignored).
5. **Lisenssi:** `game/models/README.md` ja README lupaavat "CC0 only", mutta `F16DES.glb` on CC BY-NC-SA 4.0. `docs/PLAYTESTERS_GUIDE.txt`, `docs/SC_MANUAL.txt` ja `tmp/` sisältävät alkuperäistä tekstiä, eivät julkiseen repoon.
6. **Opkoodi `97`:** `AI_INSTRUCTIONS.md`: "etäisyys", `flight_scene.gd`: "open, push 0 for now", README: "still open". Koodin toteutus tarkistettava ja kommentti korjattava.

`C:\AI_Projektit\SC-REFORGED` on erillinen tutkimuslinja (alkuperäisen pelin muokkaus DOSBoxissa); tämä projekti käyttää sitä vain datalähteenä.

## 5. Suunnitelma

Vaiheet tehdään järjestyksessä; jokaisella on hyväksymisehto.

### Vaihe 0: Perusta kuntoon — TEHTY 16.11.

Git-init, `.gitignore`, yksi testiajuri `Aja_Testit.ps1`, yksi moottori (`tools/godot/`), siivous, `AI_INSTRUCTIONS.md` uudelleenkirjoitus. Hyväksyminen: puhdas `git status`, koko testisarja yhdellä komennolla. **Nykytila:** testiajuri toimii, mutta työpuu ei ole puhdas — committaa 23.–24.11. työ seuraavaksi.

### Vaihe 1: M1 takaisin — TEHTY 17.11.

`Aja_Testit.ps1 -Taydet 5`: 5/5 täyttä MISN-1A-lentoa `result=success`, runko 100 %, siipimiehet 2/2, skriptin "Mission accomplished". Korjaukset `flight_scene.gd:_autopilot_land`: kiitotien pää valitaan maaston mukaan ja lukitaan; liukupolku kynnyksen korkeudesta; 15 m ylityskorkeus; pystysäädin lentoradan kulmalle; keskilinjan seuranta ja lähestymiskartio; go-around liukupolun korkeudella; vapautus 8,5 km:ssä. Pikatoisto: `--approach=M --approach_high=M --approach_speed=M/S`.

### Vaihe 2: MISN-1A valmiiksi tehtävänä — OSITTAIN TEHTY

Tehtäväskriptin oma onnistumispolku, siipimiesten ampuminen, maastoväistö, C-130:n aktivointi ja nopeus, simulaatioaikaan perustuva debrief. Avoinna: toistettavuus (täydet lennot eivät ole identtisiä), käyttäjän käsin lentämä tarkistus, `46 r` -opkoodin tulkinta.

### Vaihe 3: Muiden tehtävien alustavat määritykset — POHJATYÖ TEHTY

PROG-tulkki purettu `STRIKE.EXE`:stä (`docs/PROG_VM.md`), GAMEFLOW-tulkki `OPTTEST.EXE`:stä (`docs/GAMEFLOW_VM.md`). `docs/tehtavat/`-kansiota ja kokoomataulukkoa ei ole vielä tehty. Seuraavaksi: `mission_chain.gd` kaikille IFF:ille, yhteenveto omin sanoin, `all_missions_test`, opkoodien priorisointi.

### Vaihe 4: Tehtävät lentokuntoon ja kampanja läpi — KESKEN

77 tehtävää latautuu; MISN-1A on lennetty. Autopilotin kykyrajoite kirjattu baselineen (ks. vaihe 3 / `docs/TACTICAL_OPS_TEST_PLAN.md`). Seuraavaksi: tehtävät kampanjajärjestyksessä, headless-kampanja-ajuri, loadout-ruudun kytkentä.

### Vaihe 5: Puuttuvat alkoperäisominaisuudet — OSITTAIN TEHTY

Tehty 18.11.: kirjanpito, tappotaulu ja asekatalogi (`office_screens.gd`). Tehty 23.–24.11.: Tactical Operations -kampanjaohjaus (`docs/TACTICAL_OPS.md`), cutscene-kuvasuhde 320×200, musiikki kaikissa poluissa, libRealSpace-pariteettitesti. Auki: DYNM-lentoparametrit, WEAP/HPTS-aseet, nimet tekstityksiin, musiikin läpikäynti.

### Vaihe 6: Julkaisu — EI ALOITETTU

F16DES-lisenssin päätös, `tools/make_demo.py` ajan tasalle, uusi demopaketti, `demo_test` vihreäksi, README ja `GODOT_PORT_PLAN.md` korjataan nykytilaa vastaavaksi.

### Vaihe 7: Ohjaamon lisäikkunat ja pelimoodit — TOTEUTETTU 24.11.

`Aja_Testit.ps1 -Taydet 1`: 31 yksikkötestiä OK (mukaan lukien uusi `cockpit_windows_test`), `--approach` laskeutuu, täysi MISN-1A `result=success`, runko 100 %, yhteenveto 0 vikaa. Mittarien osakuvat renderöity uudelleen. Dokumentaatio: `docs/VIRTUAL_COCKPIT.md`.

Käyttäjän 24.11. antama suunnitelma (kuva `shots/instruments/` + käyttäjän kokoama asettelukuva):

1. **Aseikkuna vasempaan suureen vihreään ruutuun.** Ohjukset, pommit ja tykkiammus yhtenä näkymänä `mfd_l`-paikassa. Tutka siirtyy oikealle `mfd_r`-paikalle. Korkeus/nopeus pysyvät nykyisinä numeerisina näyttöinä.
2. **Kohdeseurantaikkuna (killcam).** Ohjuksen laukaisun jälkeen ylävasemmalle taivaalle ilmestyy pieni ikkuna, joka seuraa kohdetta (oikea 3D-kamera jaettuun World3D:hen). Sama mekaniikka pommin pudotukselle: pommin/maalin seurantaikkuna. Ikkuna näkyy vain Arcade-moodissa.
3. **Tapahtumaikkuna killcamin alle.** Tärkeät tapahtumat näytetään omassa ikkunassa: esim. MISN-1A:ssa saatettavan C-130:n laskeutuminen / "Mission accomplished", sekä muut vastaavat merkittävät tapahtumat ja pommin pudotus.
4. **Kaksi pelimoodia.** `realistinen` (oletus): lyhyt ohjuslukitus, heikompi ohjautuminen, ei killcami. `arcade`: pidempi lukitusetäisyys, vahvempi ohjautuminen, seurantaikkunat päällä, enemmän ammuksia. Valinta komennorivillä ja asetuksissa.
5. **Testit:** uusi `cockpit_windows_test.gd` (ikkunoiden solmut, MFD-vaihto, moodin arvot), `hud_attachment_test` ja `cockpit_test` pysyvät vihreinä, täysi MISN-1A `result=success`.

Hyväksyminen: kuvatkaappaus ohjaamosta näyttää aseikkunan vasemmalla, tutkan oikealla, kohde-/tapahtumaikkunat ylävasemmalla; molemmat moodit toimivat; testisarja 0 vikaa.

## 6. Työskentelysäännöt

- Ei koodimuutosta ilman commitia sitä ennen ja testiajoa sen jälkeen.
- Laskeutumis- ja autopilottikoodiin vain pieniä, yksi kerrallaan todennettuja muutoksia.
- "Valmis" tarkoittaa: komento, päivämäärä ja tulos kirjattuna. Yksi onnistunut ajo ei riitä.
- Vain yksi istunto muokkaa `game/`-kansiota kerrallaan.
- Älä käytä `Stop-Process -Name Godot*`. Aja testit omalla nimellä kopioidulla moottorilla ja lopeta vain oma PID.
- Älä käytä Godotin `--quit`-lippua pääscenen ajoissa. `--shot` ei toimi `--headless`-tilassa.
- Suodata lokeista glTF/mesh-ERROR-rivit; ne ovat mallien latausvaroituksia.
- Alkuperäistä tekstiä tai dataa ei commitoida eikä paketoida.
- Mittarien osakuvat (`shots/instruments/`) renderöidään skriptillä `game/tools/render_cockpit_parts.gd` (ikkunallinen Godot, ei `--headless`).

## 7. Komennot

```powershell
$eng = "$env:TEMP\scr_engine_sc.exe"
Copy-Item "C:\AI_Projektit\strike commander\tools\godot\Godot_v4.7.2-stable_win64.exe" $eng

# Koko testisarja (31 yksikkötestiä + approach + 1 täysi MISN-1A)
& "C:\AI_Projektit\strike commander\Aja_Testit.ps1" -Taydet 1 -Data "C:/AI_Projektit/SC-REFORGED"

# Yksikkötesti (vaihda testin nimi)
& $eng --headless --path "C:/AI_Projektit/strike commander/game" --script res://tests/cockpit_test.gd

# Pelkkä loppulähestyminen (noin 10 s)
& $eng --headless --path "C:/AI_Projektit/strike commander/game" --auto=flight --mission=MISSIONS/MISN-1A.IFF --approach --fast --status=5 --ap_debug --timeout=150 --dir="C:/AI_Projektit/SC-REFORGED"

# Täysi MISN-1A (exit 0 = onnistui, 3 = epäonnistui, 4 = aikakatkaisu)
& $eng --headless --path "C:/AI_Projektit/strike commander/game" --auto=flight --mission=MISSIONS/MISN-1A.IFF --autopilot --fast --status=30 --ap_debug --timeout=540 --dir="C:/AI_Projektit/SC-REFORGED"

# Mittarien osakuvat (IKKUNALLINEN)
& "C:\AI_Projektit\strike commander\tools\godot\Godot_v4.7.2-stable_win64.exe" --path "C:/AI_Projektit/strike commander/game" --script res://tools/render_cockpit_parts.gd
```
