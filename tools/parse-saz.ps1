<#
  parse-saz.ps1 - Parse a Fiddler .saz capture archive (ASCII only, no BOM issues)

  Usage:
    .\parse-saz.ps1 -Saz 'C:\path\to\fiddler.saz'
    .\parse-saz.ps1 -Saz '...\fiddler.saz' -Filter 'example.edu'
    .\parse-saz.ps1 -Saz '...\fiddler.saz' -Index 3
#>
param(
  [Parameter(Mandatory=$true)][string]$Saz,
  [string]$Filter = '',
  [int]$Index = -1
)

if (-not (Test-Path $Saz)) { Write-Host "File not found: $Saz" -ForegroundColor Red; exit 1 }

$work = Join-Path $env:TEMP ("saz_" + [guid]::NewGuid().ToString('N').Substring(0,8))
New-Item -ItemType Directory -Force -Path $work | Out-Null

try {
  $zip = Join-Path $work 'capture.zip'
  Copy-Item $Saz $zip -Force
  Expand-Archive -Path $zip -DestinationPath $work -Force -ErrorAction Stop
} catch {
  Write-Host "Extract failed (encrypted SAZ?): $($_.Exception.Message)" -ForegroundColor Red
  exit 1
}

$reqs = Get-ChildItem $work -Recurse -File -Filter '*_c.txt' | Sort-Object Name
if (-not $reqs) {
  $reqs = Get-ChildItem $work -Recurse -File -Filter '*.txt' |
          Where-Object { $_.Name -notmatch '_s\.txt' } | Sort-Object Name
}
if (-not $reqs) {
  Write-Host "No request files inside SAZ. Contents:"
  Get-ChildItem $work -Recurse -File | Select-Object -First 30 -ExpandProperty FullName
  exit 0
}

Write-Host ""
Write-Host ("Total sessions: {0}" -f $reqs.Count) -ForegroundColor Cyan
Write-Host ("=" * 100)

$rows = @()
$n = 0
foreach ($r in $reqs) {
  $n++
  $raw = Get-Content $r.FullName -Raw -Encoding UTF8
  $lines = $raw -split "`r?`n"
  $first = $lines | Where-Object { $_ -match '^(GET|POST|PUT|DELETE|HEAD|OPTIONS|PATCH) ' } | Select-Object -First 1
  if (-not $first) { continue }
  $url = ($first -split ' ')[1]

  $host_ = ''
  $token = ''
  foreach ($l in $lines) {
    if ($l -match '^Host:\s*(.+)$')  { $host_ = $Matches[1].Trim() }
    if ($l -match '^token:\s*(.+)$') { $token = $Matches[1].Trim() }
  }

  $body = ''
  $sep = $lines | Select-String -Pattern '^\s*$' | Select-Object -First 1
  if ($sep) { $body = ($lines[($sep.LineNumber)..($lines.Count-1)] -join "`n").Trim() }

  $rows += [pscustomobject]@{
    Idx = $n; File = $r.Name; Host = $host_; Url = $url
    BodyLen = $body.Length; HasToken = [bool]$token; Raw = $raw; Body = $body
  }
}

$show = if ($Filter) { $rows | Where-Object { $_.Host -match $Filter -or $_.Url -match $Filter } } else { $rows }
$show | Select-Object Idx, Host, Url, BodyLen, HasToken | Format-Table -AutoSize -Wrap

if ($Index -gt 0) {
  $s = $rows | Where-Object { $_.Idx -eq $Index }
  if ($s) {
    Write-Host ("`n===== session #{0} full request =====" -f $Index) -ForegroundColor Yellow
    Write-Host $s.Raw
    $respFile = $s.File -replace '_c\.txt$', '_s.txt'
    $resp = Get-ChildItem $work -Recurse -File -Filter $respFile | Select-Object -First 1
    if ($resp) {
      Write-Host "`n----- response -----" -ForegroundColor Yellow
      Write-Host (Get-Content $resp.FullName -Raw -Encoding UTF8)
    }
  } else { Write-Host "No session #$Index" -ForegroundColor Red }
}

Write-Host ""
Write-Host ("Temp dir: {0}" -f $work) -ForegroundColor DarkGray

