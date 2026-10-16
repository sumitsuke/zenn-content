---
title: "GitHub の「メールを晒す push を止める」は古い commit と未登録のメールを見ない——4 通り × 2 回"
emoji: "📮"
type: "tech"
topics: ["github", "git", "githooks", "セキュリティ", "個人情報"]
published: true
---


2026-09-26、公開リポを外部の精査にかけたら、14 本中 9 本の履歴に Gmail のアドレスが残っていると指摘されました。作者か記録者が Gmail の commit は 38。うち 19 は個人のメールでした。

GitHub の「コマンドラインからの push で、メールを晒すものを止める」設定は、その日に有効にしました。では、この設定があれば防げたのか。非公開の捨てリポに 4 通りの push を 2 回ずつして確かめました。

**答え: 防げなかった型でした。** 個人のメールはアカウントに登録していなかったので、設定の対象の外でした。

![GitHub の設定の push の結果＝対照（最新の作者が A）止まった×2／①古い commit だけ A 通った×2／②記録者だけ A 止まった×2（予測は通る）／③未登録の B 通った×2](/images/github-email-block-misses-old-and-unregistered/fig1_push_results.png)

**この記事の位置づけ**

- 新しく示すこと: 設定が見る所・見ない所を 4 通り × 2 回の push で分けたことと、手元で止める pre-push の最小の形。
- 当てはまる範囲: GitHub.com の個人アカウント 1 つ・2026-09-28 の挙動。組織や Enterprise は確かめていません。各 2 回なので探索的な記録です。

## 4 通りの push

A＝アカウントに登録して非公開にしたメール、B＝どこにも登録していない架空のアドレス（example.com）です。

| 通り | 何を入れたか | 結果（2 回とも同じ） |
|---|---|---|
| 対照 | 最新の commit の作者が A | 止まった |
| ① | 古い commit だけ作者が A、最新は noreply | 通った |
| ② | 記録者（committer）だけ A、作者は noreply | 止まった |
| ③ | 作者が未登録の B | 通った |

止まったときの返事は `GH007: Your push would publish a private email address.` でした。

公式文書は「最新の commit の作者」と書いているので、② は通ると思っていました。実際には止まりました。文書より少し広く見ています。

見ていないのは 2 つです。**古い commit** と、**アカウントに登録していないメール**。

## 自分の漏れはどの型だったか

個人のメールの主な入り口は、公開リポの手元の作業コピーに残っていた、リポ単位の作者設定でした。そのメールはアカウントに登録していません。つまり ③ の型で、設定を先に入れていても止まらなかったことになります。

もう 19 の commit はアカウントの主メール（当時は公開の設定）で、API から一括で commit したときなどに入っていました。入った操作ごとの数は、数え直すと合わなかったので書きません。

## 手元で止める最小の pre-push

GitHub の設定に頼らず、送る前に手元で止めます。git は pre-push フックの標準入力に「送る ref」を 1 行ずつ渡すので、それを全部読みます。

```sh
#!/bin/sh
z=0000000000000000000000000000000000000000
while read lref lsha rref rsha; do
  [ "$lsha" = "$z" ] && continue                     # ブランチの削除
  if [ "$rsha" != "$z" ] && git cat-file -e "$rsha^{commit}" 2>/dev/null; then
    range="$rsha..$lsha"                             # 普通の更新
  else
    range="$lsha --not --remotes=$1"                 # 新しいブランチ・タグ・強制 push
  fi
  bad=$(git log --format='%h %ae %ce' $range | awk '$2 !~ /noreply\.github\.com$/ || $3 !~ /noreply\.github\.com$/ {print $1}')
  if [ -n "$bad" ]; then echo "止めた: $lref に noreply でない commit: $bad" >&2; exit 1; fi
done
exit 0
```

これを手元の一時リポ（送り先も手元）で 8 通り当てました。

| 当てたもの | 結果 |
|---|---|
| 全部 noreply（新しいブランチ・普通の更新） | 通った ×2 |
| 最新の作者が example.com | 止まった |
| 記録者だけ example.com | 止まった |
| 古い commit だけ example.com | 止まった |
| 今いないブランチを push | 止まった |
| 漏れた commit を指す軽いタグ | 止まった |
| 書き換えて強制 push | 止まった |

作者と記録者の両方を見るのと、`@{u}..HEAD` でなく標準入力の ref を使うのが要点です。当方の最初の版は `@{u}..HEAD` で書いていて、別のブランチとタグを見ていませんでした。注釈つきタグの tagger や、本文に入った語はこの形では見ません。

## うまくいかなかったこと

- pre-push を入れていたのは、14 本中 2 本の作業コピーだけでした。「作者は noreply」と決めて記録したのに、設定まで直していなかったからです。全部の作業コピーと、新しい clone に入る `init.templateDir` に入れました
- 履歴を書き換えても、識別子を直に開く commit のページや Events API の push の記録（89 件中 79 件が古い識別子）には古いものが残っていました。GitHub サポートへの削除の依頼の結果は、まだ確かめていません
- 挙動は 1 アカウント・1 日・各 2 回の観測です。GitHub 側でタグや別ブランチの push は試していません

この記事の本家（push の記録・8 通りの確かめ・手元の 4 層）は Sumitsuke Lab → [GitHub の「メールが見える push を止める」設定が見ていた所・見ていなかった所（検証の記録つき）](https://sumitsuke.jp/via/zenn/lab/github-email-push-block-measured/)。

### AI の利用について

点検・pre-push・この記事の下書きは AI（Claude Code）が書きました。捨てリポへの push と削除、設定の変更は本人が行いました。漏れた値と古い識別子は書いていません。

---

Sumitsuke は、AI や外注で作ったものの点検と修理、業務自動化、検証を受託しています。公開する前に「履歴に何が残るか」を数で確かめる設計は → https://sumitsuke.jp/works/verification/
