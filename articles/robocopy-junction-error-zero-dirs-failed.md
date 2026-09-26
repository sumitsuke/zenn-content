---
title: "robocopy が 67 回 ERROR でも 0 で終わるスクリプト——切れたジャンクションは写し先が在ると ERROR 行を出さない"
emoji: "💾"
type: "tech"
topics: ["robocopy", "PowerShell", "Windows", "バックアップ", "タスクスケジューラ"]
published: true
---


毎日 13:30 にタスクスケジューラで回している robocopy のミラーのログを、日課の保守点検で初めて中身まで読みました。作業フォルダのジョブは、07-19 から 09-24 までの **67 回すべて `ERROR`**（robocopy の終了コードが 8 以上）でした。一方、スクリプトはその終了コードをタスクへ返さない作りで、09-25 に見たタスクの「前回の実行結果」は **0**（成功）でした（回ごとのタスクの結果は記録に残っていません）。

原因は 2 つありました。1 つはアクセスできない一時フォルダで、こちらはログに `ERROR` の行が出ていました。もう 1 つは、フォルダを移したあとに行き先が消えた pnpm のジャンクション 651 個です。こちらは、毎日のミラーの状態では **`ERROR` の行を 1 行も出さず**、要約の `Dirs` の `FAILED` の列にだけ数えられていました。

![07-19〜09-24 の 67 回は rc 11・9・8（どれも 8 以上＝失敗あり）。スクリプトは rc をタスクへ返さない作りで、09-25 の前回の結果は 0](/images/robocopy-junction-error-zero-dirs-failed/fig1_67runs.png)

## 何が起きていたか

### スクリプトは ERROR と書くが、失敗として終わらない

直す前のスクリプト（パスは伏せています）はこうでした。

```powershell
foreach ($j in $jobs) {
    $args = @($j.Src, $j.Dst, '/MIR', '/FFT', '/R:1', '/W:1', '/NFL', '/NDL', '/NP', '/NJH')
    & robocopy @args | Out-Null
    $code = $LASTEXITCODE
    $status = if ($code -lt 8) { 'OK' } else { 'ERROR' }
    Add-Content -Encoding UTF8 $log "$status (rc=$code): $($j.Src) -> $($j.Dst)"
}
# ここで終わり＝どのジョブが ERROR でも、スクリプトは 0 で終わる
```

robocopy の終了コードはビットの足し算で、8 のビットが立っていれば「コピーできなかったものがある」です。ログの rc は 11（8+2+1）が 47 回、9（8+1）が 18 回、8 が 2 回で、67 回とも 8 以上でした。スクリプトは正しく `ERROR` と書いていましたが、最後に `exit` が無いので、その失敗はタスクスケジューラへ返りません。

⚠ タスクの実行履歴（`Microsoft-Windows-TaskScheduler/Operational`）はこの PC では無効でした。67 回の 1 回ずつの「結果 0」は記録に残っていません。言えるのは「スクリプトは rc に関係なく 0 で終わる作りだった」と「09-25 の時点の前回の結果が 0 だった」までです。

### 原因は 2 つ

| 原因 | ログに出たもの |
|---|---|
| アクセスできない一時フォルダ 8 個 | `ERROR 5`（アクセス拒否）の行が 8 行 |
| 行き先が消えた pnpm のジャンクション 651 個（`node_modules` 650・`.pnpm-store` 1） | `ERROR` の行は 0。要約の `Dirs` の `FAILED` に 651 |

2 つ目は、09-25 に `/L`（一覧だけ出してコピーしない）と `/UNILOG` で回したログで見つけました。`dir /AL /S` で数えたジャンクションの数と、`Dirs FAILED` の 651 が一致しました。

## 「ERROR の行が出ない」はいつ成り立つか

09-25 に見たのは `/L` の 1 回だけです。そこで一時フォルダの中に、ファイル 3 つと、行き先を消したジャンクション 1 個だけの合成の環境を作り、条件を変えて 2 回ずつ回しました（Windows 11・robocopy 10.0.26100.8875）。

![条件ごとの ERROR の行と Dirs FAILED。初回の写しは ERROR が 1 行出るが、写し先が既に在る 2 回目（毎日のミラーの状態）と /L では ERROR 0・Dirs FAILED 1。/XJD・/XD・/SJ は FAILED 0](/images/robocopy-junction-error-zero-dirs-failed/fig2_repro_conditions.png)

| 条件 | rc | ERROR の行 | Dirs FAILED |
|---|---|---|---|
| 初回の写し（`/MIR`） | 9 | 1 | 1 |
| 写し先が既に在る 2 回目 | 8 | **0** | 1 |
| `/L` | 9 | 0 | 1 |
| `/XJD`／`/XD node_modules`／`/SJ` | 1 | 0 | 0 |

初回の写しでは `ERROR 2 (0x00000002) Time-Stamping Destination Directory …\node_modules\` が 1 行出ます。ところが、写し先にそのフォルダが既に在る 2 回目からは、`ERROR` の行が出ず、`Dirs FAILED` と rc 8 だけが残りました。毎日回すミラーは、ほぼいつもこの「2 回目」の状態です。ログを `ERROR` で検索して 0 件でも、失敗が無いとは限りません。

写し先の通常のファイルの一覧は、どの条件でも元と一致しました（`/L` はコピーしないので除く）。

## 今夜 5 分で見る 4 か所

読むだけの点検を PowerShell 1 本にしました。コピーも修正もしません。

1. ログの `ERROR` の行
2. 要約の `Dirs`・`Files` の `FAILED` の列（5 番目の数）
3. 写す元の、行き先が無いリンク（ジャンクション・シンボリックリンク）
4. スクリプトが終了コード 8 以上で 0 以外を返すか（文字で探す目安）

```powershell
powershell -File 点検_読むだけ.ps1 -Log backup.log -Source <写す元のフォルダ> -Script backup_mirror.ps1
```

合成の再現のログに当てると、直す前のスクリプト＋2 回目のログは「見るべき所 2 か所」（Dirs FAILED 1・exit が無い）、直した後は「0」でした。

⚠ この点検のスクリプトは、**UTF-8 の BOM つきで保存**してください。BOM なしで保存したら、Windows PowerShell 5.1 が別の文字コードとして読み、日本語の行で構文エラーになりました（09-26 に当方の手元で起きました）。

## 直したこと

- 読めない一時フォルダ 8 個を、完全パスで `/XD` に入れる
- `node_modules` と `.pnpm-store` を名前で `/XD` に入れる（パッケージの置き場は作り直せるので写さない）
- ERROR のジョブが 1 つでもあれば `exit 1` で終わる

```powershell
    if ($status -eq 'ERROR') { $failed++ }
}
if ($failed) { exit 1 }
```

直した後の 3 回（09-25 11:44・13:30・13:51）は、全ジョブが OK でした。

## 言わないこと

- 「67 回のあいだもバックアップは大丈夫だった」とは言いません。09-25 の 1 回で確かめたのは「robocopy が数えたファイルの FAILED が 0」までです。読めなかった 8 フォルダの中身は写っていません。バックアップ全体が揃っていたかは、この値だけでは分かりません
- `/XJD` が正解とは言いません。合成の再現では `/XJD`・名前の `/XD`・`/SJ` のどれでも FAILED は 0 でしたが、`/SJ` は写し先にリンクのまま作ります。何を写したいかで選ぶ話です
- pnpm のせいにはしません。行き先を消したのは、フォルダを移した側です

この記事の本家（合成の再現のスクリプトと 12 本のログ・点検の PowerShell・数え直し）は Sumitsuke Lab → [robocopy の切れたジャンクションは ERROR 行なしで Dirs FAILED に数えられる（検証の記録つき）](https://sumitsuke.jp/via/zenn/lab/robocopy-broken-junction-dirs-failed/)。

### AI の利用について

ログを数え、合成の再現と点検のスクリプトを書いて回したのは AI（Claude Code）です。直す範囲・公開する範囲の判断は人が行いました。ログのフォルダ名は伏せています。

### 関連

向きが逆の話＝タスクの結果が失敗でログが空だった件 → [Task Scheduler で黙って落ちた自動デプロイ](https://sumitsuke.jp/via/zenn/lab/task-scheduler-silent-exit-diagnosis/)
