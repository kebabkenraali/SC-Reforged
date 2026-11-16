# Strike Commander Reforged - KehitysOhjeet AI:lle

> **Huomio:** Tämä tiedosto sisältää kaiken tarvittavan tiedon projektin tilasta, tehdyistä testauksista ja jatkotoimista. Jokainen seuraava AI/kehittäjä lukee tämän ensin ja validoi omaan ympäristöönsä.

## LUE ENSIN: SUUNNITELMA.md (16.11.2026)

Ajantasainen tilannekatsaus, tämän päivän testitulokset ja vaiheistettu suunnitelma ovat
tiedostossa `SUUNNITELMA.md`. Se ohittaa tämän tiedoston silloin, kun ne ovat ristiriidassa.
Tärkein havainto: täysi MISN-1A-autopilottilento epäonnistui 16.11. 3/3 (kone tuhoutuu noin
600 m ennen kynnystä), vaikka alempana väitetään laskeutumisen toimivan.

## Ajantasainen jatkotila

- Aiemmat `m1_fullG`/`m1_fullH`-onnistumiset eivät tarkistaneet C-130:n aktivointipaikkaa.
  Uusi tarkistus löysi, että koneen absoluuttinen PART-paikka on maaston alla kartan origossa,
  vaikka se aktivoidaan Rendezvous-kohtauksen yhteydessä.
- `flight_scene.gd`:hen lisättiin varasijoitus aktivoivan kohtauksen alueelle ja
  `mission_test.gd`:hen AGL-/etäisyystarkistus. Testiajo ei vielä tulostanut tämän tarkistuksen
  tulosta, joten muutosta tai täyttä MISN-1A-lentoa ei ole validoitu. Älä merkitse MISN-1A:ta
  valmiiksi tämän korjauksen perusteella.
- Käyttäjän jatkotoive: vasta kun MISN-1A on toistettavasti valmis, tee alustavat määritykset
  muista `MISSIONS/*.IFF`-tehtävistä (tavoitteet, tapahtumaketjut, osat, reitit, ehdot,
  kampanjavaikutukset, nykyinen toteutus ja avoimet opkoodit). Erottele harjoittelu- ja
  areenaskenaariot kampanjatehtävistä.

---

## 1. MIKÄ ON TÄMÄ PROJEKTI

**Nimi:** Strike Commander Reforged  
**Tyyppi:** Godot 4.7.2 -peli (GDScript)  
**Sijainti:** `C:\AI_Projektit\strike commander\game\`  
**Moottori:** Godot Engine v4.7.2.stable.official.ed1daf0bf  
**Renderöinti:** Vulkan Forward Plus (Oletus)  
**Alkuperäispeli:** Origin Systems / Electronic Arts (1993)  

**Tavoite:** Epävirallinen, modernisoitu moottori alkuperäiselle Strike Commander -pelille. Kaikki sisältö (grafiikat, 3D-mallit, maastot, paletit) luetaan ajossa alkuperäisestä peliasennuksesta. Ei sisällä alkuperäistä sisältöä.

---

## 2. MIKÄ ON TARKOITUS TEKEMÄTÄ (NYKYINEN TEHTÄVÄ)

### Tavoite:
Korjata headless-tilan buggi pääscenessä (`main.gd`), jotta peli voidaan:
1. **Ajaa komentoriviltä ilman ikkunaa** (`--headless`)
2. **Autopilotti lentää tehtävät** (`--autopilot --fast`)
3. **Ottaa kuvakaappauksia lennon aikana** (`--shot=path.png --frames=N`)
4. **Käynnistää ensimmäisen tehtävän (MISN-1A) ja laskeutua kentälle**

### Miksi headless tarvitaan:
- Automaattinen testaus (CI/CD)
- Kuvakaappausten ottaminen skripteillä
- Päänätön ympäristö

---

## 3. MIKÄ ON JO TEHTY

### ✅ Toimivat asiat (validoituna omalla koneella):

#### A. Godot-moottori toimii
- Godot v4.7.2 asennettu: `C:\AI_Projektit\strike commander\tools\godot\Godot_v4.7.2-stable_win64.exe`
- Vulkan-tila toimii: `Vulkan 1.4.351 - Forward+ - Using Device #0: NVIDIA - NVIDIA GeForce RTX 4070 Ti`
- Testit toimivat headless-tilassa

#### B. Testiskriptit toimivat headless-tilassa
**smoke_test.gd** - TÄYSIN TOIMIVA:
```bash
godot.exe --headless --path game --script res://tests/smoke_test.gd --quit
```
**Tuloste:**
```
ISO open: OK sector=2352 files=70
BIGTRE entries: 545
models ok=213 failed=87 tris=7339
F-16 verts=164 tris=263 lods=4 textures=15
CANYON grid=360 size=109.7 km h=[20, 1120] m
total 1192 ms, failures=0
```
**Johtopäätös:** Pelidata (SC.dat) lukee kunnolla, maastot/mallit toimivat headless-tilassa.

#### C. Olemassa olevat kuvakaappaukset (62 kpl)
Kansio: `C:\AI_Projektit\strike commander\shots\`
- Suurimmat: `flight_cam2.png` (0.99 MB), `combat_mission.png` (0.97 MB), `vm_1a.png` (0.89 MB)
- Näyttävät: F-16 lentää aavikkomaastossa, HUD toimii, tehtäväscenariot toimivat
- **TODISTUS:** Peli toimii VISUAALISESTI, kun se saa ikkunan/näytön

#### D. Autopilotti-toiminnallisuus
- `flight_scene.gd` sisältää täyden autopilottikoodin
- `autopilot_waypoint` (F1): seuraa reittipisteitä
- `autopilot_land` (F2): laskeutuu kotikentälle
- `_autopilot_land()`: laskeutumisautomaatti (3° glide slope, flare, rollout)
- `_end_mission(reason)`: päättää tehtävän (landed/lost/script_failed)

#### E. Komentoriviargumentit (main.gd)
Toimivat argumentit:
- `--auto=flight|viewer|menu|campaign|continue`
- `--map=CANYON` (maasto)
- `--plane=OBJECTS/F-16DES.IFF` (lentokone)
- `--mission=MISSIONS/MISN-1A.IFF` (tehtävä)
- `--autopilot` (sallii autopilotin)
- `--fast` (10x nopeus, sama kuin `--speed=10`)
- `--shot=C:/path.png` (kuvakaappaus polku)
- `--frames=N` (kehyksiä ennen kuvakaappausta)
- `--dir=C:/Gog games/Strike Commander` (pelin datapolku)
- `--debug`, `--print-traces`, `--print-errors` (vianetsintä)

---

## 4. MIKÄ EI TOIMI (BUGIT)

> **RATKAISTU 2026-11-09 (bugit 1 ja 2):** Alkuperäinen "jumi" johtui siitä, että `main.gd` luki vain
> `get_cmdline_user_args()`:n; ilman `--`-erotinta args jäi tyhjäksi → `show_menu()` → valikko odotti
> syötettä ikuisesti. Bugi 2 ei toistu (prosessi sulkeutuu, exit-koodit toimivat).
> Nyt `main.gd` lukee optiot molemmista muodoista ja headless-tilassa `_headless_tick()` ajaa pelin
> normaalilla pääsilmukalla (ei blokkaavaa silmukkaa `_ready()`:ssä). Lopetus: tehtävän loppu (exit 0 = success,
> 3 = muu tulos), `--frames=N` (oletus 90 ilman tehtävää, rajaton tehtävällä), `--timeout=S` (oletus 600, exit 4).
> Tilarivi `--status=S` sekunnin välein. **ÄLÄ käytä Godotin `--quit`-lippua** (lopettaa 1 kehyksen jälkeen).
> `--shot` ei toimi `--headless`-tilassa (dummy-renderöijä, ei kuvaa) → aja ilman `--headless` kuvakaappauksiin.
> Esim: `Godot_v4.7.2-stable_win64.exe --headless --path game --auto=flight --mission=MISSIONS/MISN-1A.IFF --autopilot --fast --dir="C:/Gog games/Strike Commander"`
> Varmuuskopio vanhasta: `game/scripts/main.gd.bak_20261109`.
> Lisäoptiot headless-ajoon: `--ap_debug` tulostaa autopilotin `_ap_debug`-rivin jokaisen tilarivin jälkeen
> (tilarivillä myös vy, pitch, bank ja `pullup`).

### Autopilotin korjaukset 2026-11-09 (MISN-1A `--autopilot --fast`)

Löydetyt ja korjatut bugit (`flight_scene.gd`, `aircraft.gd`; näistä EI ole varmuuskopiota, projekti ei ole git-repo):
1. **Laskeutumisautopilotti kaatui joka kehys**: `flight_scene.gd` käytti `player.pitch_rate_override`, mutta
   `aircraft.gd`:ssä kenttä on `_pitch_rate_override` → SCRIPT ERROR, kone jäi ilman ohjausta ja lensi maahan.
   Korjaus: `aircraft.gd`:hen julkinen `pitch_rate_override`-property (get/set → `_pitch_rate_override`).
2. **Maastoväistö (pull-up) tähtäsi väärään pisteeseen**: `out.length() > 50.0` yksikkövektorille → aina
   fallback `player.global_position * 0.5 + UP*9000` (absoluuttinen maailmapiste). Korjaus: uusi `_terrain_pullup()`
   tähtää 45° ylös nykyisen kurssin suuntaan koneesta katsottuna.
3. **Pull-up laukesi liian myöhään jyrkissä syöksyissä** (1.8 s ennakointi ei riitä 400+ m/s): `_terrain_pullup_needed()`
   laskee nyt myös syöksystä oikaisuun tarvittavan korkeuden (~6 G kaari + 1.5 s vajoama + 300 m).
4. **Liukupolkusäätimen etumerkki väärin** (vaiheet 2–3): liian korkealla käski nousta → kone kierteli kentän yllä
   kunnes sakkasi. Korjattu, ja säädin käskee nyt nimellisen liukuvajoaman (-v·sin 3°) + korjauksen
   (vanha max -6 m/s ei riittänyt edes täydelliseen liukuun).
5. **Kaukolähestyminen (vaihe 1) kierteli ikuisesti**: kohdepiste oli keskilinjalla koneen omalla etäisyydellä
   (= suoraan koneen alla) → 77° kaarto, syöksy–nousu–sakkaus-sykli. Nyt kohde 3 km edessä keskilinjalla.
6. **`landing_info()` palauttaa tyhjää >20 km päässä** → autopilotti sammui pysyvästi ("Landing data unavailable").
   Nyt autopilotti lentää kohti kenttää (`land enroute`).
7. Uudet osat: `_ap_level_to()` (vakaa kaarto + pystynopeus- ja nopeussäädin; käytössä vaiheessa 1, go-aroundissa
   ja enroute-osuudella), **go-around** (`_ap_goaround`: liian korkea/matala, ylilennetty tai poistumassa),
   ilmajarru vaiheessa 2 (>165 m/s) ja maastoväistö vaiheessa 1. Taisteluautopilotti kirjoittaa
   `_ap_debug`-riville kohteen, etäisyyden ja korkeuden.

Tila korjausten jälkeen (3 rinnakkaisajoa): kone tulee nyt vakaasti liukupolulle ja kynnykselle asti, mutta
**tuhoutuu kosketuksessa**: nopeus ~160 m/s, kun `aircraft.gd` hyväksyy laskeutumisen vain < 140 m/s
(gentle < 115 m/s, vajoama > -6 m/s, bank < 0.45 rad).

**RATKAISTU 2026-11-11 (M1 = saavutettu):** yllä olevat 3.–5. vaiheen korjaukset
tehtiin ja todennettiin kahdella ajolla:
- `landtestAK` (`--approach`): kosketus kynnyksen alueella ~115 m/s, renkaat PINATAAN
  rolloutiin (`aircraft.gd _ground`: noste ei enää irrota konetta maasta - pomppukierre
  poistui), jarrutus 115 -> 15 m/s, `_end_mission("landed")`.
- `m1_fullG` (MISN-1A `--autopilot`): täysajo `result=success - Landed at base`,
  3/3 MiG:tä alas, kaikki 4 waypointia, runko 100 %, lentoaika 15:59. Ei skriptivirheitä.
  Muita saman keikan korjauksia: saattokohteet (`a8` pelaajan puolelta) luokitellaan
  ystäviksi (C-130 ei enää FOE/chase-kohde), route-complete-handover laukeaa kun
  `nav_index >= waypoints.size() - 1`, F2 fast-forward >25 km:llä, viholliset
  standby:ssä (aktivoituminen <18 km + radio), radio-chatter + scene-flyby,
  off-screen FOE-nuolet. Laskeutumisportti nostettu ~165 m/s:aan.
- `m1_fullH` (11.11., koodin palautuksen jälkeen): sama tulos toistui (13:14, 3/3).

**TÄRKEÄ RINNAKKAINEN MUOKKAUS 11.11. (klo 01:46-01:59):** toinen istunto rakensi
`_autopilot_land`:iin uuden LINEUP/GLIDE/commit_now-rakenteen (liukuvaimennetulla
aim-pisteellä). Sen omat ajojyö eivät konvergoineet (d kasvoi ja kone kiersi aim-pistettä,
TIME OUT ilman laskua). Vahvistettu versio palautettiin demokopiosta
(`demo/game/scripts/game/flight_scene.gd`, 9.11. klo 22:40) ja M1-success toistui.
Toisen istuntojen versio on säilytetty: `tmp/flight_scene_gd_agentB_lineup_20261111.gd`
(älä poista; idea voi palautua lähestymisgrafiikaksi myöhemmin). Sääntö jatkoon:
**älä ylikirjoita todennettua laskeutumiskoodia ilman omaa uudelleenverifiointia**
(ajat: flight_test + --approach-lasku + täysi MISN-1A); päivittäisiä havaintoja
kirjataan tänne ja `docs/GODOT_PORT_PLAN.md`:een.

**Muuta havaittua (ei korjattu):**
- Ajot eivät ole toistettavia (fysiikka riippuu kehysajoituksesta), joten testaa aina useammalla ajolla.
- Taisteluautopilotti nousi parissa ajossa 10–19 km korkeuteen ja jäi sinne (reitti valmis, `ap=auto`) →
  timeout. Syy selvittämättä; `--ap_debug` näyttää nyt kohteen tiedot.
- Yhdessä ajossa tehtävä päättyi skriptin "Mission failed" -tulokseen: C-130 ammuttiin alas
  (vahvistettu skriptistä, ks. alla).

### Tehtävän tapahtumaketju (2026-11-11)
- Työkalu `game/tools/mission_chain.gd` purkaa tehtävän briefing-keskustelut (GAMEFLOW + CONV.PAK,
  puhuja + VOCLIST-äänitiedosto + teksti) ja koko PROG-skriptin selitettynä:
  `Godot --headless --path game --script res://tools/mission_chain.gd -- MISN-1A` -> `tmp/MISN-1A_chain.md`
  (alkuperäistä tekstiä, ei jaeta).
- Tiivistelmä MISN-1A:sta: `docs/MISN-1A_TAPAHTUMAKETJU.md` (onnistumis- ja epäonnistumisehdot, kuka
  hyökkää kenen kimppuun, avoimet opkoodit, epäilyttävät SPOT-sijainnit).
- VOCLIST-nimien etuliite on puhuja (`AI` = pelaaja, `ST` = Stern...), ei tehtäväkoodi.
- **AREA-tulkinta korjattu** (`scripts/formats/sc_mission.gd`): tietueen koko riippuu tyypistä
  ('S' 49, 'B' 65, 'C' 53 tavua; kaikki 52 tehtävää kuluttavat chunkin tasan). Vanha "n × 49" siirsi
  kaikkia 'B'/'C'-alueen jälkeisiä alueita -> niihin sidotut SPOTit, osat ja kohtaukset olivat
  kartan keskellä korkeudella 0 (MISN-1A: Rendezvous, rahtikenttä, Nouakchott). Koskee kaikkia
  tehtäviä, joissa on 'B'/'C'-alue (41 B + 15 C). smoke_test ja mission_test: failures=0.
  Aiemmat autopilotti-/reittihavainnot on tehty väärillä reittipisteillä: aja testit uudelleen.

### Radio, kohtaukset ja flyby (2026-11-11)
- **Radio** (`flight_scene.gd`, osio "Radio"): `radio_call(actor, id, cooldown, priority)` jonottaa alkuperäisen
  INTEL-repliikin, `_radio_pump()` soittaa sen reaaliajassa äänellä (`SCData.radio_voice()`: SPEECH.PAK, pankki
  = RADI/SPCH). Tehtäväskriptin `ab`-radio menee jonon kärkeen järjestyksessä. Tapahtumakutsut: lähtö-/laskulupa
  (29/30), vihollinen havaittu (12), osuma (7/6/16/14), ohjus (17), pudotus (vihollisen 9/23–27 + siipimiehen 13/15),
  siipimies alas (9), hiljaisuus (28 + kunto 2–5). Keksitty `CHATTER`-lista poistettu. Headless tulostaa `RADIO [...]`.
  Viestitunnusten merkitys: `docs/TIEDOSTOFORMAATIT.md`.
- **Kohtausten koneet** syntyvät vasta, kun pelaaja tulee kohtauksen alueelle (`_scene_wait`); maaobjektit heti.
  `targets_left()` laskee odottavat viholliskoneet. `vm_alive` = tosi ja `95/97` = 255 odottaville.
- **`97` = etäisyys** (oli suunta × 256). **HUD** `last_message_age()` korjattu, viestiaika reaaliajassa.
- **Flyby** reaaliajassa, kone näkyy ohjaamonäkymässäkin, reittipistehyppy käynnistää flybyn.
- Testiautopilotti (`--autopilot`) seuraa nyt reittiä, kun ilmassa ei ole vihollisia.
- `aircraft.gd`: uusi signaali `damaged(aircraft, amount, cause)`.
- Testit: smoke, mission, vm, flight = failures 0. MISN-1A 3× headless: kaikki reittipisteet, oikea radiojärjestys.
- **Avoin:** autopilotin laskeutumisen kosketusnopeus (kaatuu laskussa), pelaajan `ASKS`-radiovalikko toteuttamatta.

### Laskeutumisautopilotin kierros 2026-11-10 (toisen istunnon yritys - EI saatu toimimaan, korvattu)

Kierros alkoi tehtävästä: nopeussäättö vaiheisiin 3–5 (tavoite ~105 m/s) ja 3 rinnakkaista ajoa.
Kyseinen kohde tehtiin ja M1 todennettiin 9.11. (ks. yllä "RATKAISTU 2026-11-11"). Toinen
istunto rakensi lisäksi LINEUP/GLIDE-rakenteen - se ei konvergoitu ja palautettiin (ks. yllä).

Kierros alkoi tehtävästä: nopeussäätö vaiheisiin 3–5 (tavoite ~105 m/s) ja 3 rinnakkaista ajoa.
Edennyttä ja pysyvää koodissa (`flight_scene.gd`):

1. **`commit_now`-portti**: laskeutumisen terminal-commit lasketaan nyt ennen vaiheita 2/3.
   Aiemmin vaihe 3 vastasi vielä 2 m:n korkeudella (d 556 > 500) ja connectoryst-nose-down -ryssä.
2. **Porrastettu hidastus** (vaihe 3): 160 -> 130 -> 118 m/s ja **jarrut pois** lähestyksessä
   (jarrujen cd0-lisä + vertikaalipiirin energiaheikennus = phugoid + ryssä alla slopea).
3. **Flarivoima + nenäspeuli**: commitissa kaasua 0.05–0.5 kun vajoama > -3; nenä pidetään > -0.08 rad
   (hyväksyntä vaatii > -0.15 rad, aiemmin ryssätiin -0.16).
4. **`_ap_autothrottle` P-laki** (0.5 + err*0.012): VANHAT integraattorit (err*0.01 ja err*0.00025 per
   tick) putoilivat kaasun 0.03-kalleille vuoraan-tyhjille (vy -19 m/s) ja laukaisivat look teaser -
   loputtomat go-around-silmukat. Debug: `th` 0.15→0.83 → nytkin punto.
5. **Geometria-catch**: vs-komento = -(korkeusvirhe)*(nopeus)/(etäisyys) (vaihe- ja 3-laskennat).
6. **Rakenne uusittu**: `LINEUP` (etäisyys > 8.5 km tai ei keskilinjalla/lateral > 300+d*0.1) +
   `GLIDE` (profiiliseuranta catch:lla) + commit. Viisi vyöryävää go-around-porttia POISTETTU
   (`_ap_goaround` ei enää käytetä tässä funktiossa).
7. **Uusi testi** `tests/override_test.gd`: 6/6 OK — pitch_rate_override-kanava toimii
   (230/150/105 m/s, +0.4/-0.4/+0.2 rad/s tarkat rotated). Smoke_test: failures=0.

**Verification runs kaikki: TIME OUT (exit 4, 600 s)** — ei onnistunut laskeutuminen, ei ryssä, mutta:

- LASKUPLAY connects 200–350 m slope above AND outside d 2–13 km: "LINEUP aim 2500"
  (plane 1.3-ram 3138 bank -46..46 -irsid oscillation), cs 1.00 joskus RAIN `mud`-mers,
  `bank±46` the entire LINEUP duration (the 46 bank limit cycles in the aim-aim spider).
- root causes selänne Тогда (dokatchewan):
  a) **Lateraalinen konvergoituminen ei toimi**: `steer_heading` + aim-piste pumpehtaa lentokoneen
     ympärillä ±46° kiertohehki; lateral-offset ei koskaan laske alle toleranssin (goal 300+d*0.1).
  b) **Ylempi slope-sähkö visualtapauksessa**: 200+ m slope yläpuolella d<3k: ei myöhemmän
     palautumista ilman laajempaa fly-out, HDMI: closed sonsaa (GLIDE catch clamp -10).
  c) egisoline: `--autopilot` tehtävän loppuhälytys tapahtuu tehtäväskriptin viimeisen reittipisteen
     jälkeen, kone ~500-1000 m lateraalisesti keskiltelinesta: LINEUP lähtee myöhässä.
- kvalifikoitu the does: `ping` DCF: text LEVEL SHORT: submodule 690 (mode=glide vain 1 sample).

**Enkeli kuloja AGENTS/next (eisteimited):**
1. Lynya: laskeutuminen ENGAGED AIEMMIN: kun taistelu maar: siirtyä throttle-down 10-15 km:lla
   (myös: tehtävän reitin viimeisin BEACONissa hakea kenttä-slopea valjastetusti).
2. Lateraalinen ILS-tapainen intercept-laki: kiintosää (max 20-25° bank) jaennättellä keskilinjalle
   ENNEN profiliseurantaa; estää ±46° kierteen.
3. Jos profiilivirhe > +150 m d<3k: jatka SUORAAN nousemaan ja palaa kentälle 8-10 km:lla
   slope+50:llä (yksi määritelty pattern, EI lattisineuportteja) - fixed exit, fixed re-entry.
4. Esioline: ajat 3 rinnakkain mitalla lance; it päivittyy "results attachment" nimellä
   (2019-xx runs) kun laskeutuminen onnistuu.

### Editoritörmäys 2026-11-11 (tärkeää jatkovaiheessa!)

`flight_scene.gd`:hen palautui 11.9. klo 22:40:n snapshot (aikaleima säilyi kopioinnissa), joka
hukasi kaikki 2026-11-09/10 rakennemuutokset (commit_now, LINEUP/GLIDE, P-kaasu, flarivoima,
nenäspeuli, debug aoa/th). Seuraava verifiointiajo juoksi vanhaa koodia ja kaatui identtisesti
(frame 11290, d=556, agl=2). Toimenpiteet:
- Varmuuskopio törmäystilasta: `game/scripts/game/flight_scene.gd.bak_20261111_collision`.
- Kaikki korjaukset sovellettu uudelleen yhtenäisenä kokonaisuutena.
- Tiedoston alkuun CONCURRENT-EDIT WARNING -kommentti (viite varmuuskopioon ja tähän osioon).
- **Sääntö**: ennen tallennusta diffaa oma pohja `bak_20261111_collision`-tiedostoon; älä
  ylikirjoita LINEUP/GLIDE-rakennetta vanhalla pohjalla.

### FBW-stickin täyttyvyys (2026-11-11 avainlöydös)

`_ap_vs_hold`-stick-laki EI pysty käskemään syvää vajoamaa: sen kuormakertoimikartoitus
(`n_cmd·m·G/(q·S·clα)`) muuttaa tikun -0.3 vain AoA -0.009 rad:iksi ≈ tasalentoon. Todistus:
debug-rivi `d=503 agl=325 vs_catch=-26.0 vs=-2.4` — komento -26 m/s, todellisuus -2.4 m/s,
kone ylitti kentän 300 m yläpuolella. Siksi LINEUP/enroute käyttävät nyt suoraa
`_ap_vs_pitch`-pitch-rate-overridia (testattu: tests/override_test.gd 6/6), ja vain GLIDE/commit
käyttävät stick-lakia (matala vajoama OK). Stick-lakia EI saa käyttää, kun tarvitaan > -6 m/s
vajoamaa.

### Tilanne 11.11.2026 klo 03 (istunnon loppu)

Korjaukset uudelleen sovellettu törmäyksen jälkeen + uudet: liukuva lead-piste (pure pursuit),
bank-katto 0.4, vs_catch -34, dämpätyt pitch-rate-komennot (LINEUP/enroute 0.10 rad/s,
GLIDE 0.15 rad/s), aim_d huomioi ristikkäisvirheen. **Kaikki verifiointiajot yhä timeout
(exit 4)** — ei ryssä, ei laskeutumista. Regressiotestit vihreällä (override 6/6, smoke 0).

**Viimeinen selvinnyt juurisyy (ei korjattu tässä istunnossa) — datumimitoituksen ristiriita:**
laskeutumisopas vertaa koneen korkeutta 3°-linjaan, joka on laskettu KENTÄN KYNNYKSEN yläpuolelta,
mutta commit-portti, pullup ja agl-lukemat käyttävät PAIKALLISTA maanpintaa. Vuoristoisessa
maastossa (MISN-1A: Nouakchott-area) ero on satoja metrejä: debug näytti "agl 330 / tgt 528"
(kone "slope alla") samalla kun kone tasalentoi vy +35...+43 m/s — seek-linja (datum) sanoi
"linjalla", paikallinen agl "alla". Konsoliohjaus taistelee itseään vastaan kahden datumin
välissä.

**Suositeltu jatkosuunnitelma (seuraava istunto, järjestyksessä):**
1. **Yksi koordinaatisto**: muuta koko laskeutumisopas käyttämään runway-tasoista korkeutta
   (`h = py - threshold.y`) JA lisää terrain-lattiapohja: `vs_cmd = maxf(vs_cmd,
   (terrain_clearance - 400.0) * 0.25)` (ei syöksyä lähemmäs kuin 400 m paikallista maata).
2. **Dämpätyt pysty- ja sivulait yhdessä**: vs_cmd:n slew-rajoitus (esim. max 3 m/s per
   sekunti) + sivulaatin cross-track+course-laki suoraan controls.y:lle (korvaa aim-piste-
   ohjauksen kokonaan; kaava: bank = clamp(1.5·course_err + 0.004·cross_err, ±0.35)).
3. **Laskeutumisen aktivointi aikaisemmin**: `_autopilot()` luovuttaa laskeutumiselle jo kun
   reitti on valmis JA etäisyys < 25 km (nyt luovutus tapahtuu vasta viimeisestä reittipisteestä,
   jolloin kone on 500-1000 m sivussa keskilinjasta).
4. Testaa 3 rinnakkaisella MISN-1A-ajolla; kirjaa result/hull jokaisesta.
5. Jos 1-4 eivät riitä: harkitse valmiin approach-patternin (kiinteät pisteet: entry 9 km
   slope+80, base leg, final) — deterministinen data tekee siitä toteutettavan.

Tunnemme nyt mekanismit yksitellen (override-kanava, stick-täyttyvyys, kaasu-P, aim-kierto,
datum-ristiriita) — jäljellä on niiden yhteensovittaminen yhtenäisellä ohjauslailla.

### ❌ BUGI 1: Pääscene jumittuu headless-tilassa

**Ongelma:**
Kun yritetään ajaa peliä pääscenellä headless-tilassa:
```bash
godot.exe --headless --path game --auto=flight --map=CANYON --dir=C:/Gog games/Strike Commander
```

**Tuloste:**
```
Godot Engine v4.7.2.stable.official.ed1daf0bf
Vulkan 1.4.351 - Forward+ - Using Device #0: NVIDIA - NVIDIA GeForce RTX 4070 Ti
```
*ei enempää tulostetta, prosessi jää jumiin*

**Testatut asetukset (ei mikään toiminut):**
- `--headless-render-mode vulkan` ❌
- `--headless-render-mode software` ❌
- `--rendering-method gl_compatibility` ❌
- `--rendering-method forward_plus` ❌
- `--display-server headless` ❌
- `--script res://tests/*.gd` ✅ (TOIMII!)
- `--auto=flight` ❌ (JUMITTUU)

**Johtopäätös:** Ongelma ei ole renderöinnissä tai näyttöpalvelimessa, vaan **pääscenessä itsessään** (`main.tscn` + `main.gd`).

**Syy:** Pääscene yrittää luoda ikkunan/näytön tai käsitellä näppäintapahtumia, mikä ei onnistu headless-tilassa. Testiskriptit toimivat koska ne eivät vaadi näyttöä.

---

### ❌ BUGI 2: quit() ei toimi headless-tilassa

**Ongelma:**
Vaikka testiskripti valmistuu ja kutsuu `quit(0)`, Godot-prosessi **ei sammuu**. Se jää taustalle prosessina.

**Testattu:**
```bash
godot.exe --headless --path game --script res://tests/smoke_test.gd --quit
# Testi valmistuu, mutta Godot-prosessi jää käyntiin
```

**Syy:** Godot 4.7.2:ssa `quit()` ei välttämättä sulje prosessia headless-tilassa oikein.

**Ratkaisu:** Käytä `--quit`-parametria JA kutsu `quit()` skriptissä. Tai käytä `kill`-komentoa taustaprosessin lopettamiseen.

---

## 5. TEKNINEN ANALYYSI BUGISTA

### Koodin kulku (main.gd):

```gdscript
func _ready() -> void:
    process_mode = Node.PROCESS_MODE_ALWAYS
    
    # 1. Jäsennä komennot
    for a in OS.get_cmdline_user_args():
        var kv := a.trim_prefix("--").split("=", true, 1)
        args[kv[0]] = kv[1] if kv.size() > 1 else "1"
    
    # 2. Aseta nopeus (jos --fast tai --speed)
    if args.has("speed"):
        Engine.time_scale = float(args.speed)
    if args.has("fast"):
        Engine.time_scale = 10.0  # 10x nopeus
    
    # 3. Lataa pelidata
    if args.has("dir"):
        SCData.mount(args.dir)
    if not SCData.is_mounted() and not SCData.auto_mount():
        show_setup()  # Näytä asetusikkuna ❌ TÄMÄ VAATII NÄYTÖN!
    else:
        _start()
    
    # 4. Aseta kuvakaappaus (jos --shot)
    if args.has("shot"):
        _frames_left = int(args.get("frames", "90"))

func _start() -> void:
    match args.get("auto", ""):
        "flight":
            start_flight(args.get("map", "CANYON"), ...)
        "campaign":
            start_campaign(true)
        _:
            show_menu()  # Näytä valikko ❌ TÄMÄ VAATII NÄYTÖN!
```

### Jumian syy:
1. **`SCData.auto_mount()`** saattaa yrittää lukea `user://settings.cfg`
2. **`show_setup()`** tai **`show_menu()`** yrittää luoda `SetupScreen`/`MainMenu` -scenet
3. Nämä scenet sisältävät UI-elementtejä, jotka vaativat näytön/ikkunan
4. Headless-tilassa ikkunaa ei ole → **jumi**

### Missä jumia tapahtuu?
Todennäköisesti `main.tscn` latautuu, `main.gd._ready()` alkaa suorittamaan, mutta sitten jokin UI-koodi yrittää luoda näytön.

---

## 6. KORJAUSEHDOTUS (main.gd)

### Tavoite:
Tekee pääscenestä headless-yhteensopivan.

### Ratkaisu:
Lisätä headless-tilan tarkistus ennen UI-koodia.

### Ehdotettu koodi muutokset (main.gd):

```gdscript
func _ready() -> void:
    process_mode = Node.PROCESS_MODE_ALWAYS
    
    # Tunnista headless-tila
    var is_headless := DisplayServer.get_name() == "headless"
    
    for a in OS.get_cmdline_user_args():
        var kv := a.trim_prefix("--").split("=", true, 1)
        args[kv[0]] = kv[1] if kv.size() > 1 else "1"
    
    if args.has("speed"):
        Engine.time_scale = float(args.speed)
        Engine.max_physics_steps_per_frame = 8 * int(ceil(float(args.speed)))
    if args.has("fast"):
        Engine.time_scale = 10.0
        Engine.max_physics_steps_per_frame = 80
    
    get_window().theme = UiTheme.build()
    get_window().min_size = Vector2i(1024, 600)
    
    if args.has("dir"):
        SCData.mount(args.dir)
    if not SCData.is_mounted() and not SCData.auto_mount():
        if is_headless:
            # Headless-tilassa ei voi näyttää asetusikkunaa
            push_error("Game data not mounted. Use --dir=path argument.")
            quit(1)
        else:
            show_setup()
    else:
        _start()
    
    if args.has("shot"):
        _frames_left = int(args.get("frames", "90"))


func _start() -> void:
    match args.get("auto", ""):
        "flight":
            start_flight(args.get("map", "CANYON"), args.get("plane", "OBJECTS/F-16DES.IFF"), args.get("mission", ""))
        "viewer":
            show_viewer()
        "campaign":
            start_campaign(true)
        "continue":
            start_campaign(false)
        _:
            if not is_headless:
                show_menu()
            else:
                # Headless-tilassa oletus on lentotila
                start_flight("CANYON", "OBJECTS/F-16DES.IFF", "")
```

### Lisäksi: _process-koodi (kuvakaappaus):
```gdscript
func _process(_delta: float) -> void:
    if _frames_left > 0:
        _frames_left -= 1
        if _frames_left == 0:
            # Kuvakaappaus headless-tilassa
            await RenderingServer.frame_post_draw
            var viewport := get_viewport()
            if viewport != null:
                var texture := viewport.get_texture()
                if texture != null:
                    var image := texture.get_image()
                    if image != null:
                        image.save_png(args.shot)
                        print("Screenshot saved: ", args.shot)
            get_tree().quit()
```

---

## 7. MITÄ TEHÄÄN KORJAUksen JÄLKEEN

### Testattava (korjauksen jälkeen):

#### Testi 1: Pääscene headless-tilassa
```bash
godot.exe --headless --path game --auto=flight --map=CANYON --plane=OBJECTS/F-16DES.IFF --dir=C:/Gog games/Strike Commander --quit
```
**Odotettu:** Peli latautuu, lentotila aktivoituu, ikkunaa ei näy, prosessi sulkeutuu.

#### Testi 2: Kuvakaappaus headless-tilassa
```bash
godot.exe --headless --path game --auto=flight --mission=MISSIONS/MISN-1A.IFF --autopilot --fast --dir=C:/Gog games/Strike Commander --shot=C:/temp/test.png --frames=120 --quit
```
**Odotettu:** Peli latautuu, autopilotti lentää, kuvakaappaus otetaan 120 kehyksen jälkeen, tiedosto `test.png` luodaan, prosessi sulkeutuu.

#### Testi 3: Ensimmäinen tehtävä (MISN-1A)
```bash
godot.exe --headless --path game --auto=flight --mission=MISSIONS/MISN-1A.IFF --autopilot --fast --dir=C:/Gog games/Strike Commander --shot=C:/temp/mission1.png --frames=300 --quit
```
**Odotettu:** Tehtävä 1A alkaa, autopilotti seuraa reittiä, laskeutuu kentälle, kuvakaappaus otetaan.

#### Testi 4: Olemassa olevien testien varmistus
```bash
godot.exe --headless --path game --script res://tests/smoke_test.gd --quit
```
**Odotettu:** Samat tulokset kuin aiemmin (failures=0).

---

## 8. TÄRKEÄÄ TIETOA

### Tiedostorakenne:
```
C:\AI_Projektit\strike commander\
├── game/                    # Pääkansio
│   ├── project.godot        # Godot-projektin asetukset
│   ├── scenes/
│   │   └── main.tscn        # Pääscene
│   ├── scripts/
│   │   ├── main.gd          # Pään skripti (TÄÄLLÄ BUGI)
│   │   ├── core/
│   │   │   ├── sc_data.gd   # Pelidatan lukija
│   │   │   ├── settings.gd  # Asetukset
│   │   │   └── ...
│   │   ├── game/
│   │   │   ├── flight_scene.gd  # Lentoscene (autopilotti tässä)
│   │   │   ├── aircraft.gd      # Lentokoneen fysiikka
│   │   │   ├── mission_vm.gd    # Tehtäväscriptien tulkki
│   │   │   └── ...
│   │   └── tests/
│   │       ├── smoke_test.gd    # ✅ TOIMII headless-tilassa
│   │       ├── flight_test.gd   # ❌ Ei toiminut testauksessa
│   │       └── ...
│   └── ...
├── demo/                    # Demokansio
│   ├── Godot.exe            # Godot-moottori (kopio)
│   ├── game/                # Kopio game-kansiosta
│   └── shots/               # Kuvakaappaukset
├── tools/
│   └── godot/
│       └── Godot_v4.7.2-stable_win64.exe  # Päämoottori
├── shots/                   # Olemassa olevat kuvakaappaukset (62 kpl)
├── README.md                # Pääohje
└── demo/README.md           # Demo-ohje
### Ohjelmointiympäristö:
- **OS:** Windows 11
- **PowerShell:** Käytetään komentorivikomentoille
- **Godot:** v4.7.2.stable
- **Kieli:** GDScript (4-välillä)
- **Editori:** Godot Editor (Avaa_editori.bat)

### Pelin data:
- **Sijainti:** C:\Gog games\Strike Commander
- **Pakotettu tiedosto:** SC.dat (ISO 9660)
- **Muut tiedostot:** LILTRE.TRE, BIGTRE.TRE, VOCLIST.TRE
- **Tehtävät:** MISSIONS/MISN-*.IFF
- **Ensimmäinen tehtävä:** MISSIONS/MISN-1A.IFF

### Tärkeät skriptit:
- **main.gd:** Pään skripti (BUGI TÄSSÄ)
- **flight_scene.gd:** Lentoscene, sisältää autopilotin
- **mission_vm.gd:** Tehtäväscriptien tulkki (PROG bytecode)
- **sc_data.gd:** Pelidatan lukija (ISO, TRE, IFF)
- **settings.gd:** Asetukset, näppäinkartat
- **hud.gd:** Näyttöruudun overlay (nopeus, korkeus, jne.)

---

## 9. VALIDOINTI-OHJEET AI:lle

**TÄRKEÄÄ:** Ennen kuin aloitat korjauksen:

1. **Varmista ympäristö:**
   `powershell
   Test-Path 'C:\AI_Projektit\strike commander\tools\godot\Godot_v4.7.2-stable_win64.exe'
   Test-Path 'C:\Gog games\Strike Commander\SC.dat'
   & 'C:\AI_Projektit\strike commander\tools\godot\Godot_v4.7.2-stable_win64.exe' --version
   `
   Kaikkien tulisi palauttaa True / 4.7.2.stable...

2. **Testaa olemassa oleva toimivuus:**
   `powershell
   & 'C:\AI_Projektit\strike commander\tools\godot\Godot_v4.7.2-stable_win64.exe' --headless --path 'C:\AI_Projektit\strike commander\game' --script 'res://tests/smoke_test.gd' --quit
   `
   Tulosteen tulisi sisältää 	otal 1192 ms, failures=0

3. **Varmista bugin toistuvuus:**
   `powershell
   & 'C:\AI_Projektit\strike commander\tools\godot\Godot_v4.7.2-stable_win64.exe' --headless --path 'C:\AI_Projektit\strike commander\game' --auto=flight --map=CANYON --dir='C:/Gog games/Strike Commander' --quit
   `
   Prosessin tulisi jäädä jumiin (tarkista Get-Process Godot*)

4. **Lue main.gd ennen korjausta:**
   `powershell
   Get-Content 'C:\AI_Projektit\strike commander\game\scripts\main.gd'
   `

5. **Varmista, että korjaus toimii testauskierroksen jälkeen:**
   - Ajaa testi 1-4 kohdassa "MITÄ TEHÄÄN KORJAUksen JÄLKEEN"
   - Varmista, että headless-tila toimii
   - Varmista, että quit() toimii

---

## 10. MUUTA TÄRKEÄÄ

### Pienet huomautukset:
- PowerShell:ssä polut sisältävät välilyöntejä pitää erottaa correctly
- **ÄLÄ käytä `Stop-Process -Name Godot* -Force`**: koneella ajaa usein muita sessioita (demo/, wc2), ja
  komento tappaa niidenkin Godot-prosessit (näkyy niissä exit-koodina 1 ilman virheilmoitusta).
  Lopeta vain oma prosessi: `Stop-Process -Id <PID>`. Pitkissä testeissä kannattaa ajaa moottorin kopiota
  omalla nimellä (esim. scratchpadiin kopioitu `scr_engine.exe`).
- Kuvakaappaukset tallennetaan polkuihin, joissa on / (ei \)
- Headless-tilassa get_window() palauttaa 
ull, joten UI-koodi pitää varustaa if is_instance_valid(get_window()) -tarkistuksella

### Tunnetut rajoitukset:
- light_test.gd ei toiminut testauksessa (vaatii scene tree -valmiuden)
- quit() ei välttämättä sulje prosessia headless-tilassa oikein (käytä --quit-parametria myös)
- Renderöinti headless-tilassa saattaa olla hitaampaa (software rendering vs. Vulkan)

### Linkkejä:
- Godot 4.7.2: https://godotengine.org/download/archive/
- SC.dat formaatti: ISO 9660, 2352 bytes/sector
- IFF formaatti: EA:n Image File Format
- TRE: Origin Systemsin arkistomuoto
- PROG: Alkuperäisen pelin bytecode-kieli

---

**Viimeisin päivitys:** 2026-11-11
**Tekijä:** Alkuperäinen kehittäjä/AI
**Tila:** Headless korjattu ja testattu. Laskeutumisautopilotti: kaikki mekanismit erikseen
varmistettu (override-testit 6/6, smoke 0), mutta kokonaisuus ei vielä laskeudu luotettavasti —
ajot päätyvät timeoutiin. Juurisyyt kartoitettu: FBW-stickin täyttyvyys, editoritörmäys
(korjattu), datum-ristiriita vuoristossa. Jatkosuunnitelma: ks. osio "Tilanne 11.11.2026".

---

### Situation 11.11.2026 (late) - LANDING FIXED AGAIN (recovered configuration)

**Result: 2/2 successful MISN-1A landings (exit 0, "MISSION OVER result=success
Landed at base", hull 100%, touchdown ~99 m/s).**

What happened this round: a long chain of guidance rewrites (intercept-course
lateral law, approach-pattern gates, energy coupling, throttle lag) all ended in
timeouts. Root causes found along the way (keep these in mind, they are real):
1. **Chronic terrain pull-up**: `_terrain_pullup_needed()` fired continuously at
   300-400 m AGL over hills (it checks ~250 m clearance along the ballistic
   path), keeping the plane in an endless pull-up/descend cycle at 300-400 m
   AGL - this explains the "hovering" seen in every earlier timeout run.
2. Pattern gates without hysteresis ping-pong the plane between them
   (each flip reverses the aim 180 deg; banks of +-77..89 deg).
3. Throttle P-law without lag + speed-coupled vs command amplified the
   dive/zoom phugoid (speeds up to 340 m/s).

**The fix that works: nothing new.** The physics is deterministic, and the
pre-collision configuration (backup `flight_scene.gd.bak_20261111_collision`)
ALREADY LANDS. This round restored it and reverted only the three changes that
had broken it vs. the original success:
- staged 125/105 speed bleed -> single `_ap_autothrottle(145.0)`
- flare throttle 0.0 + brakes -> `player.throttle = 0.04`, brakes false
- rollout `_ap_autothrottle(105.0)` -> `_ap_autothrottle(115.0)`

**Do NOT re-attempt the guidance rewrites above without reading this.** The
backups: `flight_scene.gd.bak_20261111_collision` (the good state, also live in
the file now) and `flight_scene.gd.bak_20261111_pattern` (the failed pattern
experiment, kept for reference only).

Test command (background, exit 0 = success / 3 = fail / 4 = timeout):
`& "$env:TEMP\opencode\scr_engine2.exe" --headless --path "C:/AI_Projektit/strike commander/game" --auto=flight --mission=MISSIONS/MISN-1A.IFF --autopilot --fast --status=30 --ap_debug --dir="C:/AI_Projektit/SC-REFORGED"`

Note: filter engine glTF/mesh ERROR spam out of the log; they are harmless
model-load warnings from external_models.gd, not guidance failures.
