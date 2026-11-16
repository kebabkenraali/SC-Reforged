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

Remaken HUD/autopilotti näyttää kuitenkin Nouakchottin ennen rahtikenttää, kuten
Playtesters Guiden suosittelema taktiikka. Alkuperäisen mission IFF-dataa ei muuteta.

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
| C-130 aktivoitui kartan origoon | Sen absoluuttinen PART-alkupaikka on maaston alla, vaikka aktivointi tapahtuu Rendezvous-kohtauksen sisääntulossa | Alueeseen perustuva sijoitus on toteutettu, mutta regression-testi ja täysi lento ovat vielä varmistamatta |

Testattu headless-ajolla (3 rinnakkaista): radiojärjestys tukikohta (lähtölupa) -> C-130 "Glad you could join us"
kohtaamisessa -> Stern "Bandits inbound" kun MiGit ilmestyvät -> MiGien kuolinhuudot + Sternin kuittaukset ->
tukikohta laskeutumislupa. Kaikki 4 reittipistettä saavutettiin ja 3/3 MiGiä pudotettiin. Tehtävä päättyi silti
"Aircraft lost": autopilotin laskeutuminen on yhä liian nopea (avoin, ks. AI_INSTRUCTIONS.md).

**Pelattavuushuomio (alkuperäinen skripti):** C-130:n "We're safe" -> "Mission accomplished" vaatii, että kaikki
MiGit on pudotettu ennen kuin rahtikone on laskeutunut JA pelaaja tullut rahtikentälle (kohtaus 4 poistaa
laskeutuneen C-130:n). Testiautopilotti lentää reitin ennen MiGejä, joten se ei saa skriptin onnistumista;
kotiin laskeutuminen kaikki MiGit pudotettuina lasketaan silti onnistumiseksi (`targets_left() == 0`).

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

## Jatko muiden tehtävien kanssa

Kun MISN-1A:n C-130-spawnaus, reitti, tehtävän onnistumisehdot ja kotiinlasku on
toistettavasti validoitu, laadi jokaisesta muusta `MISSIONS/*.IFF`-tehtävästä
alustava määritys: tavoite ja tapahtumaketju, reitti/alueet, osat ja niiden
roolit, onnistumis-/epäonnistumis- ja kampanjaehdot, nykyisen Godot-toteutuksen
tila sekä tuntemattomat PROG-opkoodit ja testattavat riskit. Harjoittelu- ja
areenaskenaariot erotellaan kampanjatehtävistä.
