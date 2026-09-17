# 再デプロイ.ps1 の毒テスト（一時コピー・DryRun・Zenn API は MockLive・git と Qiita は呼ばない）。
# A 初回=2本 / B 同日2回目=0本 / C 残枠1 / D 残枠0 / E push失敗で状態を書かない・再実行で増えない / F 先頭が既に true → 落として次へ
# G Zenn 公開当日は Qiita しない / H 翌日は最大1本 / I 同日再実行で2本目なし / J 429=未投稿のまま翌日再試行 / K 成功後は再投稿しない
# 使い方: powershell.exe -NoProfile -File 再デプロイ_毒テスト.ps1
[Console]::OutputEncoding = [Text.Encoding]::UTF8
$ErrorActionPreference = 'Stop'
$script = Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) '再デプロイ.ps1'
$utf8 = New-Object System.Text.UTF8Encoding($false)
$fails = 0
function New-Repo($name, $trueSlugs, $falseSlugs, $queue) {
  $r = Join-Path $env:TEMP ("zq_" + $name + "_" + [guid]::NewGuid().ToString('N').Substring(0, 6))
  New-Item -ItemType Directory -Path (Join-Path $r 'articles') -Force | Out-Null
  foreach ($s in $trueSlugs)  { [IO.File]::WriteAllText((Join-Path $r "articles\$s.md"), "---`ntitle: $s`npublished: true`n---`n本文 published: false は本文`n", $utf8) }
  foreach ($s in $falseSlugs) { [IO.File]::WriteAllText((Join-Path $r "articles\$s.md"), "---`ntitle: $s`npublished: false`n---`n本文 published: false は本文`n", $utf8) }
  [IO.File]::WriteAllText((Join-Path $r '公開キュー.txt'), (($queue -join "`n") + "`n"), $utf8)
  [IO.File]::WriteAllText((Join-Path $r '_ids.json'), "{}", $utf8)
  return $r
}
function Pub($r, $s) { ([IO.File]::ReadAllText((Join-Path $r "articles\$s.md"), $utf8) -match '(?m)^published:\s*true') }
function Queue($r) { @(Get-Content (Join-Path $r '公開キュー.txt') -Encoding UTF8 | Where-Object { $_.Trim() -ne '' }) }
function Run($r, $today, $live, [switch]$failPush) {
  if ($live -eq '') { $live = 'none' }
  $argv = @('-NoProfile', '-File', $script, '-Repo', $r, '-Today', $today, '-DryRun', '-MockLive', $live)
  if ($failPush) { $argv += '-FailPush' }
  $o = & powershell.exe @argv 2>&1 | Out-String
  return $LASTEXITCODE
}
function Check($name, $cond) { if ($cond) { "  OK  $name" } else { "  NG  $name"; $script:fails++ } }
function LastLog($r) { (Get-Content (Join-Path $r '再デプロイ.log') -Encoding UTF8 | Select-Object -Last 1) }

'== A/B/C/D/F: 残枠と同日再実行 =='
$q = @('q1', 'q2', 'q3', 'q4')
$r = New-Repo 'A' @() $q $q
$null = Run $r '2026-09-18' ''
Check 'A 初回: 残枠 2 → q1,q2 が true' ((Pub $r 'q1') -and (Pub $r 'q2') -and -not (Pub $r 'q3'))
Check 'A キューは q3,q4 に' ((Queue $r) -join ',' -eq 'q3,q4')
$null = Run $r '2026-09-18' ''
Check 'B 同日 2 回目: 増えない（q3 は false のまま）' (-not (Pub $r 'q3'))
$null = Run $r '2026-09-18' 'q1=2026-09-18T22:30:00+09:00,q2=2026-09-18T22:30:00+09:00'
Check 'B 同日 3 回目（q1,q2 が Zenn に出た後）でも増えない' (-not (Pub $r 'q3'))
$null = Run $r '2026-09-19' 'q1=2026-09-18T22:30:00+09:00'
Check 'C 翌日・q2 がまだ Zenn に無い（残枠 1）→ q3 だけ true' ((Pub $r 'q3') -and -not (Pub $r 'q4'))
$r2 = New-Repo 'D' @('p1', 'p2') @('q1') @('q1')
$null = Run $r2 '2026-09-18' ''
Check 'D 前日の未公開が 2 本（残枠 0）→ q1 は false のまま' (-not (Pub $r2 'q1'))
$r3 = New-Repo 'F' @('q1') @('q2', 'q3') @('q1', 'q2', 'q3')
$null = Run $r3 '2026-09-18' 'q1=2026-09-17T22:30:00+09:00'
Check 'F 先頭 q1 は既に true（公開済み）→ キューから落とし、q2 と q3 を true（重複処理なし）' ((Pub $r3 'q2') -and (Pub $r3 'q3') -and ((Queue $r3).Count -eq 0))
Check 'F ログに「落とした q1(既に true)」' ((LastLog $r3) -match 'q1\(既に true\)')

'== E: push 失敗 =='
$r4 = New-Repo 'E' @() @('q1', 'q2', 'q3') @('q1', 'q2', 'q3')
$code = Run $r4 '2026-09-18' '' -failPush
Check 'E push 失敗で exit 1' ($code -eq 1)
Check 'E 状態ファイルを書いていない' (-not (Test-Path (Join-Path $r4 '待ち行列_状態.json')))
Check 'E ファイルは切り替わっている（q1,q2 true・コミット相当）' ((Pub $r4 'q1') -and (Pub $r4 'q2'))
$null = Run $r4 '2026-09-18' ''
Check 'E 再実行: pending 2 が今日の枠を埋め、q3 は増えない' (-not (Pub $r4 'q3'))
Check 'E 再実行後に状態ファイルあり' (Test-Path (Join-Path $r4 '待ち行列_状態.json'))

'== G〜K: Qiita =='
$r5 = New-Repo 'G' @('z1') @() @()
$null = Run $r5 '2026-09-18' 'z1=2026-09-18T22:30:00+09:00'
Check 'G 公開当日は Qiita 候補なし' ((LastLog $r5) -match 'Qiita: なし')
$null = Run $r5 '2026-09-19' 'z1=2026-09-18T22:30:00+09:00'
Check 'H 翌日・20h 以上で候補 1 本' ((LastLog $r5) -match 'Qiita: \[dry\] 候補 z1')
$r6 = New-Repo 'H2' @('z1', 'z2') @() @()
$null = Run $r6 '2026-09-19' 'z1=2026-09-18T10:00:00+09:00,z2=2026-09-18T11:00:00+09:00'
Check 'H 候補が 2 本あっても 1 本だけ（他 1 本）' ((LastLog $r6) -match '候補 z1（他 1 本）')
# I/K: 状態に「今日 1 本投稿済み」を書いて再実行
[IO.File]::WriteAllText((Join-Path $r6 '待ち行列_状態.json'), '{"zenn":{},"qiita":{"2026-09-19":["z1"]}}', $utf8)
$null = Run $r6 '2026-09-19' 'z1=2026-09-18T10:00:00+09:00,z2=2026-09-18T11:00:00+09:00'
Check 'I 同日再実行: 2 本目を出さない' ((LastLog $r6) -match '今日は投稿済み \[z1\]')
# K: _ids.json に z1 が入っていれば候補にしない（翌日）
[IO.File]::WriteAllText((Join-Path $r6 '_ids.json'), '{"z1":"abc"}', $utf8)
$null = Run $r6 '2026-09-20' 'z1=2026-09-18T10:00:00+09:00,z2=2026-09-18T11:00:00+09:00'
Check 'K 成功済み z1 は再投稿せず、次は z2' ((LastLog $r6) -match '候補 z2')
# J: 429（失敗）＝状態に書かれない → 翌日も同じ本が候補（DryRun では失敗を直接は出せないので、状態未記録＝翌日候補、を確認）
$null = Run $r6 '2026-09-21' 'z1=2026-09-18T10:00:00+09:00,z2=2026-09-18T11:00:00+09:00'
Check 'J 未投稿のままなら翌日も同じ本（z2）が候補' ((LastLog $r6) -match '候補 z2')
Check 'J 状態の qiita に z2 が書かれていない' (-not ((Get-Content (Join-Path $r6 '待ち行列_状態.json') -Raw) -match 'z2'))

'== 7: front-matter 以外を変えない・BOM/改行 =='
$before = [IO.File]::ReadAllText((Join-Path $r 'articles\q4.md'), $utf8)
$null = Run $r '2026-09-25' 'q1=2026-09-18T22:30:00+09:00,q2=2026-09-18T22:30:00+09:00,q3=2026-09-19T22:30:00+09:00'
$after = [IO.File]::ReadAllText((Join-Path $r 'articles\q4.md'), $utf8)
Check '7 変わった行は published: の 1 行だけ' (($after -replace '(?m)^published: true', 'published: false') -eq $before)
$bytes = [IO.File]::ReadAllBytes((Join-Path $r 'articles\q4.md'))
Check '7 BOM が付いていない・LF のまま' (($bytes[0] -ne 0xEF) -and (-not ($after -match "`r`n")))
Check '7 本文の "published: false" は無傷' ($after -match '本文 published: false は本文')

''
if ($fails -eq 0) { "ALL PASS" } else { "🔴 $fails NG"; exit 1 }
