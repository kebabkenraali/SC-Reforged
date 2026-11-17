# Strike Commander Reforged: tilannekatsaus ja suunnitelma

Laadittu 16.11.2026. Perustuu kaikkiin projektin ohjetiedostoihin, koodin läpikäyntiin
ja samana päivänä ajettuihin testeihin. Tämä tiedosto korvaa aiemmat jatkosuunnitelmat
(`AI_INSTRUCTIONS.md`:n eri osiot, `README.md`:n "Next steps", `docs/GODOT_PORT_PLAN.md`:n
avoimet kohdat) siltä osin kuin ne ovat ristiriidassa tämän kanssa.

## 1. Mitä yritetään tehdä

Epävirallinen moderni moottori alkuperäiselle Strike Commanderille (1993) Godot 4.7.2:lla
(GDScript). Kaikki sisältö luetaan ajon aikana pelaajan omasta asennuksesta; projektissa
ei jaeta alkuperäistä dataa. Lopputavoite on koko kampanja pelattavana alusta loppuun.

Välitavoitteet tärkeysjärjestyksessä:

1. **M1:** ensimmäinen tehtävä MISN-1A lentää autopilotilla alusta loppuun ja laskeutuu
   toistettavasti (headless, exit 0). Tämä on automaattitestauksen perusta.
2. **Tehtävämääritykset:** kun M1 on vakaa, alustava määritys jokaisesta muusta
   `MISSIONS/*.IFF`-tehtävästä (käyttäjän nimenomainen toive).
3. **Kampanja:** kaikki tehtävät ja tarinavaiheet läpi.
4. **Puuttuvat alkuperäisominaisuudet** ja julkaisukelpoinen demo.

## 2. Todennettu tila 16.11.2026

Ajettu tänään omalla moottorikopiolla, data `C:/AI_Projektit/SC-REFORGED`.

| Testi | Tulos |
|---|---|
| `smoke_test` | OK, failures=0 (213 mallia, 545 BIGTRE-merkintää) |
| `mission_test` | OK, failures=0. C-130:n aktivointitarkistus tulostuu nyt: etäisyys 0 m, AGL 300 m |
| `vm_test` | OK |
| `flight_test` | OK (5/5) |
| `override_test` | OK (6/6) |
| `campaign_test` | OK |
| `story_test` | OK (241/241 keskustelua) |
| `cutscene_vm_test` | OK |
| `audio_test` | OK |
| MISN-1A `--approach` (pelkkä loppulähestyminen), 2 ajoa | Laskeutuu, runko 100 %. Ajot olivat keskenään identtiset |
| **MISN-1A täysi lento `--autopilot --fast`, 3 ajoa** | **0/3. Kaikki päättyivät "Aircraft lost" (exit 3)** |
| `all_missions_test`, `demo_test`, `music_test` | Ei ajettu tänään |

### Täyden lennon epäonnistuminen tarkemmin

Kaikissa kolmessa ajossa tehtävän sisältö onnistui: 4/4 reittipistettä, 3/3 MiGiä,
radiojärjestys oikea, luovutus laskeutumisautopilotille toimi. Kone tuhoutui joka kerta
samassa kohdassa:

```
land d=596..630  agl=3..5  tgt=31..33  spd=146  vs=-17..-19.5  pr=0.42 (täysi veto)
```

Eli noin 600 m ennen kynnystä kone on 30 m liukupolun alla ja vajoaa 17–19 m/s, kun
3 asteen liuku olisi noin 7,6 m/s. Nousukäsky on jo tapissa, mutta liian myöhään.
Todennäköinen mekanismi (`flight_scene.gd` `_autopilot_land`, vaihe 3, rivit ~2046–2052):

- Vaiheen 3 vajoamiskäsky on `-v·sin 3° + clamp(-gs_err/8, -8, 5)`, eli liukupolun
  yläpuolelta tultaessa jopa -15,6 m/s. Käskyllä ei ole korkeuteen sidottua lattiaa.
- Pitch-rate-säädin (`_ap_vs_pitch`, k=0.08) ei ehdi oikaista tätä vajoamaa viimeisten
  kymmenien metrien aikana.
- Terminal commit laukeaa vasta `agl <= 110` tai `d < 600`; kone osuu maahan ennen kuin
  loiva loppuvajoama ehtii vaikuttaa.
- Aiemmin dokumentoitu datum-ristiriita on yhä koodissa: `agl` lasketaan paikallisesta
  maastosta, liukupolku kynnyksestä.

`--approach`-ajo onnistuu, koska se alkaa valmiiksi linjalta 8 km:stä. Täysi lento tulee
loppuosalle eri energiatilassa. Vanha "2/2 onnistui" -tulos (11.11.) ei siis päde
nykykoodiin: `flight_scene.gd`:tä on muokattu sen jälkeen (viimeksi 15.11. klo 22:59),
eikä muutoshistoriaa ole.

Sivuhavainnot samoista ajoista:

- Debriefin "Flight time" näyttää 1:22–1:46, vaikka simuloitu lento kesti 14–18 min
  (laskee ilmeisesti seinäkelloa, ei simulaatioaikaa).
- Siipimies Stern menetettiin 2/3 ajossa ("Ejecting now!").
- "Wingman kills: 0" ja "Rounds fired" eivät vastaa sitä, kuka pudotti kenet.

## 3. Mikä toimii, mikä ei

**Toimii (testein todennettu):**
datalukijat (ISO, TRE, PAK, IFF, LZW, paletit, mallit, maastot, tehtävät), lentomalli ja
nousu, PROG-virtuaalikone tunnetuilla opkoodeilla, kampanjan haarautuminen ja tallennus,
keskustelut puheineen, välianimaatioiden aikajanat (viitatut MID-kohtaukset, 18 establishing
shotia, trans0–8), äänet, headless-ajo ja sen lopetuskoodit, radio, kohtausten
aktivointi, reittiautopilotti, taisteluautopilotti, loppulähestyminen suoralta linjalta.

**Ei toimi:**

- Täyden MISN-1A-lennon laskeutuminen (ks. yllä). M1 ei ole tällä hetkellä saavutettu.
- `demo/`-kansion kopio on vanhentunut (9.11.) ja rikki: `demo/log.txt` (15.11.) näyttää
  jäsennysvirheen `base_screen.gd`:ssä.
- `Aja_Headless_Test.bat` ajaa `--auto=campaign` headless-tilassa. Kampanja jää
  tukikohtaruutuun odottamaan klikkausta, joten skripti ei testaa lentoa.

**Varmistamatta:**

- C-130:n spawnaus oikeaan paikkaan itse lennossa (yksikkötesti on vihreä, ja radio
  "Glad you could join us" tulee kohtaamisessa, mutta sijaintia ei ole katsottu ajosta).
- Tehtäväskriptin oma onnistumispolku (lippu 12, "Mission accomplished"). Autopilotti
  saa onnistumisen `targets_left() == 0` -oikopolulla, ei skriptin kautta.
- Uusi `loadout_screen.gd` (15.11.) ja sen kytkentä kampanjaan: ei testiä.
- Ulkoiset glb-mallit (F16DES, C130DES, 15.11. muutokset suunnassa ja mittakaavassa).
- Kaikki muut 46 tehtävää lennettyinä.
- Opkoodit `09`, `b5`, `b6`, `b8`, `b9`, `02 04`, parametrit `21/24/25/2f`. Opkoodista
  `97` dokumentit ovat ristiriidassa (ks. kohta 4).
- GAMEFLOW:n effect-12-arvot 9, 11–39, 43–46 ja MID1:n täysi jäljitys.

## 4. Ohjeiden ristiriidat ja rakenteelliset ongelmat

1. **Ei versionhallintaa.** Kansio ei ole git-repo. Tämä on aiheuttanut jo kaksi
   dokumentoitua ylikirjoitusta (11.11. "editoritörmäys" ja rinnakkainen istunto), ja
   siksi tänäänkään ei voi selvittää, mikä muutos rikkoi laskeutumisen. Varmuuskopiot
   ovat käsin nimettyjä `.bak_*`-tiedostoja.
2. **`AI_INSTRUCTIONS.md` on ristiriitainen.** Osiot 4–9 kuvaavat 9.11. ratkaistua
   headless-bugia nykytilana ja neuvovat käyttämään `--quit`-lippua, jonka sama tiedosto
   toisaalla kieltää. Laskeutumisesta on neljä eri "nykytilaa". Osa tekstistä on
   sotkeutunutta (rivit ~233–255).
3. **M1:n tila.** README ja porttisuunnitelma sanovat "DONE / REACHED 8.11.",
   `MISN-1A_TAPAHTUMAKETJU.md` sanoo "laskeutuminen yhä liian nopea", ja tämän päivän
   ajot sanovat 0/3.
4. **Opkoodi `97`.** `AI_INSTRUCTIONS.md`: "97 = etäisyys". `flight_scene.gd`:n kommentti
   (rivi ~843): "97 = open, push 0 for now". README: "97 is still open". Koodin todellinen
   toteutus pitää tarkistaa ja kommentti korjata.
5. **Kolme moottorikopiota ja kaksi datapolkua.** `tools/godot/`, `engine/` ja
   `demo/Godot.exe` (kukin 181 Mt). `Aja_*.bat` käyttää `engine/` + `SC-REFORGED`,
   `Kaynnista.bat` käyttää `tools/godot/` + automaattista hakua, README neuvoo
   `C:/Gog games/Strike Commander`.
6. **Roskaa lähdepuussa.** Noin 35 kertakäyttöistä `fix_*.py` / `add_debug*.py`
   -paikkausskriptiä `game/scripts/`-kansiossa, `src/main.py` (MSX2-pseudokoodia, ei
   liity projektiin), `dist/` ja `dist.7z` (5.11., vanhentuneet, 350 Mt).
7. **Lisenssiristiriita.** `game/models/README.md` ja README lupaavat "CC0 only", mutta
   `F16DES.glb` on CC BY-NC-SA 4.0. Lisäksi `docs/PLAYTESTERS_GUIDE.txt`,
   `docs/SC_MANUAL.txt` ja `tmp/MISN-1A_chain.md` sisältävät alkuperäistä tekijänoikeuden
   alaista tekstiä, eikä niitä saa päätyä julkiseen repoon tai demopakettiin.

`C:\AI_Projektit\SC-REFORGED` on erillinen tutkimuslinja (alkuperäisen pelin muokkaus
DOSBoxissa, ks. sen `MOD_NOTES.md`). Tämä projekti käyttää kansiota vain datalähteenä.
Se ei kuulu tähän suunnitelmaan.

## 5. Suunnitelma

Vaiheet tehdään järjestyksessä. Jokaisella on hyväksymisehto; seuraavaan ei siirrytä
ennen kuin se täyttyy.

### Vaihe 0: Perusta kuntoon (ennen yhtään koodimuutosta)

**TEHTY 16.11.2026.** Lähtötila on commitissa `2aca5e2`. Poikkeamat alla olevasta listasta:
`engine/`-kansio on vielä levyllä, koska siitä oli käynnissä Godot-prosessi (kansio on
`.gitignore`:ssa, eikä mikään käynnistin enää viittaa siihen; sen voi poistaa käsin).
`dist/` ja `dist.7z` jätettiin levylle (350 Mt, `.gitignore`:ssa), koska niiden
tarpeellisuudesta ei ole tietoa. `demo/`-kansio poistettiin kokonaan.

1. `git init` projektin juureen ja ensimmäinen commit nykytilasta sellaisenaan.
   `.gitignore`:en lisäksi: `dist/`, `dist.7z`, `tmp/`, `engine/`, `demo/Godot.exe`,
   `tools/blender-*/`, `docs/PLAYTESTERS_GUIDE.txt`, `docs/SC_MANUAL.txt`,
   `docs/DEKOMPILU/*.asm`, `*.bak_*`.
2. Tästä eteenpäin jokainen todennettu tila on commit. `.bak_*`-tiedostot commitoidaan
   kerran talteen ja poistetaan sitten työpuusta.
3. Yksi testiajuri `Aja_Testit.ps1` (ASCII): kopioi moottorin omalla nimellä temp-kansioon,
   ajaa yksikkötestit, sitten `--approach` ja N täyttä MISN-1A-ajoa, tulostaa yhteenvedon
   ja palauttaa virhekoodin. Korvaa `Aja_Headless_Test.bat`:n.
4. Yksi moottori (`tools/godot/`) ja yksi oletusdatapolku kaikkiin käynnistimiin.
   `engine/` pois.
5. Siivous: kertakäyttöiset `.py`-paikkausskriptit, `src/`, vanha `dist/`.
   `demo/`-kansio joko poistetaan tai synkataan skriptillä `game/`:sta; käsin
   ylläpidettyä kopiota ei pidetä.
6. `AI_INSTRUCTIONS.md` kirjoitetaan uudelleen lyhyeksi (tavoite, komennot, säännöt,
   tunnetut ansat, viittaus tähän suunnitelmaan). Vanha versio jää git-historiaan.
   README:n ja porttisuunnitelman M1-merkinnät korjataan vastaamaan todellisuutta.

Hyväksyminen: puhdas `git status`, `Aja_Testit.ps1` ajaa koko sarjan yhdellä komennolla.

### Vaihe 1: M1 takaisin, laskeutuminen täydestä lennosta

**TEHTY 17.11.2026: M1 saavutettu.** `Aja_Testit.ps1 -Taydet 5`: 5/5 täyttä MISN-1A-lentoa
`result=success`, runko 100 %, siipimiehet 2/2, skriptin oma "Mission accomplished" joka
lennossa. Korjaukset (`flight_scene.gd _autopilot_land`): kiitotien pää valitaan maaston
mukaan ja lukitaan (pohjoispään edessä kumpare 24 m liukupolun yllä); liukupolku kynnyksen
korkeudesta (ei paikallisesta AGL:stä) ja 15 m ylityskorkeus; pystysäädin lentoradan kulmalle
(vaimennus ~0,1 -> ~0,5); keskilinjan seuranta ja lähestymiskartio; go-around liukupolun
korkeudella ja vapautus 8,5 km:ssä; väärältä puolelta tuleva kone kiertää. Pikatoisto:
`--approach=M --approach_high=M --approach_speed=M/S`.

Lähtötieto: vika on rajattu vaiheeseen 3 ja siirtymään commitiin, ei koko ohjaukseen.
Aiemmat laajat uudelleenkirjoitukset (LINEUP/GLIDE, pattern-portit) epäonnistuivat,
joten muutos pidetään pienenä.

1. Toista vika nopeasti: lisää testilippu, joka aloittaa laskeutumisen tilasta, johon
   täysi lento tyypillisesti tulee (esim. 13 km, 750 m AGL, 210 m/s, sivussa linjalta).
   Näin korjausta ei tarvitse testata 15 minuutin lennoilla.
2. Korjaus, ehdotus järjestyksessä:
   - yksi korkeusdatumi koko laskeutumiseen: `h = y - threshold.y`, ja erikseen
     paikallinen maavara vain turvalattiana;
   - vajoamiskäskylle korkeuteen sidottu lattia vaiheissa 2–3, esim.
     `vs_cmd = max(vs_cmd, -(h / 6 s) - 2)`, jolloin vajoama loivenee itsestään lähellä maata;
   - yläpuolelta tulevan korjauksen katto pienemmäksi lähellä kenttää (nyt -8 m/s lisää);
   - jos liukupolun yläpuolella liikaa alle 3 km:ssä, go-around eikä syöksy.
3. Mittaa myös kosketusnopeus: `--approach` koskettaa nyt noin 146 m/s, dokumenttien
   "~99 m/s" ei toteudu.

Hyväksyminen: `--approach` 2/2 ja täysi MISN-1A vähintään 5/5 `result=success`, runko
100 %, ei skriptivirheitä. Tulos commitoidaan ja kirjataan päivämäärällä.

### Vaihe 2: MISN-1A valmiiksi tehtävänä

**OSITTAIN TEHTY 16.11.2026** (ennen vaihetta 1, käyttäjän pyynnöstä). Tulos 3 lokitetulla
täydellä lennolla: tehtäväskriptin oma onnistumispolku 3/3 ("We're safe" → lippu 12 →
"Mission accomplished"), Stern ja C-130 selviävät 3/3, siipimies pudottaa 1–2 MiGiä.
Kaikki 3 lentoa kaatuvat silti laskussa (vaihe 1). Korjatut viat:
- Siipimiehet eivät ampuneet koskaan: `_enemy_ai()` ajaa nyt myös liittoutuneet hävittäjät
  (kuljetuskoneet rajataan `TRANSPORT_MODELS`-listalla). Siipimies irtoaa muodostelmasta
  alle 10 km:n uhkiin.
- Tekoälyllä ei ollut maastoväistöä: Stern lensi maahan joka ajossa (ensin kaartotaistelussa,
  sitten muodostelmassa pelaajan laskeutuessa). Uusi `aircraft.gd _terrain_escape()` kaikissa
  ilmatiloissa.
- Kohtauksen koneet heräsivät vain pelaajan tullessa alueelle. Nyt myös saatettava
  liittolainen herättää ne (C-130 lentää MiGien ilmatilan läpi).
- C-130 lensi hävittäjän nopeudella (kaikilla koneilla on F-16:n fysiikka): kuljetuskoneille
  `cruise_speed` PART-nopeudesta (C-130: 170 kt, alaraja 120 m/s).
- Autopilotti valitsee ensin saatettavaa uhkaavan vihollisen ja lähtee puolustamaan myös
  yli 12 km:n päähän.
- Debriefin lentoaika, skriptin `a0`-odotus ja vihollisten tykkisarjat käyttivät
  seinäkelloa (10× nopeudella väärin): nyt simulaatioaika `_sim_time`.
- Laskeutunut (skriptin poistama) C-130 laskettiin menetetyksi siipimieheksi.
- `ACTIVATE`-lokirivi näytti maanalaisen PART-paikan; nyt todellinen syntypaikka.
  C-130:n aktivointi kohtaamispaikalle 300 m AGL:ään on varmistettu lennosta.

Avoinna tästä vaiheesta: kohdat 5 (toistettavuus) ja 6 (käyttäjän käsilento).
Havainto skriptistä: `46 r` -opkoodin tulkinta ("jos toiminto kesken") on epävarma.
C-130:n blokissa 7 sitä edeltää `45 06` (push lippu 6), mikä viittaa ehdolliseen hyppyyn
pinon arvon perusteella. Nykyisellä tulkinnalla onnistumispolku toimii, mutta asia
kannattaa tarkistaa muiden tehtävien kanssa (vaihe 3, `prog_analyze.gd`).

1. C-130: lokita aktivointipaikka lennossa (`--log`) ja varmista, että se lentää
   rahtikentälle ja laskeutuu (lippu 8).
2. Skriptin oma onnistumispolku: autopilotti hoitaa MiGit ennen rahtikentälle menoa
   ja ampuu ensin MiG id 5:n (se jahtaa C-130:aa), jotta lippu 12 ja "Mission
   accomplished" -radio toteutuvat. Tarkista 3 ajolla.
3. Sternin menetykset: selvitä, onko syy siipimiesten tekoälyssä vai vihollisten
   ylivoimassa; vertaa Playtester's Guiden kuvaukseen tehtävän vaikeudesta.
4. Debriefin lentoaika simulaatioajasta, pudotusten kirjaus ampujan mukaan.
5. Toistettavuus: `--approach`-ajot olivat identtiset, täydet lennot eivät. Kokeile
   headless-ajoon kiinteää askellusta (kiinteä määrä fysiikka-askelia per kehys seinäkellon
   sijaan), jotta sama ajo antaa aina saman tuloksen. Jos onnistuu, regressiotestaus
   helpottuu ratkaisevasti.
6. Yksi käsin lennetty tarkistus ikkunassa (käyttäjä): nousu, kohtaaminen, taistelu,
   lasku, debrief.

Hyväksyminen: 5/5 ajoa päättyy skriptin omaan onnistumiseen ja laskuun; käyttäjä on
lentänyt tehtävän kerran itse.

### Vaihe 3: Muiden tehtävien alustavat määritykset

**Pohjatyö 17.11.2026:** tehtäväskriptien tulkki on purettu alkuperäisestä STRIKE.EXE:stä ja
toteutettu uudelleen (`docs/PROG_VM.md`). Kohdan 5 opkoodiselvitys on siten pääosin tehty;
auki ovat toimintojen `a9`, `b1`–`b5`, `bf` merkitykset, `09`-lisäargumentit ja
GAMEFLOW-tulkki (OPTTEST.EXE).

1. Aja `game/tools/mission_chain.gd` kaikille `MISSIONS/*.IFF`-tiedostoille. Raaka
   tuloste jää `tmp/`:iin (alkuperäistä tekstiä, ei jaeta).
2. Kirjoita jokaisesta tiivistelmä omin sanoin kansioon `docs/tehtavat/` samalla
   rakenteella kuin `MISN-1A_TAPAHTUMAKETJU.md`: tavoite, tapahtumaketju, reitti ja
   alueet, osat ja roolit, onnistumis- ja epäonnistumisehdot, kampanjavaikutus,
   toteutuksen tila, avoimet opkoodit, testattavat riskit.
3. Kokoomataulukko `docs/tehtavat/README.md`: kampanjatehtävät erikseen harjoittelu- ja
   areenaskenaarioista; sarakkeina mm. latautuu / lennetty autopilotilla / tuntemattomia
   opkoodeja.
4. Aja `all_missions_test.gd` ja kirjaa tulos.
5. Opkoodit: `prog_analyze.gd`:llä esiintymät kaikista tehtävistä, tärkeysjärjestys sen
   mukaan, kuinka monta tehtävää kukin estää. Korjaa `97`:n dokumentaatio vastaamaan
   koodia.

Hyväksyminen: jokaisella tehtävällä on määritys ja rivi kokoomataulukossa.

### Vaihe 4: Tehtävät lentokuntoon ja kampanja läpi

1. Tehtävä kerrallaan kampanjajärjestyksessä (1B, 1C, 2A, ...): headless-autopilottiajo,
   korjaukset, määrityksen tilan päivitys. Sama hyväksymisehto kuin M1:llä, mutta 3 ajoa.
2. Headless-kampanja-ajuri: valitsee tukikohtaruudussa automaattisesti briefingin ja
   lennon, jotta koko kampanjan voi ajaa läpi ilman käyttäjää.
3. Loadout-ruudun testi ja kytkentä (valittu kuorma päätyy koneeseen, rahat vähenevät).
4. Välianimaatiot: effect-12-valitsimen selvitys, MID1:n jäljitys isommalla budjetilla.

### Lentokonemallien ulkoasu (käyttäjän päätös 16.11.2026)

Nykyaikaiset `.glb`-mallit on arkistoitu (`arkisto/nykyaikaiset_mallit/`). Peli käyttää
alkuperäisiä RealSpace-malleja, ja niiden skinejä parannetaan ajonaikaisesti; mitään
alkuperäisdatasta johdettua ei tallenneta levylle.

Tehty 16.11.: kun "Smooth textures" on päällä, vähävärisille tekstuureille (≤ 16
palettiväriä: naamioinnit, merkinnät) tehdään 2× Scale2x-skaalaus palettiväri-indekseille,
ja `model.gdshader` lisää satiinimaalin, kirkaslakan sekä hennon kulumis- ja
paneelivaihtelun mallin koordinaateissa. Pois päältä näytetään alkuperäiset pikselit
entisellä valaistuksella.

Tehty 16.11. (2. kierros), samoin vain parannetussa tilassa:
- Osakohtaiset materiaalit tekstuurin nimestä (`RealSpaceModel.surface_kind`): kuomu
  (`CPU/CPS/CKP/CANP/PIL`, tummat tekselit kiiltäväksi lasiksi), pakoputki (`EXH`,
  metalli), potkuri (`PROP`, läpikuultava kiekko).
- Pehmeät normaalit alle 50°:n tahkokulmissa (pyöreät rungot), terävät reunat muualla.
- Paneelit: 1,6 m:n solukohtainen sävy- ja karheusvaihtelu, saumat himmeämmät.
- Mallikatselimen kuvakaappausvalitsimet `--view_zoom`, `--view_still`, `--view_orbit=yaw,pitch`.

Tehty 16.11. (3. kierros):
- Kuomu: koko kuomutekstuuri lasina (tummennettu, sinertävä, kiiltävä). Lasitekselit ovat
  alkuperäisessä keskiharmaita, joten tummuusraja ei löytänyt niitä.
- Maali mattaisemmaksi (karheus 0,45–0,7, kirkaslakka 0,1): pehmeät normaalit kokosivat
  auringon valkoiseksi läiskäksi MiG-29:n kylkeen.
- Potkurit: oma varjostin `prop_disc.gdshader`, pyöreä läpikuultava kiekko ja kärkirengas.
- Skaalaus 4× → 2×: ulkonäkö lähes sama, lennon lataus noin 3,7 s → 2,7 s
  (ennen skinejä noin 2 s). `smoke_test` (kaikki 213 mallia) noin 6 s.

Ideoita jatkoon: paneelijaon sovitus geometriaan; normaalikartta tekstuurin
kirkkaudesta; skaalaus näytönohjaimella, jos latausaika haittaa.

### Vaihe 5: Puuttuvat alkuperäisominaisuudet (backlog, ei järjestyksessä)

Ohjaamot (`*-CKPT.IFF`, `COCKPITS/*.PAK`) ja mittarit, siipimieskäskyt ja pelaajan
radiovalikko, lentomallin parametrit `DYNM`-lohkosta, aseet `WEAP`/`HPTS`-datasta,
ohjusten osumatodennäköisyyden pelitestaus (MISN-10A), tappotaulu, asekatalogi,
kirjanpito, nimet tekstityksiin, musiikin läpikäynti.

### Vaihe 6: Julkaisu

1. Lisenssit: päätä F16DES.glb:n kohtalo (CC BY-NC-SA: joko pois jaettavasta paketista
   tai dokumentit ja krediitit sen mukaisiksi).
2. `tools/make_demo.py` ajan tasalle, uusi demopaketti, `demo_test` vihreäksi.
3. README vastaamaan toteutunutta tilaa.

## 6. Työskentelysäännöt

- Ei koodimuutosta ilman commitia sitä ennen ja testiajoa sen jälkeen.
- Laskeutumis- ja autopilottikoodiin vain pieniä, yksi kerrallaan todennettuja muutoksia.
- "Valmis" tarkoittaa: komento, päivämäärä ja tulos kirjattuna. Yksi onnistunut ajo ei
  riitä; täydet lennot eivät toistaiseksi ole toistettavia.
- Vain yksi istunto muokkaa `game/`-kansiota kerrallaan.
- Älä käytä `Stop-Process -Name Godot*`. Aja testit omalla nimellä kopioidulla
  moottorilla ja lopeta vain oma PID. (Koneella on tätä kirjoitettaessa käynnissä toinen
  Godot-prosessi 15.11. klo 18:27 alkaen; siihen ei ole koskettu.)
- Älä käytä Godotin `--quit`-lippua pääscenen ajoissa. `--shot` ei toimi `--headless`-tilassa.
- Suodata lokeista glTF/mesh-ERROR-rivit; ne ovat mallien latausvaroituksia.
- Alkuperäistä tekstiä tai dataa ei commitoida eikä paketoida.

## 7. Komennot

```powershell
$eng = "$env:TEMP\scr_engine_sc.exe"
Copy-Item "C:\AI_Projektit\strike commander\tools\godot\Godot_v4.7.2-stable_win64.exe" $eng

# Yksikkötesti (vaihda testin nimi)
& $eng --headless --path "C:/AI_Projektit/strike commander/game" --script res://tests/smoke_test.gd

# Pelkkä loppulähestyminen (noin 10 s)
& $eng --headless --path "C:/AI_Projektit/strike commander/game" --auto=flight --mission=MISSIONS/MISN-1A.IFF --approach --fast --status=5 --ap_debug --timeout=150 --dir="C:/AI_Projektit/SC-REFORGED"

# Täysi MISN-1A (noin 2-3 min; exit 0 = onnistui, 3 = epäonnistui, 4 = aikakatkaisu)
& $eng --headless --path "C:/AI_Projektit/strike commander/game" --auto=flight --mission=MISSIONS/MISN-1A.IFF --autopilot --fast --status=30 --ap_debug --timeout=540 --dir="C:/AI_Projektit/SC-REFORGED"
```
