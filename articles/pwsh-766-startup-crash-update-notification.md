---
title: "PowerShell 7.6.6 が起動直後に totalWidth で落ちたら——更新の知らせを Off にして開いた 18 回"
emoji: "🪟"
type: "tech"
topics: ["PowerShell", "pwsh", "Windows", "環境変数", "不具合"]
published: true
---


手元の PowerShell 7.6.6 で、設定を何もせずに `pwsh` を対話で起動したら、窓が出て 1 秒足らずで終わりました。窓に残ったのは `Process terminated.` と `totalWidth ('-10') must be a non-negative value.` の例外です。

![落ちた窓。PowerShell 7.6.6 の次に Process terminated. と totalWidth ('-10') の例外・スタックが出て、窓が終わる](/images/pwsh-766-startup-crash-update-notification/photo1_crashed_window.png)

この記事は、同じ症状の人が次に何を試せばよいかを 1 枚の判断表にして、その各段を手元で何回試したかを並べた記録です。

**この記事の位置づけ**

- 測ったこと: 手元の 1 台（Windows 11・表示の言語 ja-JP・PowerShell 7.6.6）で、設定なし／`POWERSHELL_UPDATECHECK=Off`／`LTS` × 既定／`-NoProfile` × 各 3 回の 18 回。
- 先に弱点: 英語表示では起動していません。7.6.7 も入れていません。`LTS` で開いた理由は測っていません。1 台・各 3 回です。
- 公式と課題に書いてあること（引用は後ろの節）と、手元で測ったことは分けて書きます。

## 先に結論（手元の範囲）

- 設定なしの対話の起動は 6/6 落ちました（既定 3・`-NoProfile` 3）。`-NoProfile` でも変わりませんでした。
- `POWERSHELL_UPDATECHECK=Off` を、起動する pwsh だけに渡すと 6/6 開きました。順を 無し→Off→無し にしても、落ち→開き→落ちでした。外せばまた落ち、入れれば開きます。
- `LTS` も 6/6 開きました。理由は見ていません。

![条件ごとの起動の成否。設定なしは既定・-NoProfile とも落ちた 3/3、Off と LTS はどちらの形でも開いた 3/3](/images/pwsh-766-startup-crash-update-notification/fig1_result_matrix.png)

## 起動で落ちたときの判断表

手元で測れた段と、測っていない段を分けています。

| 段 | やること | 手元の結果 |
|---|---|---|
| 1 | `pwsh --version` で版を見る | 手元は `PowerShell 7.6.6`。以降の数字はこの版の物 |
| 2 | `pwsh -NoProfile` で開くか | 手元では `-NoProfile` でも 3/3 落ちた（プロファイルの有無で変わらなかった） |
| 3 | `POWERSHELL_UPDATECHECK=Off` を、その起動にだけ渡す | 開いた 6/6。測った形は「pwsh 7 のセッションで環境変数を入れてから `Start-Process` で起動」 |
| 4 | 毎回の起動に効かせたいとき | ユーザーの環境変数に永続で入れる形は試していない（変えない方針で測った） |
| 5 | 直った版が出たら | 設定を外す。`Off` は知らせの機能そのものを止める（公式の逐語は後ろ） |

段 3 の 1 行は、手元で測った形をそのまま書くとこうです（入れ先は既定の Program Files の下。`$env:ProgramFiles` はこの PC では手元で測ったときの入れ先と同じ所を指します）。

```powershell
$env:POWERSHELL_UPDATECHECK = 'Off'
Start-Process "$env:ProgramFiles\PowerShell\7\pwsh.exe"
```

落ちる pwsh の中では打てないので、別のシェルから出すことになります。Windows PowerShell 5.1 や `cmd`、ショートカットから同じ値を渡す形は測っていません。公式は "You must set this environment variable before PowerShell starts." と書いています。

## どうやって試したか

1. 測る前に、予測と条件（設定なしで落ちる・Off で開く・外すとまた落ちる）をファイルに書きました。
2. `Start-Process` で新しい窓に `pwsh` を出し、12 秒後に生きているか・終了コード・Windows の Application ログ（`.NET Runtime`／`Application Error` の pwsh の行）を 1 回 1 行で記録。生きていれば止めました。
3. 回避の設定は、親のプロセスの環境変数にだけ入れ、起動の直後に戻しました。ユーザー・システムの環境変数は変えていません。
4. 順は 無し・Off・無し・LTS・Off・無し・LTS・Off・LTS（既定と `-NoProfile` で同じ）。
5. 窓の写真は、18 回とは別の追加の起動で、前景の窓の矩形だけを撮りました。

## 何が起きたか

落ちた 6 回はどれも終了コード -2146232797（0x80131623）でした。Application ログの行は、起動から 0.36〜0.67 秒後に出ています。

- `.NET Runtime`（1025・FailFast）: `totalWidth ('-10') must be a non-negative value.`
- スタック: `System.String.PadRight` ← `Microsoft.PowerShell.UpdatesNotification.ShowUpdateNotification` ← `ConsoleHost.Start`
- `Application Error`（1000）: 例外コード 0x80131623・`Microsoft.PowerShell.ConsoleHost.dll`。プロセス ID は 6 回とも、起動した pid と一致

写真の窓の文言は、このログの 1025 と同じ文言・同じスタックの順でした。

Off を渡した 6 回と LTS の 6 回は、12 秒後に生きていました。窓にはバナーとプロンプトだけが出ています（プロンプトのパスは伏せました）。

![Off を渡して開いた窓。PowerShell 7.6.6 のバナーのあと、プロンプトの行（パスを伏せた）が出る](/images/pwsh-766-startup-crash-update-notification/photo2_off_window.png)

## 知らせの文の長さを数えた

インストール先の資源（`Microsoft.PowerShell.ConsoleHost`）を読み、更新の知らせの雛形を行ごとに数えました。日本語の stable の文は 1 行目が 41 字、3 行目（URL の行）が 51 字で、1 行目から引くと -10 です。起動で落ちたときの `-10` と数字が合いました。英語の stable は 57 と 51 で +6 です。

![知らせの文の 1 行目と 3 行目の文字数の差。英語は stable +6・LTS +3、日本語は stable −10・LTS −9](/images/pwsh-766-startup-crash-update-notification/fig2_template_line_lengths.png)

v7.6.6 のソース（`UpdatesNotification.cs` の 127〜136 行）では、3 行目の余白の幅を `line1Length - line3Length + 3` で出しています（`lineNLength` は雛形の改行の位置から数えた長さ）。手元の資源の雛形をこの式にそのまま当てると、日本語は `45 - 58 + 3 = -10`、英語は `61 - 58 + 3 = 6` でした（[ソース](https://github.com/PowerShell/PowerShell/blob/v7.6.6/src/Microsoft.PowerShell.ConsoleHost/host/msh/UpdatesNotification.cs)）。日本語の値は、落ちたときの `-10` と同じです。英語での起動は試していません。窓の幅は変えていないので、幅との関係も測っていません。

## 公式と課題に書いてあること

- about_Update_Notifications（PowerShell 7.6）: "Every time PowerShell starts, PowerShell waits 3 seconds before it checks for updated versions." "`Off` turns off the update notification feature" "`LTS` only notifies of updates to long-term-servicing (LTS) GA releases" "You must set this environment variable before PowerShell starts."（[公式](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_update_notifications?view=powershell-7.6)）
- 課題 #28235（2026-10-20 起票・OPEN）の題は "[Bug] Startup crash: PadRight totalWidth -17 in ShowUpdateNotification when console width is too narrow"。コメントの 1 つは、利用者の分析（公式の見解ではない）として "The console width is not involved in this crash" "The value depends only on the line lengths of the localized template and the release tag" と書き、回避策に "set `POWERSHELL_UPDATECHECK=Off` before PowerShell starts." を挙げています（[課題](https://github.com/PowerShell/PowerShell/issues/28235)）。手元の `-10` は題の `-17` と別の数字です。
- 課題 #28131（2026-09-30 起票・CLOSED）の題は "PowerShell can crash on startup when displaying the update notification under zh-Hans due to negative PadRight width"（[課題](https://github.com/PowerShell/PowerShell/issues/28131)）。
- PR #28242 "Remove the Update Notification feature from PowerShell" は 2026-10-20 に MERGED で、ラベルに "Backport-7.6.x-Approved" があります（[PR](https://github.com/PowerShell/PowerShell/pull/28242)）。取り込まれたのは master と、7.6 系へ戻す承認の札までで、出た版は確かめていません。

## うまくいかなかったこと・測っていないこと

- 本人の知らせの記録を守るため、記録の複製を `LOCALAPPDATA` で渡す予定でしたが、子の pwsh は差し替え先を使わず本来の場所を答えました。起動は本来の場所のまま行い、既存の記録のハッシュと時刻が前後で同じことを確かめています。
- 測定のあと、pwsh が `sentinel2-2026-10-21.done`（0 バイト）を新しく作っていました。LTS の起動の最中に作られましたが、起動した pid とは結べておらず、消していません。
- 設定なしで落ちた 1 回と LTS の 1 回で、別の pwsh の物かもしれない 1025 が混ざりました。判定は生存と終了コードで行ったので、18 回の分類は変わりません。
- 英語表示での起動・7.6.7・別の PC・ユーザーの環境変数を永続で入れた場合・窓の幅を変えた場合は測っていません。

### AI の利用について

起動・待機・Application ログの照合・集計の道具の作成と実行、資源の数え、図と原稿の下書きは AI（Claude Code）が行いました。人がしたのは、記事に出すかどうかの判断です。

### 関連

測定の全記録（18 回の起動の 1 行ずつの記録・予測と結果の照らし合わせ・道具）は Sumitsuke Lab → [PowerShell 7.6.6 が起動時に落ちた——更新の知らせを切ると開くか、手元で 18 回試した](https://sumitsuke.jp/via/zenn/lab/pwsh-7-6-6-startup-crash-update-notification/)

別の版・別の原因の記事 → [タスクスケジューラの PowerShell 5.1——BOM と git の stderr で自動デプロイが 2 回止まった](https://zenn.dev/tauridev/articles/task-scheduler-powershell51-silent-exit)
