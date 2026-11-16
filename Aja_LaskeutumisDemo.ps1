# Strike Commander Reforged - laskeutumisautopilotin demo
# (tiedosto pysyy ASCII:na - PS 5.1 lukee BOMattoman .ps1:n ANSI:na)
#
# Kaksi tilaa:
#   .\Aja_LaskeutumisDemo.ps1              -> loppulähestymis-demo (kone 8 km:llä
#                                             kiitotiellä, autopilotti laskeuttaa;
#                                             n. 2-4 min katseluaika oletusnopeudella)
#   .\Aja_LaskeutumisDemo.ps1 -Tila tehtava -> koko MISN-1A-tehtava: taistelu +
#                                             laskeutuminen (pidempi ajo)
#
# Valinnaiset parametrit:
#   -Nopeus 2   -> simulaationopeus (1 = reaaliaika, 3 = nopea, 10 = treeniloppu)
#   -Ikkuna     -> ei tehda mitaan ylimaarista; skripti avaa pelin ikkunaan
#
# Tausta: laskeutumisopas saatiin taas luotettavaksi 11.11.2026 (3/3 onnistunutta
# MISN-1A-laskeutumista headless-verifioinnissa). Tama demo nayttaa saman koodin
# nakyvassa ikkunassa.

param(
	[string]$Tila = "laske",      # "laske" = approach-demo, "tehtava" = koko tehtava
	[double]$Nopeus = 2.0
)

$ErrorActionPreference = "Stop"

$projekti = "C:\AI_Projektit\strike commander"
$lahde    = Join-Path $projekti "tools\godot\Godot_v4.7.2-stable_win64.exe"
$temp     = Join-Path $env:TEMP "opencode"
if (-not (Test-Path $temp)) { New-Item -ItemType Directory -Path $temp | Out-Null }
$engine   = Join-Path $temp "scr_engine_demo.exe"

# Oma nimikopio moottorista: sulku ja prosessin hallinta ei osu muiden sessioiden
# Godot-prosesseihin (ala KOSKAAN kayttaa Stop-Process -Name Godot*).
if (-not (Test-Path $engine)) {
	Copy-Item $lahde $engine -Force
}

$game = Join-Path $projekti "game"
$data = "C:/AI_Projektit/SC-REFORGED"

if ($Tila -eq "tehtava") {
	# Koko tehtava: taisteluautopilotti hoitaa tehtavan ja luovuttaa laskeutumiselle.
	& $engine --path "$game" --auto=flight --mission=MISSIONS/MISN-1A.IFF `
		--autopilot --speed=$Nopeus --dir="$data"
}
else {
	# Approach-demo: spawnataan suoraan loppulähestymiselle 8 km:llä.
	# Lippu --approach kaynnistaa laskeutumisautopilotin heti.
	& $engine --path "$game" --auto=flight --mission=MISSIONS/MISN-1A.IFF `
		--approach --speed=$Nopeus --dir="$data"
}

Write-Host ""
Write-Host "Demo paattyi (exit $LASTEXITCODE)."
Write-Host "Vinkit ikkunassa: F1 = reittiautopilot, F2 = laskeutumisautopilot, ESC = valikko."
