---
title: "タスクスケジューラの PowerShell 5.1——BOM と git の stderr で自動デプロイが 2 回止まった"
emoji: "🕳️"
type: "tech"
topics: ["PowerShell", "Windows", "Git", "自動化", "技術記事"]
published: true
---


pwsh 7 で通した `.ps1` をタスクスケジューラに載せたら、**2 日続けて「実行された形跡はあるのに何も起きない」**が起きました。LastRunTime は入り、LastTaskResult は 1、ログは 0 行。原因は 2 つとも別の既知の仕様で、しかも 2 回目は**1 回目の直しの範囲を取りこぼした**だけでした。

この記事は、その 2 回の記録と、「LastTaskResult=1・ログ 0 行」を見たときの診断順（一本道）です。

![LastTaskResult=1・ログ 0 行のときの診断順＝①実行器（powershell.exe か pwsh.exe か）→②同じ引数で手で 1 回→③先頭 3 バイト EF BB BF→④native コマンドの stderr→⑤$LASTEXITCODE。1 回目は③で、2 回目は④で止まっていた](/images/task-scheduler-powershell51-silent-exit/fig1_diagnosis_path.png)

**この記事の位置づけ**（2026-09-26 追記）

- 既に知られていること: BOM の無い .ps1 を Windows PowerShell が古い ANSI のコードページとして読むこと（[Microsoft Learn](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_character_encoding)）。
- この記事で新しく示すこと: 「LastTaskResult=1・ログ 0 行」から原因に行き着く診断の順番と、2 回目は 1 回目の直しの範囲の取りこぼしだったこと。
- 当てはまる範囲: タスクスケジューラから powershell.exe（5.1）で呼ぶ場合。同じ .ps1 は pwsh 7 では通っていました。

## 先に結論

- タスクスケジューラは**指定した実行ファイルを起動するだけ**です。`powershell.exe` は Windows PowerShell **5.1**、PowerShell 7 は `pwsh.exe` という別の実行ファイルです。手元で pwsh 7 を使っていても、タスクの `<Command>` が `powershell.exe` なら 5.1 で走ります。
- 5.1 は pwsh 7 と 2 点で違い、どちらも**黙って exit 1** になりました。
  1. **BOM の無い UTF-8 ソースを、システムの ANSI コードページとして読む**（公式 `about_Character_Encoding`）。当方の日本語 Windows では shift_jis（cp932）で、日本語コメントの中の文字が構文を壊して `MissingEndCurlyBrace`。
  2. `$ErrorActionPreference = 'Stop'` の下で、**native コマンドの stderr を `2>&1` でリダイレクトすると、5.1 は stderr の各行を ErrorRecord にして NativeCommandError** で終了します（リダイレクトしなければ起きません。本機の 5.1 で確認）。git は成功時にも stderr に書く（CRLF の警告）ので、`git add … 2>&1` の行でスクリプトが止まり、ログを書く行に届く前に終了（当時の版に `trap` はありませんでした）。
- 2 回目は新しい原因ではありません。1 回目の日に stderr の件は分かっていて `push` だけ `Continue` にしたのに、**`commit` が残り、翌日に足した `add` も同じ形で書いた**。同じ外部コマンドの呼び出しは全部数えてから直す、が一番効く教訓でした。

## 環境（凍結した値）

| 項目 | 値 |
|---|---|
| OS | Windows 11・ja-JP |
| タスクの `<Command>` | `powershell.exe`（引数 `-NoProfile -ExecutionPolicy Bypass -File …\再デプロイ.ps1`） |
| そこで動く PowerShell | 5.1.26100.9444 |
| `[Console]::OutputEncoding` ／ ANSI | shift_jis ／ shift_jis |
| 手元で書いていた PowerShell | pwsh 7.x |
| git | git for Windows |

`Export-ScheduledTask` の XML・`Get-ScheduledTaskInfo` の出力・ログ・直し前後の `.ps1` は、パス・ユーザー名・SID を伏せた写しを記事の本家（Lab）の `evidence/` に置いています（SHA256 台帳つき）。

公式の根拠は 2 文です。`about_Character_Encoding`（5.1）: *"Without the BOM, Windows PowerShell misinterprets your script as being encoded in the legacy \"ANSI\" codepage."*／「Windows PowerShell 5.1 と PowerShell 7.x の差分」の見出し: *"Make `$ErrorActionPreference` not affect `stderr` output of native commands"*（7 で変わった＝5.1 では効く）。

## 1 回目（09-16 22:20）: BOM 無し → ANSI コードページ → 構文エラー

- 観測: `LastTaskResult=1`・`再デプロイ.log` は 0 行・コミット無し。
- 5.1 に読ませると **`MissingEndCurlyBrace`**（pwsh 7 では同じファイルが通る＝手元では気づけなかった）。
- 先頭 3 バイト: `# Z`（BOM 無し）。
- 仕様: Windows PowerShell は BOM の無いファイルを**現在の ANSI コードページ**で読む。ja-JP では cp932。UTF-8 の日本語コメントが cp932 として解釈されて構文が壊れた、までが観測で、**どの文字が `}` を食ったかは特定していません**。
- 構文エラーなのでスクリプト自体が実行を始められず、スクリプト内でログを書く手段は何であれ動きません。
- 直し: 先頭に BOM（`EF BB BF`）。同じ日に、native の呼び出し 2 か所（`commit`・`push`）のうち `push` だけ `Continue` にした（次の伏線）。

## 2 回目（09-17 22:20）: git の stderr → NativeCommandError → ログを書く前に終了

- 観測: `LastTaskResult=1`・ログ 0 行。BOM は付いている。
- 同じ条件で再実行して再現: `git add -A`（前日に足した行）が `公開キュー.txt` の CRLF 警告を **stderr** に出す → `$ErrorActionPreference='Stop'` ＋ `2>&1` で **NativeCommandError** → ログを書く行に届く前に終了。当時の版に `trap` は無く、`trap` は 2 回目の直しで入れました。
- 5.1 の挙動: native コマンドの stderr を `2>&1` でリダイレクトすると、stderr の各行が ErrorRecord になり、`Stop` なら NativeCommandError で終了する。リダイレクトしなければ起きない（2026-10-01 に本機の 5.1.26100 で確認。`cmd /c "echo err 1>&2"` を `Stop` の下で単独で呼ぶと、`-File` でも `-Command` でも例外にならず次の行へ進み、exit 0。`2>&1 | Out-Null` を付けたときだけ NativeCommandError）。PowerShell 7 では扱いが変わっている（公式「Windows PowerShell との差分」）。
- 直し: `add`・`commit`・`push` の **3 か所**を、native 呼び出し 1 つずつ `Continue` → `$LASTEXITCODE` で判定 → `Stop` に戻す形に。あわせて `trap` でログに 1 行残す（`trap` は同じスクリプトブロック全体に効きます＝公式 `about_Trap`「hoisting」。位置ではなく**有無**の話です）。
- 直し後の 22:20 実走: 09-18 に `LastTaskResult=0`。その後も 09-30 まで、22:20 の実走でログに行がある日が **10 日分**あります（ログ行は公開物がある日にだけ書かれるので、全日ではありません）。2026-10-01 に見た直近（09-30 22:20）は `LastTaskResult=0`・取りこぼし 0 回。

```powershell
$ErrorActionPreference = 'Stop'
trap { Add-Content $log "$(Get-Date -f 'yyyy-MM-dd HH:mm') 異常終了: $($_.Exception.Message)" -Encoding UTF8; exit 1 }

# native 1 呼び出しずつ: Continue → exit code → Stop
$ErrorActionPreference = 'Continue'
git add -A 2>&1 | Out-Null
$ErrorActionPreference = 'Stop'
if ($LASTEXITCODE -ne 0) { Add-Content $log "add 失敗 exit $LASTEXITCODE"; exit 1 }
```

`Continue` の範囲を広げすぎると、本物の PowerShell エラーまで流れます。**native コマンド 1 回分だけ**に限るのが安全でした。

## 診断順（LastTaskResult=1・ログ 0 行を見たら）

1. **実行器**: `Export-ScheduledTask -TaskName …` の `<Command>` が `powershell.exe` か `pwsh.exe` か。
2. **同じ引数で手で 1 回**: `powershell.exe -NoProfile -ExecutionPolicy Bypass -File x.ps1`。ここでエラーが画面に出る（タスクでは出ない）。
3. **先頭 3 バイト**: `EF BB BF` か。5.1: `Get-Content x.ps1 -Encoding Byte -TotalCount 3`／7: `Get-Content x.ps1 -AsByteStream -TotalCount 3`（`Format-Hex -Count` は 5.1 に無い）。
4. **native コマンドの stderr**: `Stop` の下で `2>&1` している行はどれか。git・npm・curl は成功時にも stderr に書く。
5. **`$LASTEXITCODE`**: PowerShell の例外と native の失敗を分けて判定しているか。

## 載せる前の 4 行（Windows PowerShell 5.1 preflight）

- タスクに載せる前に、**5.1 で 1 回**通す（`powershell.exe -NoProfile -File`）。
- 非 ASCII を含む `.ps1` は **UTF-8 with BOM** で保存（5.1 で扱うなら。7 だけなら不要）。
- native コマンドは **1 呼び出しずつ** `Continue` → `$LASTEXITCODE` → `Stop`。
- `trap { ログ 1 行; exit 1 }`。これが無いと「ログ 0 行」になる。

もう 1 行足すなら、**同じ外部コマンドの呼び出しを全部数える**。1 か所直して安心したのが 2 回目でした。

## 測っていないこと・言わないこと

- 「PowerShell 5.1 を使うな」とは言いません。タスクに `pwsh.exe` を登録すれば 7 で走るはずですが、当方はそちらを測っていません。
- 「`trap` があれば 2 回目は書けた」とも言いません。当時の版に `trap` が無かった、までが観測です。
- 「タスクスケジューラが 5.1 を選ぶ」のではなく、`powershell.exe` を指定していたのが当方です。
- 「cp932 で読む」は当方の環境の話で、仕様は「システムの ANSI コードページ」です。他のロケール・`-Command` 経路・`[Console]::OutputEncoding` の変更は測っていません。
- git が stderr に出す警告の全種類は網羅していません。CRLF の警告 1 種で再現しただけです。
- 事前に回しているテスト（23 項目）は待ち行列と Qiita の論理のもので、5.1 の parse と BOM は項目に入っていません。そこは手で 1 回ずつです。
- 直し後の確認は、09-18〜09-30 の 22:20 実走でログに行がある日が 10 日分、直近の `LastTaskResult=0` までです（2026-10-01 に数えました）。毎日の結果を全部見たわけではなく、期間も 2 週間弱です。

この記事の本家（タスクの XML・ログ・直し前後の .ps1・毒テストの凍結、検証の記録）は Sumitsuke Lab → [沈黙する自動化の見つけ方——タスクスケジューラで LastTaskResult=1・ログ 0 行を 2 日続けて踏んだ](https://sumitsuke.jp/via/zenn/lab/task-scheduler-silent-exit-diagnosis/)

### AI の利用について

再デプロイの .ps1 の実装と、この記事の下書きには AI（Claude Code）を使っています。数字（2 回・0 行・23 項目・10 日分）は運用記録とタスクの状態から写し、判断と公開は人が行いました。案件の情報は含みません。

### 関連

書く側の cp932（AI にファイルを書き換えさせたときの罠）は別記事 → [Windows で AI にファイルを書き換えさせたら触っていない行が変わった——5 つの型を 5 行のファイルで再現した](https://sumitsuke.jp/via/zenn/lab/file-edit-five-traps-windows/)。

次に読む: [自作の検査器を数か月運用して数えたら、捕まえた欠陥 5 件に対して検査器を直した回数が 22 件だった](https://sumitsuke.jp/via/zenn/lab/green-is-not-proof/)（こちらは「緑が嘘」、本記事は「赤が出ない」）
