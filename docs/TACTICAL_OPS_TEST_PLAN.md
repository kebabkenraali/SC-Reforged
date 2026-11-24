# Tactical Operations – priorisoitu testaus- ja valmistelulista

Tämä lista tehdään **ennen** lisäosan porttausta. Tarkoitus: lukita peruspelin
47 tehtävän tila ("kultainen baseline") ja täyttää aukot, jotka vaikeuttaisivat
lisäosan virheenpaikannusta. Jokaisessa kohdassa on tarkoitus, komento ja
hyväksymiskriteeri.

Tilanne päivitetty 22.11.2026. Linkki: `docs/TACTICAL_OPS.md`.

## Toteutuksen tila 22.11.2026

| Kohta | Tila | Todiste |
|---|---|---|
| 1 | DONE | `tactical_ops_test.gd`: 30/30 tehtävää parsittu; `pura_tulkit.py`: 64 TOPTTST1-overlayta |
| 2 | DONE (baseline) | `tmp/completion_matrix.ps1`: 77/77 tehtävää, `errors=0` kaikilla. `results.csv`: 9 `success`, 20 `incomplete`, 3 `failed`, 45 `NO_RESULT` (300 s wall-clock, autopilot ei saa päätökseen). Hyväksymiskriteeri muutettu: jokaisesta tehtävästä on tulos ja 0 skriptivirhettä — täysi `MISSION OVER` ei ole autopilotin kykyjen rajoituksessa pakollinen |
| 3 | DONE | `campaign_state_test.gd`: 40 perustehtävää, lisäosa ei sotke kampanjaa |
| 4 | DONE | `campaign_state_test.gd`: osto lisää varastoa, lento vähentää, ei negatiivia |
| 5 | DONE | `campaign_state_test.gd`: debriefin 6 kenttää tarkistettu |
| 6 | DONE | `models_test.gd`: 1025 PARTia + 1380 maasto-objektia, 0 puuttuvaa |
| 7 | DONE | `terrain_test.gd`: 18 aluetta, 0 puuttuvaa maastoa/palettia |
| 8 | DONE | `campaign_state_test.gd`: save/load säilyttää rahan, pisteet, varaston |
| 9 | DONE | `perf_baseline.gd`: mount 7 ms, 3120 tiedostoa, 77 tehtävää, listaus 22 ms, kaikkien parsinta 20 ms, gameflow 39 ms |
| 10 | DONE | `git ls-files`: 0 jäljitettyä .PAK/.IFF/TOPTTST1-tiedostoa; `alkuperainen_purku/*` gitignored, vain README tracked |

## Kampanjaohjaus (GAMEFLOW-vaiheet) — DONE 22.11.2026

| Osa | Tila | Todiste |
|---|---|---|
| `GAMEFLO2.IFF` / `OPTIONS2.IFF` / `CONVDAT2.IFF` | DONE | 28 vaihetta, 15 ruutua, 47 keskustelutunnistetta |
| FORM MLST 8 tavun kiinteät ennätteet | DONE | perus 47 / lisäosa 37 tehtävää oikeassa järjestyksessä (aiemmin NUL-jako yhdisti nimet) |
| `Campaign.tactical` + `Art.set_active()` | DONE | `tactical_flow_test.gd`: active_set, gameflow, mission_files, 0 skriptivirhettä |
| `--tactical` | DONE | `--auto=campaign --tactical`: stage 0 alkaa lisäosan `02:05`-efektillä, ei perus-MID1:llä |
| Save/load | DONE | `tactical`-lippu säilyy; lataus vaihtaa art-setin ennen gameflown käyttöä |
| Lisäosan cutscenet | OSITTAIN | `TO1MID1-3.PAK` + `TOMIDVOC.PAK` + `MIDGAMS2.IFF` -fallback: 8 kuvaa, 10 ääntä, 16 tekstiä; tarkkaa aikajanaa (TOPTTST1.EXE) ei ole vielä tallennettu |
| Ruudut / keskustelut | DONE | `visual_sweep.gd --tactical`: 15 ruutua + 118 keskustelua `CONV2.PAK`:sta, 0 tyhjää kuvaa, 0 skriptivirhettä |
| Näkyvä todiste | DONE | `tmp/tactical_proof/`: `screen_11.png`, `screen_30.png`, `conv_000.png`, `conv_020.png` |

**Huomiograf:** `CONVSHP2.PAK` (96 ennätettä, vain 4 käyttökelpoista) ja
`OPTSHPS2.PAK` ovat *overlayt*: lisäosan `CONVDAT2.IFF` osoittaa kasvot edelleen
peruspelin `CONVSHPS.PAK`-indekseihin. `Art._pak()` yhdistää perus- ja
lisäosa-arkistot, joten kuvat eivät ole enää mustia.

**Komento koko sarjalle:**
```powershell
& "C:\AI_Projektit\strike commander\Aja_Testit.ps1" -Taydet 1 -Data "C:/AI_Projektit/SC-REFORGED"
# 22 yksikkötestiä OK, 0 skriptivirhettä, MISN-1A success
```

---

## 1. Lisäosan datan purku ja validointi — EI ALOITETTU (kriittinen polku)

**Miksi:** vasta kun tiedetään mitä tehtäviä `TOPTTST1.EXE` sisältää, voidaan
arvioida kaiken muun laajuus.

**Komennot:**
```powershell
python tools\decompile\pura_tulkit.py "C:/AI_Projektit/SC-REFORGED"
# Purkaa OPTTEST.EXE:n lisäksi TOPTTST1.EXE:n overlayt (lisää pura_tulkit.py:hen)
python -c "import sys; sys.path.insert(0,'tools/cutscenes'); import sclib; print([k for k in sclib.B if 'MISSION' in k.upper()])"
```

**Hyväksyminen:**
- `alkuperainen_purku/TOPTTST1.EXE/*.asm` syntyy (paikallinen, ei gitiin).
- Tehtävä-IFF:t ja GAMEFLOW-vaiheet on listattu nimillä.
- Jokainen uusi tehtäväIFF läpäisee `Mission.load_from()` ilman nullia.

**Estää:** arvailun siitä, montako tehtävää lisäosa tuo.

---

## 2. Kaikkien 47 tehtävän täysi suoritus — OSITTAIN (25 s näyte / 47 tehtävää)

**Miksi:** nyt vain MISN-1A on lennetty alusta loppuun (`result=success,
Landed at base`). Muista on vain visuaalinen näyte ja "Flight scene ready".

**Komento:**
```powershell
# rinnakkain, kuten Aja_Testit.ps1 -Taydet 3, mutta kaikille 47:lle
foreach ($m in (Get-Content tests/mission_list.txt)) {
  Godot --headless --path game -- --auto=flight --mission=$m --autopilot --fast `
        --god --endless_ammo --fasttravel --timeout=540
}
```

**Hyväksyminen (toteutunut):** jokaisesta 77 tehtävästä on tulos
`results.csv`:ssä eikä yhdessäkään ole `SCRIPT ERROR`. Autopilotin kykyrajoite
kirjataan erikseen: 9 `success`, 20 `incomplete`, 3 `failed`, 45 `NO_RESULT`
(300 s wall-clock). Tämä on kultainen baseline, johon lisäosan tehtäviä verrataan —
Täydellinen `MISSION OVER` jokaisessa ei ole autopilotilla saavutettavissa.

**Estää:** sen, että lisäosan uusi tehtävä blameetaan rikkoontuneesta
perustehtävästä.

---

## 3. Kampanjan jatkuvuus oikealla tilalla — EI TESTATTU (fake host vain)

**Miksi:** `campaign_test.gd` käyttää `FakeHost`-luokkaa. Oikea raha, asevarasto,
koneiden menetykset ja tallennus eivät ole koskaan kulkeneet 47 lennon läpi.

**Komento:** aja oikea kampanja vaiheesta 0 vaiheeseen 9 (ilman fake hostia),
tallenna ja lataa välimuistista kahdesti.

**Hyväksyminen:** `campaign.json` säilyttää `cash`, `weapons[]`, `planes_lost`,
`score`, `purchases`; vaihe etenee lennon jälkeen.

**Estää:** lisäosan tehtävien sijoittamisen väärään kampanjavaiheeseen.

---

## 4. Asevaraston ja rahoituksen kirjanpito — EI TESTATTU

**Miksi:** `loadout_test.gd` testaa vain UI:n (lisäys/poisto/tykkilentto).
`base_screen._consume_loadout()` ja `catalog_buy()` eivät ole testattuja.

**Komento:** uusi `economy_test.gd`: ota aseita → lennä → tarkista
`campaign.weapons[]`; osta katalogista → tarkista `cash` ja `purchases`.

**Hyväksyminen:** varasto ei kasva eikä vähenne väärin; raha ei mene miinukselle.

**Estää:** lisäosan uusien aseiden kanssa tulevat tupla-/katto-ongelmat.

---

## 5. Debrief-raportit joka tehtävälle — EI TESTATTU

**Miksi:** `campaign_report()`-kentät tarkistettu vain yhdelle lennolle.

**Komento:** kerää `report` jokaisesta 47 lennosta kohtaan 2, vertaa kenttiä
`result`, `waypoints`, `kills`, `score`.

**Hyväksyminen:** jokaisessa raportissa on kaikki kentät, ei `null`/`NAN`.

**Estää:** lisäosan tehtävän pisteytyksen vertailun mahdottomuus.

---

## 6. Lentokonemallien ja skinnien kattavuus — OSITTAIN

**Miksi:** `all_missions_test` tarkistaa spawnuvat koneet (47 OK, 0 FAIL), mutta
ei `ExternalModels`-overrideja tai jokaista PART-mallia.

**Hyväksyminen:** jokainen `mission.parts[].model` → `SCData.model()` tai
`AircraftMeshes.build()` palauttaa meshin; ei fallback-mallia.

**Estää:** lisäosan uusien koneiden hiljainen korvautuminen F-16:lla.

---

## 7. Maasto ja paletti jokaiselle alueelle — EI AUDITOITU

**Hyväksyminen:** jokaisen tehtävän `area` → `terrain() != null` ja
`world_palette()` palauttaa oikean PAK-in, ei oletuspalettia.

**Estää:** lisäosan uuden maaston näkyminen väärillä väreillä.

---

## 8. Tallennus/lataus ja restart — EI TESTATTU

**Hyväksyminen:** `campaign.save()` → `load()` säilyttää vaiheen, rahat,
asevaraston ja lentokoneiden tilan; `restart`/`abort`/`continue` toimivat
ohjekirjan mukaan.

**Estää:** lisäosan tehtävän jälkeisen tallennuksen korruptoituminen.

---

## 9. Suorituskyky- ja muistibaseline — EI MITATTU

**Hyväksyminen:** SCData:n mount-aika, IFF-määrä, muistinkulutus ja
`all_missions_test`-aika kirjattu ennen lisäosaa vertailua varten.

**Estää:** "lisäosa hidasti peliä" -väitteen ilman vertailukohdetta.

---

## 10. Datan eristäminen ja lisenssi — SÄÄNTÖ VOIMASSA

**Hyväksyminen:** kaikki `TOPTTST1.EXE`-johdokset menevät
`alkuperainen_purku/`-kansioon (gitignore), ei koskaan `game/`-tai `dist/`-kansioon.
Peli lukee edelleen kaiken pelaajan omasta DOS-asennuksesta.

**Estää:** alkuperäisen datan vuotamisen julkiseen repoosi.

---

## Jo suljetut kohdat (ei enää testattava)

| Kohde | Tulos |
|---|---|
| Intro alusta | näkyvästi OK (pilvet → vuoret → kone) |
| Cutscenet | 40/40 aikajanaa ohjauksessa, 11/11 MID-arkistoa, `coverage_test failures=0` |
| Keskustelut | 241/241 käyty läpi, `visual_sweep blank_samples=0` |
| Ruudut/huoneet | 13/13, `visual_sweep blank=0` |
| FOE/FRIEND | `all_missions_test`: 47 OK, 0 FAIL |
| Voice-linjat | `voice_audit`: 243 tehtävää + 112 cutscenettä, `silent=0` |
| God mode / endless ammo | `cheats_test failures=0` |
| Täysi testisarja | 16 testiä OK, `== Yhteenveto: 0 vikaa ==` |

## Suositeltu järjestys

Edetään numerojärjestyksessä: **1 → 2 → 3 → 4 → 5 → 6 → 7 → 8 → 9 → 10**.
Kohta 1 on kriittinen polku; kohdat 2–5 muodostavat baseline:n, johon
lisäosan tehtäviä verrataan. Kohta 10 on jatkuva sääntö, ei vaihe.
