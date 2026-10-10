---
title: "「テスト 3,000 件・全部緑」を証拠にする出し方——数え方と範囲を変えて数えたら 453／3,160／4,878 になった"
emoji: "🧾"
type: "tech"
topics: ["テスト", "Rust", "vitest", "CI", "開発プロセス"]
published: true
---


「テストが 3,000 件あって全部通っています」は、そのままでは自己申告です。第三者が信じられる形にするには、**何件・何を・どのコミットで・どのコマンドで**回したかが要ります。自作アプリ（Rust＋TypeScript・ソロ開発）のローカル CI のログ 1 回分を材料に、証拠として出す 3 点と、**同じ commit のテストが、数え方と範囲で 453〜4,878 に変わった実例**（453 は TypeScript だけの静的な数）を書きます。

**この記事の位置づけ**（2026-09-26 追記）

- この記事で新しく示すこと: 証拠として出す 3 点（件数・コマンド・commit）と、`cargo test --tests` が lib のテストを再走させて二重に数える実例。
- 当てはまる範囲: 自作アプリ 1 本・CI ログ 1 回分。453 は TypeScript だけを静的に数えた数で、3,160・4,878 とは範囲が違います。

## 証拠に必要な 3 点

1. **ランナーの生ログ**（passed／failed／ignored の実数が書かれた行）
2. **再現手順**（commit・コマンド・日時）
3. **二重計上を引いた数**（ここが本題）

合否を終了コードでなく件数で読む理由は別の記事（[緑を信じない](https://sumitsuke.jp/via/zenn/lab/green-is-not-proof/)）に書いたので、ここは「出し方」だけに絞ります。

## 材料＝2026-06-10 のローカル CI ログ 1 回分

commit `13638212`（2026-06-10 15:02）に対して 15:10 に回した 13 ステップ、全 exit 0、114.6 秒。ステップごとにログが 1 本ずつ残っています。テストに関わるのは 3 本です。

| ステップ | コマンド | ログの結果行 |
|---|---|---|
| cargo-test-lib | `cargo test --lib` | `test result: ok. 1718 passed; 0 failed; 1 ignored; 0 measured; 0 filtered out` |
| cargo-test-integration | `cargo test --tests` | `test result:` が **12 行**・passed の合計 2,199 |
| vitest | `npm run test` | `Test Files 57 passed (57)` `Tests 961 passed (961)` |

![同じ commit を、数え方と範囲を変えて数えたら 453（TypeScript だけの静的 grep＝範囲が違う）／3,160（ランナーのログ・二重を引く）／4,878（passed を素直に足す）](/images/prove-tests-by-run-log/t1_three_counts.png)

## 数え方 1: ログの passed を素直に足す → 4,878

1,718 ＋ 2,199 ＋ 961 ＝ **4,878**。これを「テスト 4,878 件」と書くと嘘になります。

## 数え方 2: 二重計上を引く → 3,160

`cargo test --tests` のログの 12 行を `Running` 行と突き合わせると、こうなっていました。

```
unittests src\lib.rs                            1718 passed (1 ignored)   ← --lib と同じもの
unittests src\main.rs                              0 passed
tests\baseline_integrity.rs                       11
tests\db.rs                                       45
tests\deletion_factory_reset_contract.rs           3
tests\dev_prod_separation.rs                       4
tests\ingest_disabled_by_default_contract.rs       2
tests\integration.rs                             363 (12 ignored)
tests\pre_release.rs                              25
tests\rendering.rs                                 6 (3 ignored)
tests\security.rs                                 19
tests\ssot_thresholds_contract.rs                  3
```

`cargo test --tests` は「テスト対象のターゲット全部」なので、**lib のユニットテスト 1,718 件をもう一度走らせています**。統合テストとして数えてよいのは残りの 481 件。したがって

- Rust ユニット 1,718
- Rust 統合 481
- vitest 961
- 合計 **3,160**（＋ ignored 16。内訳は下の「ignored も書く」）

`--lib` と `--tests` を別ステップに分けると（分けたい理由はある＝統合は遅い）、ログの上では lib が 2 回出ます。**分母は `Running` 行で作る。** `test result:` 行だけを足すと二重になります。

## 数え方 3: ソースを静的に grep する → 453

同じリポに「テストの棚卸し」用のスクリプトがあり、`test(`／`it(` の出現を数えます。同じ commit `13638212` のソースを数えると vitest **453**。ランナーは 961 と言っています。この commit の TypeScript に `describe.each`／`test.each`（`.each(`）は 0 件でした。差は、ループ（`for … of` の中で `it(` を宣言）で 1 つの宣言が複数件として実行されるためだ、と読んでいます。ただし 961−453＝508 件の内訳（ループの展開数の合計）は数えていないので、「主な理由と読んでいる」までです。逆に、`#[test]` の行数を数えるスクリプトは `#[ignore]` の行を見ないので、走らない分を引けません。

静的な件数は「テストコードの規模」の目安にはなりますが、**「実行されたテストの件数」ではない**。証拠に使う数はランナーのログからだけ取ります。

## ignored も書く

ログの結果行には、lib に `1 ignored`、統合の `integration.rs` に `12 ignored`、`rendering.rs` に `3 ignored` があり、合計は **16** です（vitest の skip は 0）。`--tests` のログにも lib の行が再び出ますが、数えるのは 1 回です。実際に抜き出すと、こうなっています。

```
test result: ok. 1718 passed; 0 failed; 1 ignored; 0 measured; 0 filtered out; finished in 3.35s
test result: ok. 363 passed; 0 failed; 12 ignored; 0 measured; 0 filtered out; finished in 1.44s
test result: ok. 6 passed; 0 failed; 3 ignored; 0 measured; 0 filtered out; finished in 0.00s
```

中身が分かっているのは lib の 1 件だけで、ビルド時の環境変数と実ネットワークが要る手動の e2e です。残りの 15 件（統合 12・rendering 3）が走らない理由は確かめていません。「全部緑」と書くときは、走らなかったものが何件あって、なぜ走らなかったかを添えます。0 件なら 0 件と書く。私自身、この記事の下書きでは ignored を 1 件と書いていました。結果行を全部数え直して 16 になりました。

## 数は動く。だから時点を書く

同じリポについて 2026-06 上旬に書いた下書きには「約 3,200 件（Rust 2,204＝ユニット 1,723＋統合 481・vitest 996）」とありました。2026-06-10 のログでは 3,160。どちらも嘘ではなく、**時点が違う**だけです。件数を書くときは日付と commit を必ず横に置く。「現在 3,000 件以上」のような書き方は、更新されない限り古くなります。

## 出す形（テンプレ）

```
テスト実行の記録
- 対象: <リポ> commit <hash>（<日付>）
- コマンド: cargo test --lib / cargo test --tests / npm run test
- 結果（ランナーのログから・二重計上を除く）:
  - Rust ユニット   1,718 passed / 0 failed / 1 ignored（理由: 環境変数と実ネットワークが要る手動 e2e）
  - Rust 統合         481 passed / 0 failed / 15 ignored（10 ファイル。--tests のログに含まれる lib 1,718 は除外。ignored＝integration.rs 12・rendering.rs 3、理由は未確認）
  - vitest            961 passed（57 ファイル）
  - 合計            3,160 passed / ignored 16
- ログ: reports/ci-local/<ts>/T2-cargo-test-lib.log ほか 2 本（添付）
- 参考: 静的な test() の出現数は 453（実行件数ではない）
```

納品やレビューで「テストは何件ですか」と聞かれたら、この形で返します。聞く側なら、**「その数はどのログのどの行から来ましたか」**の 1 問で、上の 3 通りのどれかが分かります。

## 手順として

1. 件数はランナーの結果行からだけ取る（終了コード・静的 grep・記憶からは取らない）
2. `Running` 行（またはテストファイル名）で分母を作り、同じバイナリが 2 回出ていないか見る
3. ignored／skipped を件数と理由つきで書く
4. commit・コマンド・日時をログの隣に書く
5. ログそのものを添付する（数字だけ写さない）

### AI の利用について

ローカル CI と棚卸しのスクリプトは AI（Claude・Codex）と書きました。この記事の数え直し（12 行の突き合わせ・静的 453 との比較）も AI（Claude Code）が行い、人間が裁定と公開の判断をしました。数字は 2026-06-10 のログから写しています。再計測はしていません（この記事の主張は数の出し方で、件数そのものではありません）。

### 関連

- 本家（検証の記録つき・受け取る側の 1 問）: [テスト件数を数え方と範囲を変えて数えたら 453／3,160／4,878 だった——納品書に書く数はどれか](https://sumitsuke.jp/via/zenn/lab/test-count-three-ways/)
- 合否を終了コードでなく件数で読む理由: [自作の検査器を数か月運用して数えたら、捕まえた欠陥 5 件に対して検査器を直した回数が 22 件だった](https://sumitsuke.jp/via/zenn/lab/green-is-not-proof/)
- 納品を受ける側が見る確認証拠: [AI 生成コードの検収シート（Markdown・1 枚）——「動いた」を「期待値と一致した」に置き換える 9 項目](https://sumitsuke.jp/via/zenn/lab/ai-code-acceptance-sheet/)

次に読む: [約束を縛る検査スクリプトの文面が古くなっていた——許可リストを 1 本増やしたとき、直し忘れた 2 か所](https://sumitsuke.jp/via/zenn/lab/guard-message-drift/)
