# Qiita の「投稿本数の上限」を間隔で探る（2026-09-19 運用者「上限を探るためにも間隔で予約をしておいて」）
#   ・タスクスケジューラから 1 日 2 回（10:20・16:20）呼ぶ。22:20 の 再デプロイ.ps1（1 本/日）と合わせて最大 3 本/日
#   ・1 回に 1 本だけ。待ち行列（公開キュー.txt）の先頭から、_ids.json（投稿済み）と qiita_除外.txt に無い slug を取る
#   ・結果を qiita_間隔.log に 1 行（OK／429／ERR）。429 は「上限」の証拠＝次の枠で再試行して回復までの時間も記録する
#   ・🔴 待ち行列_状態.json には書かない（22:20 の 1 本/日は独立に動く＝合計 3 本/日で上限を探るのが目的）
#   ・qiita_post_from_zenn.py は _ids.json で重複を防ぐ（同じ本を 2 回出さない）。429 等の失敗は何も記録しない＝次の枠で同じ本を再試行
#   ・上限が分かったら（429 の出る本数と回復時間が 2 回そろったら）この器を止めて、22:20 の 1 本/日か「分かった本数」に戻す
# テスト: -DryRun（候補を選ぶだけ・送らない）
param(
  [string]$Slot = '',
  [switch]$DryRun
)
$ErrorActionPreference = 'Stop'
$Repo = Split-Path -Parent $MyInvocation.MyCommand.Path
$log = Join-Path $Repo 'qiita_間隔.log'
$queueFile = Join-Path $Repo '公開キュー.txt'
$exclFile = Join-Path $Repo 'qiita_除外.txt'
$poster = '<手元のパス>'
$idsFile = '<手元のパス>'
trap { Add-Content $log ((Get-Date).ToString('yyyy-MM-dd HH:mm') + " slot=$Slot 異常終了: $($_.Exception.Message)") -Encoding UTF8; exit 1 }
$stamp = (Get-Date).ToString('yyyy-MM-dd HH:mm')

$done = @()
if (Test-Path $idsFile) { $done += @((Get-Content $idsFile -Raw -Encoding UTF8 | ConvertFrom-Json).PSObject.Properties.Name) }
if (Test-Path $exclFile) { $done += @(Get-Content $exclFile -Encoding UTF8 | ForEach-Object { [string]$_ } | Where-Object { $_.Trim() -ne '' }) }
$queue = @()
if (Test-Path $queueFile) { $queue = @(Get-Content $queueFile -Encoding UTF8 | ForEach-Object { ([string]$_).Trim() } | Where-Object { $_ -ne '' }) }
$slug = ''
foreach ($s in $queue) { if ($done -notcontains $s) { $slug = $s; break } }
if ($slug -eq '') { Add-Content $log "$stamp slot=$Slot 候補なし（待ち行列 $($queue.Count) 本は全部投稿済みか除外）" -Encoding UTF8; exit 0 }
if ($DryRun) { Add-Content $log "$stamp slot=$Slot [dry] 候補 $slug（投稿済み $($done.Count) 本・待ち行列 $($queue.Count) 本）" -Encoding UTF8; Write-Output "[dry] $slug"; exit 0 }

Set-Location $Repo
$env:PYTHONUTF8 = '1'
$ErrorActionPreference = 'Continue'
$out = (& python $poster --post $slug 2>&1 | Out-String)
$code = $LASTEXITCODE
$ErrorActionPreference = 'Stop'
$one = ($out -replace "`r?`n", ' ').Trim()
if ($code -eq 0 -and $one -match 'HTTP 201') {
  $url = ([regex]::Match($one, 'https://qiita\.com/[^\s]+')).Value
  $rem = ([regex]::Match($one, 'Rate-Remaining=\d+')).Value   # 2026-09-19: 成功時の一般 API 残量（投稿制限との切り分け）
  Add-Content $log "$stamp slot=$Slot OK $slug $url $rem" -Encoding UTF8
} elseif ($one -match '429') {
  $hdr = ([regex]::Match($one, 'HTTP 429[^|]{0,300}')).Value   # $one は改行を空白に潰してあるので、429 の行だけを 300 字まで
  Add-Content $log "$stamp slot=$Slot 429 $slug（上限） $hdr" -Encoding UTF8
} elseif ($one -match '既に投稿済み|同じ題名') {
  Add-Content $log "$stamp slot=$Slot 既存 ${slug}: $($one.Substring(0, [Math]::Min(120, $one.Length)))" -Encoding UTF8
} else {
  Add-Content $log "$stamp slot=$Slot ERR(exit $code) ${slug}: $($one.Substring(0, [Math]::Min(200, $one.Length)))" -Encoding UTF8
}
