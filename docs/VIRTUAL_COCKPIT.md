# Virtuaalinen ohjaamo alkuperäisestä pelidataista

Ohjaamo rakennetaan **vain pelaajan omasta asennuksesta luetusta datasta**.
Mitään alkuperäistä tiedostoa ei kopioida repositorioon.

## Lähdedata

`OBJECTS/F16-CKPT.IFF`, `OBJECTS/F22-CKPT.IFF` (SC.dat) ja
`OBJECTS/F22BCKPT.IFF` (TOBIGTRE.TRE, Tactical Operations) ovat `FORM:CKPT`
-tiedostoja — eivät RealSpace-malleja. Niiden `FORM:REAL / OBJS` -kenttä nimeää
3D-mallin:

| Ohjaamotiedosto | OBJS | Malli |
|---|---|---|
| `F16-CKPT.IFF` | `F16PITXP` | `OBJECTS/F16PITXP.IFF` (26 pintaa) |
| `F22-CKPT.IFF` | `F22PIT` | `OBJECTS/F22PIT.IFF` (26 pintaa) |
| `F22BCKPT.IFF` | `F22PIT` | `OBJECTS/F22PIT.IFF` |

`flight_scene.gd:_setup_cockpit_model()` lukee OBJS-kentän, lataa mallin
`SCData.model():llä`, liittää sen pelaajaan ja antaa sen
`camera_rig.cockpit_model`-kenttään. Kameran ohjaamonäkymä näyttää ohjaamon ja
piilottaa ulkoisen ilmakunta-mallin; muissa näkymissä ohjaamo on piilotettu.

Korjaukset matkan varrella:

- aiemmin ohjaamoa yritettiin ladata `OBJECTS/F-16-CKPT.IFF`-nimellä (väärä nimi)
  ja malliksi luultiin itse CKPT-tiedostoa → ohjaamoa ei koskaan syntynyt,
- `rig.cockpit_model` ei ollut koskaan asetettu → kamera ei näyttänyt sitä,
- `_setup_cockpit_model()` kutsuttiin jokaisen koneen spawnissa, ei vain pelaajalle,
- vapaa lento ei asettanut `_pal`/`_smooth`-arvoja → `build_mesh` kaatui
  puuttuvaan paletti-indeksiin.

## Silmäpisteen kalibrointi alkuperäisen datan mukaan

Vertasin `libRealSpace`-toteutuksen (remileonard/libRealSpace, `SCStrike.h`,
`SCJetVirtualCockpit.cpp`) arvoihin:

- `eye_y = 3` yksikköä lentokoneen origon yläpuolella,
- HUD-quad `x = 5.8..6.0` yksikköä edessä, `y = 2.0 .. -0.8`,
- MFD:t `x = 6.1..6.2` edessä, `y = -2.5 .. -4.4`,
- ohjaamomalli piirretään `ajustement = (0, -eye_y, 0)`.

Meidän RealSpace-mallin AABB-muunnos eroaa, joten kalibroin AABB-frakcioilla:
kameran oletuspaikka on nyt `(x = 0.5, y = 0.46, z = 0.50)` pit-meshin
AABB:sta — oletuksena näkyvät vain mittarit ja ulos lentokoneesta.
Ääripäät testattiin: `(0.55, 0.70)` meni mallin sisään (musta ruutu),
`(0.58, 0.50)` oli liian korkea (ohjaamo katosi) ja `(0.40, 0.22)` ohitti
mallin kokonaan (pelkkä maa).

Hiiren kääntönopeus on nyt `0.20° / px × mouse_sensitivity` (aiemmin 0.03),
eli noin 6.7× nopeampi.

## VR-tuki (OpenXR) — koko peli headsetissa

**Käynnistys:**
- `Kaynnista_Flat.bat` — tavallinen desktop-versio, kaikki 2D-näytöllä.
- `Kaynnista_VR.bat` — lisää `--vr`; koko peli näkyy headsetissa.

**Näkymät VR-moodissa:**
- **Lento** (vapaa lento + kaikki tehtävät): oikea stereoskooppinen 3D,
  päänseuranta ja ohjaamokamera.
- **Muut näkymät** (päävalikko, varusteet, keskustelut, leikkaukset, debrief,
  mallikatselin, lataus): litteä 2D-kuva headsetissa.

**Toteutus:**
- `project.godot`: `xr/openxr/enabled=true`, `xr/shaders/enabled=true`,
  `xr/openxr/default_action_map="res://openxr_action_map.tres"`.
- `main.gd:_init_vr()` alustaa OpenXR:in `--vr`-lipulla ja asettaa
  `viewport.use_xr = true` koko sessioksi. Ilman tätä OpenXR herjaa:
  `No viewport was marked with use_xr, there is no rendered output!`
  V-sync pois (OpenXR synkkaa itse 90 Hz+).
- **Flat 2D -paneli:** `SubViewport` (`VRFlatUI`) sisältää kaikki 2D-näkymät.
  `OpenXRCompositionLayerQuad` (`VRFlatPanel`) näyttää sen tekstuurin litteällä
  tasolla n. 1.6 m päässä silmäkorkeudella. Godotin dokumentaation mukaan
  pelkkä 2D-canvas ei toimi XR:ssä — composition layer piirtää kuvan linssin
  vääristymänkorjauksen **jälkeen**, joten teksti pysyy terävänä.
- `vr_menu_origin` + `vr_menu_camera` (`XROrigin3D` / `XRCamera3D`) ovat
  2D-näkymien XR-rig. Lentokoneen `camera_rig` ottaa XR-kamerat käyttöön lennon
  ajaksi ja ne palautetaan lennon jälkeen. `VRFlatPanel` piilotetaan lennon ajaksi.
- **Ohjaus:** oikea käsi (`/user/hand/right`, `trigger_click`) toimii osoittimena:
  `intersects_ray()` muuntaa säteen UV-koordinaatiksi ja `push_input()` syöttää
  hiiren liikkeen/napsauksen `VRFlatUI`:hen. `vr_cursor.gd` piirtää ristikon.
  Myös tavallinen hiiri/näppäimistö välitetään `VRFlatUI`:hen (`_input`).
- `camera_rig.gd`: VR:ssa rakennetaan `XROrigin3D` + `XRCamera3D`.
  `_set_cam()` synkronoi origon lentokoneen kameratransformiin, jolloin
  headsetin seuranta lisätään päälle. Hiirikääntö on pois päältä VR:ssa.
- Jos runtime alustuu mutta ei tuota frameja (headset nukkuu/pois),
  `_disable_vr()` palauttaa koko pelin desktop-tilaan ja siirtää 2D-näkymät
  takaisin pääviewporttiin.

**Testit:** `vr_test.gd` tarkistaa XR-solmut ja desktop-palautuksen; 0 vikaa.
Todellinen stereokuva vaatii OpenXR-runtime:n ja yhdistetyn headsetin. Tällä
koneella VirtualDesktopXR on rekisteröity mutta headset ei ole streamaamassa.

## Elävät mittarit ohjaamossa

`cockpit_instruments.gd` rakentaa mittarit **oikeina 3D-elementteinä** ohjaamon
sisään. Sijainti perustuu libRealSpace `SCJetVirtualCockpit::f16Layout()` -
tauluihin (`FORM:CKPT`): silmä originissa, mittarit ~6 yksikköä edessä, MFD:t
±2.1 sivulla, RAWS / ALTI / SPEED / COMM alla. Skaalattu F16PITXP-malliin.

- **RAWS**: taiteilijahorizontti (sininen/ ruskea), pitch-ladder ja pankki,
  jotka seuraavat lentokoneen asentoa.
- **ALTI / SPEED**: nykyinen korkeus (ft) ja nopeus (kt) `Label3D`-teksteinä.
- **MFD_L** (vasen vihreä ruutu): aseet ja jäljellä olevat määrät — ohjukset, pommit ja tykkiammus yhdessä ikkunassa. Vaihdettu 24.11. käyttäjän toiveesta; aiemmin tässä oli tutka.
- **MFD_R** (oikea ruutu): ilmatutka 20 km, blips vihollisille (punainen) ja liittolaisille (sininen).
- **COMM**: radio-otsikko.

Jokaisella mittarilla on kohotettu kehys (syvyys), ja ne on kiinnitetty
lentokoneeseen — eivät päähän — joten ne pysyvät paikoillaan kun katsetta
käännetään ja toimivat stereona VR:ssa. `depth_test_disabled` + läpinäkyvä
materiaali piirtää ne ohjaamon panelin päälle.

## VR-testaus ilman lasteja (OpenXR Simulator)

Projektiin on asennettu `tools/xr-simulator` (OpenXR Simulator v1.7.1). Se
toimii OpenXR-runtimena ja näyttää stereo-esikatselun työpöydällä.

**Käynnistys:**
- `Kaynnista_VR_Simulaattori.bat` — koko peli headsetissa (ilman lasteja)
- `Kaynnista_VR_Testi.bat` — lentotesti ilman vihollisia (`--no_enemies`),
  kuolemattomalla koneella (`--god`) ja loputtomalla ammuksella

Simulaattori otetaan käyttöön **vain kyseiselle prosessille**
`XR_RUNTIME_JSON`-ympäristömuuttujalla — koneen globaalia OpenXR-runtimea ei
muuteta. Käynnistyslippu `--no_enemies` estää vihollisten ja ilmapuolustuksen
spawnin myös tehtävissä.

**Todennus:** `tmp/vr_cockpit_stereo.png` (ohjaamo) ja
`tmp/vr_clean_stereo.png` (ilman ohjaamoa) — molemmissa silmissä näkyvät
alkuperäinen ohjaamo/maailma, 3D-mittarit ja HUD-tekstit. Simulaattorin
`runtime_status.json` raportoi `session_state=FOCUSED`, 90 Hz ja yli 700 framea.

## HUD libRealSpacein tavalla (framebuffer → HUD-taso)

libRealSpace (`SCCockpit::RenderHUD`, `SCJetVirtualCockpit`) piirtää HUD:n
erilliseen framebufferiin ja sijoittaa sen tekstuurin ohjaamon HUD-tasoon
`f16Layout()`-quadilla: etäisyys 5.9 yksikköä edessä, x −1.22…+1.35,
y +2.0…−0.8. Meidän `cockpit_instruments.gd:attach_hud()` tekee saman:
`SubViewport` (1600×900) → `ViewportTexture` → `QuadMesh` lentokoneen
koordinaatistossa. HUD-tekstit eivät enää liu'u pään mukana, koska ne ovat
osana lentokonetta. `hud_attachment_test` varmistaa tämän.

HUD-taso on sijoitettu tuulilasin yläosaan (18 × 10,1 yksikköä, libRealSpace-
quadin keskeltä ylöspäin siirrettynä), jotta se vastaa alkuperäisen pelin
oletusnäkymää: koko mittaristo näkyy lasilla eikä paneelin takana. Ohjaamon
oletuskulma on lähes vaakatasossa (`PIT_COCKPIT_PITCH_DEG = -1°`), jolloin
kuvan alaosaan jää ohjaimisto ja yläosaan taivas + HUD — sama kuin
alkuperäisessä ja VR-versiossa.

Ero alkuperäiseen: libRealSpace käyttää 8-bittisiä framebuffereita ja
RLE-shapeja; me käytämme Godotin vektoripiirtoa `SubViewport`:ssa. Sijainti,
suunta ja kiinnitys ovat samat, grafiikan esitystapa eri.

## Vertailu libRealSpaceen

`tools/librealspace/` on paikallinen checkout (`remileonard/libRealSpace`,
commit `529fdc3`), käännetty VS BuildTools 2022 + vcpkg -yhdistelmällä
(`cmake --preset windows`). Se on gitignoroitu — alkuperäistä `SC.DAT`:ää ei
säilytetä projektissa; vertailuajossa se kopioitiin väiaikaisesti build-kansioon
ja poistettiin sen jälkeen.

Käyttö:
```
cmake --preset windows
cmake --build out/build/windows --config Release --parallel 4
# kopioi oma SC.DAT tiedostoon out/build/windows/src/executables/sc/Release/
# ja käynnistä neosc.exe samasta kansiosta
```

`librealspace_parity_test.gd` varmistaa:
- ohjaamomittareiden quad-keskukset vastaavat `SCJetVirtualCockpit::f16Layout()`-arvoja
- tehtävien PROG-opkoodit ovat `SCenums.h::prog_op`-listalta
- `mission_vm.gd` käsittelee `OP_SET_EXIT_CODE` (0x0f) — onnistumisen/epäonnistumisen luku

Testi: 0 vikaa. Kaikilla mitatuilla tehtävillä (MISN-1A, 1B, 3A, 10A, 15A)
käytetyt opkoodit löytyvät libRealSpacesta; tuntemattomia ei jäänyt.

## Välien videot ja musiikki

- `cutscene_vm.gd` ja `cutscene_player.gd`: videon kuvasuhde korjattu
  **320×200** (alkuperäinen resoluutio) — aiempi 4:3 venytti kuvan ja siirsi
  sen keskipisteen; nyt kuva on keskellä.
- Kaikki cutscene-polut käynnistävät musiikin: tallennetuissa `midN`-aikajonoissa
  on `music`-op, mutta `estN`/`transN`-jonoissa ei — niille ja fallback
  `CutscenePlayer`:lle käynnistetään `MIDGAMES/AMUSIC.PAK` (entry 2).
- `cutscene_audio_test.gd` tarkistaa musiikin jokaisessa polussa.

## Neljä kameranäkymää (C)

`CameraRig.Mode`: `Chase (0) → Cockpit (1) → No cockpit (2) → Free orbit (3)`.
"No cockpit" käyttää täsmälleen samaa istuinpaikkaa ja suuntaa kuin ohjaamo,
mutta ohjaamomalli ja lentäjän jalat piilotetaan — HUD ja ulkomaailma näkyvät
ilman ohjaamoa. Komentorivillä `--cam=0..3`.

## HUD:n sijoittelu alkuperäisen mukaan

Perustuu `docs/SC_MANUAL.txt` sivuihin 58–64 (F-16 HUD):

| Elementti | Paikka |
|---|---|
| Pitch ladder + velocity vector | keskellä (vain istuin näkymissä 1 ja 2) |
| Ilmanopeusnauha | vasen reuna, pysty, 10 kt välein, "T" ja Mach alla |
| Korkeusnauha | oikea reuna, pysty, 100 ft välein, viiva = MSL, `>` = AGL |
| Suuntanauha | **alas**, vaaka, kiinteä nuoli + reittipisteen `:V:` |
| G-voima (nykyinen / maksimi) | vasen yläkulma |
| GEAR / FLAPS / BRAKE | oikea yläkulma |
| Aseet + jäljellä olevat + IN RNG | vasen alakulma |
| Matka reittipisteeseen `D`, etäisyys `R`, lähentyminen `C` | oikealla, korkeusnauhan alla |
| FUEL / STALL / PULL UP / MISSILE WARNING | keskellä |

VR:ssa HUD siirretään `SubViewport`iin ja näytetään samassa
`OpenXRCompositionLayerQuad`-tasossa kuin muu 2D — muuten XR ei piirrä 2D-
kanvasta ollenkaan. Tason koko kasvaa lennon ajaksi, jotta HUD peittää näkymän.

## Pilvet pysyvät maailmassa

`shaders/clouds.gdshader` käytti aiemmin fragmentissa `VERTEX.xz`:ää, joka
Godotissa on **kamerakoordinaatti** — siksi pilvet liukuivat pään (ja
hiirikääntöjen) mukana. Nyt vertex-vaihe laskee maailmaposition
(`model_matrix * vec4(VERTEX, 1.0)`) ja välittää sen `v_world_pos`-varyingina
fragmentille. Sekä kohinakuvio että etäisyyshairaus (`fade_start/end`) käyttävät
maailmapositiota, joten pilvet pysyvät paikoillaan kun päätä kääntää.
`shader_test.gd` estää regressiin.

## Hiiripohjainen avotila ja lentäjän jalat

- **Mouse look:** vasen dragaa siirtymän — kaappaa pystysuuntaisia ja
  vaakasuuntaisia kulmia ±30°, ympäripyörytöiksi. **Vasen painallus**
  (ei liikettä) palauttaa oletuspaikkan. Kameran oletuspaikka on hieman
  alaspäin ja lähemmäs istuinta (`PIT_COCKPIT_OFFSET`,
  `PIT_COCKPIT_PITCH_DEG`), jotta lentäjän jalat tavataan paremmin.
- **Lentäjän jalat:** pelaajalla on `rig.pilot_node` — `Node3D` kaksi
  `MeshInstance3D:a` (kaksi capsule-malliista, 0.75 m pituista, 0.2 m pohjaa,
  asetettu istuinteimen alle). Jalat näkyvät pitin taustassa ohjaamonäkymässä,
  ja kaikilla muillakin lennettävillä koneilla jalat ovat näkyvissä.
  Kuva: `tmp/cockpit_f16_ml.png`.

## Koneet, joilla on alkuperäinen ohjaamo

Neljä lennettävää konetta: `F-16DES`, `F-16GRAY`, `F-22`, `F-22B`.
Muilla 20 koneella alkuperäisessä pelissa ei ole 3D-ohjaamoa; niillä
ohjaamonäkymä toimii HUD-pohjaisesti.

## Kohde-/pommiseuranta ja tapahtumaikkuna (24.11.2026)

`cockpit_windows.gd` lisää ohjaamoon kaksi `SubViewport`-pohjaista ikkunaa:

- **Kohdeseuranta (killcam)** ylävasemmalle taivaalle. `SubViewport` jakaa lennon `World3D`:n, joten siinä oleva `Camera3D` on oikea 3D-kamera: se seuraa laukaistua ohjusta tai pommia ja katsoo kohdetta. Ohjuksella kohde on vihollinen; pommilla kohde on `bomb.predict_impact()`-ennustettu osumapiste (`Marker3D`).
- **Tapahtumaikkuna** sen alla: lyhyt teksti tärkeistä tapahtumista (esim. MISN-1A:ssa saatettavan C-130:n laskeutuminen / "Mission accomplished", sekä vastaavat radiotapahtumat). Näkyy molemmissa moodissa.
- Seurantaikkuna näkyy vain **Arcade**-moodissa; Realistisessa se on piilotettu. Ikkunat ovat osa lentokonetta, joten ne pysyvät paikoillaan päätä käännettäessä ja toimivat stereona VR:ssa.

## Kaksi pelimoodia (24.11.2026)

`Settings.is_arcade()` / `--mode=arcade|realistic` (session-only override) ja asetusten "Gameplay"-välilehti:

| | Realistinen (oletus) | Arcade |
|---|---|---|
| Ohjuslukitus | 7/16 km, kartio 0.52 rad | 1,5× kantama, kartio 0.75 rad |
| Ohjuksen ohjaus | `spec.turn` | 1,6× ohjausvalta |
| Ammukset | `Weapons.loadout()` | +2 jokaista asetta |
| Kohdeseurantaikkuna | pois | päällä |

Tapahtumaikkuna on molemmissa. Asetus tallentuu `user://settings.cfg`:n `game/mode`-arvona (0 = realistic, 1 = arcade).

## Testit ja todisteet

```
cockpit_test.gd           24/24 lennettävää konetta, 0 skriptivirhettä
cockpit_windows_test.gd   MFD-vaihto + ikkunat + moodit, 0 vikaa
cockpit_mission_sweep.gd  77/77 tehtävää ohjaamonäkymässä, 0 vikaa
Aja_Testit.ps1 -Taydet 1  31 yksikkötestiä OK, täysi MISN-1A success (24.11.)
```

Näkyvät kuvat: `tmp/cockpit_f16.png`, `tmp/cockpit_f22.png`,
`tmp/cockpit_f16_ml.png`.
