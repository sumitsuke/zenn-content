---
title: "1 行直しただけなのに git の差分が全行になったとき、孤立した CR を見つけて直す 3 手"
emoji: "🔍"
type: "tech"
topics: ["git", "autocrlf", "CRLF", "Windows", "Markdown"]
published: true
---


**読むと分かること**: 1 行しか直していない Markdown の `git diff` が全行になったとき、孤立した CR（直後が LF でない CR）が原因かどうかを、コミットの前に見分ける 3 手と、安全に直す順。`core.autocrlf`（4 通り）× `.gitattributes`（2 通り）× 孤立した CR の位置（3 つ）の 24 組を、実際に作って測った結果も付けています。

**結論**

- 全行の差分に当たったら、まず `git ls-files --eol` を打ち、隣のファイルと `i/` の表示が違うものを探す。次に `git diff --stat` と `git diff --ignore-cr-at-eol --stat` の行数を並べ、最後に孤立した CR の行番号を出す
- 手元の測定（200 行の Markdown）では、`.gitattributes` が無い 12 組は、孤立した CR が 1 つあるだけで、`core.autocrlf` が `true` でも `input` でも `false` でも未設定でも、全行の差分（200〜201 行）になった。`*.md text` を足した 12 組は 2 行だった
- `*.md text` で差分が小さくなっても、孤立した CR は残る組が多い。直すなら、孤立した CR を消して `git add --renormalize .` し、`i/lf` になったかを確かめる。直した後に 1 行だけ変えたコミットの差分は 1 行だった

**どう確かめたか**: 使い捨てのリポジトリで、LF だけで記録した 200 行の Markdown の作業コピーを全行 CRLF にして 1 行だけ変え、孤立した CR を 1 つ足してから `git add`・`git commit` し、`git` の 3 つのコマンドの出力をそのまま写しました。予測と、何を全行と呼ぶかの線（変更行数 180）は、測る前に決めて残しました。

**決め手の数**: コミットされる差の変更行数は、`.gitattributes` 無しの 12 組で 200（行末・行の途中）か 201（ファイルの末尾）、`*.md text` ありの 12 組で 2。孤立した CR の無い全行 CRLF のファイルは、属性無しで `true`・`input` なら 1、`false`・未設定なら 200。

**環境**: Windows 11・git 2.53.0.windows.2・Python 3.12.10・2026-10-24 に測定。

**結論が崩れるいちばん大きな限界**: 手元の Windows 1 台・git 1 つの版・200 行の Markdown 1 つで、ほかの版の git・mac・Linux は測っていません。

## 孤立した CR は、3 手で行番号まで絞れる

2026-10-23 に Qiita で、Git for Windows・`core.autocrlf=true`・`.gitattributes` 無しの Markdown に余分な CR が入り、数行を足したコミットが +11,227／−11,220 行になった、という報告が出ました（https://qiita.com/AUTOMOS/items/315ce35f70eec9b3b166）。報告では `git ls-files --eol` が `i/-text w/-text` と出ています。ここでは、同じ形を使い捨てのリポジトリで作り、報告が確かめていない設定と属性の組まで広げて数えました。

### 1 手目: `git ls-files --eol` で、孤立した CR のあるファイルだけ表示が違う

公式の頁（https://git-scm.com/docs/git-ls-files）には、「Both the `<eolinfo>` in the index ("i/`<eolinfo>`") and in the working tree ("w/`<eolinfo>`") are shown for regular files, followed by the ("attr/`<eolattr>`")」とあります。手元で、孤立した CR を 1 つ入れた `doc.md` と、入れていない `neighbor.md` を並べると、こうなりました（属性なし・`true`）。

![git ls-files --eol の出力。孤立した CR を入れた doc.md は i/-text w/-text、入れていない neighbor.md は i/lf w/crlf と表示されている](/images/git-lone-cr-whole-file-diff/photo1_ls_files_eol.png)

`doc.md` だけ `i/-text w/-text`、`neighbor.md` は `i/lf w/crlf` です。なぜ `-text` になるのかは、公式の頁に書かれていないので、ここでは測った表示だけを書きます。

### 2 手目: `--ignore-cr-at-eol` を付けると、行数が桁で減る

```
$ git diff --stat -- doc.md
 doc.md | 400 ++++++++++++++++++++++++++++++++---------------------------------
 1 file changed, 200 insertions(+), 200 deletions(-)

$ git diff --ignore-cr-at-eol --stat -- doc.md
 doc.md | 4 ++--
 1 file changed, 2 insertions(+), 2 deletions(-)
```

上は `git add` の前に打った形です。もう `git add` したなら、2 つとも `git diff --cached` にします（付けないと add した差は出ません。測った 24 組では、add の前の `git diff --stat` と add の後の `git diff --cached --stat` の行数は同じでした）。400 が 4 になるなら、差の大半は行末の CR の違いです。ただし 0 にも 1 にもならず 2 行でした（入れた変更は 1 行）。位置が行末の孤立した CR でも、行の途中でも、ファイルの末尾でも、属性なしでは 2 行でした。

### 3 手目: 孤立した CR の行番号と数を、道具で出す

`check_lone_cr.py` にファイルを渡すと、LF だけの改行・CRLF・孤立した CR の数と、孤立した CR のある行を印字します。孤立した CR が在れば終了の値 1 で終わり、無ければ 0 です。

```
$ python check_lone_cr.py doc.md
doc.md: LF だけ 0 / CRLF 200 / 孤立した CR 1
  孤立した CR のある行: 50
```

この道具は、手で作ったバイト列 6 つ（孤立なし・LF だけ・行末の CR CR LF・行の途中・末尾・LF と CRLF の混在）で、数・行番号・終了の値を先に確かめてあります。コミットの前の確かめにどう組み込むかは、測っていません。

## 直すときは、CR を消して renormalize し、i/lf を確かめる

公式の頁（https://git-scm.com/docs/gitattributes）には、`text` を指定した場合について「Line endings are normalized to LF in the index every time the file is checked in, even if the file was previously added to Git with CRLF line endings.」とあり、直し方の例として `git add --renormalize .` が挙がっています。24 組でいちばん全行になった通り（属性なし・`true`・孤立した CR をファイルの末尾に入れた組）で、見つける・直す・確かめるを 1 回ずつ通しました。

- 見つける: `python check_lone_cr.py doc.md` が「孤立した CR 1・行 201」・終了の値 1
- 直す: 孤立した CR だけ消す（道具をもう一度当てると 0・終了の値 0）→ `git add --renormalize .` → commit
- 確かめる: `doc.md` の `ls-files --eol` と、`git diff --stat HEAD~1 HEAD` を 3 つのコミットで並べる

| コミット | `git ls-files --eol`（doc.md） | `git diff --stat HEAD~1 HEAD -- doc.md` |
|---|---|---|
| 直す前（孤立した CR を含めて記録） | `i/-text w/-text` | +201 −200 |
| 直しのコミット（CR を消して `--renormalize`） | `i/lf w/crlf` | +200 −201 |
| そのあと行 150 だけ変えたコミット | `i/lf w/crlf` | +1 −1 |

直した後は `i/lf` になり、別の 1 行だけ変えたコミットは 1 行の差分になりました。直しのコミット自身は全行を CRLF から LF に戻すので 201 行の差分になります。レビューする人には、先に伝えておくとよさそうです。

## 24 組を測ると、属性なしは全行、`*.md text` ありは 2 行だった

入れたのは 1 行の変更と 1 つの孤立した CR だけです。孤立した CR の位置は、A＝行 50 の行末（CR CR LF）・B＝行 50 の途中・C＝ファイルの末尾（最終行の CRLF のあとに CR を 1 つ）の 3 つ。`core.autocrlf` は `true`・`input`・`false`・未設定、属性は無しか `.gitattributes` に `*.md text` の 1 行で、3 × 4 × 2 の 24 組です。「全行の差分」は、`git add` のあとの `git diff --cached --stat -- doc.md` の変更行数（挿入と削除の大きい方）が 180 以上（200 行の 9 割）のこととしました。

![設定 4 通り × 属性 2 通りの 8 行と、孤立した CR の位置 3 つ＋対照の表。属性なしの 4 行は孤立した CR の 3 位置とも全行の差分（赤）、*.md text ありの 4 行は 2 行（緑）。孤立した CR の無い対照は、属性なしの false と未設定だけ 200 行（赤）](/images/git-lone-cr-whole-file-diff/fig1_lone_cr_matrix.png)

| 属性 | autocrlf | A 行末 | B 途中 | C 末尾 | 対照（孤立した CR なし） |
|---|---|---|---|---|---|
| なし | `true`・`input` | 200（中身 2）`i/-text` | 200（中身 2）`i/-text` | 201（中身 2）`i/-text` | 1 行・`i/lf` |
| なし | `false`・未設定 | 200（中身 2）`i/-text` | 200（中身 2）`i/-text` | 201（中身 2）`i/-text` | 200 行・`i/crlf` |
| `*.md text` | 4 通りとも | 2（中身 1）`i/mixed` | 2（中身 2）`i/-text` | 2（中身 2）`i/-text` | 1 行・`i/lf` |

各マスは、コミットされる差の変更行数で、「中身」は `--ignore-cr-at-eol` を付けたときの変更行数です。

属性なしの 12 組は、`true` でも全行になりました。対照を見ると、孤立した CR が無ければ `true`・`input` は 1 行で済み、`false`・未設定は CRLF のまま記録されて 200 行になります。つまり、孤立した CR が 1 つあると、`true`・`input` でも `false`・未設定と同じ結果になりました。

### `*.md text` を足すと 201 行が 2 行になる。ただし孤立した CR は残る

全行の差分がいちばん大きかった通り（属性なし・`true`・位置 C・201 行）に、add の前に `*.md text` の 1 行を足して数え直すと、差分は +2 −1 の 2 行になりました。1 行にならないのは、最終行の次に孤立した CR の 1 行が増えた分です。add のあとの `doc.md` は `i/-text w/-text` のままで、索引の中身にも孤立した CR が 1 つ残っています。`*.md text` ありの位置 B・C の組も、2 行で、孤立した CR が索引に残りました。差分を見て安心すると、孤立した CR は記録されたまま残ります。

### 予測と違った所

- 「`*.md text` ありでも、孤立した CR は索引にそのまま残る」は、位置 A では外れました。CR CR LF だった行が、索引では LF 199・CRLF 1 の内訳（`i/mixed`）になりました
- 「`--ignore-cr-at-eol` なら入れた変更の 1 行だけが出る」にはなりませんでした（属性なしは 12 組すべて 2 行・属性ありは位置 A だけ 1 行）
- 設計に無い追加として、「未設定」の組を手元の system・global の設定から切り離す環境変数（`GIT_CONFIG_NOSYSTEM=1` と空の `GIT_CONFIG_GLOBAL`）を、測る前に決めて台本に足しました。手元の通常の設定でどうなるかは測っていません

## 測っていないこと・言わないこと

- この 24 組は、それぞれ 1 回だけ作って数えた探索的な結果です（同じ組を作り直すと同じ数が出ることは 1 組で確かめました）
- ほかの版の git・mac・Linux・GitHub の画面の差分の表示
- 孤立した CR がどこから入るか（エディタ・コピー・AI など）。孤立した CR が `-text` と表示される git の中の決まり
- 最終行が CR だけで終わる（改行なし）形・行の先頭の孤立した CR など、ほかの形の孤立した CR
- 本物のリポジトリの履歴の書き換え。この記事の手順は使い捨てのリポジトリだけで通しました

## 本家（Lab）

予測と条件・24 組の出力の写し・集計・点検の道具・24 組を作り直す台本・「全行の差分を見分ける 3 手と直し方」（1 枚）は、本家の `evidence/` と同梱に置いています → [git の差分が全行になる：孤立した CR 1 つで、autocrlf を変えても属性なしでは全行だった](https://sumitsuke.jp/via/zenn/lab/git-lone-cr-whole-file-diff/)

### AI の利用について

測定の台本と点検の道具の作成・使い捨てのリポジトリでの実行・数え直し・図と写真の作成・この記事の下書きは AI（Claude Code）が行いました。人がしたのは、記事に出すかどうかの判断です。
