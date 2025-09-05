# Send.ps1 — PS5-safe
# GUI picker (Add Files / Add Folder / Remove / Clear / Start Transfer / Cancel)
# Live rclone stats, per-item logs + final total summary log

param([switch]$Pick)

# --- force STA so WinForms/WPF work even if launcher forgot -STA ---
if ([System.Threading.Thread]::CurrentThread.ApartmentState -ne 'STA') {
    $args = @('-NoLogo','-NoProfile','-ExecutionPolicy','Bypass','-STA','-File',"`"$PSCommandPath`"")
    if ($Pick) { $args += '-Pick' }
    $p = Start-Process -FilePath 'powershell.exe' -ArgumentList $args -Wait -PassThru
    exit $p.ExitCode
}

# ---------- paths ----------
$Root      = Split-Path -Parent $MyInvocation.MyCommand.Path
$CfgFile   = Join-Path $Root 'send_config.txt'
$Rclone    = Join-Path $Root 'rclone.exe'
$LogsDir   = Join-Path $Root 'logs\send_logs'
$LaunchDir = Join-Path $Root 'logs\launch_logs'
New-Item -ItemType Directory -Force -Path $LogsDir,$LaunchDir | Out-Null

# ---------- helpers ----------
function Get-Config($path){
  $h=@{}
  if (-not (Test-Path $path)) { return $h }
  Get-Content $path | ForEach-Object {
    $_ = $_.Trim()
    if (-not $_ -or $_.StartsWith('#')) { return }
    $kv = $_ -split '=',2
    if($kv.Count -eq 2){
      $key = $kv[0].Trim().ToLower()
      $val = ($kv[1] -split '#',2)[0].Trim()   # strip inline comments
      if($val -ne ''){ $h[$key] = $val }
    }
  }; $h
}
function GetOrDefault([hashtable]$h,[string]$k,[string]$def){
  if($h.ContainsKey($k) -and $h[$k]){ $h[$k] } else { $def }
}
function Convert-SizeToBytes([string]$s){
  if (-not $s) { return 0 }
  $m = [regex]::Match($s.Trim(), '([0-9]*\.?[0-9]+)\s*(GiB|MiB|KiB|GB|MB|KB|B)')
  if(-not $m.Success){ return 0 }
  $v = [double]$m.Groups[1].Value
  switch ($m.Groups[2].Value) {
    'GiB' { [long]($v * 1024*1024*1024) }
    'MiB' { [long]($v * 1024*1024) }
    'KiB' { [long]($v * 1024) }
    'GB'  { [long]($v * 1e9) }
    'MB'  { [long]($v * 1e6) }
    'KB'  { [long]($v * 1e3) }
    'B'   { [long]$v }
    default { 0 }
  }
}
function Format-MiBs([double]$bps){ "{0:N2}" -f ($bps / 1MB) }
function Format-Gbps([double]$bps){ "{0:N2}" -f (($bps * 8) / 1e9) }

# ---------- GUI picker (single window) ----------
function TK-PickInteractive {
  try {
    Add-Type -AssemblyName System.Windows.Forms | Out-Null
    [System.Windows.Forms.Application]::EnableVisualStyles()

    $form = New-Object Windows.Forms.Form
    $form.Text = "TransferKit - Select files/folders to send"
    $form.Width = 780; $form.Height = 420
    $form.StartPosition = 'CenterScreen'

    $lbl = New-Object Windows.Forms.Label
    $lbl.Text = "Items to send:"
    $lbl.AutoSize = $true; $lbl.Left = 12; $lbl.Top = 12
    $form.Controls.Add($lbl)

    $list = New-Object Windows.Forms.ListBox
    $list.Left = 12; $list.Top = 32; $list.Width = 740; $list.Height = 280
    $list.HorizontalScrollbar = $true
    $list.SelectionMode = 'MultiExtended'
    $form.Controls.Add($list)

    $btnAddFiles  = New-Object Windows.Forms.Button
    $btnAddFiles.Text="Add Files";  $btnAddFiles.Left=12;  $btnAddFiles.Top=320; $btnAddFiles.Width=110
    $btnAddFolder = New-Object Windows.Forms.Button
    $btnAddFolder.Text="Add Folder";$btnAddFolder.Left=132; $btnAddFolder.Top=320; $btnAddFolder.Width=110
    $btnRemove    = New-Object Windows.Forms.Button
    $btnRemove.Text="Remove Selected";$btnRemove.Left=252;$btnRemove.Top=320;$btnRemove.Width=140
    $btnClear     = New-Object Windows.Forms.Button
    $btnClear.Text="Clear"; $btnClear.Left=402; $btnClear.Top=320; $btnClear.Width=80
    $btnStart     = New-Object Windows.Forms.Button
    $btnStart.Text="Start Transfer"; $btnStart.Left=492; $btnStart.Top=320; $btnStart.Width=130
    $btnCancel    = New-Object Windows.Forms.Button
    $btnCancel.Text="Cancel"; $btnCancel.Left=632; $btnCancel.Top=320; $btnCancel.Width=120

    $form.Controls.AddRange(@($btnAddFiles,$btnAddFolder,$btnRemove,$btnClear,$btnStart,$btnCancel))

    $enableStart = {
      $btnStart.Enabled = ($list.Items.Count -gt 0)
    }
    $form.Add_Shown({ & $enableStart.Invoke() })

    $btnAddFiles.Add_Click({
      $dlg = New-Object System.Windows.Forms.OpenFileDialog
      $dlg.Title="Select files to send"
      $dlg.Filter="All files (*.*)|*.*"
      $dlg.Multiselect=$true
      if ($dlg.ShowDialog() -eq 'OK') {
        foreach($p in $dlg.FileNames){ if (-not $list.Items.Contains($p)) { [void]$list.Items.Add($p) } }
        & $enableStart.Invoke()
      }
    })

    $btnAddFolder.Add_Click({
      $f = New-Object System.Windows.Forms.FolderBrowserDialog
      $f.Description = "Select a folder to send"
      if ($f.ShowDialog() -eq 'OK') {
        if (-not $list.Items.Contains($f.SelectedPath)) { [void]$list.Items.Add($f.SelectedPath) }
        & $enableStart.Invoke()
      }
    })

    $btnRemove.Add_Click({
      foreach ($i in @($list.SelectedItems)) { $list.Items.Remove($i) }
      & $enableStart.Invoke()
    })

    $btnClear.Add_Click({
      $list.Items.Clear()
      & $enableStart.Invoke()
    })

    $result = @()
    $btnStart.Add_Click({
      $result = @($list.Items)
      $form.DialogResult = [System.Windows.Forms.DialogResult]::OK
      $form.Close()
    })
    $btnCancel.Add_Click({
      $result = @()
      $form.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
      $form.Close()
    })

    [void]$form.ShowDialog()
    return $result
  } catch {
    return @()  # caller will fall back to console prompt
  }
}

# Console fallback (if GUI not available)
function TK-PickConsole {
  Write-Host "`nGUI picker unavailable." -ForegroundColor Yellow
  Write-Host "Enter one or more FULL paths (separate with ; or ,). Blank line to finish." -ForegroundColor Yellow
  $list=@()
  while ($true) {
    $line = Read-Host "Path(s)"
    if (-not $line) { break }
    $parts = $line -split '[;,]' | ForEach-Object { $_.Trim() } | Where-Object { $_ }
    foreach ($p in $parts) {
      if (Test-Path -LiteralPath $p) { $list += (Resolve-Path -LiteralPath $p).Path }
      else { Write-Host "Not found: $p" -ForegroundColor Red }
    }
  }
  $list | Select-Object -Unique
}

# ---------- load config ----------
$cfg        = Get-Config $CfgFile
$TargetIP   = GetOrDefault $cfg 'target_ip' ''
$Port       = [int](GetOrDefault $cfg 'port' '8080')
$User       = GetOrDefault $cfg 'user' 'rc'
$Pass       = GetOrDefault $cfg 'pass' 'rcpass'
$SourceCfg  = GetOrDefault $cfg 'source' ''     # optional default source
$DestRoot   = GetOrDefault $cfg 'dest_root' ''
$Transfers  = [int](GetOrDefault $cfg 'transfers' '8')
$Streams    = [int](GetOrDefault $cfg 'streams'   '16')
$Checkers   = [int](GetOrDefault $cfg 'checkers'  '16')
$Checksum   = (GetOrDefault $cfg 'checksum' 'false') -match '^(1|true|yes)$'
$Bwlimit    = GetOrDefault $cfg 'bwlimit' '0'
$PauseEnd   = (GetOrDefault $cfg 'pause_on_finish' 'false') -match '^(1|true|yes)$'

# ---------- sanity ----------
if(-not (Test-Path $Rclone)){ Write-Host "Missing rclone.exe" -ForegroundColor Red; if($PauseEnd){Read-Host "Enter"}; exit 1 }
if([string]::IsNullOrEmpty($TargetIP)){ Write-Host "target_ip is empty in send_config.txt" -ForegroundColor Red; if($PauseEnd){Read-Host "Enter"}; exit 1 }

# ---------- collect sources (CLI args > config > GUI > console) ----------
$sources = @()
if ($args.Count -gt 0) {
  $sources = $args | ForEach-Object { if (Test-Path -LiteralPath $_) { (Resolve-Path -LiteralPath $_).Path } }
} elseif ($Pick -or [string]::IsNullOrEmpty($SourceCfg)) {
  $sources = TK-PickInteractive
  if (-not $sources -or $sources.Count -eq 0) { $sources = TK-PickConsole }
} else {
  $sources = @($SourceCfg)
}
$sources = $sources | Where-Object { $_ -and (Test-Path $_) }
if (-not $sources){ Write-Host "No valid source paths selected." -ForegroundColor Yellow; exit 1 }

# ---------- reachability ----------
Write-Host ("Checking receiver {0}:{1} ..." -f $TargetIP,$Port) -ForegroundColor DarkCyan
$oldPref = $ProgressPreference; $ProgressPreference = 'SilentlyContinue'
$tcpOk = $false
try {
  $tcpOk = Test-NetConnection -ComputerName $TargetIP -Port $Port -WarningAction SilentlyContinue |
           Select-Object -ExpandProperty TcpTestSucceeded
} catch { $tcpOk = $false }
$ProgressPreference = $oldPref
if ($tcpOk) { Write-Host "Receiver is reachable." -ForegroundColor Green }
else { Write-Host ("Can't reach http://{0}:{1}  (is the Receiver running?)" -f $TargetIP,$Port) -ForegroundColor Red; if ($PauseEnd) { Read-Host "Enter" }; exit 1 }

# ---------- ensure named remote ----------
& $Rclone config delete rcweb 2>$null | Out-Null
& $Rclone config create rcweb webdav url ("http://{0}:{1}" -f $TargetIP,$Port) user $User pass $Pass --non-interactive | Out-Null

# ---------- run copies ----------
$RunStamp     = Get-Date -Format 'yyyyMMdd-HHmmss'
$overallCodes = @()
$totalBytes   = [long]0
$globalStart  = Get-Date

foreach ($src in $sources) {
  $isDir = Test-Path $src -PathType Container
  $name  = Split-Path $src -Leaf

  # destination (preserve top-level folder when sending a folder)
  if ([string]::IsNullOrEmpty($DestRoot)) {
    if ($isDir) { $dest = "rcweb:/$name" } else { $dest = "rcweb:/" }
  } else {
    if ($isDir) { $dest = "rcweb:/$DestRoot/$name" } else { $dest = "rcweb:/$DestRoot" }
  }

  $copyLog   = Join-Path $LogsDir   ("rclone-copy-{0}-{1}.log" -f $RunStamp, ($name -replace '[^\w\.-]','_'))
  $launchLog = Join-Path $LaunchDir ("send-launch-{0}.log"     -f $RunStamp)
  "[$(Get-Date)] SEND start  src='$src'  dest='$dest'" | Tee-Object -FilePath $launchLog | Out-Null

  # concurrency per item
  if ($isDir) { $t = $Transfers; $s = $Streams } else { $t = 1; $s = 32 }

  $flags = @(
    '--progress',
    '--stats','1s','--stats-one-line','--stats-one-line-date',
    '--transfers', "$t",
    '--multi-thread-streams', "$s",
    '--checkers', "$Checkers",
    '--log-file', "$copyLog",
    '--log-level', 'INFO'
  )
  if($Checksum){ $flags += '--checksum' }
  if($Bwlimit -and $Bwlimit -ne '0'){ $flags += @('--bwlimit',"$Bwlimit") }

  Write-Host ("Sending '{0}' -> {1}" -f $src,$dest) -ForegroundColor Cyan
  $start = Get-Date
  & $Rclone copy "$src" "$dest" @flags
  $code  = $LASTEXITCODE
  $end   = Get-Date
  $overallCodes += $code

  # parse final transferred bytes from log
  $tail = Get-Content $copyLog -Tail 400
  $last = ($tail | Select-String -SimpleMatch 'Transferred:' | Select-Object -Last 1).Line
  $time = ($tail | Select-String -SimpleMatch 'Elapsed time:' | Select-Object -Last 1).Line
  if (-not $time) { $elapsed = New-TimeSpan -Start $start -End $end; $time = "Elapsed time: {0:g}" -f $elapsed }

  $bytesThis = 0
  if ($last) {
    $m = [regex]::Match($last, 'Transferred:\s*([0-9\.\sA-Za-z]+)\s*/')
    if ($m.Success) { $bytesThis = Convert-SizeToBytes $m.Groups[1].Value }
  }
  if (-not $bytesThis) {
    if ($isDir) { $bytesThis = ((Get-ChildItem -LiteralPath $src -Recurse -File -ErrorAction SilentlyContinue | Measure-Object -Sum Length).Sum) }
    else { $bytesThis = (Get-Item -LiteralPath $src).Length }
  }
  $totalBytes += [long]$bytesThis

  Write-Host ("ExitCode: {0}" -f $code)
  Write-Host ("Log: {0}" -f $copyLog) -ForegroundColor DarkCyan
  if ($last) { Write-Host ("Summary : {0}" -f $last.Trim()) -ForegroundColor Green }
  Write-Host ("Duration: {0}" -f $time.Trim()) -ForegroundColor Green
}

$globalEnd   = Get-Date
$elapsedAll  = New-TimeSpan -Start $globalStart -End $globalEnd
$bytesPerSec = if ($elapsedAll.TotalSeconds -gt 0) { $totalBytes / $elapsedAll.TotalSeconds } else { 0 }

# --- FINAL SUMMARY (on screen + saved to file) ---
$summaryFile = Join-Path $LogsDir ("send-summary-{0}.log" -f $RunStamp)
$summary = @()
$summary += "================ TOTAL SUMMARY ================"
$summary += ("Items     : {0}" -f $sources.Count)
$summary += ("Data      : {0:N2} GiB" -f ($totalBytes / 1GB))
$summary += ("Elapsed   : {0:g}" -f $elapsedAll)
$summary += ("Avg Speed : {0} MiB/s  ({1} Gbps)" -f (Format-MiBs $bytesPerSec), (Format-Gbps $bytesPerSec))
$summary += "=============================================="
$summary | Tee-Object -FilePath $summaryFile | ForEach-Object { Write-Host $_ -ForegroundColor Cyan }

$overall = ($overallCodes | Measure-Object -Maximum).Maximum
if($PauseEnd){ Read-Host "Press Enter to close" }
exit ([int]$overall)
