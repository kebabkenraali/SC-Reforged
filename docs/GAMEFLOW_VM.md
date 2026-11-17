# Kampanjan (GAMEFLOW) efektitulkki: alkuperäinen toiminta

Purettu 17.11.2026 alkuperäisestä OPTTEST.EXE:stä (GOG CD-versio, 875 408 tavua).
Kuvaus omin sanoin; purkulistaukset pysyvät paikallisina eivätkä kuulu versionhallintaan.
Toteutus: `game/scripts/game/campaign.gd`, isäntä `game/scripts/ui/base_screen.gd`,
testi `game/tests/campaign_test.gd`. Tehtäväskriptien tulkki: `docs/PROG_VM.md`.

## Ohjelmien työnjako

- SCCD.EXE on lataaja, joka vuorottelee ohjelmia. OPTTEST.EXE ajaa kampanjan
  (tukikohtaruudut, keskustelut, välivideot, GAMEFLOW), STRIKE.EXE lennot.
- Lentoon siirryttäessä OPTTEST kirjoittaa `op2misn.iff`:n (tehtävän nimi, aseinventaario,
  pelaajan kuorma, nimi, kutsumerkki, tiimi), tallentaa tilansa (`gensave`/`tmpsav`,
  tunniste `SCB1.22`) ja poistuu. STRIKE kirjoittaa `misn2op.iff`:n (tilastot, jäljelle
  jääneet aseet, pudotukset pilottia kohden, lopetuskoodi, kuolleet, pisteet), ja sen
  jälkeen OPTTEST jatkaa tallennetusta tilasta.

## Mistä löytyi

- Tulkkifunktio on OPTTEST.EXE:n tiedostokohdassa `0xb916` (ladattavan kuvan pysyvä osa).
  Se käy efektiparit (opkoodi, argumentti) läpi ja hyppää 43 merkinnän taulukkoon
  (`0x00`–`0x2a`) kohdassa `0xba50`. Löytyi efektikäsittelijöiden kaukokutsuista:
  keskustelu `4b1e:0043`, maisemakuva `4b1e:0057`, kuljetus `4b3b:002a`.
- Raskaat ruudut ovat overlay-segmenteissä. Stub-segmentin otsake (`CD 3F`, 0, overlay-koodin
  sijainti overlay-alueen alusta `0x58bd0`, koko, merkintöjen määrä) ja 5-tavuiset merkinnät
  antavat funktioiden osoitteet.

## Ohjausrakenne

- Ehto, joka ei toteudu, asettaa ohitustilan. Efektit ohitetaan seuraavaan `1e` (else, vaihtaa
  ohituksen) tai `1f` (endif, lopettaa ohituksen) asti; ohitetun alueen sisäkkäiset ehdot
  kasvattavat syvyyttä.
- Ehtokoodit: `09 0a 14 15 16 1c 20 23 25` (ja `27`–`2a`, joita data ei käytä).
- `21 n`: seuraavat n efektiä täytyy olla ehtoja, ja ne arvioidaan myös ohitustilassa;
  yksikin epätosi asettaa ohituksen (eli kaikkien täytyy olla tosia). Väärä rakenne antaa
  virheen "Faulty OR structure in gameflow file".
- `1d` voi pysäyttää koko listan.
- Kampanjaobjektissa on odottava komento (`+0xe8`), jonka kutsuja käsittelee listan jälkeen:
  1 = lennä (`16` kun pelaaja valitsee lennon, `0e`, `03 n`), 2 = seuraava vaihe (`0f`),
  3 = lataus (`11`).

## Efektit

Varmuus: **V** = luettu käsittelijästä; **T** = rakenne varma, pelimerkitys päätelty;
**A** = avoin. Käyttömäärät koko kampanjan GAMEFLOW-datasta (49 vaihetta).

| Efekti | Käyttöjä | Merkitys | Varmuus | Remake |
|---|---|---|---|---|
| `00 n` | 285 | keskustelu n | V | ✓ |
| `01 n` | 391 | tukikohtaruutu n | V | ✓ |
| `02 n` | 12 | tarinavälivideo MIDn | V | ✓ |
| `03 n` | 3 | valitse tehtävä n ja lennä | V | ✓ (17.11.) |
| `04`, `0b` | 43 / 0 | ei toimintoa | V | ✓ |
| `05 n` | 0 | valitse tehtävä n (ilman lentoa) | V | – |
| `06`/`07 n` | 204 / 93 | aseta / tyhjennä lippu n | V | ✓ |
| `08 n` | 118 | maisemakuva n | V | ✓ |
| `09`/`0a n` | 17 / 47 | ehto: lippu n tyhjä / asetettu | V | ✓ |
| `0c n` | 48 | valitse tehtävä n | V | ✓ |
| `0d n` | 93 | seuraava vaihe = n | V | ✓ |
| `0e` | 0 | lennä ilman latausruutua | V | ✓ (17.11.) |
| `0f` | 29 | siirry seuraavaan vaiheeseen | V | ✓ |
| `10` / `11` | 54 / 54 | tallennus / lataus | V | tallennus automaattinen |
| `12 n` | 12 | kuljetusanimaatio n | V | ✓ |
| `13` | 54 | tappotaulu (moduuli 4b32) | T | viesti (pelaajan pudotukset) |
| `14`/`15` | 20 / 6 | ehto: viimeisin vastaus kyllä / ei | V | ✓ |
| `16 n` | 42 | **ehto: aseidenlatausruutu**, tosi kun pelaaja valitsee lennon; argumentti välitetään kuorman valmisteluun (merkitys avoin) | V / A (n) | ✓ (17.11.) |
| `17 n` | 43 | asekatalogi (moduuli 4b36) | T | viesti |
| `18 n` | 11 | musiikkikappale n | V / T | ✓ GAMEFLOW.ADL (17.11.) |
| `19` | 54 | kirjanpito (moduuli 4b36): kassa, yleiskulut, konekorvaukset, ostot | V | viesti (luvut) |
| `1a` | 27 | tappotaulun päivitys lennon jälkeen, jos pelaaja pudotti jotain (`+0xed`) | V | viesti |
| `1b n` | 2 | pilotin n tila = 0 (pilottitaulukko, 8 × 26 tavua) | V | ✓ |
| `1c` | 0 | ehto, aina tosi | V | ✓ |
| `1d` | 12 | peli ohi: menetettyjä koneita > 16 tai kassa < 0 → lopetus (0xfe / 0xff), listan ajo päättyy | V | ✓ (viesti + `end_campaign`) |
| `1e` / `1f` | 117 / 159 | else / endif | V | ✓ |
| `20 n` | 62 | ehto: tehtävän n tulos = 1 (onnistui) | V | ✓ |
| `21 n` | 0 | n seuraavaa ehtoa, kaikkien tosia | V | ✓ |
| `22 n` | 94 | kirjanpitotapahtuma n (`FORM STAT / CHNG`, ks. Talous) | V | ✓ |
| `23` | 0 | ehto, aina epätosi (alkuperäisen bugi) | V | ✓ |
| `24` | 27 | jos edellisellä lennolla menetettiin kone: musiikki 8 ja keskustelu 252 (tai 253, kun `+0xf8` = 2) | V | ✓ (252) |
| `25` | 7 | ehto: edellisen lennon tehtävärekisteri 2 ≠ 0 | V | ✓ |
| `26 n` | 18 | äänimoduulin asetus n (vaiheiden alussa: 1, 2, 3 sijainnin mukaan) | V / A | – |
| `27`–`29` / `2a` | 0 | ehdot: tehtävärekisterit 3–5 ≠ 0 / kenttä `+0x3d6` (lähde avoin) | V | ✓ / epätosi |

## Mitä muuttui remakessa (17.11.2026)

- `16` on taas ehto: latausruutu, ja "palaa tukikohtaan" ohittaa listan loput eikä lennä.
- Lento käynnistyy vasta efektilistan lopussa (kuten alkuperäisen odottava komento), joten
  `16`:n jälkeiset efektit, kuten vaiheen 2 `06 40`, ajetaan ennen lentoa. Lennon jälkeen
  siirrytään `0d`-vaiheeseen tuloksesta riippumatta.
- `03 n` ja `0e` käynnistävät lennon; `18 n` soittaa tukikohtamusiikin.

## Talous (purettu 17.11.2026)

Rahat ovat tuhansina dollareina, kuten alkuperäisessä.

**Kirjanpitotapahtumat:** GAMEFLOW.IFF:n `GAME`-lomakkeen jälkeen on lomakkeet `WRLD`, `LOAD`,
`MLST` (tehtäväluettelo `DATA`), `WNGS` (siipimiehet) ja `STAT`. `STAT` sisältää 25
`CHNG`-tapahtumaa: `INFO` = tunniste (johon `22 n` viittaa), `CASH` / `OVER` = toiminto
(0 lisää, 1 vähennä, 2 aseta) ja 32-bittinen summa, `WEAP` = asevaraston muutokset
(4 tavua: toiminto, asetyyppi, määrä), `PILT` = pilottitaulukon muutokset (5 tavua:
toiminto, pilotti, kenttä 0 ilma- / 1 maapudotukset / 2 tila, arvo). Vaihe 0: kassa 4 850,
yleiskulut 1 500, asevarasto (mm. 44 × SWINDERJ, 16 × DURANDAL), muiden pilottien
pudotukset. Asetyypit: SWINDERJ, SWINDERM, AGM-65D, DURANDAL, MK20, MK82, GBU-15G, POD, AMRAAM.

**Lennon alussa** (OPTTEST `4b1e:1aac`): kassa −= yleiskulut + odottavat ostot, ostot nollataan.

**Palkkio tulee tehtäväskriptistä.** Tehtävärekisterit (`14 n`, ks. PROG_VM.md) kulkevat
tulostiedoston `STAT`-lohkossa: rekisteri 0 = onnistuiko (tulos 1 / 2, jota `20 n` lukee),
rekisteri 1 = palkkio (MISN-1A: lippu 12 × 25 × 100 = 2 500), rekisterit 2–5 = ehdot `25`,
`27`–`29`.

**Tulosten käsittely** (`misn2op`, `4b1e:141d`): `EXIT` 5 = keskeytetty, mitään ei muuteta.
Muuten `WPNS` korvaa asevaraston, `JETS` = menetetyt koneet (kokonaismäärä kasvaa,
korvaus 500 / kone vähennetään kassasta), `STAT` lisää palkkion kassaan, `KILL` lisää
pilottien pudotukset (pelaajan pudotuksista lippu tappotaulun päivitykselle), `DIED`
merkitsee kuolleet siipimiehet, `SCOR` kasvattaa kokonaispisteitä.

**Remake:** `campaign.gd` (`apply_change`, `charge_flight`, `apply_report`), lentokohtaus
raportoi `campaign_report()`:lla rekisterit, menetetyt koneet ja pelaajan pudotukset;
pausevalikosta poistuminen = keskeytys. Testit: `campaign_test.gd`.

## Avoinna

- Kirjanpidon, katalogin ja tappotaulun omat ruudut (nyt tekstiviesteinä); katalogiostot
  (`+0x283`); asevaraston kulutus lennolla (`WPNS`) ja latausruudun kytkentä varastoon.
- Kokonaispisteet (`SCOR`), siipimiesten kuolema (`DIED`) ja pilottien nimet.
- `26 n`:n äänimerkitys, `16 n`:n argumentti, kenttien `+0xf8` ja `+0x3d6` merkitys.
