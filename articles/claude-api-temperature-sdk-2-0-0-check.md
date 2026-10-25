---
title: "Claude API の SDK 2.0.0 は temperature を引数で渡すと送る前に止まる——上げる前に探す行と 2 択"
emoji: "🌡️"
type: "tech"
topics: ["ClaudeAPI", "Anthropic", "Python", "SDK", "temperature"]
published: true
---


**読むと分かること**: `anthropic` を 2.0.0 に上げる前に、手元のコードのどの行を直せば `TypeError` で止まらずに済むか。

**結論**

- 引数で `temperature=0.2` などを渡す行は、2.0.0 では送信前に `TypeError` になる
- 上げる前にその行を grep し、消すか版の札 `2023-06-01` のまま使う（公式の 2 択）
- `extra_body` に足せば届くが、公式は `2026-10-21` で 400 と書く＝逃げ道にしない

**どう確かめたか**: 手元の受け口（127.0.0.1）に向けて、anthropic 0.101.0・2.0.0 と直の HTTP から 3 つの渡し方で計 22 回送り、届いた中身と止まった所を記録しました。

**決め手の数**: 引数で渡した回は 4 回中 4 回が `TypeError` で止まり、引数なしの回は版の札 `2026-10-21` で届きました。

**環境**: Windows 11・Python 3.12・anthropic 0.101.0 と 2.0.0・1 環境。実際の API は呼んでいません（400 は公式の文の引用だけです）。

## 公式は、2026-10-21 でこの 3 つの引数を送ると 400 と書いている

- 移行の手引き「Migrating to API version 2026-10-21」に、"In `2026-10-21`, a request that sends `temperature`, `top_p`, or `top_k` returns a 400 error, even at the parameter's default value." と、"As of the latest major versions, the SDK and the CLI no longer have the three parameters."（<https://platform.claude.com/docs/en/api/migration-2026-10-21> ・2026-10-22 に開いた）。
- この記事で示すこと: 3 つの経路（古い SDK・新しい SDK・直の HTTP）から手元の受け口に何が届き、どこで止まったか。

## 引数で渡した 4 回は、送る前に TypeError で止まった

![経路 × 渡し方の表。古い SDK は版の札 2023-06-01 で temperature がそのまま届く。新しい SDK は引数なしなら版の札 2026-10-21 で届き、temperature を引数で渡すと送る前に TypeError で止まる。extra_body に足すと届く。直の HTTP は 2026-10-21 でも temperature が届く](/images/claude-api-temperature-sdk-2-0-0-check/fig1_arrived_vs_stopped.png)

22 回の実行（本体 18 回＋`extra_body` 4 回）で、受け口に届いたのは 18 件、送る前に止まったのは 4 回でした。

| 経路 | 渡し方 | 受け口に届いた版の札 | 本文の temperature |
|---|---|---|---|
| 古い SDK 0.101.0 | なし／1.0／0.2 | 2023-06-01 | なし／1.0／0.2（そのまま届く） |
| 新しい SDK 2.0.0 | なし | 2026-10-21 | なし |
| 新しい SDK 2.0.0 | 1.0／0.2（引数） | 届かず | 送る前に `TypeError`（4 回中 4 回） |
| 新しい SDK＋`extra_body` | 1.0／0.2 | 2026-10-21 | 1.0／0.2（届く） |
| 直の HTTP（版の札を自分で 2026-10-21） | なし／1.0／0.2 | 2026-10-21 | なし／1.0／0.2（そのまま届く） |

各セルとも 2 回ずつ試して、2 回とも同じ結果でした。止まった文は `TypeError: Messages.create() got an unexpected keyword argument 'temperature'`。

- 既定の 1.0 を渡した回も、0.2 の回も、新しい SDK では同じように止まりました。
- 受け口は 200 の形だけの応答を返すだけで、`temperature` があっても止めません。だから、直の HTTP や `extra_body` で「届いた」ことは、API が受け付けることを意味しません。公式の文は、2026-10-21 でこの 3 つの引数を送ると 400 と書いています。

![新しい SDK で temperature を渡さなかったときは届き、temperature=0.2 を渡すと TypeError で止まって受け口に 0 件、と表示した窓](/images/claude-api-temperature-sdk-2-0-0-check/photo1_new_sdk_stopped.png)

写真は、自分で開いた窓に、実際に走らせたスクリプトの出力を表示して撮ったものです（ターミナルそのものではありません）。

**実務では**: 上げる前に、3 つを引数で渡している行を探します。`extra_body` や直の HTTP で届いたのは受け口が止めないだけで、公式は 400 と書くので、抜け道にはしません。

## 同じ受け口に 3 経路から送って比べた

1. Python 標準の `http.server` で受け口を 127.0.0.1 に立て、届いた `anthropic-version` と本文の鍵と値を 1 件ずつ記録します。
2. 古い SDK（システムの Python）と新しい SDK（隔離した仮想環境）は `base_url` を受け口に、鍵は偽の文字列にして、再試行は 0 回にします。直の HTTP は標準の urllib です。
3. 引数なし・`temperature=1.0`・`temperature=0.2` を各 2 回。新しい SDK だけ `extra_body={"temperature": 値}` を足しました。
4. 予測は測る前に書いて、あとから直していません。5 つ（古い SDK・新しい SDK・`extra_body`・直の HTTP・同じ条件で同じ結果）はすべて当たりました。

測定の道具には、3 つの確かめを付けました。外した本文は記録に鍵が無く、入れた本文は記録に鍵がある（両向き）。到着数が送れた回数と一致する。受け口を止めてから送ると接続の例外になり、記録は増えない。3 つとも期待どおりでした。

## 上げる前の 3 手

### 1. 渡している所を数える（5 分）

次のスクリプトは、Python のソースを実行せずに、`temperature`・`top_p`・`top_k` を関数の引数や辞書の鍵として書いている行を一覧にします。

```python
import ast, sys, pathlib
NAMES = {"temperature", "top_p", "top_k"}
for p in pathlib.Path(sys.argv[1]).rglob("*.py"):
    try:
        tree = ast.parse(p.read_text(encoding="utf-8"))
    except Exception:
        continue
    for n in ast.walk(tree):
        if isinstance(n, ast.Call):
            for k in n.keywords:
                if k.arg in NAMES:
                    print(f"{p.name}:{n.lineno} 引数 {k.arg}")
        elif isinstance(n, ast.Dict):
            for k in n.keys:
                if isinstance(k, ast.Constant) and k.value in NAMES:
                    print(f"{p.name}:{k.lineno} 辞書の鍵 {k.value}")
```

測定の道具の入っているフォルダに当てると、辞書の鍵を 3 行（`measure.py` の 28・53・94 行）拾いました。**拾えなかった行もあります**: `body["temperature"] = val` のような辞書への代入は、このスクリプトでは見つかりません（同じ `measure.py` の中に 2 行あり、手で見て分かりました）。拾い漏れの形は、`grep -n "temperature\|top_p\|top_k"` でも併せて見てください。

自分の手元の `.py` 897 本（この記事の測定用を除く）に、手元で使っている完全版の点検のスクリプトを 1 回当てた結果は、temperature の鍵を持つ行が 10 行・8 ファイルで、どれも anthropic を含まないファイルでした（手元の小さな AI などに渡す設定）。Claude API に 3 つの引数を渡している所は 0 でした。見ていないのは、値を変数から組み立てる所と Python 以外の言語です。

**実務では**: 点検で 0 行でも、変数から組み立てる所と Python 以外は別に探します。

### 2. 外すか、`2023-06-01` に残すかを決める

公式の手引きは、既定以外の値に頼る呼び出しについて、こう書いています。

> "On models that accept other values, such as Claude Sonnet 4.6, a request that lowered `temperature` for more consistent output loses that effect. No other setting replaces it. If a request relies on a non-default value, either stop sending the parameter, or keep that request on `2023-06-01`."

手元の記録で確かめたのは前半だけです。新しい SDK で止まった呼び出しから `temperature=0.2` の 1 行を外すと、同じコードが版の札 `2026-10-21` で受け口に届きました。後半の「`2023-06-01` に残す」は、直の HTTP で札を替えた回を測っていないので、記録はありません。

**実務では**: 外すと効果が消える呼び出しは、公式の 2 択のどちらかに振り分けます。後者の `2023-06-01` に残す道は、この記録では未確認です。

### 3. SDK の版と送る版の札の対応を表で持つ

公式は「SDK を使うなら、SDK の大きな版が出たときの API の版が使われる。SDK を使わずに呼ぶなら、`anthropic-version` ヘッダーを `2026-10-21` にする」と書いています（原文は "If you use an SDK, your requests use the API version that was current when your SDK's major version was released. [...] If you call the API without an SDK, set the `anthropic-version` header to `2026-10-21`."）。手元の記録では、0.101.0 が `2023-06-01`、2.0.0 が `2026-10-21` を送りました。自分のコードが使う SDK の版ごとに、この対応を 1 行ずつ表にしておくと、どの呼び出しが札を変えるかを見分けられます。

**自分の場合は**: 自分のコードが `temperature` などを引数で渡していれば、上げる前に消すか残すかを決めます。渡していなければ、手元の記録では引数なしの回は `2026-10-21` で届きました。

## 測っていないこと・言わないこと

- 点検のスクリプトは文字を静的に探すだけで、値を変数や辞書への代入で組み立てる所は見つけられません。
- 測ったのは anthropic 0.101.0 と 2.0.0 の 2 つだけ。ほかの言語・ラッパーは測っていません。
- 実際の API の応答（400 かどうか）。受け口に届くことと、API が受け付けることは別です。
- 1.x の SDK（手元に入れていません）。引数が消えた版の境目は、この記事では言えません。
- `top_p`・`top_k` は 1 回ずつだけ（`top_k=5`・`top_p=0.9`）。新しい SDK は両方とも送る前に `TypeError`、古い SDK は本文に入れて届きました。回数を重ねてはいません。
- ほかの言語の SDK・CLI・ラッパー。
- 2.1.0（2026-10-22 に PyPI で見た最新）は測っていません。

## 本家（Lab）

測る前に書いた予測と条件・受け口の記録・測定と点検のスクリプト・集計は、本家の `evidence/` に置いています → [SDK を 2.0.0 に上げたら temperature は——手元の受け口に届く中身と、送る前に止まる所を記録した](https://sumitsuke.jp/via/zenn/lab/claude-api-temperature-sdk-2-0-0/)

### AI の利用について

測定のスクリプトの作成・22 回の実行・結果の照合・点検のスクリプトの作成・この記事の下書きは AI（Claude Code）が行いました。人がしたのは、記事に出すかどうかの判断です。
