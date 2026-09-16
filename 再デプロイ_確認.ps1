# 「Zenn 再デプロイ」タスクの実走結果を読むだけ（commit・push はしない）。09-16 の合格条件をそのまま並べる。
$ErrorActionPreference = 'Continue'
$repo = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $repo
$i = Get-ScheduledTaskInfo -TaskName 'Zenn 再デプロイ'
"1 タスク: LastRun=$($i.LastRunTime)  LastResult=$($i.LastTaskResult) (0=正常)  NextRun=$($i.NextRunTime)  実行中の数=$($i.NumberOfMissedRuns)missed"
"2 ログ:"; if (Test-Path .\再デプロイ.log) { Get-Content .\再デプロイ.log -Encoding UTF8 | Select-Object -Last 5 | ForEach-Object { "   $_" } } else { "   （無い）" }
"3 空コミット（本文が『再デプロイ』で始まる・直近 10）:"; git log -10 --pretty='   %h %ad %s' --date=format:'%m-%d %H:%M' | Select-String '再デプロイ'
"4 push: local=$(git rev-parse --short HEAD) remote=$(git rev-parse --short origin/main) （git fetch 後に一致なら push 済み）"; git fetch -q origin; "   fetch 後 remote=$(git rev-parse --short origin/main)"
"5 Zenn の未公開:"
$pending = @()
foreach ($f in Get-ChildItem .\articles -Filter '*.md') {
  $head = Get-Content $f.FullName -TotalCount 8 -Encoding UTF8
  if (-not ($head -match '^published:\s*true')) { continue }
  try { $r = Invoke-RestMethod -Uri "https://zenn.dev/api/articles/$($f.BaseName)" -Headers @{ 'User-Agent' = 'Mozilla/5.0' } -TimeoutSec 30; if (-not $r.article) { $pending += $f.BaseName } } catch { $pending += $f.BaseName }
}
"   未公開 $($pending.Count) 本: $($pending -join ', ')"
