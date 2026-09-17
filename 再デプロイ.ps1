# Zenn の再デプロイ＋待ち行列＋翌日 Qiita（毎日 22:20 にタスクスケジューラから powershell.exe 5.1 で呼ぶ・UTF-8 BOM 必須）
# ① articles/*.md のうち published: true なのに Zenn 側で未公開の slug を数える（＝24h 上限で止まっている本）
# ② 未公開が 2 本未満なら、公開キュー.txt の先頭から足りない分を published: true に切り替える（2 本/日）
# ③ 変更があれば commit、無ければ空コミット → push（Zenn の GitHub 連携がデプロイし、上限の範囲で公開される）
# ④ Zenn で公開済み・Qiita 未投稿の本を 1 本だけ Qiita へ（qiita_post_from_zenn.py --post。429 ならその日は諦める＝半日空けて 1 回の規則）
# ⑤ 結果を 再デプロイ.log に 1 行
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $MyInvocation.MyCommand.Path
$log = Join-Path $repo '再デプロイ.log'
$queueFile = Join-Path $repo '公開キュー.txt'
$poster = 'C:\Users\oomor\Desktop\受注案件\記事一覧\_作業中\qiita_post_from_zenn.py'
$idsFile = 'C:\Users\oomor\Desktop\受注案件\記事一覧\_作業中\qiita_out\_ids.json'
$user = 'tauridev'
$maxPerDay = 2
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
Set-Location $repo
$stamp = Get-Date -Format 'yyyy-MM-dd HH:mm'

function Get-ZennArticle($slug) {
  try {
    $r = Invoke-RestMethod -Uri "https://zenn.dev/api/articles/$slug" -Headers @{ 'User-Agent' = 'Mozilla/5.0' } -TimeoutSec 30
    if ($r.article) { return $r.article }
  } catch { }
  return $null
}

# ① 未公開（true なのに Zenn に無い）と、公開済みの一覧
$pending = @(); $live = @{}
foreach ($f in Get-ChildItem (Join-Path $repo 'articles') -Filter '*.md') {
  $head = Get-Content $f.FullName -TotalCount 8 -Encoding UTF8
  if (-not ($head -match '^published:\s*true')) { continue }
  $slug = $f.BaseName
  $a = Get-ZennArticle $slug
  if ($a) { $live[$slug] = $a } else { $pending += $slug }
}

# ② 待ち行列から足りない分を published: true に
$flipped = @()
if ((Test-Path $queueFile) -and $pending.Count -lt $maxPerDay) {
  $queue = @(Get-Content $queueFile -Encoding UTF8 | Where-Object { $_.Trim() -ne '' })
  $rest = @()
  foreach ($slug in $queue) {
    $path = Join-Path $repo "articles\$slug.md"
    if (($flipped.Count + $pending.Count) -lt $maxPerDay -and (Test-Path $path)) {
      $text = [IO.File]::ReadAllText($path, $utf8NoBom)
      if ($text -match '(?m)^published:\s*false') {
        $text = [regex]::Replace($text, '(?m)^published:\s*false', 'published: true', 1)
        [IO.File]::WriteAllText($path, $text, $utf8NoBom)
        $flipped += $slug
        continue
      }
    }
    $rest += $slug
  }
  [IO.File]::WriteAllText($queueFile, (($rest -join "`n") + "`n"), $utf8NoBom)
}

# ③ commit → push（何も無ければ何もしない）
$pushed = ''
if ($pending.Count -gt 0 -or $flipped.Count -gt 0) {
  git add -A 2>&1 | Out-Null
  $msg = "再デプロイ（未公開 $($pending.Count) 本: $($pending -join ', ')／待ち行列から $($flipped.Count) 本: $($flipped -join ', ')）"
  git commit --allow-empty -q -m $msg 2>&1 | Out-Null
  $ErrorActionPreference = 'Continue'   # git は成功時も stderr に書く（PowerShell 5.1 はそれを NativeCommandError にする）
  $push = (git push origin main 2>&1 | Out-String).Trim()
  $code = $LASTEXITCODE
  $ErrorActionPreference = 'Stop'
  if ($code -ne 0) { Add-Content $log "$stamp push 失敗 (exit $code): $push" -Encoding UTF8; exit 1 }
  $pushed = ($push -join ' ')
}

# ④ Zenn 公開済み・Qiita 未投稿の本を 1 本だけ Qiita へ（Zenn 公開から 20 時間以上たったもの）
$qiita = 'なし'
if (Test-Path $idsFile) {
  $ids = Get-Content $idsFile -Raw -Encoding UTF8 | ConvertFrom-Json
  $done = @($ids.PSObject.Properties.Name)
  $cands = @()
  foreach ($slug in $live.Keys) {
    if ($done -contains $slug) { continue }
    $pub = [datetime]::Parse($live[$slug].published_at)
    if (((Get-Date).ToUniversalTime() - $pub.ToUniversalTime()).TotalHours -ge 20) { $cands += $slug }
  }
  if ($cands.Count -gt 0) {
    $slug = ($cands | Sort-Object)[0]
    $env:PYTHONUTF8 = '1'
    $ErrorActionPreference = 'Continue'
    $out = (& python $poster --post $slug 2>&1 | Out-String).Trim()
    $qcode = $LASTEXITCODE
    $ErrorActionPreference = 'Stop'
    if ($qcode -eq 0) { $qiita = "$slug 投稿 OK" } else { $qiita = "$slug 失敗 (exit $qcode): " + ($out -replace "`r?`n", ' ').Substring(0, [Math]::Min(160, $out.Length)) }
    if ($cands.Count -gt 1) { $qiita += "（残り $($cands.Count - 1) 本は明日）" }
  }
}

Add-Content $log "$stamp 未公開 $($pending.Count) 本 [$($pending -join ', ')]／待ち行列→true $($flipped.Count) 本 [$($flipped -join ', ')]／push: $pushed／Qiita: $qiita" -Encoding UTF8
