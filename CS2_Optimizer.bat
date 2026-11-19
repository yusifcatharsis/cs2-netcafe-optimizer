<# : CS2 Optimizer - NetCafe (tek fayl). Izahat asagidadir.
@echo off
set "CS2OPT_SELF=%~f0"
if /i "%~1"=="iz" goto :vis
if /i "%~1"=="image" goto :vis
start "" /min powershell -NoLogo -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -Command "& ([ScriptBlock]::Create([IO.File]::ReadAllText($env:CS2OPT_SELF))) -Mode '%~1'"
exit /b
:vis
powershell -NoLogo -NoProfile -ExecutionPolicy Bypass -Command "& ([ScriptBlock]::Create([IO.File]::ReadAllText($env:CS2OPT_SELF))) -Mode '%~1'"
pause
exit /b
#>
param([string]$Mode = '')
# =====================================================================
#  CS2 OPTIMIZER (NetCafe) - TEK FAYL, YEKUN VERSIYA
#  Muellif: yusifcatharsis (github.com/yusifcatharsis) | Telegram: @jeisterx
#  Lisenziya: MIT | https://github.com/yusifcatharsis/cs2-netcafe-optimizer
#
#  NECE QURULUR (bir defe):
#   Cloud Update Console > Workstations > More > Set boot task > Add Task
#     Task Type  : Run only
#     Executable : bu faylin yolu (meselen Z:\share\CS2 FPS Optimizer\CS2_Optimizer.bat)
#     Delay      : 30
#   Bu qeder. Musteri CS2-ni Steam-den ozu acir, hec ne gormur.
#
#  NE EDIR (arxa planda, ekranda hec ne gostermeden):
#   - Sistemi tanir (video kart, ekran, prosessor)
#   - Her Steam hesabina cs2_video.txt yazir (musteri hesaba girende de)
#   - autoexec.cfg, Windows oyun ayarlari, prosessora gore enerji plani
#   - NVIDIA shader cache-i serverden geri yukleyir, CS2 baglananda yigir
#   - CS2 fayllarini RAM-a evvelceden oxuyur (ilk acilis ~60 san -> ~30 san)
#
#  ELAVE REJIMLER (admin ucun, CMD-den):
#   CS2_Optimizer.bat iz    -> CS2 boyuk yenilemeden sonra oxuma siyahisini
#                              yenileyir (Steam-e girin, sonra isledin)
#   CS2_Optimizer.bat play  -> CS2-ni acir (menyu ucun, mecburi deyil)
#   CS2_Optimizer.bat image -> YALNIZ SUPER REJIMDE, bir defe: VBS / Memory
#                              Integrity-ni sondurur (sonra image-i saxlayin)
#
#  Jurnal: C:\ProgramData\cs2opt\log.txt  ve  <ShareDir>\jurnal\<PC>.txt
# =====================================================================

# ======================= AYARLAR =====================================
$ShareDir     = '\\SERVER\share\cs2_shader'  # <-- DEYISIN: serverde paylasilan qovluq (shader arxivi, siyahi, jurnal)
$MSAA         = 4      # 4 = hamar kenarlar (pikselsiz) | 0 = max FPS amma kenarlar pilleli
$Reflex       = 1      # NVIDIA Reflex: 0 off | 1 on | 2 on+boost
$Contrast     = 1      # Boost Player Contrast
$FpsMax       = 0      # 0 = limitsiz
$FpsMaxUI     = 200    # menyuda FPS limiti
$PrewarmOn    = 1      # 1 = CS2 fayllarini RAM-a evvelceden oxu
$PrewarmDelay = 180    # 0..bu qeder saniye tesadufi gozle (83 PC eyni anda olmasin)
$ShaderOn     = 1      # 1 = shader cache geri yukle / yig
$ShaderMaxMB  = 3000   # her kart ucun arxiv limiti (MB)
# =====================================================================

$ErrorActionPreference = 'SilentlyContinue'
$ProgressPreference = 'SilentlyContinue'
$Visible = ($Mode -eq 'iz' -or $Mode -eq 'image')
$Self = $env:CS2OPT_SELF
$SelfDir = ''
if ($Self) { $SelfDir = Split-Path -Parent $Self }

$WorkDir = Join-Path $env:ProgramData 'cs2opt'
New-Item -ItemType Directory -Path $WorkDir -Force | Out-Null
if (-not (Test-Path -LiteralPath $WorkDir)) { $WorkDir = $env:TEMP }
$LogFile = Join-Path $WorkDir 'log.txt'

function Log([string]$m) {
  try { Add-Content -LiteralPath $LogFile -Value ('{0}  {1}' -f (Get-Date -Format 'HH:mm:ss'), $m) -Encoding ASCII } catch {}
  if ($Visible) { Write-Host $m }
}
function Push-Log {
  try {
    $d = Join-Path $ShareDir 'jurnal'
    New-Item -ItemType Directory -Path $d -Force | Out-Null
    Copy-Item -LiteralPath $LogFile -Destination (Join-Path $d "$env:COMPUTERNAME.txt") -Force
  } catch {}
}

$Me = [Security.Principal.WindowsIdentity]::GetCurrent()
$IsAdmin = (New-Object Security.Principal.WindowsPrincipal($Me)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
$IsSystem = $Me.IsSystem

# ---------------------------------------------------------------------
function Get-UserSids {
  Get-ChildItem 'Registry::HKEY_USERS' | ForEach-Object { $_.PSChildName } | Where-Object { $_ -match '^S-1-5-21-[\d-]+$' }
}
function Get-ProfileOf([string]$sid) {
  try { (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList\$sid" -ErrorAction Stop).ProfileImagePath } catch { $null }
}
# Isleyecek istifadeci kontekstleri: @{ Key; Root (registry); Prof (profil qovlugu) }
function Get-UserContexts {
  $r = @()
  if (-not $IsSystem) {
    $r += @{ Key = 'self'; Root = 'HKCU:'; Prof = $env:USERPROFILE }
  } else {
    foreach ($sid in (Get-UserSids)) {
      $p = Get-ProfileOf $sid
      if ($p -and (Test-Path -LiteralPath $p)) { $r += @{ Key = $sid; Root = "Registry::HKEY_USERS\$sid"; Prof = $p } }
    }
  }
  $r
}
function Set-Reg([string]$path, [string]$name, $value, [string]$type) {
  try {
    if (-not (Test-Path -LiteralPath $path)) { New-Item -Path $path -Force | Out-Null }
    New-ItemProperty -LiteralPath $path -Name $name -Value $value -PropertyType $type -Force | Out-Null
  } catch {}
}

function Find-SteamDirs {
  $c = New-Object System.Collections.Generic.List[string]
  $roots = @('HKCU:')
  foreach ($sid in (Get-UserSids)) { $roots += "Registry::HKEY_USERS\$sid" }
  foreach ($rt in $roots) { try { $p = (Get-ItemProperty "$rt\Software\Valve\Steam" -ErrorAction Stop).SteamPath; if ($p) { $c.Add(($p -replace '/', '\')) } } catch {} }
  foreach ($k in 'HKLM:\SOFTWARE\WOW6432Node\Valve\Steam', 'HKLM:\SOFTWARE\Valve\Steam') { try { $p = (Get-ItemProperty $k -ErrorAction Stop).InstallPath; if ($p) { $c.Add($p) } } catch {} }
  foreach ($d in 'Z', 'E', 'D', 'C') { $c.Add("${d}:\Steam") }
  $c.Add("${env:ProgramFiles(x86)}\Steam")
  @($c | Where-Object { Test-Path -LiteralPath (Join-Path $_ 'steam.exe') } | ForEach-Object { $_.TrimEnd('\') } | Select-Object -Unique)
}
function Find-Game($steamDirs) {
  $libs = @()
  foreach ($s in $steamDirs) {
    $libs += $s
    $vdf = Join-Path $s 'steamapps\libraryfolders.vdf'
    if (Test-Path -LiteralPath $vdf) { foreach ($m in [regex]::Matches((Get-Content -Raw -LiteralPath $vdf), '"path"\s+"([^"]+)"')) { $libs += ($m.Groups[1].Value -replace '\\\\', '\') } }
  }
  foreach ($d in 'Z', 'E', 'D', 'C') { $libs += "${d}:\Steam"; $libs += "${d}:\SteamLibrary" }
  foreach ($l in ($libs | Select-Object -Unique)) {
    $g = Join-Path $l 'steamapps\common\Counter-Strike Global Offensive\game'
    if (Test-Path -LiteralPath (Join-Path $g 'bin\win64\cs2.exe')) { return $g }
  }
  $null
}

function Get-SysInfo {
  $o = @{}
  $gpus = @(Get-CimInstance Win32_VideoController)
  $gpu = $gpus | Where-Object { $_.PNPDeviceID -match 'VEN_(10DE|1002)' } | Select-Object -First 1
  if (-not $gpu) { $gpu = $gpus | Select-Object -First 1 }
  $o.Ven = 4318; $o.Dev = 10243
  if ($gpu.PNPDeviceID -match 'VEN_([0-9A-F]{4})&DEV_([0-9A-F]{4})') { $o.Ven = [Convert]::ToInt32($matches[1], 16); $o.Dev = [Convert]::ToInt32($matches[2], 16) }
  $o.GpuName = ([string]$gpu.Name).Trim()
  $o.Driver = ([string]$gpu.DriverVersion).Trim()
  $o.GpuKey = (($o.GpuName -creplace '[^A-Za-z0-9 \-\._]', '').Trim() -replace ' ', '_')
  $o.Nvidia = ($o.Ven -eq 4318)
  $disp = $gpus | Where-Object { $_.CurrentHorizontalResolution } | Select-Object -First 1
  $o.W = [int]$disp.CurrentHorizontalResolution; $o.H = [int]$disp.CurrentVerticalResolution
  if ($o.W -lt 800 -or $o.H -lt 600) { $o.W = 1920; $o.H = 1080 }
  $o.Hz = [int]$disp.CurrentRefreshRate
  if ($o.Hz -lt 50) { $o.Hz = 0 }
  $cpu = Get-CimInstance Win32_Processor | Select-Object -First 1
  $o.CpuName = ([string]$cpu.Name).Trim()
  $o.CpuType = 'OTHER'
  if ($o.CpuName -match '(7950|7900|9950|9900)X3D') { $o.CpuType = 'X3D_DUAL' } elseif ($o.CpuName -match 'X3D') { $o.CpuType = 'X3D_SINGLE' }
  $o
}

# ---------------------------------------------------------------------
function Get-VideoCfgText {
  $rf = $Reflex; if (-not $SI.Nvidia) { $rf = 0 }
  $t = @"
"video.cfg"
{
	"Version"		"16"
	"VendorID"		"$($SI.Ven)"
	"DeviceID"		"$($SI.Dev)"
	"setting.cpu_level"		"0"
	"setting.gpu_mem_level"		"0"
	"setting.gpu_level"		"0"
	"setting.knowndevice"		"0"
	"setting.defaultres"		"$($SI.W)"
	"setting.defaultresheight"		"$($SI.H)"
	"setting.refreshrate_numerator"		"$($SI.Hz)"
	"setting.refreshrate_denominator"		"$(if ($SI.Hz -gt 0) { 1 } else { 0 })"
	"setting.fullscreen"		"1"
	"setting.coop_fullscreen"		"0"
	"setting.nowindowborder"		"0"
	"setting.mat_vsync"		"0"
	"setting.fullscreen_min_on_focus_loss"		"1"
	"setting.high_dpi"		"0"
	"AutoConfig"		"0"
	"setting.r_low_latency"		"$rf"
	"setting.r_player_visibility_mode"		"$Contrast"
	"setting.shaderquality"		"0"
	"setting.r_texturefilteringquality"		"5"
	"setting.msaa_samples"		"$MSAA"
	"setting.r_csgo_cmaa_enable"		"0"
	"setting.videocfg_shadow_quality"		"2"
	"setting.videocfg_dynamic_shadows"		"1"
	"setting.videocfg_texture_detail"		"1"
	"setting.videocfg_particle_detail"		"0"
	"setting.videocfg_ao_detail"		"0"
	"setting.videocfg_hdr_detail"		"-1"
	"setting.videocfg_fsr_detail"		"0"
}
"@
  $t
}
function Write-ReadOnly([string]$file, [string]$text) {
  try {
    if (Test-Path -LiteralPath $file) { (Get-Item -LiteralPath $file -Force).Attributes = 'Normal' }
    [IO.File]::WriteAllText($file, ($text -replace "`r?`n", "`r`n"), (New-Object Text.ASCIIEncoding))
    (Get-Item -LiteralPath $file -Force).Attributes = 'ReadOnly'
    $true
  } catch { $false }
}
function Write-CfgFile([string]$file, [string]$text) {
  # yazilir, amma read-only DEYIL: musteri oyunda qrafikani ozu deyise bilsin
  try {
    if (Test-Path -LiteralPath $file) { (Get-Item -LiteralPath $file -Force).Attributes = 'Normal' }
    [IO.File]::WriteAllText($file, ($text -replace "`r?`n", "`r`n"), (New-Object Text.ASCIIEncoding))
    $true
  } catch { $false }
}
$DoneUserdata = New-Object 'System.Collections.Generic.HashSet[string]'
function Apply-VideoCfg {
  foreach ($s in $SteamDirs) {
    $ud = Join-Path $s 'userdata'
    if (-not (Test-Path -LiteralPath $ud)) { continue }
    foreach ($u in (Get-ChildItem -LiteralPath $ud -Directory)) {
      if ($u.Name -eq '0' -or $u.Name -notmatch '^\d+$') { continue }
      if ($DoneUserdata.Contains($u.FullName)) { continue }
      $cfg = Join-Path $u.FullName '730\local\cfg'
      New-Item -ItemType Directory -Path $cfg -Force | Out-Null
      if (Write-CfgFile (Join-Path $cfg 'cs2_video.txt') $VideoText) { [void]$DoneUserdata.Add($u.FullName); Log "cs2_video.txt yazildi: $($u.Name)" }
    }
  }
}
function Write-Autoexec {
  $cfgDir = Join-Path $Game 'csgo\cfg'
  New-Item -ItemType Directory -Path $cfgDir -Force | Out-Null
  $t = @"
// NetCafe CS2 autoexec
fps_max $FpsMax
fps_max_ui $FpsMaxUI
engine_low_latency_sleep_after_client_tick true
r_show_build_info false
cl_teamid_overhead_fade_near_crosshair 1
"@
  if (Write-ReadOnly (Join-Path $cfgDir 'autoexec.cfg') $t) { Log 'autoexec.cfg yazildi' }
}

function Apply-MachineTweaks {
  if (-not $IsAdmin) { Log 'Admin deyil: enerji plani / prioritet kecildi'; return }
  if ($SI.CpuType -eq 'X3D_DUAL') { & powercfg /setactive 381b4222-f694-41f0-9685-ff5bb260df2e 2>$null | Out-Null }
  else { & powercfg /setactive 8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c 2>$null | Out-Null }
  Set-Reg 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options\cs2.exe\PerfOptions' 'CpuPriorityClass' 3 'DWord'
  Log "Enerji plani ve prioritet tetbiq edildi ($($SI.CpuType))"
}
function Apply-UserTweaks($ctx) {
  $r = $ctx.Root
  Set-Reg "$r\System\GameConfigStore" 'GameDVR_Enabled' 0 'DWord'
  Set-Reg "$r\Software\Microsoft\Windows\CurrentVersion\GameDVR" 'AppCaptureEnabled' 0 'DWord'
  Set-Reg "$r\Software\Microsoft\GameBar" 'AutoGameModeEnabled' 1 'DWord'
  Set-Reg "$r\Software\Microsoft\GameBar" 'AllowAutoGameMode' 1 'DWord'
  if ($SI.CpuType -ne 'X3D_DUAL') { Set-Reg "$r\Software\Microsoft\GameBar" 'UseNexusForGameBarEnabled' 0 'DWord' }
  Set-Reg "$r\Software\Microsoft\DirectX\UserGpuPreferences" $Cs2Exe 'GpuPreference=2;' 'String'
  Set-Reg "$r\Software\Microsoft\Windows NT\CurrentVersion\AppCompatFlags\Layers" $Cs2Exe '~ DISABLEDXMAXIMIZEDWINDOWEDMODE' 'String'
  Log "Windows oyun ayarlari: $($ctx.Key)"
}
function Apply-Nvidia {
  if (-not $SI.Nvidia -or -not $IsAdmin) { return }
  $npi = $null
  foreach ($d in @($SelfDir, (Split-Path -Parent $ShareDir))) { if ($d -and (Test-Path -LiteralPath (Join-Path $d 'nvidiaProfileInspector.exe'))) { $npi = Join-Path $d 'nvidiaProfileInspector.exe'; break } }
  if (-not $npi) { return }
  $nip = Join-Path $WorkDir 'cs2_nvidia.nip'
  $x = @'
<?xml version="1.0" encoding="utf-8"?>
<ArrayOfProfile>
  <Profile>
    <ProfileName>Base Profile</ProfileName>
    <Executeables />
    <Settings>
      <ProfileSetting><SettingNameInfo>Power management mode</SettingNameInfo><SettingID>274197361</SettingID><SettingValue>1</SettingValue><ValueType>Dword</ValueType></ProfileSetting>
      <ProfileSetting><SettingNameInfo>Vertical Sync</SettingNameInfo><SettingID>11041231</SettingID><SettingValue>138504007</SettingValue><ValueType>Dword</ValueType></ProfileSetting>
      <ProfileSetting><SettingNameInfo>Texture filtering - Quality</SettingNameInfo><SettingID>13510289</SettingID><SettingValue>0</SettingValue><ValueType>Dword</ValueType></ProfileSetting>
      <ProfileSetting><SettingNameInfo>Low Latency Mode</SettingNameInfo><SettingID>8102046</SettingID><SettingValue>1</SettingValue><ValueType>Dword</ValueType></ProfileSetting>
      <ProfileSetting><SettingNameInfo>Shader disk cache maximum size</SettingNameInfo><SettingID>11306135</SettingID><SettingValue>4294967295</SettingValue><ValueType>Dword</ValueType></ProfileSetting>
    </Settings>
  </Profile>
</ArrayOfProfile>
'@
  Set-Content -LiteralPath $nip -Value $x -Encoding UTF8
  Start-Process -FilePath $npi -ArgumentList @('-silentImport', "`"$nip`"") -WindowStyle Hidden -Wait
  Log 'NVIDIA ayarlari tetbiq edildi'
}

# ---------------------------------------------------------------------
function Get-ShaderPairs([string]$prof) {
  @(
    @((Join-Path $prof 'AppData\LocalLow\NVIDIA\PerDriverVersion\DXCache'), 'DXCache_LocalLow'),
    @((Join-Path $prof 'AppData\Local\NVIDIA\DXCache'), 'DXCache_Local'),
    @((Join-Path $prof 'AppData\Local\D3DSCache'), 'D3DSCache')
  )
}
function Get-ShaderArchive { Join-Path (Join-Path $ShareDir $SI.GpuKey) $SI.Driver }
function Restore-Shader($ctx) {
  if (-not $ShaderOn -or -not $SI.GpuKey -or -not $SI.Driver) { return }
  $src = Get-ShaderArchive
  if (-not (Test-Path -LiteralPath (Join-Path $src 'yigildi.txt'))) { Log "Shader arxivi yoxdur (ve ya server elcatan deyil): $src"; return }
  foreach ($p in (Get-ShaderPairs $ctx.Prof)) {
    $s = Join-Path $src $p[1]
    if (Test-Path -LiteralPath $s) { & robocopy $s $p[0] /E /XO /R:1 /W:1 /NJH /NJS /NFL /NDL /NP | Out-Null }
  }
  Log "Shader cache geri yuklendi: $($ctx.Key)"
}
function Collect-Shader($ctx) {
  if (-not $ShaderOn -or -not $SI.GpuKey -or -not $SI.Driver) { return }
  $dst = Get-ShaderArchive
  New-Item -ItemType Directory -Path $dst -Force | Out-Null
  if (-not (Test-Path -LiteralPath $dst)) { Log "XETA: servere yazmaq olmur: $dst"; return }
  $mb = [int](((Get-ChildItem -LiteralPath $dst -Recurse -File | Measure-Object Length -Sum).Sum) / 1MB)
  if ($mb -ge $ShaderMaxMB) { Log "Shader arxivi limitdedir ($mb MB)"; return }
  $any = $false
  foreach ($p in (Get-ShaderPairs $ctx.Prof)) {
    if (Test-Path -LiteralPath $p[0]) { & robocopy $p[0] (Join-Path $dst $p[1]) /E /XO /R:1 /W:1 /NJH /NJS /NFL /NDL /NP | Out-Null; $any = $true }
  }
  if ($any) { Set-Content -LiteralPath (Join-Path $dst 'yigildi.txt') -Value ("{0} {1}" -f $env:COMPUTERNAME, (Get-Date -Format 'yyyy-MM-dd HH:mm')) -Encoding ASCII; Log "Shader cache servere yigildi: $($ctx.Key)" }
}

# ---------------------------------------------------------------------
$PrewarmScript = {
  param([string]$game, [string[]]$lines, [int]$delay)
  if ($delay -gt 0) { Start-Sleep -Seconds $delay }
  try { [Diagnostics.Process]::GetCurrentProcess().PriorityClass = 'BelowNormal' } catch {}
  $buf = New-Object byte[] (4MB); $tot = [long]0
  $sw = [Diagnostics.Stopwatch]::StartNew()
  $jobs = New-Object System.Collections.Generic.List[object]
  foreach ($sub in 'bin', 'csgo\bin', 'core') {
    $p = Join-Path $game $sub
    if (Test-Path -LiteralPath $p) { foreach ($f in (Get-ChildItem -LiteralPath $p -Recurse -File)) { $jobs.Add(@($f.FullName, [long]0, [long]-1)) } }
  }
  foreach ($f in (Get-ChildItem -LiteralPath (Join-Path $game 'csgo') -Filter '*_dir.vpk' -File)) { $jobs.Add(@($f.FullName, [long]0, [long]-1)) }
  foreach ($ln in $lines) {
    $parts = $ln -split "`t"; if ($parts.Count -lt 2) { continue }
    $fp = Join-Path $game $parts[0]
    foreach ($r in ($parts[1] -split ';')) { $se = $r -split '-'; if ($se.Count -eq 2) { $jobs.Add(@($fp, [long]$se[0], [long]$se[1])) } }
  }
  foreach ($j in $jobs) {
    try {
      $fs = [IO.File]::Open($j[0], 'Open', 'Read', 'ReadWrite')
      try {
        if ($j[2] -lt 0) { $left = $fs.Length } else { [void]$fs.Seek($j[1] * 1MB, 'Begin'); $left = ($j[2] - $j[1] + 1) * 1MB }
        while ($left -gt 0) { $n = $fs.Read($buf, 0, [int][Math]::Min($buf.Length, $left)); if ($n -le 0) { break }; $left -= $n; $tot += $n }
      } finally { $fs.Close() }
    } catch {}
  }
  '{0:N2} GB {1:N0} saniyede oxundu (gozleme {2} san)' -f ($tot / 1GB), $sw.Elapsed.TotalSeconds, $delay
}
function Get-PrewarmLines {
  $f = Join-Path $ShareDir 'cs2_prewarm_list.txt'
  if (Test-Path -LiteralPath $f) { $t = @(Get-Content -LiteralPath $f); if ($t.Count -gt 20) { Log "Oxuma siyahisi: server ($($t.Count) setir)"; return $t } }
  $t = @($EmbeddedList -split "`r?`n" | Where-Object { $_ })
  Log "Oxuma siyahisi: daxili ($($t.Count) setir)"
  $t
}

# ---------------------------------------------------------------------
function Run-Trace {
  Write-Host '=== CS2 oxuma siyahisinin yenilenmesi ===' -ForegroundColor Cyan
  if (-not $IsAdmin) { Write-Host 'XETA: sag klik > Yonetici olarak calistir (Administrator) ile acin.' -ForegroundColor Red; return }
  if (-not $Game) { Write-Host 'XETA: CS2 tapilmadi' -ForegroundColor Red; return }
  Write-Host 'Diqqet: PC tezece yeniden baslamis olmalidir ve Steam-e girilmis olmalidir.' -ForegroundColor Yellow
  Add-Type -TypeDefinition @'
using System; using System.IO; using System.Text; using System.Globalization; using System.Collections.Generic;
public static class CsTrace {
  static List<string> SplitCsv(string line) {
    List<string> r = new List<string>(32); StringBuilder sb = new StringBuilder(); bool q = false;
    for (int i = 0; i < line.Length; i++) { char c = line[i];
      if (c == '"') { q = !q; continue; }
      if (c == ',' && !q) { r.Add(sb.ToString().Trim()); sb.Length = 0; continue; }
      sb.Append(c); }
    r.Add(sb.ToString().Trim()); return r; }
  static bool Num(string s, out long v) { v = 0; if (string.IsNullOrEmpty(s)) return false;
    if (s.StartsWith("0x") || s.StartsWith("0X")) return long.TryParse(s.Substring(2), NumberStyles.HexNumber, CultureInfo.InvariantCulture, out v);
    return long.TryParse(s, NumberStyles.Integer, CultureInfo.InvariantCulture, out v); }
  static string Get(List<string> f, int i) { return (i >= 0 && i < f.Count) ? f[i] : null; }
  public static string Run(string csv, string marker, string outList, long bs) {
    Dictionary<string, string> objPath = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
    Dictionary<string, string> keyPath = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
    Dictionary<string, HashSet<long>> blocks = new Dictionary<string, HashSet<long>>(StringComparer.OrdinalIgnoreCase);
    List<string> order = new List<string>();
    long reads = 0, matched = 0, bytes = 0; string mk = marker.ToLowerInvariant(); int ud = 19;
    using (StreamReader sr = new StreamReader(csv, Encoding.Default, true, 1 << 20)) {
      string line;
      while ((line = sr.ReadLine()) != null) {
        if (line.Length < 5) continue;
        if (line.IndexOf("FileIo", StringComparison.OrdinalIgnoreCase) < 0) {
          if (line.IndexOf("Event Name", StringComparison.OrdinalIgnoreCase) >= 0) { List<string> hh = SplitCsv(line); for (int i = 0; i < hh.Count; i++) if (hh[i].Equals("User Data", StringComparison.OrdinalIgnoreCase)) ud = i; }
          continue; }
        List<string> f = SplitCsv(line); if (f.Count < ud + 2) continue;
        if (!f[0].Equals("FileIo", StringComparison.OrdinalIgnoreCase)) continue;
        string t = f[1];
        if (t.Equals("Create", StringComparison.OrdinalIgnoreCase)) { string o = Get(f, ud + 1), p = f[f.Count - 1]; if (o != null && p.IndexOf('\\') >= 0) objPath[o] = p; continue; }
        if (t.Equals("Name", StringComparison.OrdinalIgnoreCase) || t.Equals("FileCreate", StringComparison.OrdinalIgnoreCase) || t.Equals("FileRundown", StringComparison.OrdinalIgnoreCase)) {
          string k = Get(f, ud), p = Get(f, ud + 1); if (k != null && p != null) keyPath[k] = p; continue; }
        if (t.Equals("Read", StringComparison.OrdinalIgnoreCase)) {
          reads++;
          string o = Get(f, ud + 2), k = Get(f, ud + 3), p = null;
          if (o != null) objPath.TryGetValue(o, out p);
          if (p == null && k != null) keyPath.TryGetValue(k, out p);
          if (p == null && o != null) keyPath.TryGetValue(o, out p);
          if (p == null) continue;
          int x = p.ToLowerInvariant().IndexOf(mk); if (x < 0) continue;
          string rel = p.Substring(x + marker.Length);
          long off, sz; if (!Num(Get(f, ud), out off) || !Num(Get(f, ud + 5), out sz) || sz <= 0) continue;
          matched++; bytes += sz;
          HashSet<long> set; if (!blocks.TryGetValue(rel, out set)) { set = new HashSet<long>(); blocks[rel] = set; order.Add(rel); }
          for (long b = off / bs; b <= (off + sz - 1) / bs; b++) set.Add(b);
        }
      }
    }
    long tb = 0;
    using (StreamWriter w = new StreamWriter(outList, false, new UTF8Encoding(false))) {
      foreach (string rel in order) {
        List<long> a = new List<long>(blocks[rel]); a.Sort(); tb += a.Count;
        StringBuilder sb = new StringBuilder(); long s = a[0], e = a[0];
        for (int i = 1; i < a.Count; i++) { if (a[i] == e + 1) e = a[i]; else { sb.Append(s).Append('-').Append(e).Append(';'); s = e = a[i]; } }
        sb.Append(s).Append('-').Append(e);
        w.WriteLine(rel + "\t" + sb.ToString());
      }
    }
    return string.Format("read={0} uygun={1} fayl={2} hecm={3:N0} MB", reads, matched, blocks.Count, tb * bs / 1048576);
  }
}
'@
  $steamExe = Join-Path $SteamDirs[0] 'steam.exe'
  $etl = Join-Path $WorkDir 'trace.etl'; $csv = Join-Path $WorkDir 'trace.csv'; $out = Join-Path $WorkDir 'cs2_prewarm_list.txt'
  Remove-Item $etl, $csv, $out -ErrorAction SilentlyContinue
  & wpr.exe -cancel 2>$null | Out-Null
  & wpr.exe -start FileIO -filemode
  if ($LASTEXITCODE -ne 0) { Write-Host "XETA: wpr basladilmadi ($LASTEXITCODE)" -ForegroundColor Red; return }
  Start-Process -FilePath $steamExe -ArgumentList @('-applaunch', '730')
  Write-Host ''
  Write-Host ' CS2 acilir. ANA MENYU gorunende Alt+Tab edib bu pencerede ENTER basin.' -ForegroundColor Yellow
  [void](Read-Host)
  Start-Sleep -Seconds 5
  Write-Host 'Iz dayandirilir ve analiz edilir (2-5 deqiqe), pencereni baglamayin...' -ForegroundColor Yellow
  & wpr.exe -stop $etl -skipPdbGen 2>$null | Out-Null
  if (-not (Test-Path $etl)) { & wpr.exe -stop $etl | Out-Null }
  if (-not (Test-Path $etl)) { Write-Host 'XETA: iz fayli yaranmadi' -ForegroundColor Red; return }
  & tracerpt.exe $etl -o $csv -of CSV -y | Out-Null
  $res = [CsTrace]::Run($csv, '\steamapps\common\Counter-Strike Global Offensive\game\', $out, 1MB)
  Write-Host $res
  Remove-Item $etl, $csv -ErrorAction SilentlyContinue
  if ((Test-Path $out) -and ((Get-Item $out).Length -gt 1000)) {
    try { Copy-Item $out (Join-Path $ShareDir 'cs2_prewarm_list.txt') -Force -ErrorAction Stop; Write-Host "HAZIRDIR. Yeni siyahi servere yazildi: $ShareDir\cs2_prewarm_list.txt" -ForegroundColor Green }
    catch { Write-Host "XETA: servere yazmaq olmadi: $($_.Exception.Message)" -ForegroundColor Red }
  } else { Write-Host 'XETA: siyahi bos cixdi, yeniden yoxlayin.' -ForegroundColor Red }
}

function Start-Daemon {
  Start-Process -FilePath 'powershell.exe' -WindowStyle Hidden -ArgumentList @('-NoLogo', '-NoProfile', '-WindowStyle', 'Hidden', '-ExecutionPolicy', 'Bypass', '-Command', '& ([ScriptBlock]::Create([IO.File]::ReadAllText($env:CS2OPT_SELF)))')
}

# CS2-nin menyuya qeder oxudugu hisseler (19.11.2026 olcusu). Serverde
# cs2_prewarm_list.txt varsa o istifade olunur ("iz" rejimi yaradir).
$EmbeddedList = @'
bin\win64\cs2.exe	0-2
bin\win64\csgo.signatures	0-0
core\gameinfo.gi	0-0
core\gameinfo_branchspecific.gi	0-0
csgo\bin\win64\client.dll	0-37
csgo\bin\win64\host.dll	0-1
csgo\bin\win64\matchmaking.dll	0-1
csgo\bin\win64\modtools.dll	0-17
csgo\bin\win64\server.dll	0-32
csgo\gameinfo.gi	0-0
csgo\gameinfo_branchspecific.gi	0-0
csgo\steam.inf	0-0
csgo_lv\gameinfo.gi	0-0
csgo_lv\gameinfo_branchspecific.gi	0-0
bin\win64\OpenImageDenoise.dll	0-0
bin\win64\OpenImageDenoise_core.dll	0-48
bin\win64\OpenImageDenoise_device_cpu.dll	0-0
bin\win64\OpenImageDenoise_device_cuda.dll	0-2
bin\win64\OpenImageDenoise_device_hip.dll	0-3
bin\win64\OpenImageDenoise_device_sycl.dll	0-5
bin\win64\Qt5Concurrent.dll	0-0
bin\win64\Qt5Core.dll	0-5
bin\win64\Qt5Gui.dll	0-6
bin\win64\Qt5Widgets.dll	0-5
bin\win64\SDL3.dll	0-2
bin\win64\amd_ags_x64.dll	0-0
bin\win64\animationsystem.dll	0-8
bin\win64\assetbrowser.dll	0-3
bin\win64\assetpreview.dll	0-46
bin\win64\assetrename.dll	0-32
bin\win64\assetsystem.dll	0-5
bin\win64\ati_compress_wrapper.dll	0-0
bin\win64\bc7e.dll	0-1
bin\win64\bugreporter_filequeue.dll	0-0
bin\win64\cairo.dll	0-1
bin\win64\cs2_build_econ_items_workshop.exe	0-0
bin\win64\cs_mdl_import.exe	0-14
bin\win64\csgocfg.exe	0-1
bin\win64\d3dcompiler_47.dll	0-4
bin\win64\dbghelp.dll	0-1
bin\win64\dmxconvert.exe	0-1
bin\win64\embree3.dll	0-20
bin\win64\engine2.dll	0-7
bin\win64\exportsystem.dll	0-3
bin\win64\filesystem_stdio.dll	0-2
bin\win64\foreign.signatures	0-0
bin\win64\gfsdk_aftermath_lib.x64.dll	0-5
bin\win64\helpsystem.dll	0-0
bin\win64\imemanager.dll	0-0
bin\win64\inputsystem.dll	0-0
bin\win64\ispc_texcomp.dll	0-1
bin\win64\libavcodec-58.dll	0-6
bin\win64\libavformat-58.dll	0-1
bin\win64\libavresample-4.dll	0-0
bin\win64\libavutil-56.dll	0-1
bin\win64\libfbxsdk_2020_3_1.dll	0-9
bin\win64\libfontconfig-1.dll	0-0
bin\win64\libfreetype-6.dll	0-1
bin\win64\libglib-2.0-0.dll	0-1
bin\win64\libgmodule-2.0-0.dll	0-0
bin\win64\libgobject-2.0-0.dll	0-0
bin\win64\libgthread-2.0-0.dll	0-0
bin\win64\libmpg123-0.dll	0-0
bin\win64\libpango-1.0-0.dll	0-0
bin\win64\libpangoft2-1.0-0.dll	0-0
bin\win64\libswscale-5.dll	0-1
bin\win64\localize.dll	0-0
bin\win64\materialsystem2.dll	0-1
bin\win64\meshsystem.dll	0-1
bin\win64\modeldoc_utils.dll	0-16
bin\win64\navsystem.dll	0-1
bin\win64\networksystem.dll	0-2
bin\win64\p4lib.dll	0-0
bin\win64\panorama.dll	0-5
bin\win64\panorama_text_pango.dll	0-2
bin\win64\panoramauiclient.dll	0-2
bin\win64\particles.dll	0-6
bin\win64\phonon.dll	0-50
bin\win64\phonon4.dll	0-0
bin\win64\physicsbuilder.dll	0-13
bin\win64\pi_level_zero.dll	0-0
bin\win64\pi_win_proxy_loader.dll	0-0
bin\win64\propertyeditor.dll	0-1
bin\win64\pulse_system.dll	0-1
bin\win64\qt5_plugins\imageformats\qgif.dll	0-0
bin\win64\qt5_plugins\imageformats\qico.dll	0-0
bin\win64\qt5_plugins\imageformats\qjpeg.dll	0-0
bin\win64\qt5_plugins\imageformats\qtga.dll	0-0
bin\win64\qt5_plugins\imageformats\qtiff.dll	0-0
bin\win64\qt5_plugins\platforms\qwindows.dll	0-1
bin\win64\qt5_plugins\styles\qwindowsvistastyle.dll	0-0
bin\win64\qtadvanceddocking-qt5.dll	0-0
bin\win64\rendersystemdx11.dll	0-4
bin\win64\rendersystemempty.dll	0-1
bin\win64\rendersystemvulkan.dll	0-5
bin\win64\resourcecompiler.dll	0-53
bin\win64\resourcecompiler.exe	0-0
bin\win64\resourcecopy.exe	0-1
bin\win64\resourceinfo.exe	0-3
bin\win64\resourcesystem.dll	0-0
bin\win64\scenefilecache.dll	0-1
bin\win64\scenesystem.dll	0-6
bin\win64\schemasystem.dll	0-0
bin\win64\smartprops.dll	0-1
bin\win64\soundsystem.dll	0-5
bin\win64\source1import.exe	0-17
bin\win64\steam_api64.dll	0-0
bin\win64\steamaudio.dll	0-3
bin\win64\steamnetworkingsockets.dll	0-4
bin\win64\subtools\convarhelper_subtool.dll	0-0
bin\win64\subtools\dashboard_subtool.dll	0-0
bin\win64\subtools\netgraph_subtool.dll	0-0
bin\win64\subtools\soundviewer_subtool.dll	0-0
bin\win64\subtools\vprof_subtool.dll	0-0
bin\win64\sycl7.dll	0-4
bin\win64\symsrv.dll	0-0
bin\win64\system.signatures	0-0
bin\win64\tbb12.dll	0-0
bin\win64\tbbbind.dll	0-0
bin\win64\tbbbind_2_0.dll	0-0
bin\win64\tbbbind_2_5.dll	0-0
bin\win64\tier0.dll	0-3
bin\win64\toolframework2.dll	0-13
bin\win64\tools\cs2_item_editor.dll	0-6
bin\win64\tools\cs2_workshop_manager.dll	0-2
bin\win64\tools\hammer.dll	0-37
bin\win64\tools\met.dll	0-4
bin\win64\tools\modeldoc_editor.dll	0-26
bin\win64\tools\pet.dll	0-8
bin\win64\tools\postprocessingeditor.dll	0-7
bin\win64\tools\sfm.dll	0-12
bin\win64\tools\subrecteditor.dll	0-1
bin\win64\toolscenenodes.dll	0-14
bin\win64\v8.dll	0-48
bin\win64\v8_icui18n.dll	0-3
bin\win64\v8_icuuc.dll	0-2
bin\win64\v8_libbase.dll	0-1
bin\win64\v8_libplatform.dll	0-1
bin\win64\v8_zlib.dll	0-0
bin\win64\v8system.dll	0-0
bin\win64\valve_avi.dll	0-0
bin\win64\valve_webm.dll	0-10
bin\win64\valve_wmf.dll	0-0
bin\win64\vconcomm.dll	0-0
bin\win64\vconsole2.exe	0-4
bin\win64\vfx_dx11.dll	0-1
bin\win64\video64.dll	0-4
bin\win64\visbuilder.dll	0-1
bin\win64\vphysics2.dll	0-4
bin\win64\vpk.signatures	0-0
bin\win64\vrad3.dll	0-3
bin\win64\vrad3.exe	0-0
bin\win64\vscript.dll	0-1
bin\win64\worldrenderer.dll	0-1
csgo\cfg\boot.vcfg	0-0
core\pak01_dir.vpk	0-0
csgo\pak01_dir.vpk	0-7
core\pak01_005.vpk	9-14;20-21;30-30;38-38;40-40;42-42;50-52;56-60;65-67;69-69;71-72;75-86
csgo\pak01_502.vpk	21-22;25-26;52-62;65-65;67-68;90-90;94-94;96-96
csgo\pak01_276.vpk	15-16;20-21;24-24;44-44;47-47;63-66;72-72
csgo\resource\game-icon.bmp	0-0
csgo\shaders_pc_dir.vpk	0-0
core\shaders_pc_dir.vpk	0-0
csgo\shaders_pc_003.vpk	0-3;24-24;30-31;33-39
csgo\pak01_262.vpk	102-116
core\shaders_pc_000.vpk	0-3
csgo\pak01_250.vpk	23-27;52-53;70-70;104-104;106-107;111-111
core\pak01_004.vpk	44-44;52-52;81-81;98-102
csgo\pak01_463.vpk	33-33;35-35;38-38;44-45;47-47;52-53;75-76;91-96
csgo\pak01_151.vpk	0-6;9-24;28-28;57-60;64-64;88-96
csgo\pak01_269.vpk	1-1;25-26;46-46;54-54;62-64;68-68;76-76;79-79;84-85;87-89
csgo\pak01_023.vpk	26-34;36-67;69-74;76-81;95-96
csgo\pak01_240.vpk	5-5;10-10;13-13;16-16;29-29;37-40;42-42;44-44;47-48;52-52;54-54;57-58;75-75;79-80;82-82;85-85
csgo\pak01_386.vpk	0-0;2-2;28-28;30-37;45-48;50-55;59-59;66-67;69-70;73-75;85-86;89-89;91-95
csgo\pak01_222.vpk	4-7;17-20;30-30;34-34;40-41;49-49;52-52;61-63
csgo\pak01_108.vpk	3-4;7-7;10-10;13-13;17-17;31-34;45-46;52-52;55-55;70-71;76-76;78-78;96-98
csgo\pak01_335.vpk	28-28;34-38;41-41;50-50;72-76
csgo\pak01_546.vpk	0-3;5-17;20-32
csgo\cfg\user_keys_default.vcfg	0-0
csgo\panorama\fonts\notomono-regular.ttf	0-0
csgo\panorama\fonts\notosans-bold.ttf	0-0
csgo\panorama\fonts\notosans-bolditalic.ttf	0-0
csgo\panorama\fonts\notosans-italic.ttf	0-0
csgo\panorama\fonts\notosans-regular.ttf	0-0
csgo\panorama\fonts\notosansjp-bold.ttf	0-4
csgo\panorama\fonts\notosansjp-light.ttf	0-4
csgo\panorama\fonts\notosansjp-regular.ttf	0-4
csgo\panorama\fonts\notosanskr-bold.ttf	0-4
csgo\panorama\fonts\notosanskr-light.ttf	0-4
csgo\panorama\fonts\notosanskr-regular.ttf	0-4
csgo\panorama\fonts\notosanssc-bold.ttf	0-8
csgo\panorama\fonts\notosanssc-light.ttf	0-7
csgo\panorama\fonts\notosanssc-regular.ttf	0-7
csgo\panorama\fonts\notosanssymbols-regular.ttf	0-0
csgo\panorama\fonts\notosanstc-bold.ttf	0-5
csgo\pak01_541.vpk	51-56;99-102
csgo\panorama\fonts\notosanstc-light.ttf	0-5
csgo\panorama\fonts\notosanstc-regular.ttf	0-5
csgo\panorama\fonts\notosansthai-bold.ttf	0-0
csgo\panorama\fonts\notosansthai-light.ttf	0-0
csgo\panorama\fonts\notosansthai-regular.ttf	0-0
csgo\panorama\fonts\notoserif-bold.ttf	0-0
csgo\panorama\fonts\notoserif-boliitalic.ttf	0-0
csgo\panorama\fonts\notoserif-italic.ttf	0-0
csgo\panorama\fonts\notoserif-regular.ttf	0-0
csgo\panorama\fonts\stratum2.uifont	0-1
csgo\pak01_213.vpk	50-50
csgo\panorama\fonts\fonts.conf	0-0
core\panorama\fonts\conf.d\20-aliases-default-win.conf	0-0
core\panorama\fonts\conf.d\20-fix-cantarell.conf	0-0
csgo\pak01_190.vpk	8-10;14-15;18-18;32-33;35-35;38-39;75-77;97-98;100-101;103-104;106-106;108-108
core\panorama\fonts\conf.d\21-aliases-wine-win7-inf.conf	0-0
core\panorama\fonts\conf.d\30-non-latin-inf-win.conf	0-0
core\panorama\fonts\conf.d\41-repl-os-win.conf	0-0
core\panorama\fonts\conf.d\42-repl-global.conf	0-0
core\panorama\fonts\conf.d\43-repl-tt-traced-bitmap.conf	0-0
core\panorama\fonts\conf.d\44-repl-corrective.conf	0-0
core\panorama\fonts\conf.d\50-base-rendering-win7-winxp.conf	0-0
core\panorama\fonts\conf.d\60-group-non-tt-fonts.conf	0-0
core\panorama\fonts\conf.d\60-group-tt-fonts.conf	0-0
core\panorama\fonts\conf.d\61-group-non-tt-rendering-inf-7-xp-lin.conf	0-0
csgo\pak01_545.vpk	5-16;24-27;30-34;41-43;52-53;56-59;70-70;81-81;92-92
core\panorama\fonts\conf.d\61-group-tt-rendering-inf-7-xp.conf	0-0
core\panorama\fonts\conf.d\62-tt-monospace-rendering.conf	0-0
core\panorama\fonts\conf.d\62-tt-traced-bitmap-rendering.conf	0-0
core\panorama\fonts\conf.d\65-override.conf	0-0
core\panorama\fonts\conf.d\70-forced-synthetic.conf	0-0
core\panorama\fonts\conf.d\80-selective-rendering-inf-7-xp.conf	0-0
csgo\pak01_264.vpk	35-35;61-61;66-66;74-75
core\panorama\fonts\conf.d\80-selective-rendering-inf-win-lin.conf	0-0
core\panorama\fonts\conf.d\81-final-rendering-inf-7-xp.conf	0-0
core\panorama\fonts\conf.d\90-no-synthetic.conf	0-0
core\panorama\fonts\conf.d\90-reject.conf	0-0
csgo\pak01_281.vpk	55-59;64-64;68-68;75-75;80-81;87-87;96-96
core\panorama\fonts\conf.d\95-valve.conf	0-0
csgo\cfg\gamestate_integration_logitech.cfg	0-0
csgo\cfg\gamestate_integration_steelseries.cfg	0-0
csgo\pak01_187.vpk	1-1;3-6;41-42;46-46;48-50;56-56;61-61
csgo\pak01_220.vpk	35-35;37-39;47-48;52-52;57-58;61-61;64-64;66-71;73-73;75-75;77-78;80-80;85-86;93-93
csgo\pak01_306.vpk	60-62;94-94;98-99;111-111
csgo\shaders_pc_000.vpk	0-0;3-3;5-7;18-20;22-23;28-28;34-34;37-37;55-56;59-63;74-74;80-81;84-87;92-92;95-95
csgo\pak01_158.vpk	10-11;22-22;34-36;42-48;50-52;54-60;62-62;64-66;69-72;77-77
csgo\pak01_280.vpk	59-59;62-65;68-71
csgo\pak01_103.vpk	0-0;87-87;92-92;94-94
csgo\pak01_473.vpk	0-40
csgo\pak01_279.vpk	2-2;14-15;32-34;36-37;41-41;69-69
csgo\pak01_095.vpk	28-33;40-41;44-45;47-48;50-51;54-55;78-83
csgo\pak01_236.vpk	0-5
csgo\pak01_153.vpk	0-2;31-31;33-33;35-35;38-39;45-46;80-80;82-83;86-87;91-91;95-95;98-98;100-101;103-103;106-108;112-112
csgo\pak01_118.vpk	0-2;6-7;9-9;13-13;16-16;29-30;41-42;44-46;62-62;64-65
csgo\pak01_204.vpk	8-12;16-18;36-45;48-48;51-51;53-54;69-70
csgo\pak01_227.vpk	0-0;2-3;65-65;79-79
csgo\pak01_384.vpk	0-0;12-12;21-21;32-32;35-35;41-41;43-45;53-53;55-55;58-58
csgo\pak01_178.vpk	41-41;63-63;77-81;83-86;92-95
csgo\pak01_373.vpk	0-0;2-2;54-54
csgo\pak01_210.vpk	66-66;74-75;81-82
csgo\pak01_144.vpk	0-0;4-5;8-8;17-19;62-62;64-65;71-71;78-78;80-81;83-83;88-88
csgo\pak01_471.vpk	15-15;20-21;26-27;29-29;53-53;77-78
csgo\pak01_055.vpk	54-54
csgo\pak01_499.vpk	8-9;24-26;29-29;44-46;49-54;63-63;68-68;75-76;85-86
csgo\pak01_249.vpk	13-15;30-32;35-36;48-48;58-59;73-73;75-75;77-77;82-82;91-91;93-93;96-96;99-99
csgo\pak01_202.vpk	32-32;35-35;57-59;61-64;66-67;69-69;85-86;90-90
csgo\pak01_139.vpk	28-28;44-44;49-49;52-52;54-54
csgo\pak01_099.vpk	0-0;12-14;17-19;29-36;42-44;52-53;59-59;62-65
csgo\pak01_157.vpk	15-15
csgo\pak01_160.vpk	5-5;7-7;11-11;31-32;35-35;54-54;56-56;60-61;64-65;69-71;73-73;76-76;95-95
csgo\pak01_205.vpk	2-3;19-21;36-37;70-72;76-77;81-84
csgo\pak01_321.vpk	49-49;56-58;62-66
csgo\pak01_135.vpk	59-59;68-70;72-73
csgo\pak01_407.vpk	31-31;57-57;60-63;73-73;80-83;87-88;93-93
csgo\pak01_409.vpk	11-11;13-18;20-20;27-27;32-33;40-40;46-47;55-55;57-60;80-80;84-85;90-91;94-94
csgo\pak01_243.vpk	0-6
csgo\pak01_064.vpk	7-7;35-35
csgo\pak01_050.vpk	41-41;76-76
csgo\pak01_251.vpk	16-16;34-34;38-39;47-47;51-53;56-56;58-58;63-63;74-74;94-95
csgo\pak01_228.vpk	56-59;93-93
csgo\pak01_182.vpk	4-4;21-21;33-34;74-81;88-88;92-92;94-95
csgo\pak01_215.vpk	1-1;10-12;18-21;28-30;75-76;82-83
csgo\pak01_392.vpk	15-15;26-29;33-34;40-41;55-58;63-64;83-83;85-86;90-91
csgo\pak01_201.vpk	12-29;41-41;43-44;46-47;56-57;76-77;91-91
csgo\pak01_445.vpk	0-0;33-34;97-99;102-102;107-107;109-109;114-114
csgo\pak01_137.vpk	0-0;4-4;8-8;43-43;46-46;70-70;73-74;79-80;88-88;90-92
csgo\pak01_013.vpk	53-57;71-76
csgo\pak01_020.vpk	5-5;34-34;82-82
csgo\pak01_245.vpk	39-39;59-61;65-65;67-67;70-71;93-93
csgo\pak01_267.vpk	3-3;5-5;7-7;23-23;25-26;31-31;37-38;40-41;43-44;57-57;62-62;64-64
csgo\pak01_214.vpk	0-2;5-5;9-9
csgo\pak01_503.vpk	0-0;32-32;34-35;39-40;47-48;52-60;64-66;75-75;77-80;82-86;90-91;93-94
csgo\pak01_169.vpk	23-23;25-27;29-29;61-63;65-65;67-69
csgo\pak01_358.vpk	49-49;63-63;82-83;95-95
csgo\pak01_261.vpk	16-16;70-70;86-86;89-89
csgo\pak01_039.vpk	0-0;2-4;6-8;11-12;20-21;79-80
csgo\pak01_192.vpk	3-8;31-32;44-46;83-85
csgo\pak01_273.vpk	21-21;72-73;82-82;93-93;97-97;99-99
csgo\pak01_368.vpk	0-0;24-25;37-37;49-52;68-73;94-95
csgo\pak01_193.vpk	2-2;74-75;78-78;80-80;82-82;86-86
csgo\pak01_224.vpk	0-7;24-24;26-27;29-30;40-41;45-45;50-50;76-76
csgo\pak01_394.vpk	0-1;19-19;21-21;23-35;56-58;72-72
csgo\pak01_216.vpk	7-8;28-28;60-60;74-74
csgo\pak01_315.vpk	56-56;59-59;70-71;86-87;90-94;103-105
csgo\pak01_314.vpk	56-56;89-89;93-94;97-97
csgo\pak01_271.vpk	10-12;14-14;59-61;81-82;84-84
csgo\pak01_305.vpk	0-1;3-3;5-5;51-52
csgo\pak01_161.vpk	0-1;5-5;7-9;12-12;16-16;19-20;24-24;40-41;43-43;57-57;67-67;79-79;83-83;87-88;92-93;97-98
csgo\pak01_172.vpk	4-4;22-29;31-31;33-35;49-50;55-55;60-60;78-80;82-82
csgo\pak01_031.vpk	0-0;2-3;55-58;85-86;88-88;90-90;97-98;101-101
csgo\pak01_366.vpk	50-50;53-84;88-89
csgo\pak01_241.vpk	0-0;14-15;30-30;36-38;43-44;57-57;59-60;62-62;64-67;75-75;89-89
csgo\pak01_130.vpk	2-3;6-7;10-11;73-73;89-89;93-93
csgo\pak01_252.vpk	50-50;54-55;92-92
csgo\pak01_154.vpk	0-2;13-13;26-28;33-33;43-43;45-46;50-50;54-55;82-83
csgo\pak01_126.vpk	0-0;2-2;9-12;50-53;69-69;72-73;76-77
csgo\pak01_376.vpk	0-0;15-15;26-26;32-33;39-39;55-56;77-77;90-92
csgo\pak01_377.vpk	6-6;15-15;30-30;73-73
csgo\pak01_140.vpk	1-6;10-10;53-53;56-57;63-63;66-67;69-73;75-75
csgo\pak01_185.vpk	16-20;23-24;26-26;28-30;64-65;67-69;93-95
csgo\pak01_229.vpk	7-8;11-12;27-27;29-29;31-31;57-58;61-61;66-66;68-68;77-77;82-82;89-89;94-94;108-109;111-111;114-116
csgo\pak01_166.vpk	6-6;10-10;14-14;18-18;22-22;26-27;53-53;77-78;87-87;89-90;99-99
csgo\pak01_283.vpk	3-3;5-5;89-89
csgo\pak01_089.vpk	16-16;21-26;37-37;74-74;85-85
csgo\pak01_067.vpk	15-15;18-18;20-20;24-24;41-42;46-47;49-49
csgo\pak01_247.vpk	11-11;16-16;18-18;52-53;67-68;88-90
csgo\pak01_044.vpk	0-1;5-6;41-41;81-83;97-97;99-100
csgo\pak01_188.vpk	38-38;64-66;68-71;73-75;89-89;98-102
csgo\pak01_441.vpk	50-51;60-61;65-66;84-85
csgo\pak01_500.vpk	0-1;7-11;24-24;30-30;34-35;93-93
csgo\pak01_387.vpk	39-39;47-47;90-90
csgo\shaders_pc_002.vpk	0-1;4-4;9-9;16-16;45-45;53-53;72-72;123-125;127-128;139-139;166-167
csgo\pak01_003.vpk	16-16;51-51;65-66;73-74;79-107;110-111
csgo\pak01_259.vpk	0-0;6-6;56-58;61-61
csgo\pak01_268.vpk	19-20;23-24;26-26;31-32;53-54;63-63
csgo\pak01_045.vpk	20-20;22-23;41-41;44-44;46-46;71-71
csgo\pak01_412.vpk	0-0;3-5;7-8;11-11;30-30;34-35;81-81;86-89
csgo\pak01_390.vpk	3-5;45-45;47-51
csgo\pak01_246.vpk	0-0;12-12;15-15;52-62;65-65;67-67;70-70
csgo\pak01_462.vpk	32-33;49-49;57-57;61-61;90-91;93-97;111-114
csgo\pak01_088.vpk	39-39;54-55;59-59;102-102;104-104;107-109;113-113
csgo\pak01_253.vpk	10-10;23-24;26-26;36-36;69-69;75-76;79-81;88-88
csgo\pak01_109.vpk	13-14;17-18;34-34;38-39;42-47;49-49;51-51;56-57;87-87
csgo\pak01_150.vpk	17-22;24-24
csgo\pak01_083.vpk	74-74;78-78;80-82;85-86;89-89
csgo\pak01_433.vpk	11-11;13-14;16-18;65-67;69-69;84-84;88-88;90-91
csgo\pak01_174.vpk	70-70;74-75;80-80;82-82;86-87
csgo\pak01_211.vpk	5-10;14-16;20-20;51-51
csgo\pak01_325.vpk	44-44;73-74;77-77;82-82;85-86;97-97
csgo\pak01_198.vpk	1-1;38-39;62-62;89-89
csgo\pak01_359.vpk	54-54;66-66;73-73
csgo\pak01_313.vpk	13-14;27-28;30-30;35-37;44-44;60-60;66-66
csgo\pak01_354.vpk	19-20;23-24;30-31;49-52
csgo\pak01_257.vpk	0-0;19-19;37-37;48-50;53-54;56-56;58-60;64-65;67-67;84-85;92-97;99-99;113-113
csgo\pak01_041.vpk	9-10;45-46;78-79;88-88
csgo\pak01_285.vpk	33-33;37-38;93-93;95-97
csgo\pak01_181.vpk	76-77;97-98
csgo\pak01_353.vpk	0-1;3-3;26-26;32-32;36-36;48-48;51-51;97-98
csgo\pak01_119.vpk	74-74;76-77;81-81;83-83;92-92
csgo\pak01_191.vpk	45-45;55-57;60-60;62-62;64-64;71-71;73-73;84-84;87-87
csgo\pak01_040.vpk	0-0;16-16;20-23;26-27;45-47;81-82
csgo\pak01_046.vpk	51-51;81-84
csgo\pak01_266.vpk	0-1;21-21;29-30;34-35;47-48;66-66
csgo\pak01_197.vpk	28-28;31-34;53-54;60-63;93-93
csgo\pak01_196.vpk	15-15;17-17;34-35;58-61;65-65;69-70;92-94;97-99
csgo\pak01_042.vpk	0-1;21-21;25-26;28-28;32-32;40-41
csgo\pak01_223.vpk	38-39;47-56
csgo\pak01_086.vpk	50-50;67-67;71-71;79-80
csgo\pak01_026.vpk	38-39;42-42
csgo\pak01_091.vpk	21-21;23-23;25-26;28-30;32-32;37-38;50-56;77-77
csgo\pak01_286.vpk	11-12;35-37;52-52;55-56
csgo\pak01_256.vpk	89-89;92-92;96-97
csgo\pak01_110.vpk	23-25;97-97;99-100
csgo\pak01_194.vpk	26-29;67-67;78-78;101-104
csgo\pak01_145.vpk	20-20;92-92;100-100;104-104;107-108;117-119
csgo\pak01_111.vpk	31-32;56-56;58-58
csgo\pak01_147.vpk	25-25;32-32;36-36;81-82;94-94
csgo\pak01_141.vpk	20-22;29-30;33-34;57-57;71-74
csgo\pak01_498.vpk	19-38
csgo\pak01_309.vpk	0-0;18-18
csgo\pak01_233.vpk	82-82
csgo\pak01_304.vpk	1-1;4-5;7-7;63-63
csgo\pak01_149.vpk	17-17;33-33;49-49;60-61;99-99;101-102
csgo\pak01_260.vpk	52-52;66-67;75-76
csgo\pak01_408.vpk	49-50;61-61;63-64;67-67;69-69;71-73;77-78
csgo\pak01_232.vpk	64-64;68-68
csgo\pak01_125.vpk	88-89
csgo\pak01_007.vpk	0-0;6-7;10-11;65-67;69-69;71-73;75-75;87-87
csgo\pak01_378.vpk	46-48;53-53;91-91
csgo\pak01_391.vpk	29-32;36-36;38-39;50-52;55-56;69-73
csgo\pak01_116.vpk	65-66;72-72;75-76;82-82;85-85;87-87
csgo\pak01_235.vpk	75-75
csgo\pak01_447.vpk	46-47;49-49;73-74;77-77;80-80
csgo\pak01_226.vpk	26-26;28-28;30-30;32-33;82-82
csgo\pak01_176.vpk	68-68;107-108
csgo\pak01_539.vpk	44-44;76-76;85-86;89-90;100-100
csgo\pak01_048.vpk	47-47;52-53;56-57
csgo\pak01_164.vpk	41-41;44-45;49-49;60-60;100-101
csgo\pak01_221.vpk	7-8;13-13;63-65;68-68;83-85;93-94
csgo\pak01_427.vpk	33-34;52-52;57-57;65-65;69-76
csgo\pak01_106.vpk	53-53;76-77;81-81;84-84;91-91
csgo\pak01_367.vpk	1-1;15-15;18-19;21-22;25-26;28-29;31-31;46-46
csgo\pak01_278.vpk	28-28;38-38;43-45;52-53;65-66
csgo\pak01_155.vpk	4-4;6-6;18-18;22-22;48-49;51-51;53-63
csgo\pak01_123.vpk	50-52;57-57;62-63;68-68;70-70;73-74;79-79;84-85;95-95
csgo\pak01_009.vpk	63-64;102-104;118-118;120-120
csgo\pak01_360.vpk	39-40;59-60
csgo\pak01_272.vpk	66-66;81-84;86-87;89-89
csgo\pak01_027.vpk	0-4;6-6;8-8;10-13;18-18;21-22;27-27;58-58;73-73;78-78;81-81
csgo\pak01_138.vpk	10-11;31-31
csgo\pak01_024.vpk	34-35;74-74;86-87;89-89
csgo\pak01_122.vpk	76-76
csgo\pak01_237.vpk	9-10
csgo\pak01_472.vpk	14-14;16-16;35-35;37-37;54-54
csgo\pak01_143.vpk	9-9;13-13;18-18;22-23;27-27;31-31;36-36;39-40;44-45;53-54;57-58;62-63;65-65;69-70;73-74;78-78;81-81;84-84;87-88
csgo\pak01_142.vpk	67-69;92-92;98-99
csgo\pak01_087.vpk	1-2;27-27;45-46;49-49;53-54;57-58;61-62;76-76;83-83;87-87
csgo\pak01_152.vpk	0-0;9-9;13-14;18-18;23-24;28-28;31-33;36-36;39-40;43-43;46-46;49-50;58-58;61-62
csgo\pak01_081.vpk	39-39;43-43;46-46;87-87;98-98
csgo\pak01_212.vpk	0-0;98-98
csgo\pak01_156.vpk	33-33;47-48;50-50;53-53;56-58;62-62;65-65;75-75;83-83;92-93
csgo\pak01_173.vpk	0-0;5-5;18-23;66-66;68-68
csgo\pak01_316.vpk	81-81
csgo\pak01_544.vpk	0-9
csgo\pak01_102.vpk	44-44;62-62;81-81
csgo\pak01_107.vpk	78-78
csgo\pak01_339.vpk	15-15;26-27;52-52
csgo\pak01_475.vpk	93-94
csgo\pak01_022.vpk	2-3;47-47;76-76;81-81;83-83
csgo\pak01_307.vpk	0-0;22-22
csgo\pak01_218.vpk	0-0;4-5;37-37
csgo\pak01_543.vpk	87-87
csgo\pak01_375.vpk	6-6;23-24;54-54;65-65
csgo\pak01_000.vpk	0-0;18-18;58-59;62-63;66-68;71-72;75-77;79-79
csgo\pak01_171.vpk	34-34;37-38;50-50;55-56;77-77;79-79;83-83;92-92;95-95
csgo\pak01_085.vpk	47-48;51-51;54-56;58-60;63-64;66-68;70-71;74-75;78-78;81-81;84-84;86-99
csgo\pak01_476.vpk	26-27;30-31
csgo\pak01_129.vpk	0-0;30-30;35-35;49-50;64-64;81-81;93-93
csgo\pak01_165.vpk	9-10;12-14;54-54;57-58;62-62
csgo\pak01_170.vpk	26-26;51-51;53-53;57-57;60-61;65-65;68-71
csgo\pak01_258.vpk	0-0;9-10;20-20;30-31;41-41;43-44;47-47;50-50
csgo\cfg\autoexec.cfg	0-0
csgo\pak01_080.vpk	55-55;58-59;62-62;64-68;73-90;93-94;97-98
csgo\panorama\videos\intro.webm	0-5
csgo\pak01_263.vpk	19-20;23-23;31-32;47-48;88-89
csgo\pak01_371.vpk	41-41
csgo\pak01_504.vpk	3-3;31-31
csgo\pak01_508.vpk	62-62;78-78;89-89
csgo\pak01_512.vpk	78-78
csgo\pak01_511.vpk	95-95
csgo\pak01_513.vpk	77-77
csgo\pak01_506.vpk	92-93
csgo\pak01_495.vpk	71-73;78-80;85-86;93-95
csgo\pak01_474.vpk	92-93
csgo\pak01_446.vpk	10-11;14-14;46-47;63-63;65-67;71-71;84-85
csgo\pak01_450.vpk	52-54
csgo\pak01_312.vpk	89-90;92-94
csgo\pak01_438.vpk	15-16;20-21;24-25;29-30;34-35;38-39;57-57;60-60;62-62;85-85
csgo\pak01_357.vpk	30-30;59-59;67-68;89-90
csgo\cfg\gamemode_competitive.cfg	0-0
csgo\cfg\gamemode_competitive_offline.cfg	0-0
csgo\cfg\server_default.cfg	0-0
csgo\pak01_134.vpk	24-24;51-51;71-71
csgo\pak01_270.vpk	92-93
csgo\pak01_291.vpk	41-41;78-78
csgo\pak01_244.vpk	4-5;24-26;46-47;59-59
csgo\pak01_035.vpk	0-1
csgo\pak01_540.vpk	50-50
csgo\pak01_311.vpk	40-40;82-82;91-91
csgo\pak01_177.vpk	0-0;3-4;7-9;11-13;16-17;20-20;33-34;36-36;38-38;41-42;51-51;55-55;58-58;61-61;69-69;71-71
csgo\pak01_239.vpk	48-48;54-54;68-69;85-85
csgo\pak01_132.vpk	0-0;4-5;9-10;19-19;35-35;54-54
csgo\pak01_136.vpk	0-0;18-18;28-29;42-42;59-59;69-70;84-84;101-101
csgo\pak01_242.vpk	61-62;89-89
csgo\pak01_090.vpk	0-0;16-17;33-34;79-79;88-88
csgo\pak01_104.vpk	55-55;58-59;65-65;68-69;75-75;78-79;85-85
csgo\pak01_435.vpk	14-14;24-25;47-47;68-69
csgo\pak01_133.vpk	0-0;11-11;37-37;51-51;67-67;81-81
csgo\pak01_265.vpk	17-17;35-35
csgo\pak01_124.vpk	0-0
csgo\pak01_128.vpk	9-10;22-23;42-42;52-52;54-55;68-68;86-86
csgo\pak01_079.vpk	39-39;43-44;48-49;65-65
csgo\pak01_290.vpk	51-51;66-66
csgo\pak01_206.vpk	34-34;37-38;48-48;67-67;71-72
csgo\pak01_043.vpk	19-19;29-30;33-34;37-38;44-44
csgo\pak01_146.vpk	68-69;83-83
csgo\pak01_054.vpk	43-45;48-49;63-63;67-67;86-86
csgo\pak01_442.vpk	0-0;12-12;29-29;38-39
csgo\pak01_101.vpk	61-61;77-77
csgo\pak01_120.vpk	46-47;50-50
csgo\pak01_092.vpk	8-9;13-15;36-36;40-41;43-43
csgo\pak01_374.vpk	20-20;59-59
csgo\pak01_326.vpk	49-49
csgo\pak01_059.vpk	13-13;31-31
csgo\addoninfo.txt	0-0
csgo\maps\	0-0
csgo\pak01_254.vpk	77-77;81-81
csgo\pak01_148.vpk	0-0;18-18
csgo\pak01_372.vpk	45-45
core\maps\	0-0
csgo\pak01_255.vpk	3-3;10-10;21-21;23-23;25-25;35-35
csgo\maps\ui\csgo_ui_particle_scene_panel_empty.vpk	0-0
csgo\maps\graphics_settings.vpk	0-4
csgo\maps\de_cache_vanity.vpk	0-16
csgo\maps\ui\buy_menu.vpk	0-0
csgo\maps\ui	0-0
csgo\maps\ui\xpshop_item.vpk	0-1
csgo\maps\ui\match_mvp.vpk	0-0
csgo\maps\ui\icon_generation_basic_nuke_bombsitea.vpk	0-0
csgo\shaders_pc_001.vpk	0-1;16-16;30-30;38-38
csgo\pak01_121.vpk	59-59
csgo\pak01_432.vpk	0-1;18-19;39-40;56-56;73-74;90-91
csgo\pak01_420.vpk	0-2;5-6;24-25;63-64;81-83
csgo\pak01_428.vpk	0-0;50-51;63-65;69-69
csgo\pak01_418.vpk	43-43;46-47;61-62;73-74;83-83
csgo\pak01_422.vpk	16-17;33-33;43-43
csgo\pak01_419.vpk	0-0;5-6;11-11;50-50;68-68;72-73;93-96
csgo\pak01_425.vpk	0-0;2-5;7-7;11-19;24-30;32-33;40-44;48-49;55-55;63-64;80-80
csgo\pak01_439.vpk	67-68;77-77;81-81
csgo\pak01_444.vpk	37-38;46-47;50-52
csgo\pak01_184.vpk	33-33
csgo\pak01_416.vpk	0-0
csgo\pak01_421.vpk	0-1;21-22;40-41;59-60
csgo\pak01_284.vpk	58-58
csgo\pak01_430.vpk	48-49;67-67;92-93
csgo\pak01_431.vpk	0-0;21-21;42-42;54-55;76-77
csgo\pak01_440.vpk	0-1;19-20
csgo\pak01_426.vpk	9-10;16-16;19-19;24-24;26-27
csgo\pak01_167.vpk	0-1;4-5;11-12;16-17;20-22;60-61;79-80
csgo\pak01_436.vpk	39-41;45-48
csgo\pak01_424.vpk	23-24;27-30;35-37
csgo\pak01_179.vpk	39-42;88-88;95-95
csgo\pak01_021.vpk	57-58;80-80;82-83;88-89
csgo\pak01_497.vpk	61-61
csgo\pak01_217.vpk	67-67
'@

# =====================================================================
#  ESAS HISSE
# =====================================================================
$SteamDirs = @(Find-SteamDirs)
$Game = Find-Game $SteamDirs

if ($Mode -eq 'iz') { Run-Trace; return }
if ($Mode -eq 'image') {
  if (-not $IsAdmin) { Write-Host 'XETA: Administrator kimi acin.' -ForegroundColor Red; return }
  Set-Reg 'HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard' 'EnableVirtualizationBasedSecurity' 0 'DWord'
  Set-Reg 'HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard\Scenarios\HypervisorEnforcedCodeIntegrity' 'Enabled' 0 'DWord'
  Write-Host 'VBS / Memory Integrity sonduruldu. Yeniden baslatdiqdan sonra Cloud Update-de image-i SAXLAYIN.' -ForegroundColor Green
  return
}

if ($Mode -eq 'play') {
  $m = New-Object System.Threading.Mutex($false, 'Global\cs2opt_daemon')
  $free = $false; try { $free = $m.WaitOne(0) } catch [System.Threading.AbandonedMutexException] { $free = $true } catch { $free = $false }
  if ($free) { $m.ReleaseMutex(); $m.Dispose(); Start-Daemon; Start-Sleep -Seconds 3 }
  if ($SteamDirs.Count -gt 0) { Start-Process -FilePath (Join-Path $SteamDirs[0] 'steam.exe') -ArgumentList @('-applaunch', '730') }
  else { Start-Process 'steam://rungameid/730' }
  return
}

# --- Arxa plan xidmeti (boot task) ---
$Mutex = New-Object System.Threading.Mutex($false, 'Global\cs2opt_daemon')
$got = $false; try { $got = $Mutex.WaitOne(0) } catch [System.Threading.AbandonedMutexException] { $got = $true } catch { $got = $false }
if (-not $got) { return }

Set-Content -LiteralPath $LogFile -Value ("=== CS2 Optimizer  {0}  {1} ===" -f $env:COMPUTERNAME, (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')) -Encoding ASCII
Log ("Istifadeci: {0}  admin={1}  system={2}" -f $Me.Name, $IsAdmin, $IsSystem)

# Oyun diski gec qosula biler: 5 deqiqeye qeder gozle
$t0 = Get-Date
while (-not $Game -and ((Get-Date) - $t0).TotalSeconds -lt 300) { Start-Sleep -Seconds 10; $SteamDirs = @(Find-SteamDirs); $Game = Find-Game $SteamDirs }
if (-not $Game) { Log 'XETA: CS2 tapilmadi, cixilir'; Push-Log; return }
$Cs2Exe = Join-Path $Game 'bin\win64\cs2.exe'
Log "Steam: $($SteamDirs -join ', ')"
Log "CS2: $Game"

$SI = Get-SysInfo
Log ("Sistem: {0} (driver {1}) | {2}x{3} {6}Hz | {4} ({5})" -f $SI.GpuName, $SI.Driver, $SI.W, $SI.H, $SI.CpuName, $SI.CpuType, $SI.Hz)
$VideoText = Get-VideoCfgText

Apply-MachineTweaks
Write-Autoexec
Apply-VideoCfg
Apply-Nvidia

# Evvelceden oxuma (ayri axinda)
$PwPs = $null; $PwH = $null
if ($PrewarmOn) {
  $lines = Get-PrewarmLines
  $delay = Get-Random -Minimum 0 -Maximum ([Math]::Max(1, $PrewarmDelay + 1))
  $PwPs = [PowerShell]::Create()
  [void]$PwPs.AddScript($PrewarmScript).AddArgument($Game).AddArgument([string[]]$lines).AddArgument($delay)
  $PwH = $PwPs.BeginInvoke()
  Log "Evvelceden oxuma basladi ($delay san sonra)"
}

$DoneCtx = New-Object 'System.Collections.Generic.HashSet[string]'
$Cs2Running = $false
$tick = 0
Push-Log
while ($true) {
  foreach ($ctx in (Get-UserContexts)) {
    if ($DoneCtx.Contains($ctx.Key)) { continue }
    [void]$DoneCtx.Add($ctx.Key)
    Apply-UserTweaks $ctx
    Restore-Shader $ctx
    Push-Log
  }
  Apply-VideoCfg
  if ($PwH -and $PwH.IsCompleted) { try { Log ('Evvelceden oxuma: ' + ($PwPs.EndInvoke($PwH) -join ' ')) } catch { Log 'Evvelceden oxuma: xeta' }; $PwPs.Dispose(); $PwH = $null; Push-Log }
  $p = Get-Process -Name cs2 -ErrorAction SilentlyContinue
  if ($p -and -not $Cs2Running) { $Cs2Running = $true; Log 'CS2 acildi' }
  elseif (-not $p -and $Cs2Running) {
    $Cs2Running = $false; Log 'CS2 baglandi'
    Start-Sleep -Seconds 3
    foreach ($ctx in (Get-UserContexts)) { Collect-Shader $ctx }
    Push-Log
  }
  Start-Sleep -Seconds 3
  $tick++
  if ($tick % 200 -eq 0) { $SteamDirs = @(Find-SteamDirs) }
}
