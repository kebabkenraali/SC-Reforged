# Strike Commander CD-ROM (GOG) – tiedostoformaatit

Muistiinpanot tämän projektin käänteismallinnuksesta. Lukijat: `game/scripts/formats/`.

## Asennus

| Tiedosto | Sisältö |
|---|---|
| `SC.dat` | Pelin CD-kuva: raaka Mode 1 -kuva, 2352 tavua/sektori, data alkaa sektorin tavusta 16. ISO 9660, levyn nimi `STRIKE`. |
| `LILTRE.TRE` | Kiintolevylle asennettu pieni arkisto (äänet, ohjaamo, maastotekstuurit `TXM/TXMPACK.PAK`). |
| CD: `BIGTRE.TRE` | Pääarkisto: `OBJECTS`, `MISSIONS`, `PALETTE`, `GAMEFLOW`, `MIDGAMES`, `INTEL`, `FONTS`. |
| CD: `VOCLIST.TRE` | Puhe. `TOBIGTRE.TRE` / `TOVOCLST.TRE` = Tactical Operations -lisäosa. |
| CD: `*.PAK` juuressa | Maastoalueet: ALASKA, ANDMAL1/2, ARENA, CANYON, EGYPT, EUROPE, HAWAII, IRELAND, MAURITAN, NICARAGA, QUEBEC, RHODEI, SANFRAN, SIBERIA, SOAFRICA, SYRIA, TURKEY. |

`SC.CFG` määrää arkistojen hakujärjestyksen: `liltre.tre`, `bigtre.tre`, `voclist.tre`.

## TRE-arkisto

```
u32 count
u32 data_start
count × 74 tavua: u8 flag, char name[65] ("..\..\DATA\OBJECTS\F-16DES.IFF"), u32 offset, u32 size
```

## IFF

EA IFF-85, isot endiaanit kokokentissä. `FORM`/`CAT `/`LIST` sisältävät 4 merkin tyypin.

## PAK

```
u32 total_size
u32 offset[n]   ylin tavu = liput (0xE0 tavallinen, 0x20 sisäkkäinen/pakattu)
```
Entryjen määrä = (offset[0] − 4) / 4.

## LZW ("LZ")

CD-version tekstuurit ja maastolohkot: LSB-first-bittijärjestys, koodit 9→12 bittiä,
256 = nollaus, 257 = loppu, sanakirja alkaa 258:sta, bittileveys kasvaa kun
sanakirjan koko saavuttaa 2^n.

## 3D-objekti (FORM REAL)

```
FORM REAL
  FORM OBJT          pelidata: JETP (suihkukone), DYNM (lentomalli), WEAP, DAMG, EXPL, DEBR …
  FORM APPR
    FORM POLY
      INFO
      VERT  n × (i32 x, i32 y, i32 z)    x = oikea, y = eteen, z = ylös; F-16 ≈ 8000 yks. = 15 m
      FORM DETA
        LVLn  u32 etäisyys, u16 kolmio-id[]   (LOD-tasot)
      FORM TRIS
        VTRI  n × 8: shade, v0, v1, v2, väri (palettiindeksi), 0, LOD-bittimaski, liput
        UVXY  n × 8: kolmio-id (u8), tekstuuri-id, (u,v)×3 tekseleinä
        FORM TXMS
          TXMP  name[8], u16 w, u16 h, "LZ" + LZW-data (tai raakapikselit)
```
Tekstuurin palettiindeksi 255 on läpinäkyvä: alkuperäinen piirtäjä näyttää siinä kohtaa
kolmion oman värin (ei reikää).

## Ohjaamot (OBJECTS/<kone>-CKPT.IFF) - EI tavallinen RealSpace-malli

`F16-CKPT.IFF` (182 kt) ja `F22-CKPT.IFF` ovat `FORM:CKPT`-säiliöitä, joiden
sisältö ei ole FORM:REAL-mallia: geometria on **ARTP**-chunkissä (F16: 66 kt)
ja sisällä oleva `FORM:REAL` on tyhjä (OBJS = 0). Siksi `SCData.model()`
palauttaa null. Lohko-rakenne:

| Chunk | Sisältö (arvaus rakenteesta) |
|---|---|
| `INFO` | mittadata |
| `ARTP` | **ohjaamon 3D-geometria** (oma koodaus; avoin dekoodaustehtävä) |
| `VTMP` | verteksipohjat / materiaalit |
| `EJEC` | istuimen heittosekvenssi? |
| `GUNF` | tykkinäkymän osat? |
| `GHUD` / `FORM:CHUD` | HUD-lasi (FILE-viittaus) |
| `FORM:MONI` + `FORM:MFDS` + `FORM:COMM` | 2D-MFD-näytöt (SHP-kuvat + spotit) |

Ohjaamon kamera sijoitetaan nyt meshin AABB:stä (`camera_rig.gd` COCKPIT:
nokka = meshin +z-pää, ohjaamo ~38 % nokasta taaksepäin, korkeus 42 %;
muunnos `model_instance.global_transform`-avulla, koska meshin lokaloksuunta
eroaa rungon etusuunnasta). Kun ARTP-dekooderi valmistuu, kytkeytyy
`_setup_cockpit_model()` (flight_scene.gd) suoraan - se on jo kytketty ja
odottaa vain mallia.

## Paletti (PALETTE/*.IFF)

`FORM PALT` → `PALT`: 4 tavun otsake + 256 × RGB (6-bittinen VGA). `RANG`: u16 määrä +
13 tavun tietueet (u16 alkuindeksi, u16, u16, RGB, 4 tavua). Maastopaletin RANG-tietueet
0–6 ovat maastotyyppien värit järjestyksessä vesi, aavikko, karkea maa, ruoho, metsä,
kallio, lumi. Alueen paletti löytyy tehtävätiedostosta (`FORM WRLD` → `TERA` + `PALT`).

## Maastoalue (*.PAK)

```
entry 0  FORM TERA: ELEV (lohkoja 18, kärkiä/lohko 20, lohkon koko 20000 ft), ATRI, OBJS,
         FORM TXMS / MAPS (u16 TXMPACK-indeksi, name[8], u16)
entry 1  LOD 0: PAK, 324 lohkoa (18×18), kukin u32 koko + LZW → 400 × 6 tavua
entry 2  LOD 1 (10×10), entry 3 LOD 2 (5×5)
entry 4  lohkokohtaiset nimettömät pisteet (13 t: i32 x, y, z 24.8 + 1 tavu; mm. valot)
entry 5  nimetyt maaobjektit lohkoittain: u16 määrä + 70 tavun tietueet:
         char malli[13], char tuhoutunut_malli[9], i32 x @22, y @26, z @30 (24.8, ft)
entry 6  lohkokohtainen yhteenveto
```
Kärkipiste (6 tavua): `i16 korkeus (ft)`, `u8 varjostuskohina`, `u8 maastotyyppi 0–6`,
`u8 laatta kolmiolle u>v`, `u8 laatta kolmiolle u<v` (255 = ei laattaa). Neliö jaetaan
diagonaalilla (0,0)–(1,1). Kärkien väli 1000 ft (≈ 305 m) → kartta ≈ 110 km.

## Maastolaatat (LILTRE: TXM/TXMPACK.PAK)

255 × (u16 64, u16 64, 4096 palettitavua). Indeksit 255, 229 ja 230 ovat läpinäkyviä
(229/230 = taiteilijan saumamerkit). Laatat ovat siirtymiä (ranta, metsänreuna, kallio,
kaupunki, kiitotie …) perusvärin päälle.

## Koordinaatisto

Kaikki maailman sijainnit (tehtävät, maaobjektit) ovat **i32 24.8 -kiintolukuja jalkoina**:
x = itä, y = pohjoinen, z = ylös, origo kartan keskellä. Maastoruudukossa
`gx = x / 1000 + 180`, `gz = 180 − y / 1000`. Godotissa `(x, z, −y) × 0,3048` m.
Varmistettu: objektien z täsmää maaston korkeuteen (esim. 1621 vs 1620 ft), pelaajan F-16
on kiitotiellä 18 suunnassa 180°, ja vihollistukikohdat osuvat maaston metsäaukeille.
Suunta: asteina pohjoisesta myötäpäivään.

## Tehtävä (MISSIONS/*.IFF, FORM MISN)

```
FORM MISN
  VERS, INFO (alueen nimi), NAME
  FORM WRLD / FILE   maastoalue, esim. "rhodei" -> RHODEI.PAK
  AREA   tietueet, koko tyypin mukaan (tarkistettu kaikista 52 tehtävästä):
         u8 tyyppi, char nimi[32], x @33, y @37, z @41, sitten
         'S' pallo  49 tavua: säde @45
         'B' laatikko 65 tavua: 5 mittaa @45..@61 (säteenä käytetään @45)
         'C' sylinteri 53 tavua: korkeus @45, säde @49
         (Vanha tulkinta "n × 49" siirsi kaikkia 'B'/'C'-tietueen jälkeisiä alueita.)
  SPOT, NUMS, FLAG
  MSGS   nollalla erotetut reittipiste-/tavoitetekstit
  CAST   n × 9: toimijoiden nimet; "PLAYER"-nimen indeksi = pelaajan PART-id
  PROG   tehtäväskripti (tavukoodi, vielä tulkitsematta)
  PART   n × 62 (objektit):
         u16 id, char malli[8], char tuhoutunut[8], char kuorma[8],
         i16 alue @26 (AREA-indeksi, −1 = absoluuttinen), u8 puoli @28 (0 = pelaaja),
         x @29, y @33, z @37 (suhteessa alueeseen), u16 suunta @41 (°), u16 nopeus @43 (kt),
         u8 @45, i16 muodostelman johtajan id @46, i16 poikkeama x/y/z @48/50/52 (ft),
         i16 skriptilohkot: @54 käynnistys, @56 AI, @58 tuhoutuminen, @60 reitti
  SPOT   n × 14: i16 alue, i32 x, y, z (24.8 ft, suhteessa alueeseen) – reittipisteet
  PROG   tavukoodi, ks. alla
  FORM PLAY / SCNE  kohtaukset: u8, i16 alue @1, i16 lohkot @3 (alueelle tultaessa),
         @5, @7 (myös alueelle tultaessa), u8 @9 (1 = sijainti seuraa),
         u16 PART-indeksit kohdasta 24 (kohtauksen objektit, aktiivisia alusta)
  TEAM, LOAD, CACH
```

## Tehtäväskripti (PROG)

2-tavuisia käskyjä (opkoodi, argumentti); lohkot päättyvät `00 00`. Lohko on
**pinokoneohjelma, joka ajetaan alusta jokaisella skriptikierroksella**; pysyvä tila on
muuttujissa, lipuissa ja omistajan nykyisessä toiminnossa. AI-ohjelmat ovat tilakoneita:
muuttuja sisältää nimiön tunnuksen (esim. `0x61` = 'a'), ja `11 n 4f 00` hyppää siihen.
Käynnistyslohko alustaa tilan (`10 61 50 06`), ja `55 n` siirtää seuraavaan tilaan.

Lohkojen laukaisu:
- PART @54: kerran objektin syntyessä · @56: AI joka kierros · @58: kerran tuhoutuessa
  · @60: reitti (pelaajalla reittisuunnitelma)
- SCNE-lohkot: joka kierros sen jälkeen, kun pelaaja on tullut kohtauksen alueelle.
  Kohtauksen PART-lista = sen alueen omat objektit: niiden lentokoneet luodaan vasta, kun
  pelaaja tulee alueelle (ennen sitä ne ovat "elossa, odottamassa": `92` = tosi, etäisyys = 255)
- lohkot, joihin mikään ei viittaa: tehtävän yleislogiikka, joka kierros
- `ab n` näyttää viestin n omistajan hahmotiedostosta `INTEL/<CAST-nimi>.IFF`
  (`FORM PROF/RADI`: `SPCH` = u8 äänipankki, `INFO` = nimi + kutsunimi, `MSGS` = n × (u8 tunnus,
  teksti), pelaajalla myös `ASKS` = radiovalikon kyselyt); `CAST`-indeksi = PART-id
- Ääni: `INTEL/SPEECH.PAK` alkio `SPCH` on sisäkkäinen PAK, jonka alkio n = viestin n VOC
  (useimmat LZW: u32 koko + LZW; puuttuvat repliikit tyhjiä). Pelaajalla (pankki 7) ei ääniä.
- Viestitunnukset ovat samat kaikissa profiileissa: 0 ei, 1 kyllä, 2–5 kunto (hyvä → kriittinen),
  6 apua, 7 osuma, 8 palaan tukikohtaan, 9 heittoistuin / putoan, 10 pahasti osuttu, 11 kohde edessä,
  12 vihollisia tulossa, 13 kohde tuhottu, 14 omien tulitus, 15 hieno pudotus, 16 varo kuutta,
  17 ohjus perässä, 18 hoidan tämän, 19 ilmatorjuntaa, 20–27 tehtäväkohtaiset (viholliset: kuolinhuudot),
  28 miten menee, 29 kiitotie vapaa lentoonlähtöön, 30 kiitotie vapaa laskuun

| Opkoodi | Merkitys |
|---|---|
| `10 k` / `11 n` | työnnä vakio k / muuttuja n |
| `50 n` / `55 n` / `56 n` / `23 n` | muuttuja n = pop / += 1 / −= 1 / += pop |
| `40 k` / `41 k` | työnnä (pop ≥ k) / (pop < k) |
| `45 n` / `52 n` / `53 n` | työnnä lippu n / aseta / tyhjennä |
| `92 id` | työnnä (objekti id elossa) |
| `08 r` | nimiö r |
| `48 r`, `4b r` / `49 r`, `4a r` | hyppää r:ään, jos pop tosi / epätosi |
| `4e r` / `4f 00` | hyppää r:ään / pinosta otettuun nimiöön |
| `46 r` | hyppää, jos omistajan nykyinen toiminto on kesken |
| `01 00` | kierros päättyy (yield) |
| `0f n` | tehtävä päättyy (1 = onnistui) |
| `90 id` / `91 id` | herätä / poista objekti |
| `a0 k` | odota k s |
| `a1` / `a2 n` / `a5 n`, `a6 n` | nouse / laskeudu SPOT n:ään / lennä SPOT n:ään |
| `a7 id` / `a8 id` / `aa id` | hyökkää / saata / seuraa objektia id. Saattokohteet (`a8`, esim. MISN-1A:n C-130) ovat ystäviä, kunsa saattajan omistaja on pelaajan puolella (`flight_scene._escort_ids`) — side-tavu ei erota ystävää ja vihollista (kuljettatuki ja häiriköinti molemmat side=1). |
| `ab n` | radioviesti n (tai reittipisteen teksti reittilohkossa) |
| `14 n` | var n = pop (lopettaa parametrisarjan, esim. `2e 64 14 01` → var 1 = parametri 64) |
| `21 k`, `24 k`, `2e k`, `2f k` | työnnä parametri (2e on todistettu: työntää vakion k; muille parametritaulukon lähde auki) |
| `93 id` / `98 id` | työnnä (kone id ilmassa) / (kone id maassa) — pareina esim. vahvistusten herätyksessä (MISN-10D) ja "pelaaja laskeutunut" (MISN-14A: 93 epätosi ja 98 tosi) |
| `95 id` | työnnä etäisyys omistajasta kohteeseen, kokonaisina maili/lähimäärinä; vertailut 1, 2, 5, 10 (kiitotien "laskeutunut" < 1, mayday-radio < 5, hyökkäys < 10) |
| `97 id` | **etäisyys omistajasta kohteeseen** (95:n sisar). Molemmat datan käytöt ovat muotoa `97 id, 40 05, 4b ohita, 52 lippu` = aseta lippu, kun kohde on **alle 5 yksikön päässä** (MISN-1A blk 7: lippu 6 = "MiG 7 on hyökännyt C-130:n kimppuun", sen jälkeen C-130 sanoo "turvassa", kun kaikki MiGit ovat kuolleet tai ≥ 5 päässä; MISN-1C blk 5 lippu 3). Yksikkö ei selviä datasta: toteutus käyttää 95:n tapaan merimailia (3D). Koodi luki tätä aiemmin suuntana × 256, jolloin ehto oli merkityksetön (korjattu 2026-11-11, `flight_scene.vm_query_object`). Kuollut kohde → 0, kohtauksessa odottava → 255. |
| `21 k` / `24 k` / `25 k` / `2f k` | parametrien työnnöt, samalla tavalla kuin `2e k`: k kertoo lähteen mutta lähdetyyppiä ei voi erottaa datasta (aina seurataan `14/50`-poppia, joka nappaa viimeisimmän = `2e 64` → var 1 = 100, ja `run()` nollaa pinon per tick, joten käyttäytyminen on todennettu ajossa: m1_fullG/H onnistuivat). Epäily: 21 = lohkokohtainen parametri, 24 = tehtävätason parametri, 25 = omistaja-osan attribuutti, 2f = toinen parametritaulu — varmuus vain STRIKE.EXE:n VM-silmukasta. |
| `02`, `09`, `0f`, `35`, `38`, `80`, `81`, `94`, `99`, `a3`, `a4`, `a9`, `ac`, `b*`, `be`, `d0` | ohitetaan |

Esimerkki (MISN-10A): rakennusten tuhoutumislohkot kasvattavat muuttujia 0, 9 ja 10 ja
kiitotiet asettavat liput 7/8; yleislogiikka asettaa lipun 4, kun muuttuja 0 ≥ 9 tai molemmat
kiitotiet on tuhottu, ja Strike Basen AI-ohjelma sanoo silloin kerran viestin 0x14
"Mission accomplished. Return to base." Tämä on varmistettu testissä `tests/vm_test.gd`.

## Mielenkiintoinen lisä sisällystetty PROG-opkoodien analysointi

Kehitystyökalu `tools/prog_analyze.gd` purkaa kaikkien tehtävien PROG-tavukoodin
ja listaa avoimien opkoodien (14, 21, 25, 2e, 92-98) käyttöyhteydet:

```bash
tools/godot/Godot_v4.7.2-stable_win64.exe --headless --path game --script res://tools/prog_analyze.gd -- tmp/prog_analysis.txt    # tilastot + yhteydet
tools/godot/Godot_v4.7.2-stable_win64.exe --headless --path game --script res://tools/prog_analyze.gd -- tmp/dump.txt MISN-1A 7 MISN-4C 1    # kokonaislohkot muistiinpanoilla
```

Sen tuloksella dekoodattu: `14 n` = var n = pop; `21/24/25/2e/2f k` =
parametrin työntö; `93/98` = kone ilmassa/maassa; `95` = etäisyys kokonaisina
mailina. Katso TIEDOSTOFORMAATIT.md ja tests/vm_test.gd (uudet tapaukset:
MISN-4C lohko 1, MISN-10D lohko 10, MISN-14A lohko 3).

## Kiitotiet (RNWY-objektit)

Esim. `RWYEXT18.IFF`/`RWYEXT27.IFF`: `FORM APPR` on tyhjä (`NONE`), eli alkuperäinen
piirtäjä tekee kiitotien itse. `OBJT/EXTE` sisältää mitat kohdasta 16:
`i32 x_max, x_min, y_max, y_min, z_max, z_min` (24.8, ft). RWYEXT18 ≈ 2300 × 72 ft
pohjois–etelä. Tämä moottori piirtää ne proseduraalisella asfalttishaderilla.

## Aseet

`FORM OBJT`-lomakkeen tyyppi kertoo objektin luokan: `JETP` suihkukone, `SWPN` maa-ase
(ilmatorjunta / SAM), `ORNT` rakennus tai koriste, `RNWY` kiitotie, `MISS` ohjus,
`TRCR` ammus.

- **Kuorma** `JETP/WEAP/WPNS`: n × (u16 määrä, char nimi[8]); esim. F-16: AGM-65D ×6,
  SWINDERM ×2, AMRAAM ×4, 20mm ×1000, MK82 ×12. MiG-29: SWINDERM ×2, AMRAAM ×2.
- **Maa-ase** `SWPN/DATA`: u32 @0 (laukaisimilla ohjusmäärä), u32 @4 kantama (ft),
  u32 @8 korkeusraja (ft), asenimi @21 (esim. `40MM`, `23MM`, `SA2`). 40MMAA: kantama
  10 000 ft, raja 4000 ft. STASAMLN: 4 × SA2, kantama 20 000 ft.
- **Asevaikutus** `BOMB|MISS|DURD/WDAT`: u16 vahinko @0, u16 räjähdyssäde (ft) @2.
  MK82 350 / 75 ft, MK20 100 / 200 ft, AGM-65D 250 / 40 ft, DURANDAL 195 / 0.
  `EXPL` nimeää räjähdysefektin (esim. `GRNDEX4`).
- **Kestävyys** `OBJT/FORM xxx/DAMG`: u16; esim. 40MMAA 20, ZSU-23 40, HANGB22 100,
  RDRSTL2 150, MIG29 29.
- Ohjusten ja pommien lentoarvot (`DYNM`, `MISS`, `ATMO`) ovat vielä tulkitsematta;
  moottori käyttää `scripts/game/weapons.gd`:n taulukkoa.
- Harhautteiden mallit `FLARE.IFF` ja `CHAFF.IFF` ovat olemassa (ei vielä käytössä).

## Äänet

- **Tehosteet** `LILTRE: SOUND/DSOUNDFX.PAK`: PAK, jonka ainoa entry on sisäkkäinen PAK
  32 äänestä. Lippu 0x20 = `u32 koko + LZW` (sama LZW kuin tekstuureissa), 0xE0 = raaka.
  Purettuna Creative Voice File (VOC): 8-bittinen etumerkitön mono, lohkot 1 (näytetaajuus
  `1 000 000 / (256 − tavu)`, tyypillisesti 11 111 Hz) ja 2. Äänillä ei ole nimiä.
  Pääteltyjä rooleja: 23–26, 28, 30 ≈ 5 s tasaiset silmukat (moottorit), 2–3 suuret
  räjähdykset, 4–5 pienet, 18/20 ohjuksen laukaisu, 7/10–15 laukauksia tai osumia (epävarma). Kuuntelun perusteella
  pankissa ei ole tykin ääntä – moottori syntetisoi Gatling-tykin: 20 mm noin 110 laukausta/s ja 30 mm (GAU-8, A-10:n
  `30MMGAU` kuormassa) noin 65 laukausta/s.
- **Puhe** `CD: VOCLIST.TRE`: 2301 VOC-tiedostoa (`F:1AI001.VOC` …), nimen alku = jakso ja
  puhuja (esim. `2ST` Stern, `3GW` Gwen). `BIGTRE: VOCLIST.IFF` = `FORM LIST`, `SIZE 20`,
  ja lista 20-tavuisia tiedostonimiä (indeksi → VOC). Hahmotiedostojen `SPCH`-tavu
  (STRIBASE 0x0a, PLAYER 07, STERN 09, geneeriset lentäjät 0x0c) liittyy puhepankkiin;
  vastaavuus radioviesteihin on vielä selvittämättä.
- **Musiikki** `SOUND/COMBAT.MID`, `GAMEFLOW.MID` (XMIDI) sekä AdLib- (`.ADL`) ja Roland-
  (`.ROL`) versiot.

## 2D-kuvat (SHP, OPTSHPS.PAK, CONVSHPS.PAK)

PAK-entryt ovat `u32 koko + LZW` (tai raakoja). Purettuna: `u32 kokonaiskoko`, `u32 kehysten
offsetit`. Kehys: `i16 x2, x1, y1, y2` (ulottuvuus origosta oikealle/vasemmalle/ylös/alas),
sitten rivitietueet `u16 key` (0 = loppu, `count = key >> 1`), `i16 dx, dy` ja joko `count`
raakapikseliä (key parillinen) tai RLE (key pariton: tavu b, `n = b >> 1`, pariton = toista
seuraavaa tavua n kertaa, parillinen = kopioi n tavua). Koko ruudun kuvissa origo on 320×200-
ruudun vasen yläkulma. Paletit (`OPTPALS.PAK`, `CONVPALS.PAK`) ovat osapaletteja:
`u16 ensimmäinen, u16 määrä, määrä × RGB (6 bit)`, jotka kerrostetaan `PALETTE.IFF`:n päälle.

## Tukikohtanäkymät (GAMEFLOW/OPTIONS.IFF)

`FORM OPTS / FORM SCEN`: `INFO` id, `TUNE`, `FORM BACK` (`PALT` osapaletti, `SHAP` kerrokset
OPTSHPS:stä), `FORM FORE` (`PALT`, `FORM SPRT`: `SHAP` = sprite-id, kuvan indeksi (0xFF = vain
klikkausalue), u8; `LABL` ohjeteksti; `RECT` x1,y1,x2,y2; `SEQU` animaatiokehykset).
Kuvan kehys 0 on spriten kuva, `SEQU`-kehykset piirretään sen päälle.

## Kampanja (GAMEFLOW/GAMEFLOW.IFF)

`FORM GAME`: 49 × `FORM MISS` (kampanjan vaihe): `INFO` id, `EFCT` (vaiheeseen tultaessa),
`FORM SCEN` (näkymän id) / `FORM SPRT` (`INFO` sprite-id, `EFCT`, `REQU` = parit arvo/lippu,
lipun on oltava arvon mukainen). Efektit (op, arg):

| Koodi | Merkitys |
|---|---|
| `00 n` | keskustelu n (CONV.PAK) |
| `01 n` | siirry näkymään n |
| `06 n` / `07 n` | aseta / tyhjennä lippu |
| `02 n` | tarinan välianimaatio MIDn |
| `08 n` | "establishing shot" n: OPTIONS.IFF `FORM ESTB` → `SHOT`, jonka `INFO` = n (overlay 4b1e:0057) |
| `0c n` / `16 n` | valitse tehtävä n / lennä se (n = MISN-1A, 1B, 1C, 2A, 3A … ilman X/AA/BB-versioita) |
| `0d n` / `0f` | seuraava vaihe = n / siirry siihen |
| `09 n` / `0a n` | ehto: lippu n ei ole / on asetettu |
| `14` / `15` | ehto: viimeisin keskustelun vastaus kyllä / ei |
| `16 n` | lennä valittu tehtävä; ehto: lento onnistui |
| `20 n` | ehto: tehtävä n onnistui (lennon tulos 1 = onnistui, 2 = epäonnistui) |
| `21 n` | seuraavat n ehtoa yhdistetään (kaikkien oltava tosia) |
| `1e` / `1f` | else / endif. Epätosi ehto ohittaa efektit vastaavaan `1e`:hen tai `1f`:ään asti; ohitetun haaran sisäiset ehdot lisäävät sisäkkäisyyttä |
| `12 n` | kuljetus: maailmankartan reittianimaatio n (overlay 4b3b:002a) |
| `10` `11` `12` `13` `17` `19` | tallenna, lataa, kuljetus, tappotaulu, asekatalogi, kirjanpito |

## Keskustelut (GAMEFLOW/CONV.PAK, CONVDATA.IFF)

CONV.PAK: 256 LZW-pakattua skriptiä. Tietueet: `00 tausta[9]` laaja kuva · `01 nimi[9] x y`
hahmo · `02 nimi[9] x y u8 puhe  teksti ` hahmo puhuu · `03 nimi[9] ilme tausta[9] x y
puhe  teksti  u8` lähikuva · `04 puhe  teksti ` jatkuu · `0a u8 puhe  teksti ` kuvateksti ·
`0b n u8` kyllä/ei (ei → hyppää n tavua eteenpäin) · `0c n u8` hyppy · `0e u8 u8` · `0f` siipimiehen
valinta. Puhe = `VOCLIST.TRE: F:<puhe>.VOC`; tekstissä `$N` `$S` `$C` (pelaajan nimet) ja `$W`
(siipimies). CONVDATA.IFF: `BCKS/BACK` (nimi, n × {u8 arkisto 0 = CONVSHPS / 1 = OPTSHPS,
u8 kuva, u8 paletti, i16 y}), `FACE` / `FIGR` (nimi[8] + CONVSHPS-indeksi), `PFIG`, `FCPL` /
`FGPL` (kasvojen / hahmojen paletti). Kasvokuvan kehykset: 0 = pää, 1 = hiukset ja otsa,
2–11 suun asennot, 12 = silmät kiinni, 13–33 ilmeet, 34 = hartiat ja vaatteet.
Alkuperäinen piirtää lähikuvan järjestyksessä 0, ilme, (suu), 1, 34 samaan pisteeseen;
keskustelukomennon `mood` on suoraan ilmekehyksen numero (255 = ei ilmettä).
Taustan kerrokset tuovat kukin osapalettinsa omasta arkistostaan (OPTPALS / CONVPALS), ja
kuvasta näytetään rivit 0–127 ruudun riveillä 24–151 (kuten välianimaatioissa).

## Välianimaatiot (OPTTEST.EXE, MIDGAMES/MID*.PAK)

Välianimaatioiden lavastus ei ole datassa vaan `OPTTEST.EXE`:ssä: jokainen MIDn on
oma C++-funktionsa Borland-overlayssa (16-bittinen MZ + `FBOV`; overlay-tyngät
segmenteissä 4b5c–4b83, MID1 = 4b5c:0025, muut tynkä:0020). Ohjelma ajaa
Originin JEMM-ympäristössä (SCCD.EXE + JEMM.OVL, `int 15h` AX=1209h, BX = kaksi ASCII-kirjainta):

| Palvelu | Merkitys (sikäli kuin tarvitaan) |
|---|---|
| `AC` / `VE` | asennustarkistus (BX=1209h) / versio (≥ 436h) |
| `FF` | ES:DI → lippu (≠ 0 = laajennettu EMS-sivutus) |
| `FH` | EDX = EMS-kahvan lineaarinen osoite (muistiin päästään 32-bittisillä siirtymillä) |
| `sm` / `SM` | A000–AFFF näkyy VGA-muistina / EMS-sivuna; BL = edellinen tila |

EMS-fyysiset sivut 0–23 ovat peräkkäin A000–FFFF (0–19 iso ikkuna, keko alkaa A000:sta,
20–23 = F000-kehys). Näyttöpinta on segmentissä FFFF (rivi 0 = FFFF:0010).

`tools/cutscenes` ajaa ohjelmaa unicorn-emulaattorissa (DOS, BIOS, EMS, JEMM, VGA, PIT),
korvaa käynnistyksen MID1-kutsun halutulla MIDn:llä (tai kutsuu efektin 08 käsittelijää
4b1e:0057 argumentein (pelitilaolio, n)) ja kirjaa kirjaston kutsut. GAMEFLOW-efektien
hyppytaulu on tiedostosiirtymässä bd47 (43 efektiä, käsittelijät ba55–bd22):

| Funktio (tiedostosiirtymä) | Toiminto |
|---|---|
| 40570 | piirrä SHP-kehys (pinta, x, y, kuva, kehys) |
| 407be | skaalattu piirto (… skaala x/y 256 = 1.0, sävytaulukko, värialue) |
| 4730e | etäällä oleva hahmo: tasainen skaala `[bp+14]` / 256 (1.0 jatkaa 40570:een) |
| 402f0 | fontin merkki yhdellä värillä (pinta, x, y, fontti, merkki, väri) – esim. paikan nimet |
| 3ff7e / 3fc3c | viiva (pinta, x1, y1, x2, y2, väri) / täytetty ellipsi (pinta, cx, cy, rx, ry, väri) |
| 3fbb0 / 3fb64 | kopioi pinnan alue / täytä pinta |
| 195da | lataa PAK-merkintä; 199fc / 4b3a8 / 4b378 polku ja arkiston avaus |
| 14587 / 16e34 | soita näyte / hahmo puhuu (VOC-arkistosta) |
| 48244 | LZW-purku (syötön täyttö 494e9 vaihtaa F000-kehyksen sivuja) |

Tuloksena on piirtolista `midN.json`: `{"ops": [[t_ms, tyyppi, …], …]}`. Tyypit:
`surface nimi seg base stride [x1,y1,x2,y2]`, `draw pinta arkisto merkintä kehys x y`,
`sdraw … sx sy ensimmäinen määrä taulukko`, `copy lähde kohde lähderect kohderect`,
`fill pinta väri rect`, `glyph pinta arkisto merkintä merkki x y väri`,
`line pinta x1 y1 x2 y2 väri`, `ellipse pinta cx cy rx ry väri`, `pal ensimmäinen [r,g,b …]` (6-bittiset VGA-arvot),
`table id [taso × 256]` (sävytaulukko: värit ensimmäinen…ensimmäinen+määrä−1 muuttavat
alla olevaa väriä), `voice arkisto merkintä` ja `subtitle teksti` ("" poistaa tekstin).

Tekstitys (`tools/cutscenes/subtitles.py`): ilman digitaalista puhetta OPTTEST.EXE
näyttää repliikit tekstinä (MIDGAMES.IFF `FORM MGnn` → `DATA`/`SPOK` → `TEXT`; rivi
piirretään funktiolla 3f36b(teksti-olio, merkkijono)) ja tahdittaa kohtaukset lukemista
varten, joten tekstitila kestää pidempään kuin puhetila. Työkalu ajaa välianimaation
tekstitilassa, ryhmittelee piirretyt rivit repliikeiksi ja kohdistaa ne puhetilan
aikajanaan: kummankin ajon kohtaukset tunnistetaan piirrettyjen kuvien joukosta
(difflib), repliikin aika skaalataan kohtauksen sisällä ja kiinnitetään lähimpään
puherepliikkiin (±0,7 s). Isoilla kirjaimilla kirjoitetut otsikot (ORIGIN PRESENTS …)
jätetään pois, koska ne piirretään kuvina. Nimet eivät ole emulaattorissa asetettuina,
joten niiden paikat jätetään tyhjiksi. Arkisto `TIEDOSTO@n` = kuva toisen
tiedoston sisällä (esim. fontti `MIDGAMES/CREDITS.IFF@876`).

PAK-merkinnän lippu 0x20 = LZW, 0xE0 = tallennettu sellaisenaan; 0xE0-kuvan perässä voi
olla muuta dataa (kuvan koko on sen ensimmäinen u32).
