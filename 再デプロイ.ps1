# Zenn の再デプロイ（24h の投稿上限で止まった記事を、翌日以降に出す）。毎日 22:20 にタスクスケジューラから呼ぶ。
# ① articles/*.md のうち published: true なのに Zenn 側で未公開の slug を数える
# ② 1 本以上あれば空コミット → push（Zenn の GitHub 連携がデプロイし、上限の範囲で公開される）
# ③ 結果を 再デプロイ.log に 1 行。未公開が 0 なら何もしない
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $MyInvocation.MyCommand.Path
$log = Join-Path $repo '再デプロイ.log'
$user = 'tauridev'
Set-Location $repo
$pending = @()
foreach ($f in Get-ChildItem (Join-Path $repo 'articles') -Filter '*.md') {
  $head = Get-Content $f.FullName -TotalCount 8 -Encoding UTF8
  if (-not ($head -match '^published:\s*true')) { continue }
  $slug = $f.BaseName
  try {
    $r = Invoke-RestMethod -Uri "https://zenn.dev/api/articles/$slug" -Headers @{ 'User-Agent' = 'Mozilla/5.0' } -TimeoutSec 30
    if (-not $r.article) { $pending += $slug }
  } catch { $pending += $slug }   # 404 = 未公開
}
$stamp = Get-Date -Format 'yyyy-MM-dd HH:mm'
if ($pending.Count -eq 0) {
  Add-Content $log "$stamp 未公開 0 本・何もしない" -Encoding UTF8
  exit 0
}
git commit --allow-empty -q -m "再デプロイ（未公開 $($pending.Count) 本: $($pending -join ', ')）" 2>&1 | Out-Null
$ErrorActionPreference = 'Continue'   # git は成功時も stderr に書く（PowerShell 5.1 はそれを NativeCommandError にする）
$push = (git push origin main 2>&1 | Out-String).Trim()
$code = $LASTEXITCODE
$ErrorActionPreference = 'Stop'
if ($code -ne 0) { Add-Content $log "$stamp push 失敗 (exit $code): $push" -Encoding UTF8; exit 1 }
Add-Content $log "$stamp 未公開 $($pending.Count) 本 [$($pending -join ', ')] → push: $($push -join ' ' )" -Encoding UTF8
