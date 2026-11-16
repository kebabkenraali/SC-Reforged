# arkisto/

Käytöstä poistettua materiaalia, joka säilytetään mahdollista myöhempää käyttöä varten.
Kansio on Godot-projektin (`game/`) ulkopuolella, joten peli ei lataa eikä importoi sitä.

## nykyaikaiset_mallit/ (arkistoitu 16.11.2026)

Ulkopuoliset `.glb`-lentokonemallit, jotka aiemmin olivat kansiossa `game/models/` ja
korvasivat alkuperäiset RealSpace-mallit. Käyttäjän päätös 16.11.2026: peli käyttää
alkuperäisiä malleja, ja niiden ulkoasua (tekstuureja) parannetaan sen sijaan.
Lisenssit ja lähteet: `nykyaikaiset_mallit/README.md` (huom. `F16DES.glb` on
CC BY-NC-SA 4.0, muut CC0).

Palautus: siirrä tiedostot takaisin kansioon `game/models/`. Lataajakoodi
`game/scripts/game/external_models.gd` on yhä paikallaan ja käyttää malleja
automaattisesti, jos kansio on olemassa.
