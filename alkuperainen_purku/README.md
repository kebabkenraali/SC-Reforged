# alkuperainen_purku/ – PAIKALLINEN, EI JAETA

Tähän kansioon tallennetaan alkuperäisestä Strike Commanderista johdettu tutkimusaineisto:
ohjelmatiedostojen purkulistaukset ja datavedokset. Aineisto auttaa pitämään remaken
yhteensopivana alkuperäisen kanssa kehityksen aikana.

**Sääntö: mitään tämän kansion sisällöstä ei commitoida, julkaista, paketoida eikä lähetetä
minnekään.** Kansio on `.gitignore`ssa (vain tämä README on versionhallinnassa), eikä
`tools/make_demo.py` kopioi sitä. GitHubiin joskus jaettava versio ei sisällä alkuperäistä
koodia eikä dataa; peli lukee kaiken pelaajan omasta asennuksesta.

Projektin dokumentteihin (`docs/PROG_VM.md`, `docs/GAMEFLOW_VM.md`) kirjataan vain omin
sanoin kirjoitetut havainnot, eivät listaukset.

## Sisällön luonti uudelleen

Sisältö syntyy omasta asennuksesta (GOG / CD), joten sen voi aina luoda uudelleen:

```powershell
python tools\decompile\pura_tulkit.py "C:\Gog games\Strike Commander"
```

(vaatii `pip install capstone`). Skripti on omaa koodia eikä sisällä alkuperäistä aineistoa.

## Sisältö

| Polku | Mitä |
|---|---|
| `STRIKE.EXE/prog_vm.asm` | tehtäväskriptien tulkki, käsittelijät nimetty opkoodeittain |
| `STRIKE.EXE/actions.asm` | toimintojen (`a1`–`bf`) suoritusfunktio |
| `OPTTEST.EXE/gameflow_vm.asm` | kampanjan efektitulkki, käsittelijät nimetty efekteittäin |
| `OPTTEST.EXE/overlay_segments.txt` | overlay-segmenttien sijainnit ja funktiomerkinnät |
| `OPTTEST.EXE/ovl_4b1e_*.asm` | keskustelut, tulosten (`misn2op`) luku, lennon aloitus, uusi kampanja |
| `OPTTEST.EXE/ovl_4b32_*.asm` | kirjanpitotapahtumat (`22 n`), peli ohi (`1d`), tappotaulu |
| `OPTTEST.EXE/ovl_4b36_*.asm` | aseidenlatausruutu (`16`), asekatalogi (`17`), kirjanpito (`19`) |
| `tutkimus/` | istuntojen aikana tehdyt väliaikaiset listaukset ja vedokset |

Vanhemmat lineaariset vedokset ovat yhä kansiossa `docs/DEKOMPILU/` (sekin paikallinen).
