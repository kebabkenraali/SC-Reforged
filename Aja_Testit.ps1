# Strike Commander Reforged - koko testisarja yhdella komennolla.
# (tiedosto pysyy ASCII:na - PS 5.1 lukee BOMattoman .ps1:n ANSI:na)
#
#   .\Aja_Testit.ps1                 yksikkotestit + loppulahestyminen + 3 taytta MISN-1A-lentoa
#   .\Aja_Testit.ps1 -Taydet 5       sama, 5 taytta lentoa (M1:n hyvaksymisraja)
#   .\Aja_Testit.ps1 -Taydet 0       vain yksikkotestit + loppulahestyminen (alle minuutti)
#   .\Aja_Testit.ps1 -Hitaat         lisaksi all_missions_test (useita minuutteja)
#   .\Aja_Testit.ps1 -Data "C:/Gog games/Strike Commander"
#
# Pelidata: -Data, muuten ymparistomuuttuja SC_GAME_DIR, muuten pelin oma
# automaattihaku (asetuksiin tallennettu kansio).
# Lokit: tmp\testit\ (ei versionhallinnassa). Paluukoodi = epaonnistuneiden kohtien maara.
#
# Moottorista tehdaan oma nimikopio temp-kansioon, jotta tama skripti ei koskaan
# osu muiden istuntojen Godot-prosesseihin. Ala kayta Stop-Process -Name Godot*.

param(
	[int]$Taydet = 3,
	[switch]$Hitaat,
	[string]$Data = $env:SC_GAME_DIR
)

$ErrorActionPreference = "Stop"
$juuri  = Split-Path -Parent $MyInvocation.MyCommand.Path
$lahde  = Join-Path $juuri "tools\godot\Godot_v4.7.2-stable_win64.exe"
$game   = (Join-Path $juuri "game") -replace '\\', '/'
$lokit  = Join-Path $juuri "tmp\testit"
$temp   = Join-Path $env:TEMP "sc_reforged"
$engine = Join-Path $temp "scr_engine_testit.exe"

if (-not (Test-Path $lahde)) { Write-Host "Moottoria ei loydy: $lahde"; exit 99 }
New-Item -ItemType Directory -Force -Path $lokit, $temp | Out-Null
if (-not (Test-Path $engine) -or (Get-Item $engine).Length -ne (Get-Item $lahde).Length) {
	Copy-Item $lahde $engine -Force
}

$tulokset = New-Object System.Collections.ArrayList
$viat = 0

function Kaynnista([string]$nimi, [string[]]$argit) {
	$kaikki = @('--headless', '--path', "`"$game`"") + $argit
	$p = Start-Process -FilePath $engine -ArgumentList $kaikki -PassThru -WindowStyle Hidden `
		-RedirectStandardOutput (Join-Path $lokit "$nimi.out") `
		-RedirectStandardError (Join-Path $lokit "$nimi.err")
	# PS 5.1: the exit code is only kept when the handle is opened at start.
	$null = $p.Handle
	return $p
}

function Odota($p, [int]$sekunnit) {
	if (-not $p.WaitForExit($sekunnit * 1000)) {
		Stop-Process -Id $p.Id -Force
		return "JUMI"
	}
	return [string]$p.ExitCode
}

function Skriptivirheet([string]$nimi) {
	$rivit = @(Get-Content (Join-Path $lokit "$nimi.err") -ErrorAction SilentlyContinue |
		Where-Object { $_ -match 'SCRIPT ERROR|Parse Error' })
	return $rivit.Count
}

function Kirjaa([string]$nimi, [bool]$ok, [string]$tieto) {
	$tila = "OK  "
	if (-not $ok) { $tila = "VIKA"; $script:viat++ }
	[void]$tulokset.Add(("{0}  {1,-22} {2}" -f $tila, $nimi, $tieto))
	Write-Host ("{0}  {1,-22} {2}" -f $tila, $nimi, $tieto)
}

function Lentoargit([string[]]$lisa) {
	$a = @('--auto=flight', '--mission=MISSIONS/MISN-1A.IFF', '--fast', '--ap_debug') + $lisa
	if ($Data) { $a += "--dir=`"$Data`"" }
	return $a
}

function Lentotulos([string]$nimi) {
	$ulos = @(Get-Content (Join-Path $lokit "$nimi.out") -ErrorAction SilentlyContinue)
	$loppu = $ulos | Where-Object { $_ -match 'MISSION OVER' } | Select-Object -Last 1
	$runko = $ulos | Where-Object { $_ -match '^\s+Hull:' } | Select-Object -Last 1
	if (-not $loppu) { return "ei MISSION OVER -rivia" }
	return (($loppu -replace '^HEADLESS: MISSION OVER ', '') + " |" + $runko).Trim()
}

# --- 1. Yksikkotestit -------------------------------------------------------
Write-Host "== Yksikkotestit =="
$testit = @('smoke_test', 'mission_test', 'waypoint_test', 'conversation_test', 'coverage_test',
	'mission_events_test', 'voice_audit', 'models_test', 'terrain_test', 'tactical_ops_test',
	'mission_index_test',
	'loadout_test', 'waypoint_approach_test', 'cockpit_test', 'cockpit_windows_test', 'cheats_test', 'vm_test', 'flight_test', 'override_test',
	'campaign_test', 'campaign_state_test', 'tactical_flow_test', 'story_test', 'cutscene_vm_test', 'audio_test', 'vr_test', 'shader_test', 'camera_view_test', 'cutscene_audio_test', 'hud_attachment_test', 'librealspace_parity_test')
if ($Hitaat) { $testit += 'all_missions_test', 'cockpit_mission_sweep' }
foreach ($t in $testit) {
	$raja = 150
	if ($t -eq 'all_missions_test') { $raja = 900 }
	$koodi = Odota (Kaynnista $t @('--script', "res://tests/$t.gd")) $raja
	$sv = Skriptivirheet $t
	$vika = @(Get-Content (Join-Path $lokit "$t.out") | Where-Object { $_ -match 'failures=' }) | Select-Object -Last 1
	Kirjaa $t (($koodi -eq "0") -and ($sv -eq 0)) "exit=$koodi skriptivirheita=$sv $vika"
}

# --- 2. Loppulahestyminen (8 km finaali, noin 10 s) -------------------------
# Tavoitteet ovat tekematta, joten oikea tulos on "incomplete" + "Landed at base", runko ehja.
Write-Host "== Loppulahestyminen =="
$koodi = Odota (Kaynnista 'approach' (Lentoargit @('--approach', '--status=5', '--timeout=150'))) 180
$tulos = Lentotulos 'approach'
Kirjaa 'approach' (($tulos -match 'Landed at base') -and ($tulos -match 'Hull:\s+100') -and ((Skriptivirheet 'approach') -eq 0)) "exit=$koodi $tulos"

# --- 3. Taydet MISN-1A-lennot rinnakkain ------------------------------------
if ($Taydet -gt 0) {
	Write-Host "== Taysi MISN-1A x $Taydet (rinnakkain, muutama minuutti) =="
	$ajot = @()
	for ($i = 1; $i -le $Taydet; $i++) {
		$ajot += , @("m1_$i", (Kaynnista "m1_$i" (Lentoargit @('--autopilot', '--status=30', '--timeout=540'))))
	}
	$onnistui = 0
	foreach ($a in $ajot) {
		$koodi = Odota $a[1] 600
		$ok = ($koodi -eq "0") -and ((Skriptivirheet $a[0]) -eq 0)
		if ($ok) { $onnistui++ }
		Kirjaa $a[0] $ok "exit=$koodi $(Lentotulos $a[0])"
	}
	Write-Host "Taydet lennot: $onnistui / $Taydet onnistui"
}

Write-Host ""
Write-Host "== Yhteenveto: $viat vikaa, lokit $lokit =="
exit $viat
