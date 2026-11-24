# Strike Commander: Tactical Operations (lisäosa)

Alkuperäisen pelin lisäosa on **Tactical Operations** (ei "Secret Operations").
Se löytyy pelaajan omasta GOG/CD-asennuksesta, esim.
`C:/AI_Projektit/SC-REFORGED/`. Mitään alkuperäistä ei kopioida repositorioon —
kaikki luetaan pelaajan omasta installista.

## Missä data on

| Sijainti | Mitä |
|---|---|
| `TOPTTST1.EXE` (837 kt) | Lisäosan oma GAMEFLOW-/työkaluohjelma (kuten `OPTTEST.EXE` peruspelissä); 64 overlayta purettu |
| `TOBIGTRE.TRE` | Lisäosan 30 tehtävää `MISN-A1.IFF` … `MISN-H1.IFF` sekä oma gameflow-data |
| `GAMEFLOW/GAMEFLO2.IFF` | 28 kampanjavaihetta, FORM MLST (37 tehtävänimeä) |
| `GAMEFLOW/OPTIONS2.IFF` | 15 ruutua (FORM OPTS / SCEN) |
| `GAMEFLOW/CONVDAT2.IFF` | 47 keskustelutaustaa, 19 kasvoa |
| `GAMEFLOW/CONV2.PAK`, `CONVSHP2.PAK`, `OPTSHPS2.PAK`, `OPTPALS2.PAK` | Lisäosan omat kuvat (overlayt peruspelin arkistojen päällä) |
| `MIDGAMES/TO1MID1-3.PAK`, `TOMIDVOC.PAK`, `MIDGAMS2.IFF` | Lisäosan cutscenet |
| `MISN2OP.IFF`, `OP2MISN.IFF` | `INVNINFO` / `INSTANT STAT` -tiedot |

## Toteutettu kampanjaohjaus

- `SCData` indeksoi `TOBIGTRE.TRE`:n; `SCData.missions()` palauttaa nyt **77**
  tehtävää (47 perus + 30 lisäosan). Maastoaliakset kuten `SYRIA22 → SYRIA.PAK`
  on resolvoitu `has_terrain()`-tarkistuksella.
- `Campaign.tactical` + `Art.set_active("tactical")` vaihtavat koko UI:n
  lisäosan dataan. `GAMEFLO2.IFF:n` FORM MLST antaa tehtävien järjestyksen:
  effect `0c n` / `16 n` valitsee saman tehtävän kuin alkuperäisessä.
- `--tactical` käynnistää lisäosan kampanjan (`--auto=campaign --tactical`).
  Se ei soita peruspelin MID1:tä: vaihe 0 alkaa lisäosan omalla `02:05`
  (story) ja `08:05` (establishing shot) -efektillä.
- Tactical-lippu tallentuu saveen ja lataus vaihtaa art-setin ennen gameflown
  käyttöä.
- Lisäosan cutscene-fallback lukee `TO1MID1-3.PAK`, `TOMIDVOC.PAK` ja
  `MIDGAMS2.IFF`:n (8 kuvaa, 10 ääntä, 16 tekstiä). Tarkka esitysaika on
  edelleen tallentamatta `TOPTTST1.EXE`:stä; siihen asti näytetään
  likimääräinen staging.

### Miksi tarkkaa aikajanaa ei saatu tallennettua (tutkittu 23.11.2026)

`tools/cutscenes/trace_mid.py` on sidottu `OPTTEST.EXE`:n absoluuttisiin
osoitteisiin (DRAW `0x40570`, COPY `0x3fbb0`, SDRAW `0x407be`, speech-hookit
`0x14277` jne.). `TOPTTST1.EXE` on **uudelleen käännetty**, ei vain uusi overlay:
näiden funktioiden tavujonot eivät löydy siitä (esim. DRAW `c48ae2360306...`
ei esiinny missään kohdassa; SDRAW:sta löytyy kaksi eri sijaintia). Osa
funktioista löytyi siirtymällä — SPINIT `0x14277 → 0x115a0`, PAKLOAD
`0x195da → 0x16b5e`, MKPATH `0x199fc → 0x16f80` — mutta siirtymä ei ole
vakio, joten pelkkä uudelleenpohjustus ei riitä.

Lisäksi emulaattori (`emu.py`, `UC_MODE_16`) pysähtyy `TOPTTST1.EXE`:llä heti
ensimmäisessä tickissä osoitteeseen `d80b:00de`, jossa tavut `fe 75 0e` ovat
virheellinen 16-bittinen opcode — eli suoritus on ajautunut dataan. Syy on
todennäköisesti erilainen PSP/overlay-lataus tai 386-koodi, jota nykyinen
emulaattori ei tue.

Tutkimusväline: `tools/cutscenes/probe_to.py` (ajetaan `SC_EXE=TOPTTST1.EXE`).
`emu.py` hyväksyy nyt `SC_EXE`-ympäristömuuttujan, jolla valitaan ajettava
EXE. Tarkan aikajanan tallennus vaatii erillisen työn: uusien hook-osoitteiden
kartoitus + emulaattorin käynnistyskorjaus. Siihen asti fallback on ainoa
toimiva polku, ja se on testattu (8 kuvaa / 10 ääntä / 16 tekstiä, 0 virhettä).

## Tärkeä huomio: lisäosan PAK:t ovat overlayt

`CONVSHP2.PAK`:ssa on 96 ennätettä, joista vain 4 on käyttökelpoisia
(indeksit 0, 93, 94, 95 — indeksi 0 on tiedostonimi, ei kuva). `CONVDAT2.IFF`
osoittaa kasvot edelleen peruspelin `CONVSHPS.PAK`-indekseihin (esim. Gwen =
46). `Art._pak()` yhdistää perus- ja lisäosa-arkistot: perusentriä käytetään
aina, paitsi kun lisäosalla on samassa indeksissä oikea kuva. Ilman tätä
keskustelut ja ruudut olivat mustia.

## Todisteet

```powershell
& "C:\AI_Projektit\strike commander\Aja_Testit.ps1" -Taydet 1 -Data "C:/AI_Projektit/SC-REFORGED"
# 22 yksikkötestiä OK, 0 skriptivirhettä, MISN-1A success

Godot --path game --script res://tests/visual_sweep.gd -- --tactical --demo `
  --dir=C:/AI_Projektit/SC-REFORGED
# 15 ruutua + 118 keskustelua, 0 tyhjää kuvaa, 0 skriptivirhettä
# kuvat: tmp/tactical_proof/
```

Testauslista ja baseline: `docs/TACTICAL_OPS_TEST_PLAN.md`.
Purkutyökalut: `tools/decompile/pura_tulkit.py`, `tools/cutscenes/`.
Purkutulokset ovat paikallisesti `alkuperainen_purku/` (vain README tracked).
