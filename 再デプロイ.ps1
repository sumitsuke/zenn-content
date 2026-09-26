# Zenn の再デプロイ＋待ち行列＋翌日 Qiita（毎日 22:20 にタスクスケジューラから powershell.exe 5.1 で呼ぶ・UTF-8 BOM 必須）
# ① articles/*.md のうち published: true なのに Zenn 側で未公開の slug を数える（＝24h 上限で止まっている本）
# ② 今日の枠（2 本）から「今日すでに回した本数」を引いた残枠だけ、公開キュー.txt の先頭から published: true に切り替える
#    今日すでに回した本数 ＝ 待ち行列_状態.json の today の slugs ＋ 状態に無い pending（前日以前に true にしたが Zenn に出ていない本）
#    同じ日に何度実行しても、その日の合計は 2 本を超えない（状態ファイルで数える。true の本数を数えて pending にはしない）
# ③ 変更があれば commit、無ければ空コミット → push。push が失敗したら状態ファイルを書かずに exit 1（再実行で同じ本を数え直す＝安全）
# ④ Zenn で公開済み・Qiita 未投稿・Zenn 公開日の翌日以降かつ 20 時間以上・今日まだ Qiita へ出していない → 1 本だけ
#    🔴 09-18: Zenn 由来の候補が 0 なら、待ち行列の順で Zenn 未公開の本を 1 本（Zenn より先に Qiita）＝Zenn が止まっても Qiita は 1 本/日で進む
#    qiita_post_from_zenn.py --post（成功は _ids.json に残る＝重複しない／429 等の失敗は何も記録せず翌日に同じ本を再試行）
# ⑤ 結果を 再デプロイ.log に 1 行
# テスト用: -Repo <一時コピー> -Today 'YYYY-MM-DD' -DryRun（git・Qiita を呼ばない）-MockLive 'slug=2026-09-16T23:13:02+09:00,...'（Zenn API の代わり）-FailPush
param(
  [string]$Repo = '',
  [string]$Today = '',
  [switch]$DryRun,
  [string]$MockLive = $null,
  [switch]$FailPush
)
$ErrorActionPreference = 'Stop'
trap { try { Add-Content (Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) '再デプロイ.log') ((Get-Date).ToString('yyyy-MM-dd HH:mm') + " 異常終了: $($_.Exception.Message)") -Encoding UTF8 } catch { }; exit 1 }   # 途中で落ちても 1 行は残す（黙って exit 1 にしない・09-18）
if ($Repo -eq '') { $Repo = Split-Path -Parent $MyInvocation.MyCommand.Path }
$log = Join-Path $Repo '再デプロイ.log'
$queueFile = Join-Path $Repo '公開キュー.txt'
$stateFile = Join-Path $Repo '待ち行列_状態.json'
# 器の場所はこのスクリプトの置き場所の 1 つ上から組み立てる＝公開リポに手元の絶対パス（ユーザー名）を書かない（2026-09-26 外部精査）
$tools = Join-Path (Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)) '記事一覧\_作業中'
$poster = Join-Path $tools 'qiita_post_from_zenn.py'
$queueTool = Join-Path $tools 'zenn_queue.py'
$idsFile = Join-Path $tools 'qiita_out\_ids.json'
if ($DryRun) { $idsFile = Join-Path $Repo '_ids.json' }
$maxPerDay = 2
$qiitaPerDay = 1
$qiitaMinHours = 20
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
Set-Location $Repo
$now = Get-Date
if ($Today -ne '') { $now = [datetime]::ParseExact($Today, 'yyyy-MM-dd', $null).AddHours(22).AddMinutes(20) }
$today = $now.ToString('yyyy-MM-dd')
$stamp = $now.ToString('yyyy-MM-dd HH:mm')

# 状態ファイル（{"zenn": {"YYYY-MM-DD": [slug,...]}, "qiita": {"YYYY-MM-DD": [slug,...]}}）
$state = @{ zenn = @{}; qiita = @{} }
if (Test-Path $stateFile) {
  $j = Get-Content $stateFile -Raw -Encoding UTF8 | ConvertFrom-Json
  foreach ($k in @('zenn', 'qiita')) {
    if ($j.$k) { foreach ($p in $j.$k.PSObject.Properties) { $state[$k][[string]$p.Name] = @($p.Value | ForEach-Object { [string]$_ }) } }
  }
}
if (-not $state.zenn.ContainsKey($today)) { $state.zenn[$today] = @() }
if (-not $state.qiita.ContainsKey($today)) { $state.qiita[$today] = @() }

function Save-State {
  $o = @{ zenn = @{}; qiita = @{} }
  foreach ($k in @('zenn', 'qiita')) { foreach ($d in $state[$k].Keys) { $o[$k][$d] = @($state[$k][$d]) } }
  [IO.File]::WriteAllText($stateFile, (ConvertTo-Json $o -Depth 4), $utf8NoBom)
}

# Zenn 側の公開状態（テストでは -MockLive）
$mock = $null
if ($MockLive -eq 'live') { $mock = $null }   # DryRun でも本物の Zenn API を見る（実リポの写しでの下見用）
elseif ($MockLive -ne $null -and $MockLive -ne '' -and $MockLive -ne 'none') {   # 'slug=published_at,...'（テスト用）
  $mock = @{}
  foreach ($kv in $MockLive.Split(',')) { $a = $kv.Split('='); $mock[$a[0].Trim()] = $a[1].Trim() }
} elseif ($DryRun -or $MockLive -eq 'none') { $mock = @{} }   # 'none' ＝ 何も公開されていない（テスト用）
function Get-ZennPublishedAt($slug) {
  if ($mock -ne $null) { if ($mock.ContainsKey($slug)) { return $mock[$slug] } else { return $null } }
  try {
    $r = Invoke-RestMethod -Uri "https://zenn.dev/api/articles/$slug" -Headers @{ 'User-Agent' = 'Mozilla/5.0' } -TimeoutSec 30
    if ($r.article) { return [string]$r.article.published_at }
  } catch { }
  return $null
}

# ① 未公開（true なのに Zenn に無い）と、公開済み
$pending = @(); $live = @{}
foreach ($f in Get-ChildItem (Join-Path $Repo 'articles') -Filter '*.md') {
  $head = Get-Content $f.FullName -TotalCount 8 -Encoding UTF8
  if (-not ($head -match '^published:\s*true')) { continue }
  $slug = $f.BaseName
  $at = Get-ZennPublishedAt $slug
  if ($at) { $live[$slug] = $at } else { $pending += $slug }
}

# ② 今日の枠
$flippedToday = @($state.zenn[$today])
$pendingOld = @($pending | Where-Object { $flippedToday -notcontains $_ })   # 前日以前に true にして、まだ Zenn に出ていない本
$usedToday = $flippedToday.Count + $pendingOld.Count
$slots = [Math]::Max(0, $maxPerDay - $usedToday)
$flipped = @(); $skipped = @()
if (Test-Path $queueFile) {
  $queue = @(Get-Content $queueFile -Encoding UTF8 | ForEach-Object { [string]$_ } | Where-Object { $_.Trim() -ne '' })   # [string] にしないと Get-Content の注記つき文字列が JSON にオブジェクトとして出る
  $rest = @()
  foreach ($slug in $queue) {
    $path = Join-Path $Repo "articles\$slug.md"
    if (-not (Test-Path $path)) {
      # 🔴 09-18 改定: repo に下書きを置かない。枠があれば正本（記事一覧/zenn/_作業中）から --materialize で published: true のまま写す
      #   （Zenn の「投稿数の上限」が下書きも数える可能性への対策。正本が無い slug だけキューから落とす）
      if ($flipped.Count -lt $slots) {
        $env:PYTHONUTF8 = '1'
        $ErrorActionPreference = 'Continue'
        $mo = (& python $queueTool --materialize $slug --repo $Repo 2>&1 | Out-String).Trim()
        $mcode = $LASTEXITCODE
        $ErrorActionPreference = 'Stop'
        if ($mcode -eq 0 -and (Test-Path $path)) { $flipped += $slug } else { $skipped += "$slug(正本から写せない: " + ($mo -replace "`r?`n", ' ').Substring(0, [Math]::Min(80, $mo.Length)) + ")" }
      } else { $rest += $slug }
      continue
    }
    $text = [IO.File]::ReadAllText($path, $utf8NoBom)
    if (-not ($text -match '(?m)^published:\s*false')) { $skipped += "$slug(既に true)"; continue }   # 既に公開済み＝キューから落とす（重複処理しない）
    if ($flipped.Count -lt $slots) {
      $text = [regex]::Replace($text, '(?m)^published:\s*false', 'published: true', 1)
      [IO.File]::WriteAllText($path, $text, $utf8NoBom)
      $flipped += $slug
    } else { $rest += $slug }
  }
  [IO.File]::WriteAllText($queueFile, (($rest -join "`n") + "`n"), $utf8NoBom)
}

# ③ commit → push（変更も未公開も無ければ何もしない）。push 失敗＝状態を書かずに終わる
$pushed = ''
if ($pending.Count -gt 0 -or $flipped.Count -gt 0) {
  $msg = "再デプロイ（未公開 $($pending.Count) 本: $($pending -join ', ')／待ち行列から $($flipped.Count) 本: $($flipped -join ', ')）"
  if ($DryRun) {
    if ($FailPush) { Add-Content $log "$stamp [dry] push 失敗（模擬）: $msg" -Encoding UTF8; exit 1 }
    $pushed = "[dry] $msg"
  } else {
    $ErrorActionPreference = 'Continue'   # git は成功時も stderr に書く（PowerShell 5.1 はそれを NativeCommandError にする）。add・commit も同じ＝09-17 22:20 は add の CRLF 警告で落ちて何も記録されなかった（09-18 実測）
    git add -A 2>&1 | Out-Null
    git commit --allow-empty -q -m $msg 2>&1 | Out-Null
    # 公開リポの漏れ点検（手元のパス・個人のメール・読者のハンドル名＝2026-09-26 外部精査）。赤なら push しない（状態も書かない＝翌日に再試行）
    $env:PYTHONUTF8 = '1'
    $leakTool = Join-Path (Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)) '1_運用マニュアル\公開リポ_漏れ点検.py'
    $leak = ((& python $leakTool --local $Repo 2>&1 | Out-String) -replace "`r?`n", ' ').Trim()   # ログは 1 回 1 行
    if ($LASTEXITCODE -ne 0) { $ErrorActionPreference = 'Stop'; Add-Content $log "$stamp push 中止（公開リポの漏れ点検 exit $LASTEXITCODE）: $($leak.Substring(0, [Math]::Min(300, $leak.Length)))" -Encoding UTF8; exit 1 }
    $push = (git push origin main 2>&1 | Out-String).Trim()
    $code = $LASTEXITCODE
    $ErrorActionPreference = 'Stop'
    if ($code -ne 0) { Add-Content $log "$stamp push 失敗 (exit $code): $push（状態は更新しない・翌日に再試行）" -Encoding UTF8; exit 1 }
    $pushed = ($push -join ' ')
  }
}
$state.zenn[$today] = @($flippedToday + $flipped)
Save-State

# ④ Qiita: Zenn 公開日の翌日以降・20h 以上・未投稿・今日まだ出していない → 1 本
$qiita = 'なし'
$doneToday = @($state.qiita[$today])
if ($doneToday.Count -ge $qiitaPerDay) {
  $qiita = "今日は投稿済み [$($doneToday -join ', ')]"
} elseif (Test-Path $idsFile) {
  $ids = Get-Content $idsFile -Raw -Encoding UTF8 | ConvertFrom-Json
  $done = @($ids.PSObject.Properties.Name)
  $exclFile = Join-Path $Repo 'qiita_除外.txt'   # Qiita に出さない slug（旧記事など・1 行 1 slug）
  if (Test-Path $exclFile) { $done += @(Get-Content $exclFile -Encoding UTF8 | ForEach-Object { [string]$_ } | Where-Object { $_.Trim() -ne '' }) }
  $cands = @()
  foreach ($slug in $live.Keys) {
    if ($done -contains $slug) { continue }
    $pub = [datetime]::Parse($live[$slug])
    $pubDay = $pub.ToString('yyyy-MM-dd')
    $hours = ($now - $pub).TotalHours
    if ($pubDay -lt $today -and $hours -ge $qiitaMinHours) { $cands += $slug }
  }
  # 🔴 09-18 裁定: Zenn 由来の候補が 0（Zenn が投稿数の上限で止まっている等）なら、待ち行列の順で Zenn 未公開（pending か正本）を 1 本だけ Qiita へ先に出す
  #   （qiita_post_from_zenn.py が正本から組み、図だけ先に push する。Zenn が流れているときは Zenn 由来の候補が必ず在るのでここは通らない）
  $fromSource = ''
  if ($cands.Count -eq 0) {
    # 順＝①repo で pending（true なのに Zenn 未公開＝②が既に待ち行列から落としている）→ ②待ち行列（正本）
    $order = @($pending | Sort-Object)
    if (Test-Path $queueFile) { $order += @(Get-Content $queueFile -Encoding UTF8 | ForEach-Object { [string]$_ } | Where-Object { $_.Trim() -ne '' }) }
    foreach ($slug in $order) {
      $slug = $slug.Trim()
      if ($done -contains $slug) { continue }
      if ($live.ContainsKey($slug)) { continue }   # Zenn 公開済み＝上の「翌日・20h」の側で扱う（pending＝repo に在るが Zenn 未公開、は正本と同じくここで拾う）
      $cands = @($slug); $fromSource = '（正本から・Zenn より先）'; break
    }
  }
  if ($cands.Count -gt 0) {
    $slug = @($cands | Sort-Object)[0]   # @() が無いと候補 1 本のとき文字列の 1 文字目になる（毒テストで発見）
    if ($DryRun) {
      $qiita = "[dry] 候補 $slug$fromSource（他 $($cands.Count - 1) 本）"
    } else {
      $env:PYTHONUTF8 = '1'
      $ErrorActionPreference = 'Continue'
      $out = (& python $poster --post $slug 2>&1 | Out-String).Trim()
      $qcode = $LASTEXITCODE
      $ErrorActionPreference = 'Stop'
      if ($qcode -eq 0) {
        $qiita = "$slug 投稿 OK$fromSource"
        $state.qiita[$today] = @($doneToday + $slug); Save-State
      } else {
        $qiita = "$slug 失敗 (exit $qcode・翌日に再試行): " + ($out -replace "`r?`n", ' ').Substring(0, [Math]::Min(160, $out.Length))
      }
      if ($cands.Count -gt 1) { $qiita += "（残り $($cands.Count - 1) 本は明日以降）" }
    }
  }
}

Add-Content $log "$stamp 未公開 $($pending.Count) 本 [$($pending -join ', ')]／今日の枠 $usedToday+$($flipped.Count)/$maxPerDay 本／待ち行列→true [$($flipped -join ', ')]／落とした [$($skipped -join ', ')]／push: $pushed／Qiita: $qiita" -Encoding UTF8
