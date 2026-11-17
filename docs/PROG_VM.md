# Tehtäväskriptien (PROG) tulkki: alkuperäinen toiminta

Purettu 17.11.2026 alkuperäisestä STRIKE.EXE:stä (GOG CD-versio, 745 920 tavua).
Tämä on omin sanoin kirjoitettu kuvaus käyttäytymisestä. Alkuperäistä koodia ei ole
kopioitu tähän; purkulistaukset pysyvät paikallisina (`docs/DEKOMPILU/`, scratchpad) eivätkä
kuulu versionhallintaan. Toteutus: `game/scripts/game/mission_vm.gd`, isäntä
`flight_scene.gd` ("host interface for MissionVM"), testi `game/tests/vm_test.gd`.

## Mistä löytyi

- Ohjelmat: SCCD.EXE on lataaja; MENU.EXE, OPTTEST.EXE (kampanja, GAMEFLOW, keskustelut,
  briefingit) ja STRIKE.EXE (lento) ovat Borland C++ -ohjelmia, joissa on VROOMM-overlayt
  (`FBOV`). Ne eivät ole pakattuja.
- STRIKE.EXE:n tiedostokohdassa `0x55711` on 209 sanan hyppytaulukko (opkoodit `00`–`d0`),
  jota dispatcher kohdassa `0x54b5e` käyttää: hae käsky, `cmp bx, 0xd0`, hyppää taulukkoon.
  Käsittelijät ovat segmentin `0x548a0` sisäisiä osoitteita.
- Toimintojen (`a1`–`bf`) varsinainen suoritus on funktiossa `0x56499` ja sen omassa
  taulukossa (`0x56a0e`, 31 sanaa).
- Kaikki 47 tehtävää käyttävät yhteensä 62 eri opkoodia. Alkuperäinen tulkki tuntee 91;
  kaikilla datan opkoodeilla on käsittelijä paitsi `08`, `09` ja `a6` (ks. alla).

## Malli

- **Akkumulaattorikone**, ei pinokone. Tila omistajaa kohden: akkumulaattori ACC,
  toiminnon tila E (≠ 0 = toiminto kesken), ehtoliput (1 = pienempi, 2 = yhtä suuri,
  4 = suurempi) ja kutsupino (enintään 16 tasoa).
- **Yksi muuttujataulukko** koko tehtävälle. "Liput" ovat samoja muuttujia arvoilla 0/1.
- **Käsky = 2 tavua** (opkoodi, argumentti). Jos seuraava pari alkaa tavulla `09`, sen
  argumentti on edellisen käskyn lisäargumentti, ei oma käsky.
- **Nimiöt** (`08 n`) etsitään vain eteenpäin nykyisestä kohdasta lohkon loppuun.
- Ajo jatkuu, kunnes ylimmällä tasolla tulee `00`/`01` (tikin loppu) tai `04`.

## Opkoodit

Varmuus: **V** = luettu suoraan käsittelijästä; **T** = rakenne varma, pelimerkitys
päätelty; **A** = avoin.

| Opkoodi | Merkitys | Varmuus |
|---|---|---|
| `00`/`01` | paluu kutsutusta lohkosta, ylimmällä tasolla tikin loppu | V |
| `02 n` / `03` | kutsu PROG-lohkoa n / lohkoa ACC aliohjelmana | V |
| `04` | lopeta (myös kutsupino tyhjenee) | V |
| `08 n` | nimiö | V |
| `09 x` | edellisen käskyn lisäargumentti (esim. `a5 07, 09 0b`) | V |
| `0f k` | globaali tavu = k (datassa ei käytetä) | V |
| `10 k` / `11 n` | ACC = k / ACC = muuttuja n | V |
| `12 n` | vaihda ACC ja muuttuja n | V |
| `13` | ACC = E | V |
| `14 n` | tehtävärekisteri n = ACC (n < 8); moottori lukee näitä muualla | V / A (käyttö) |
| `20`/`21` | ACC += k / muuttuja n | V |
| `22 n`, `26 n` | muuttuja n ± n (datassa ei käytetä) | V |
| `23 n` / `27 n` | muuttuja n += ACC / muuttuja n −= ACC | V |
| `24`/`25` | ACC −= k / muuttuja n | V |
| `28`–`2d` | OR, AND, XOR vakiolla / muuttujalla | V |
| `2e`/`2f` | ACC ×= k / muuttuja n | V |
| `30`/`31` | ACC ÷= k / muuttuja n | V |
| `40 k` / `41 k` | vertaa ACC:ta k:hon / k:ta ACC:hen | V |
| `42 n` / `43 n` | vertaa ACC:ta muuttujaan n / päinvastoin | V |
| `44 k` | vertaa E:tä k:hon | V |
| `45 n` | vertaa muuttujaa n arvoon 1 ("lippu asetettu?") | V |
| `46 r` / `47 r` | hyppää, jos E ≠ 0 (toiminto kesken) / E = 0 | V |
| `48`–`4d r` | hyppää, jos = / ≠ / < / > / ≤ / ≥ | V |
| `4e r` / `4f` | hyppää aina / nimiöön ACC (tilakone) | V |
| `50 n` / `51 n` | muuttuja n = ACC / = E | V |
| `52`/`53`/`54 n` | muuttuja n = 1 / 0 / vaihda | V |
| `55`/`56 n` | muuttuja n += 1 / −= 1 | V |
| `80`/`81 n` | tehtävän listan n tilatavu päälle / pois | V / A (mikä lista) |
| `82 n` | testaa listan n tilatavu (ehtolippu =) | V / A |
| `90 id` / `91 id` | aktivoi osa / poista osa | T |
| `92 id` | ehtolippu = osan tilabitti 0 (elossa) | V / T |
| `93 id` | ehtolippu = osan tilabitti 1 (tuhottu: toiminnot estyvät sillä) | V / T |
| `98 id` | ehtolippu = osa on maailmassa (entiteettiosoitin ≠ 0) | V |
| `94 id`, `99 id` | moottorikutsuja osalle | A |
| `95 id` | ACC = 3D-etäisyys omistaja → osa, yksikkö 1000 ft, enintään 255 | V |
| `96 id` | ACC = (osan korkeus ft − 2250) / 100, enintään 255 | V |
| `97 n` | ACC = 3D-etäisyys omistaja → **SPOT n**, 1000 ft, enintään 255 | V |
| `a0 k` | odota k sekuntia omistajan ajastimella (E = 1 odotuksen ajan) | V |
| `a1`–`a5`, `a7`–`ac`, `b1`–`b5`, `bf` | omistajan toiminto, E = tila. Ilman omistajaa E = 0. Toiminto suoritetaan vain, jos omistaja on maailmassa eikä tuhottu | V (rakenne) |
| `a1` nousu, `a2` lasku SPOTiin, `a3`/`a4`/`a5`/`ac` lento SPOTiin, `a7` hyökkäys, `a8` saattaa, `aa` seuraa, `ab` radioviesti | T |
| `a9`, `b1`–`b5`, `bf` | toimintoja, merkitys avoin | A |
| `a6` | ei toimintoa tulkissa (reitin kuvaus, jota käytetään muualla) | V |
| `b6`/`b7`, `b8`/`b9 id` | aseta / tyhjennä osan tilabitti 0x10 / 0x20 | V / A (merkitys) |
| `be id` | aja toimintofunktion esikäsittely osalle; oma toiminto puuttuu | V / A |
| `c0 k` | moottorikutsu | A |
| `d0 k` | globaali tavu = k (65 käyttöä) | V / A (merkitys) |

## Mikä muuttui remakessa (17.11.2026)

Vanha toteutus oli päätelty datasta pinokoneeksi. Erot, jotka korjattiin:

- `21`/`24`/`25`/`2e`/`2f` olivat "parametrien työntöjä"; todellisuudessa aritmetiikkaa.
- `27`, `12`, `13`, `42`–`44`, `47`, `4c`, `4d`, `51`, `54` puuttuivat.
- `40 k` + `48`/`4b` tulkittiin "ACC ≥ k" + "jos tosi"; alkuperäisessä on erilliset =, <, >.
- Liput ja muuttujat olivat eri taulukoissa.
- `02 n` (111 aliohjelmakutsua datassa) ohitettiin.
- `09 x` -lisäargumentit hävisivät.
- Nimiöt haettiin mistä tahansa kohdasta; alkuperäinen hakee vain eteenpäin.
- `93` = "lentää" ja `98` = "maassa" olivat arvauksia; alkuperäinen: tuhottu / maailmassa.
- `95` oli vaakaetäisyys merimaileina (1 = 6076 ft); alkuperäinen 3D, 1 = 1000 ft.
- **`97` oli etäisyys osaan; alkuperäinen on etäisyys SPOTiin.** MISN-1A:n C-130 asettaa
  lipun 6, kun se on alle 5 000 ft:n päässä rahtikentästä (SPOT 7), ja kuittaa
  "We're safe" vain laskeutumisen aikana, jos MiGit on hoidettu.
- E-rekisteri ja toimintojen tila: toiminto ilman elävää omistajaa ei tee mitään.

Isäntä toteuttaa lisäksi `a2`:n oikeana laskeutumisena (liuku SPOTiin, valmis kentällä),
koska alkuperäinen tarkistaa skriptiehtoja laskeutumisen aikana.

## Avoinna

- Toimintofunktion (`0x56499`) tapausten tarkka purku: `a9`, `b1`–`b5`, `bf` sekä se, mitä
  `09`-lisäargumentti tarkoittaa kullekin toiminnolle (esim. `a5 07, 09 0b`).
- Mitkä moottorin osat lukevat tehtävärekistereitä (`14 n`), tilabittejä 0x10/0x20 (`b6`–`b9`)
  ja globaaleja tavuja (`d0`, `0f`), sekä mikä lista on `80`–`82`:n kohde.
- Kampanjan GAMEFLOW-tulkki on purettu erikseen: `docs/GAMEFLOW_VM.md`.
