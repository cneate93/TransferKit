# Receiver.ps1  — PS5-safe

$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$CfgFile = Join-Path $Root 'receiver_config.txt'
$Rclone  = Join-Path $Root 'rclone.exe'
$RecvLogDir   = Join-Path $Root 'logs\receiver_logs'
$LaunchLogDir = Join-Path $Root 'logs\launch_logs'
New-Item -ItemType Directory -Force -Path $RecvLogDir,$LaunchLogDir | Out-Null

function Get-Config($path){
  $h=@{}
  Get-Content $path | ForEach-Object {
    $_ = $_.Trim()
    if (-not $_ -or $_.StartsWith('#')) { return }
    $kv = $_ -split '=',2
    if($kv.Count -eq 2){ $h[$kv[0].Trim().ToLower()] = $kv[1].Trim() }
  }
  $h
}

if(-not (Test-Path $CfgFile)){ Write-Host "Missing $CfgFile" -ForegroundColor Red; Pause; exit 1 }
$cfg = Get-Config $CfgFile

function GetOrDefault([hashtable]$h,[string]$k,[string]$def){
  if($h.ContainsKey($k) -and $h[$k] -ne $null -and $h[$k].ToString() -ne ''){ return $h[$k] } else { return $def }
}

$BindIP  = GetOrDefault $cfg 'bind_ip'       '0.0.0.0'
$PortStr = GetOrDefault $cfg 'port'          '8080'
[int]$Port = $PortStr
$User    = GetOrDefault $cfg 'user'          'rc'
$Pass    = GetOrDefault $cfg 'pass'          'rcpass'
$RecvDir = GetOrDefault $cfg 'receive_dir'   'C:\ReceivedFiles'
$KeepStr = GetOrDefault $cfg 'keep_window_open' 'true'
$KeepOpen = $KeepStr -match '^(1|true|yes)$'

if(-not (Test-Path $Rclone)){ Write-Host "Missing rclone.exe" -ForegroundColor Red; if($KeepOpen){Read-Host "Press Enter"}; exit 1 }
New-Item -ItemType Directory -Force -Path $RecvDir | Out-Null

# Firewall rule (idempotent)
$RuleName = "rclone WebDAV $Port"
if(-not (Get-NetFirewallRule -DisplayName $RuleName -ErrorAction SilentlyContinue)){
  New-NetFirewallRule -DisplayName $RuleName -Direction Inbound -Action Allow -Protocol TCP -LocalPort $Port | Out-Null
}

$Stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$SrvLog = Join-Path $RecvLogDir ("rclone-serve-{0}.log" -f $Stamp)
$LauncherLog = Join-Path $LaunchLogDir ("receiver-launch-{0}.log" -f $Stamp)

('{0} Starting WebDAV on http://{1}:{2} -> {3}  log={4}' -f ("[$(Get-Date)]"), $BindIP, $Port, $RecvDir, $SrvLog) |
  Tee-Object -FilePath $LauncherLog | Out-Null

# Start rclone (new minimized window)
$Args = @('serve','webdav',$RecvDir,'--addr',("$BindIP`:$Port"),
          '--user',$User,'--pass',$Pass,'--vfs-cache-mode','writes',
          '--log-file',$SrvLog,'--log-level','INFO')

Start-Process -FilePath $Rclone -ArgumentList $Args -WindowStyle Minimized

Write-Host ("Started WebDAV on http://{0}:{1} -> {2}" -f $BindIP,$Port,$RecvDir)
Write-Host ("Server log: {0}" -f $SrvLog) -ForegroundColor DarkCyan
if($KeepOpen){ Read-Host "Press Enter to close this launcher (server stays running)" }
