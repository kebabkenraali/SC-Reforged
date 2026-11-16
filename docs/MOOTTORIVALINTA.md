# Moottorivalinta: mihin Strike Commander kannattaa kääntää?

## Lähtökohta

Strike Commander (Origin Systems, 1993) on rakennettu Originin omalla **RealSpace**-moottorilla.
Tavoitteena on versio, joka

1. **vaatii alkuperäisen pelin** – mitään Originin/EA:n sisältöä ei jaeta, vaan grafiikka,
   mallit, maastot, äänet ja tehtävät luetaan käyttäjän omasta asennuksesta (GOG: `SC.dat`
   + `LILTRE.TRE`);
2. on **modernisoitu**: korkea resoluutio ja laajakuva, moderni valaistus, peliohjaimet,
   näppäinten uudelleenmääritys, asetukset, 64-bittinen nykyalusta.

Tämä on sama malli kuin tunnetuissa "source port" -projekteissa: OpenMW (Morrowind), OpenXcom,
OpenRA, ScummVM, Arx Libertatis. Malli on oikeudellisesti kestävin, koska jaettava koodi on
omaa ja sisältö tulee käyttäjän ostamasta pelistä.

## Mitä alkuperäinen data vaatii moottorilta

Tutkin GOG-asennuksen (ks. [TIEDOSTOFORMAATIT.md](TIEDOSTOFORMAATIT.md)):

| Data | Muoto | Moottorilta vaaditaan |
|---|---|---|
| CD-kuva `SC.dat` | raaka ISO 9660, 2352 t/sektori | oma tiedostojärjestelmäkerros |
| Arkistot `BIGTRE.TRE`, `LILTRE.TRE` | Originin TRE | ajonaikainen lataus (ei esikäsittelyä) |
| 3D-objektit `OBJECTS/*.IFF` | IFF "FORM REAL", LOD-tasot, LZW-tekstuurit | proseduraalinen mesh-generointi ajossa |
| Maastot `CANYON.PAK` ym. | 360×360 korkeuskartta, 7 maastotyyppiä, 64×64 laatat | iso maailma (110 km), oma shader |
| Paletit `PALETTE/*.IFF` | 256 väriä VGA | indeksoitu → RGBA muunnos |
| Musiikki/äänet | XMIDI, VOC | (myöhemmin) MIDI-syntetisaattori |

Tärkein havainto: **kaikki pitää pystyä rakentamaan ajonaikaisesti koodista**, koska
sisältöä ei saa paketoida moottorin mukaan. Moottorin työkaluketjun (asset import, editori)
hyöty jää siksi pienemmäksi kuin tavallisessa pelissä – mutta renderöinnin, syötteen,
käyttöliittymän ja alustatuen hyöty on suuri.

## Vaihtoehdot

| | **Godot 4** | Unity 6 | Unreal Engine 5 | Oma C++ (SDL3 + OpenGL/Vulkan) |
|---|---|---|---|---|
| Lisenssi | MIT, ei rojalteja | suljettu, lisenssiehdot muuttuneet | suljettu, 5 % rojalti | vapaa valinta |
| Avoin lähdekoodi koko ketjussa | ✅ | ❌ | osittain | ✅ |
| Ajonaikainen mesh/tekstuuri | ✅ ArrayMesh, Texture2DArray | ✅ | ✅ (raskas) | itse tehtävä |
| Moderni renderöinti (PBR, varjot, SSAO, FSR 2) | ✅ Vulkan/D3D12 | ✅ | ✅✅ | itse tehtävä |
| Syöte: näppäimistö, hiiri, ohjaimet, uudelleenmääritys | ✅ InputMap | ✅ | ✅ | SDL3 antaa pohjan |
| Käyttöliittymä, asetukset | ✅ | ✅ | ✅ | itse tehtävä |
| Jakelukoko | ~ 80 Mt | ~ 100 Mt+ | 500 Mt+ | pieni |
| Yhteisöprojektiin sopivuus | ✅ erinomainen | heikko (suljettu) | heikko | hyvä, mutta työläs |
| Tarkkuus alkuperäiseen (bittitarkka) | hyvä | hyvä | hyvä | paras |

Lisäksi tutkittiin olemassa oleva **libRealSpace** (Fabien Sanglardin käänteismallinnusprojekti,
C++). Se dokumentoi samoja formaatteja, mutta kohdistuu levykeversioon eikä ole valmis peli.
Tämän projektin formaattitulkinnat (mm. CD-version LZW-pakkaus ja maastotyypit) on tehty itse
GOG-version datasta.

## Suositus: Godot 4

**Godot 4 (MIT)** on paras kohde tälle projektille:

- Avoin lisenssi sopii täydellisesti "vaatii alkuperäisen pelin" -malliin: koko moottorin voi
  jakaa vapaasti, eikä EA:n sisältöä tarvita.
- Ajonaikainen geometria (`ArrayMesh`), tekstuuritaulukot (`Texture2DArray`) ja omat shaderit
  riittävät RealSpace-datan näyttämiseen modernisti.
- Saa "ilmaiseksi" asiat, jotka oman moottorin kanssa veisivät kuukausia: PBR-valaistus,
  varjot, ilmakehän sumu, bloom, FSR 2 -skaalaus, MSAA, peliohjaimet, näppäinasetukset,
  käyttöliittymä, äänimoottori, OpenXR (VR-lento on luonteva jatko).
- GDScriptillä formaattien lukijat ovat lyhyitä ja helppolukuisia; jos jokin osa (esim. LZW)
  osoittautuu hitaaksi, sen voi siirtää GDExtension-C++:aan muuttamatta muuta koodia.

Milloin valitsisin toisin: jos tavoite on **bittitarkka** alkuperäisen 320×200-pelin
uudelleentoteutus (kuten ScummVM), oma C++/SDL3-moottori libRealSpacen pohjalta olisi
perustellumpi. Unity ja Unreal eivät tuo tähän projektiin mitään, mitä Godot ei tarjoaisi,
mutta tuovat lisenssi- ja jakeluongelmia.

## Riskit ja huomiot

- **Suuri maailma**: kartat ovat ~110 km × 110 km. Godotin 32-bittinen tarkkuus riittää, kun
  kartta keskitetään origoon (±55 km). Isompiin maailmoihin Godot tukee "large world
  coordinates" -käännöstä tai liikkuvaa origoa.
- **Tehtäväskriptit ja tarinaosuudet** (GAMEFLOW, MIDGAMES, konversaatiot) ovat formaateiltaan
  vielä tutkimatta – ne ovat seuraava iso työvaihe.
- **Musiikki** on XMIDI-muodossa; vaatii MIDI-syntetisaattorin (esim. FluidSynth + SoundFont)
  GDExtensionina.
