# MISN-1A (Mauritania) – tapahtumaketju

Koonnut `game/tools/mission_chain.gd` pelin omasta datasta (GAMEFLOW.IFF, CONV.PAK,
MISSIONS/MISN-1A.IFF, INTEL/*.IFF). Tämä tiedosto on tiivistelmä omin sanoin; täysi
raportti alkuperäisine repliikkeineen syntyy ajamalla:

```bash
tools/godot/Godot_v4.7.2-stable_win64.exe --headless --path game --script res://tools/mission_chain.gd -- MISN-1A
```

-> `tmp/MISN-1A_chain.md` (sisältää alkuperäistä tekstiä: pidä paikallisena, älä jaa).
Toimii millä tahansa tehtävällä (`-- MISN-2A` jne.).

## Äänitiedostojen nimet (VOCLIST.TRE)

Nimi on `<erä><puhuja><numero>`, EI tehtäväkoodi: `AI` = pelaaja (Airhead, "air"),
`ST` = Stern, `MI` = Miguel, `VI` = Virgil, `GW` = Gwen, `JA` = Janet. Esim. `1AI119`
ja `2AI621` ovat molemmat pelaajan repliikkejä. Keskustelu kertoo jokaiselle riville
oman `voc`-nimen, joten oikea ääni löytyy aina keskustelun kautta, ei nimen etuliitteestä.

## 1. Ennen lentoa: kampanjan vaihe 0

Kampanjan tehtävänumero 0 = MISN-1A. Vaihe 0 alkaa establishing shotilla 5 ja avaa
tukikohtaruudun 11; seuraava vaihe on 1.

| Missä (ruutu / sprite) | Ehto | Keskustelu | Sisältö lyhyesti | Äänet |
|---|---|---|---|---|
| 29 / 21 | lippu 105 ei asetettu | 10 | Stern taustoittaa: nälänhätä, kapinalliset kaappaavat avustuksia; saatamme avustuskoneen kentälle | 2ST067–081, 2AI385–387 |
| 11 / 3 | lippu 102 | 12 | Hangaari: Miguel romuttaa vaurioituneen F-16:n, Virgilin kanssa kiistaa; lähtö Mauritaniaan | 3MI061–067, 4VI214–220, 2ST082–084, 2AI431–432 |
| 11 / 2 | lippu 103 | 13 | Gwen ja Janet kiistelevät edellisestä rahtilennosta | 2AI572–576, 4GW086–089, 3JA054–060 |
| 11 / 28 | lippu 103 | 14 | Janet vihjaa kilpailevan laivueen värvääjästä | 3JA046–051, 2AI450–451 |
| 13 / 16 | lippu 104 | 31 | Virgil: talous tiukoilla, halpa Mauritania-keikka pitää hoitaa siististi | 4VI071–082, 1AI119–121 |
| **20 / 12** | – | **11** | **Varsinainen briefing** (alla), sitten lento | 2ST139–149, 2AI621 |

Briefing (keskustelu 11), Sternin ohjeet tiivistettynä:
1. C-130 on matkalla kohtauspisteeseen; tapaaminen noin 20 000 jalassa.
2. Jatketaan yhdessä kohti kiitotietä kaakossa.
3. Perillä kierros pääkaupungin Nouakchottin yli, sitten kotiin.
4. Varo vihollisen koneita, Hercules on suojaton; kapinallisilla tuskin paljon ilmavoimia.

Kulku: sprite 12 ruudulla 20 -> `0c 0` (valitse tehtävä 0) -> keskustelu 11 -> `16` lennä.

## 2. Lento: MISN-1A.IFF

Maasto MAURITAN. Reitti (pelaajan route-blokki 0, tekstit MSGS 0–3):

| # | Reittipiste | SPOT | Huom. |
|---|---|---|---|
| 1 | Rendezvous With Cargo | 3 | kohtaaminen C-130:n kanssa |
| 2 | Land Cargo | 7 | sama SPOT, jolle C-130 laskeutuu |
| 3 | Scenic Nouakchott | 8 | |
| 4 | Head Home | 2 | laskeutuminen (a2 02), Strike Base |

**Korjattu 23.11.2026:** aiempi remake-override vaihtoi Land Cargo ja Scenic
Nouakchott -reittipisteet keskenään. Tämä ohjasi autopilotin länteen, vaikka
saatettava C-130 lensi rahtikentälle, ja pikamatka ohitti MiG-alueen niin, että
banditit ilmestyivät vasta tukikohdassa. Override on poistettu; reitti noudattaa
alkuperäistä mission IFF -järjestystä.

Sijainnit (karttakoordinaatit itä/pohjoinen, korjatun AREA-tulkinnan jälkeen, tarkistettu maastoa vasten):

| Alue | Tyyppi | Sijainti | Säde | Maaston korkeus |
|---|---|---|---|---|
| Strike Base | S | (-21.3, 39.6 km) | 6.1 km | 786 m |
| Rendezvous | S | (-13.7, 13.7 km) | 7.6 km | ~1450 m |
| Cargo Destination | C | (0.0, -29.6 km) | 1.5 km | 1248 m (kiitotie id 4 tasan maassa) |
| Nouakchott | S | (-38.7, -16.8 km) | 7.6 km | 75 m (rannikko) |
| Restricted Airspace (MiG:t) | B | (-12.2, -17.4 km) | 15.2 km | ~960 m |

Reitti siis: tukikohdasta etelään kohtaamiseen, sieltä etelä-kaakkoon rahtikentälle,
länteen rannikolle Nouakchottiin ja takaisin pohjoiseen. MiG-alue on rahtikentän ja
Nouakchottin välissä.

Osat:

| id | Kuka | Käytös (skripti) |
|---|---|---|
| 0 | Pelaaja, F-16 | reitti yllä |
| 1 | Stern, F-16 (siipimies) | nousee ilmaan, seuraa pelaajaa; jos yksikin MiG elossa ja C-130 elossa -> saattaa C-130:aa |
| 8 | C-130 (rahti) | **lepää alussa**; aktivoituu kohtauksen 5 sisääntulossa. Lentää SPOT 7:lle ja laskeutuu (lippu 8). Kun MiG:t ovat poissa (kuolleet tai kyselyn 95 arvo >= 5) -> kiitosradio, liput 7 ja 12 |
| 5 | MiG-21 | hyökkää C-130:n kimppuun kunnes lippu 12, sitten pelaajan |
| 6 | MiG-21 | hyökkää Sternin kimppuun |
| 7 | MiG-21 | hyökkää pelaajan kimppuun |
| 2 | Strike Base | lippu 13 -> "tehtävä epäonnistui" -radio; lippu 12 -> "tehtävä suoritettu, palaa tukikohtaan" -radio (kerran, lippu 14) |

MiG:t kuuluvat kohtaukseen 2 (alue "Restricted Airspace", r = 15 km).

Onnistuminen ja epäonnistuminen:
- **Onnistuu:** C-130 selviää ja MiG:t on hoidettu -> lippu 12 -> Strike Base kuittaa ->
  lennä Head Home ja laskeudu.
- **Epäonnistuu:** C-130 tuhoutuu (blokki 8 -> lippu 13) -> Strike Base keskeyttää.
- Kohtaus 4: jos C-130 on laskeutunut (lippu 8), se poistetaan. Tehtävänlaajuinen blokki 5
  odottaa 10 s lipun 8 jälkeen.

Radiorepliikit tulevat INTEL/<cast>.IFF:stä (C-130 #20/#21, STRIBASE #20/#21).

## Korjattu 2026-11-11 (pelin toteutus)

| Oire | Syy | Korjaus |
|---|---|---|
| Reittipisteet eivät toimineet | AREA-tietueet luettiin 49-tavuisina -> pisteet kartan keskellä | `sc_mission.gd` lukee tietueet tyypin mukaan |
| MiGit kartalla heti alussa | `dormant_part_indices()` ohitti kohtausten osat; MiGit odottivat näkyvinä "standby"-tilassa | Kohtauksen lentokoneet luodaan, kun pelaaja tulee alueelle (`_scene_wait`); siihen asti `92` = elossa, etäisyys 255 |
| C-130 "turvassa" ja "tehtävä suoritettu" heti kohtaamisessa | `97` luettiin suuntana ja odottavat MiGit "kuolleina" | `97` = etäisyys; odottavat koneet elossa ja kaukana |
| Radio ei toiminut | Ei ääniä; keksityt chatter-rivit; HUD:n `last_message_age()` -bugi kirjoitti viestien päälle | Alkuperäiset INTEL-repliikit SPEECH.PAK-äänillä jonossa (`radio_call`), tapahtumakutsut, HUD-ikä korjattu |
| Flyby ei näkynyt pikamatkalla | Animaatio pelin ajassa (time_scale 8 -> 0.6 s); ohjaamonäkymässä kone piilossa; hyppy ilman flybyta | Reaaliaika, kone näkyvissä flybyn ajan, hyppy käynnistää flybyn; odottavat viholliset eivät estä pikamatkaa |
| **Pikamatka korvattu 23.11.2026** | Hyppy suoraan reittipisteen keskelle ohitti skenaarioalueen: saatettava kone jäi omalle reitilleen, autopilotti kääntyi väärään reittipisteeseen ja banditit syntyivät vasta tukikohdassa | F7 asettaa nyt pelaajan ja ystävälliset koneet **10 km ennen** reittipistettä, suunnattuna sitä kohti. `nav_index` ei enää hyppyydy: viimeinen osuus lennetään, joten alueen skripti (C-130-kohtaus, MiG:t) käynnistyy oikeassa järjestyksessä. `--fasttravel` on testikomentona käytössä (alias `--approachjump`). Kohtauksen tarkistus ajetaan myös reittipisteen saapumishetkellä, jotta nopea ajoharppaus ei ohita sitä. Lisäksi taisteluautopilotin luovutus laskeutumiselle asettaa koneen puhtaalle 8 km loppulähestymiselle (alkuperäinen reitti tulee kotiin lännestä Nouakchottin yli) |
| C-130 aktivoitui kartan origoon | Sen absoluuttinen PART-alkupaikka on maaston alla, vaikka aktivointi tapahtuu Rendezvous-kohtauksen sisääntulossa | Alueeseen perustuva sijoitus on toteutettu, mutta regression-testi ja täysi lento ovat vielä varmistamatta |

### Rahtikoneen rullaus ja laskeutumisanimaatio (23.11.2026)

Aiemmin C-130 poistettiin heti kosketuksen jälkeen (`vm_remove`), joten se ei
ehtinyt rullata sivuun. Nyt skriptin `a2`-laskeutumisen päätyttyä koneelle
annetaan `taxi_to`-piste 220 m eteenpäin ja 150 m sivuun, ja `vm_action_done`
odottaa rullauksen loppua ennen poistamista. Lokista:
`TRANSPORT landed, taxiing aside to (-2096.7, 1241.0, 29968.2)`.

F6/--autoland -toiminnolla on nyt oma kamera-animaatio: kamera seuraa konetta
3 s, siirtyy sitten kiinteään paikkaan kiitotien vieressä ja katsoo
laskeutumista. Hyppy tehdään 3,5 km:n loppulähestymiseen (aiemmin 9 km), joten
kokonaisuus mahtuu näkyväksi. Kuva: `tmp/landing_anim.png` (kamera hangaarin
kohdalla, F-16 1,3 km päässä lähestymässä).

### Siirtymän animaatio ja lisäosan valikkopääsys (23.11.2026)

F7:n yhteydessä toistetaan nyt alkuperäisen kaltainen **siirtymäanimaatio**
(`camera_rig.gd start_jump`): 3 sekunnin leikkaus, jossa kamera lähtee koneen
nenästä, liukuu siiven ohi ja nousee perän taakse. Animaatio on oikeassa
ajassa, joten `--fast` (time_scale 10) ei lyhennä sitä. Mikä tahansa kameran
vaihto keskeyttää leikkauksen, kuten alkuperäisessäkin. Valikkopainike
**Tactical Operations** käynnistää lisäosan kampanjan suoraan
(`main.gd start_tactical` → `Art.set_active("tactical")` → GAMEFLO2.IFF).

**Todistus 23.11.2026:** täysi MISN-1A ilman `--god`/`--endless_ammo`: `result=success`,
`Landed at base`, radiojärjestys lähtölupa → C-130 "Glad you could join us" →
Hawk "Bandits inbound" → MiG:t alas → C-130 "We're safe" → "Mission accomplished"
→ laskeutumislupa. `waypoint_approach_test.gd`: 4/4 lähestymistä, 10 km (viimeinen
8 km), ystävällinen kone mukana, 0 virhettä. Näkyvä kuva: `tmp/approach_proof.png`
(HUD: `NAV 1/4: Rendezvous With Cargo 9.0 km`, siipimies 0.2 km päässä).
Animaatiosta `tmp/jump_anim.png` ja valikosta `tmp/menu_tactical.png`.

Testattu headless-ajolla (3 rinnakkaista): radiojärjestys tukikohta (lähtölupa) -> C-130 "Glad you could join us"
kohtaamisessa -> Stern "Bandits inbound" kun MiGit ilmestyvät -> MiGien kuolinhuudot + Sternin kuittaukset ->
tukikohta laskeutumislupa. Kaikki 4 reittipistettä saavutettiin ja 3/3 MiGiä pudotettiin. Tehtävä päättyi silti
"Aircraft lost": autopilotin laskeutuminen on yhä liian nopea (avoin, ks. AI_INSTRUCTIONS.md).

**Pelattavuushuomio (alkuperäinen skripti):** C-130:n "We're safe" -> "Mission accomplished" vaatii, että kaikki
MiGit on pudotettu ennen kuin rahtikone on laskeutunut JA pelaaja tullut rahtikentälle (kohtaus 4 poistaa
laskeutuneen C-130:n). Testiautopilotti lentää reitin ennen MiGejä, joten se ei saa skriptin onnistumista;
kotiin laskeutuminen kaikki MiGit pudotettuina lasketaan silti onnistumiseksi (`targets_left() == 0`).

## Korjattu 2026-11-16: skriptin onnistumispolku toimii

C-130:n "We're safe" vaatii, että MiG 7 on ensin tullut 5 NM:n päähän rahtikoneesta (lippu 6)
ja kaikki MiGit on hoidettu rahtikoneen vielä lentäessä. Aiemmin se ei voinut toteutua:
MiGit syntyivät vasta pelaajan tullessa ilmatilaan, ja C-130 lensi hävittäjän nopeudella ja
ehti laskeutua 50 s MiGien ilmestymisen jälkeen. Nyt saatettava C-130 herättää kohtauksen
itse, lentää 170 solmun PART-nopeuttaan ja siipimies taistelee. Tulos 3/3 lokitetulla
lennolla: liput 6, 7, 12, 14 ja Strike Basen "Mission accomplished". Yksityiskohdat:
`SUUNNITELMA.md`, vaihe 2.

## Huomioita suunnitteluun ja autopilottiin

- Pelaajan route-blokin `ab n` -käskyt ovat reittipisteiden tekstejä (MSGS[n]), eivät
  radiolähetyksiä. Raportti näyttää niille myös PLAYER-castin radiorivit (sisällöltään
  geneerisiä kuittauksia), mutta niitä ei pidä soittaa.
- Testiajojen "Mission failed" = C-130 ammuttiin alas. Autopilotin pitää suojata rahtikonetta
  ja ampua ensin MiG id 5 (se jahtaa C-130:aa), ei vain lähintä vihollista.
- Avoimia/dekoodaamattomia opkoodeja tässä tehtävässä: `09 n` (reittiaskeleen jälkeen),
  `b5`, `b6`, `b8`, `b9`, `02 04`, kyselyt `95`/`97` (arvo verrataan >= 5; ehkä etäisyys
  tai tila) ja parametrit `2e`.
- **Korjattu 2026-11-11:** SPOT 3, 4 ja 8 sekä rahtikentän kiitotie olivat kohdassa (0, 0 km)
  korkeudella 0 (~1.9 km maan alla), koska `sc_mission.gd` luki kaikki AREA-tietueet 49-tavuisina.
  'B' on 65 ja 'C' 53 tavua -> alueet 2–4 siirtyivät. Nyt tietueet luetaan tyypin mukaan.
- C-130:n (id 8) PART-sijainti on absoluuttinen (0, 0.6 km, 152 m) eli maaston alla.
  `flight_scene.gd` käyttää aktivoivan kohtauksen aluetta tällaisen aktivoitavan koneen
  sijoituspaikkana ja nostaa sen vähintään 300 m maaston yläpuolelle. `mission_test.gd`:hen
  lisättiin etäisyys- ja AGL-tarkistus. 16.11.2026 testi tulostaa tuloksen ja menee läpi
  (etäisyys 0 m, AGL 300 m). Itse lennossa sijaintia ei ole vielä katsottu lokista.
- SPOT 9–11 (alue -1, ±150 ft / 50000 ft) ovat todennäköisesti suhteellisia siirtymiä
  (muodostelma/sivuun ohjaus), eivät karttapisteitä.

## 3. Lennon jälkeen (tutkittu 17.11.2026)

Lähteet: GAMEFLOW.IFF (vaiheet 0–9 purettu), ohjekirja (`docs/SC_MANUAL.txt`: tukikohta,
toimisto, kirjanpito, keskeytys) ja Playtester's Guide (Mauritania 1).

**Kampanjan eteneminen (toteutettu 17.11.):**
- Jokainen vaihe nimeää heti alussa seuraajansa (`0d n`). Lento (`16`) vie aina siihen,
  **myös epäonnistuneen lennon jälkeen**. Vaihe 1 alkaa `20 0` (onnistuiko tehtävä 0?) ja
  asettaa tai tyhjentää lipun 72, jonka mukaan myöhemmät keskustelut valitaan (vaiheen 1
  Stern-keskustelu 15/16, vaiheen 2 keskustelut 19–22).
- Vaihe 2 nimeää itsensä (`0d 2`): lennon jälkeen se palaa itseensä, ja lennon perään
  ajettu `06 40` avaa kuljetusauton (sprite 18), joka vie vaiheeseen 3. Lippu 40
  asetetaan myös epäonnistumisen jälkeen; vaihe käsittelee tuloksen haarallaan.
- Remake käsitteli `16`:ta ehtona eikä vaihtanut vaihetta lennon jälkeen, joten
  kampanja jäi vaiheeseen 0. Korjattu `campaign.gd`:ssä, testi `campaign_test.gd`.
- `16 n`:n argumentti (1, 2, 5, 1, 8, 5, 6 vaiheissa 0–8) ei ole vaiheen numero.
  Merkitys avoin.

**Tunnistettu, ei vielä toteutettu:**
- Lennon jälkeen avautuvat vaiheet (1, 2, 5, 7, 8) sisältävät aina efektit `1a 0` ja
  `24 0`: todennäköisesti tehtävän jälkikäsittely (palkkio, kirjanpito, tappotaulu).
- Ohjekirja: toimistossa Virgil kertoo talouden tilan, kirjanpito (`19`) näyttää
  kassan, kulut ja ennustetut kulut tehtävää kohden ("jos kassa menee miinukselle, Wildcats
  on mennyttä"), tappotaulu (`13`) vertaa pilotteja. Opas: MISN-1A:n palkkio
  $2,5 miljoonaa; C-130:n menetys = epäonnistuminen.
- Ohjekirja, keskeytys: *restart*, *abort* (takaisin tukikohtaan kuin tehtävää ei olisi
  lennetty) ja *continue* (tukikohtaan kuin tehtävä olisi päättynyt siihen).
- Ohjekirja, autopilotti: ei voi autopilotoida pois toiminta-alueelta ennen kuin
  viholliset on hoidettu tai 10 nm:n päässä. Remaken pikamatka katkeaa uhkaan, mutta tätä
  rajoitusta ei ole.

## Jatko muiden tehtävien kanssa

Kun MISN-1A:n C-130-spawnaus, reitti, tehtävän onnistumisehdot ja kotiinlasku on
toistettavasti validoitu, laadi jokaisesta muusta `MISSIONS/*.IFF`-tehtävästä
alustava määritys: tavoite ja tapahtumaketju, reitti/alueet, osat ja niiden
roolit, onnistumis-/epäonnistumis- ja kampanjaehdot, nykyisen Godot-toteutuksen
tila sekä tuntemattomat PROG-opkoodit ja testattavat riskit. Harjoittelu- ja
areenaskenaariot erotellaan kampanjatehtävistä.

## Tarkistus 17.11.2026 (2)

- **Välivideot:** tehtävän 1 vaiheet viittaavat introon MID1, maisemakuviin 5, 12 ja 10
  sekä kuljetukseen trans0 (myöhemmin 13 ja 3). Kaikki on tallennettu ja toistetaan.
  Vaiheiden alun efektit `26`, `18` ja `22` ovat tuntemattomia, joten puuttuvaa
  kohtausta ei voi täysin sulkea pois.
- **C-130:n nopeus:** mitattu 123 m/s (alaraja 120 m/s). Alkuperäinen PART-nopeus on
  170 kt = 87 m/s; alaraja laskettu 80 m/s:iin, nyt mitattu 92–97 m/s. Kuljetuskone kaartaa
  loivasti (kallistus <= ~23°); aiemmin se kallistui reittikaarroissa lähes 90°.
- **Kohtaamisanimaatio (uusi, remaken oma):** kun saatettava C-130 aktivoituu
  kohtaamispaikalla, kamera näyttää 7 s ulkokuvan ja pelaajan F-16 sekä hävittäjäsiipimiehet
  liukuvat muodostelmaan rahtikoneen taakse (`flight_scene.gd _start_joinup`,
  `camera_rig.gd start_cinematic`). 5/5 täyttä lentoa onnistui animaation kanssa.
