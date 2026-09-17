---
title: "「外部に通信しません」を CI で縛る——許可 2 ファイル・8 パターン・97 行の bash と、その器の文面が古くなっていた話"
emoji: "🔒"
type: "tech"
topics: ["Rust", "Tauri", "CI", "セキュリティ", "シェル"]
published: false
---


「データを外に出しません」と説明文に書いたアプリは、その後に足される便利な API・解析タグ・クラッシュレポート 1 本で、説明文だけが嘘になります。設計思想はコードを縛らないので、**約束を CI で縛る**ことにしました。先に言うと、これは**外部通信ゼロの証明ではありません**。新しい通信経路が黙って増えたときに検知するトリップワイヤーで、見ない範囲が 4 つあります（後半に表）。自作の Tauri アプリ（Rust バックエンド・ソロ開発）で運用している 97 行の bash と、今日その器に毒を入れて赤を確かめた記録、そして**読んで見つけた欠陥 1 つ**の話です。

![器が見る範囲と見ない範囲。縛る語 8 パターン・許可 2 ファイル・毒で exit 1・見ないもの 4 つ・エラー文の文面ドリフト](/images/outbound-network-guard-ci/g1_guard_scope.png)

## 何を縛るか＝「外向き通信を作れる語」

外向きの通信を作るコードは、Rust では限られた語で書かれます。HTTP クライアントと生ソケットの 8 パターンを grep の対象にしました。

| 種類 | パターン |
|---|---|
| HTTP クライアント | `reqwest::` `hyper::Client` `isahc::HttpClient` `surf::Client` `ureq::` |
| 生ソケット | `TcpStream::connect` `UdpSocket::bind` `TcpListener::bind` |

これらが**許可リスト以外の `.rs`** に 1 つでも出たら exit 1。許可リストは 2 ファイルだけです。

| 許可ファイル | 用途 |
|---|---|
| `infrastructure/update_checker.rs`（447 行） | 手動の更新確認（利用者が押したときだけ・TLS 1.2 以上・リダイレクト方針・JSON サイズ上限） |
| `infrastructure/ingest_client.rs`（150 行） | 同意した人だけの送信。ビルド時の環境変数が無いビルドでは送信そのものが無効 |

`UdpSocket::bind` は listen にも使う語なので偽陽性が出ますが、コメントに「不正確だが安全側」と書いて許容しています。落とす側に倒す。

## 器の骨（97 行のうち効いている部分）

```bash
ALLOWLIST=(
  "src-tauri/src/infrastructure/update_checker.rs"
  "src-tauri/src/infrastructure/ingest_client.rs"
)
PATTERNS=( "reqwest::" "hyper::Client" "isahc::HttpClient" "surf::Client" "ureq::"
           "TcpStream::connect" "UdpSocket::bind" "TcpListener::bind" )

violations=0
for pattern in "${PATTERNS[@]}"; do
  if matches=$(grep -rln "$pattern" "$src_dir" 2>/dev/null); then
    while IFS= read -r file; do
      rel_path="${file#"$repo_root/"}"
      allowed=0
      for allow in "${ALLOWLIST[@]}"; do
        [ "$rel_path" = "$allow" ] && { allowed=1; break; }
      done
      if [ "$allowed" = "0" ]; then
        echo "[outbound-network-guard] VIOLATION: $rel_path uses '$pattern'"
        violations=$((violations + 1))
      fi
    done <<< "$matches"
  fi
done
[ "$violations" -gt 0 ] && { echo "FAIL — $violations violation(s)"; exit 1; }
echo "OK — outbound network surface limited to allowlist (${#ALLOWLIST[@]} file(s))"
```

ローカル CI の第 2 層（型チェック・lint・テストと同じ層）に 1 ステップとして置いてあります。記録に残っている 9 走で **494〜872 ms**。1 秒未満なので、毎回回しても誰も止めません。

## 毒を 1 本入れて赤を見る（2026-09-16）

「落ちるはず」は、落としてみるまで分かりません。許可リストに無いファイルに `reqwest::` を 1 行書いて走らせました。

```bash
$ bash tools/outbound-network-guard.sh
[outbound-network-guard] OK — outbound network surface limited to allowlist (2 file(s))
exit=0

$ mkdir -p src-tauri/src/_poison_tmp
$ printf 'fn x(){ let _c = reqwest::Client::new(); }\n' > src-tauri/src/_poison_tmp/p.rs
$ bash tools/outbound-network-guard.sh
[outbound-network-guard] VIOLATION: src-tauri/src/_poison_tmp/p.rs uses 'reqwest::'
  (SSOT §5.2 Data Sovereignty: only update_checker.rs may make outbound HTTP calls)
  If this is intentional (new feature requiring outbound), update:
    1. SSOT §5.2 to document the new outbound path
    2. tools/outbound-network-guard.sh ALLOWLIST
    3. Privacy.md user-facing description
[outbound-network-guard] FAIL — 1 outbound network violation(s) detected
exit=1
```

clean で 0、毒で 1。器は効いています。

## 読んで見つけた欠陥＝器の文面が古い

上の出力をよく読むと、**エラー文が「only update_checker.rs may make outbound HTTP calls」と言っているのに、許可リストは 2 ファイル**です。2 本目（同意した人だけの送信）は 2026-05-22 に足されました。そのとき、器の本体（配列）は直したのに、**エラー文と冒頭のコメント**は直していない。

皮肉なのは、そのエラー文自身が「許可を増やすときは ①設計文書 ②許可リスト ③利用者向けの説明 の 3 点を直せ」と指示していることです。指示している当の文が 4 か月古いままだった。

ここから持ち帰ったのは 1 つ。**約束を縛る器は、器の中の「約束の文面」までは縛らない。** 配列は grep で効くが、文字列は誰も検査しない。許可リストの件数をエラー文に埋め込む（`${#ALLOWLIST[@]}` は末尾の OK 行では使っているのに、FAIL 側の文では固定文だった）だけで、この種のドリフトは消えます。

## この器が見ないもの（ここを書かないと嘘になる）

| 見ないもの | 理由 |
|---|---|
| フロント側の `fetch()` | Tauri の IPC で内部に閉じる前提。フロントは CSP（`connect-src 'self' https://api.github.com`）という**別の層**で縛る |
| `std::process::Command` で curl 等を呼ぶ経路 | 語が違う。パターンに無い |
| 依存クレートの内部が通信する場合 | 自分のソースしか grep していない |
| ドキュメント・設定ファイルの URL | 記述であって通信ではない（意図的に除外） |

だからこの器の主張は「外部通信がゼロである」ではなく、**「新しい通信経路が黙って増えない」**です。証明ではなくトリップワイヤー。約束の文面もその強さで書く必要があります。

## 手順として

1. 約束を「語の許可リスト」に落とす（何が出たら約束違反か、grep できる形で）
2. 許可する場所をファイル単位で列挙する（ディレクトリ単位にしない）
3. CI の軽い層に置く（1 秒未満なら毎回回る）
4. 毒を 1 本入れて exit 1 を見る（見るまで「効いている」と言わない）
5. 許可を増やしたら、配列・エラー文・利用者向けの説明を同じコミットで直す。文面に件数を埋め込めるなら埋め込む
6. 「見ないもの」を器の冒頭に書く。器の主張はその範囲まで

### AI の利用について

器の初版は 2026-05 に AI（Claude）と書き、8 パターンへの拡張と許可リストの追加も同様です。今日の毒テストの実行と文面ドリフトの発見も AI（Claude Code）の作業で、記事の構成と公開の判断は人間が行いました。エラー文の引用は現物のままです（「SSOT §5.2」は自社の設計文書の節番号）。

### 関連

- 本家（検証の記録つき・器の文面が古くなっていた側の話）: [約束を縛る器の文面が古くなっていた](https://sumitsuke.jp/via/zenn/lab/guard-message-drift/)
- 検査器そのものの収支を数えた話: [緑を信じない——捕まえた 5 件・直した 22 件](https://sumitsuke.jp/via/zenn/lab/green-is-not-proof/)（失敗パターン実測録 #04）
- 顧客データを外部の AI に渡さない方針の技術的な裏付けとして: [Sumitsuke の AI 利用方針](https://sumitsuke.jp/ai-policy/)

次に読む: [毒で赤を見たら、器の収支を数える——プラグイン 4 本を入れた日に 2 本外した](https://sumitsuke.jp/via/zenn/lab/plugin-cost-benefit/)
