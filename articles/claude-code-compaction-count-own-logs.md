---
title: "Claude Code の放置圧縮を自分の記録で数えたら、候補は 0 件で確定は判定不能だった"
emoji: "🧮"
type: "tech"
topics: ["ClaudeCode", "Python", "AI", "計測"]
published: true
---


Claude Code の更新履歴に、**席を外していた会話を、キャッシュが切れる前に要約する「放置圧縮」**が加わりました（2.1.299）。では自分の記録では、圧縮は何回走っていて、そのうち放置で走った物はいくつあるのか。手元の記録 213 本で数えました。

結果は先に書きます。圧縮の印は重なりを除いて 116 件。放置の候補（auto・直前の発言から 50 分以上・前の量が 20 万トークン以上）は **0 件**で、放置で走ったと確定できる値は記録に無く、**判定不能**でした。測る前に「候補は 1 割を超える」と置いた予測は外れています。

![圧縮の印 116 件の直前の間（横）と前の量（縦）。印はどれも間が 3.4 分未満の左端に集まり、間 50 分以上・量 20 万以上の領域に圧縮の点は無い](/images/claude-code-compaction-count-own-logs/fig1_scatter_gap_tokens.png)

**この記事の位置づけ**

- 既に書かれていること: 放置圧縮の仕組みと止め方は、公式の更新履歴にあります（下の「止める・遅らせる 3 通り」に逐語）。
- この記事で示すこと: 自分の記録で圧縮の印を数える小さな道具（Python 1 枚）と、手元の記録で数えた結果。印の理由の欄に「放置」の値が無い中で、間と量から放置の候補を分けて数えています。
- 当てはまる範囲: Windows 11・Claude Code のデスクトップ入口・1 人の使い方・1 回の走査。ほかの人の記録で同じ割合になるとは言いません。

## 先に弱点

- **確定は 0 件ではなく判定不能**です。記録の理由の欄に出た値は auto と manual だけで、放置を示す値はありません。更新履歴の全文を検索しても、記録で放置の圧縮を見分ける値の説明は見つかりませんでした。「放置で走った」と言えるのは記録の印ではなく、間と量からの推定までです。
- 数えた記録は入口がすべて claude-desktop です。公式の文は "in the terminal" と書いているので、デスクトップのアプリでの放置圧縮について、この記録から言えることはありません。
- 印の無い圧縮は数えられません。
- 数えたのは 1 人の使い方の記録を 1 回走査した結果で、探索的な結果です。

## 環境

| 項目 | 値 |
|---|---|
| OS | Windows 11 |
| Claude Code | デスクトップ入口（印の版は 2.1.209〜2.1.299） |
| 対象 | `~/.claude/projects/` の下の `*.jsonl` のうち、2026-10-14 以降に更新された 213 本（印がある記録は 28 本） |
| 道具 | Python 標準ライブラリだけ |

## 道具（記録の読み方）

記録の 1 行が 1 つの JSON で、圧縮の印は `type` が system・`subtype` が compact_boundary の行です。その `compactMetadata` に理由（`trigger`）・前の量（`preTokens`）・後の量（`postTokens`）が入っています。時刻は `timestamp`、版は `version`、入口は `entrypoint`、印の識別は `uuid` です。

分かれた会話の写しは同じ印を持つので、`uuid` で 1 回に数えます（行 164 が 116 になりました）。直前の間は、印より前で最も遅い user／assistant の記録の時刻との差です。

```python
import json, os, sys, time
from datetime import datetime

since = sys.argv[1] if len(sys.argv) > 1 else "2026-10-14"
cut = time.mktime(time.strptime(since, "%Y-%m-%d"))
root = os.path.join(os.path.expanduser("~"), ".claude", "projects")
ts = lambda s: datetime.fromisoformat(s.replace("Z", "+00:00"))
seen, rows = set(), []
for d, _, fs in os.walk(root):
    for f in sorted(fs):
        p = os.path.join(d, f)
        if not f.endswith(".jsonl") or os.path.getmtime(p) < cut:
            continue
        talk, marks = [], []
        for line in open(p, encoding="utf-8", errors="replace"):
            try:
                o = json.loads(line)
            except ValueError:
                continue
            if not o.get("timestamp"):
                continue
            if o.get("subtype") == "compact_boundary":
                marks.append(o)
            elif o.get("type") in ("user", "assistant") and not o.get("isSidechain") and not o.get("isCompactSummary"):
                talk.append(ts(o["timestamp"]))
        for m in marks:
            if m["uuid"] in seen:
                continue
            seen.add(m["uuid"])
            t, before = ts(m["timestamp"]), [x for x in talk if x < ts(m["timestamp"])]
            c = m.get("compactMetadata", {})
            rows.append((t, c.get("trigger"), c.get("preTokens"), c.get("postTokens"),
                         round((t - max(before)).total_seconds() / 60, 2) if before else None))
rows.sort()
print("時刻(UTC)\t理由\t前\t後\t直前の間(分)")
for t, *r in rows:
    print(t.strftime("%Y-%m-%d %H:%M:%S"), *r, sep="\t")
cand = [r for r in rows if r[1] == "auto" and r[4] is not None and r[4] >= 50 and (r[2] or 0) >= 200000]
print("印 %d 件・放置の候補（auto・間 50 分以上・前 20 万以上）%d 件" % (len(rows), len(cand)))
```

出すのは時刻・理由・量・間だけで、会話の中身は読んでも書き出しません。当方の記録で走らせた最後の行は「印 116 件・放置の候補 0 件」でした（Lab の evidence に、同じ数を出す詳しい版と表があります）。

![数える道具（count_compactions_min.py）を端末の窓で走らせた実画面。最後の行は「印 117 件・放置の候補（auto・間 50 分以上・前 20 万以上）0 件」。窓に出ているのは時刻・理由・量・直前の間の数だけで、記録のファイル名・パス・会話の中身は出ていません](/images/claude-code-compaction-count-own-logs/fig3_tool_window.png)

窓の最後の行が 117 件なのは、撮った時点で、測定のあとに圧縮の印が 1 件増えたためです（2026-10-21 10:26:24 UTC・理由 auto・直前の間 1.28 分）。測定の 116 件に、この 1 件が加わった数で、放置の候補が 0 件なのは変わりません。

## 結果

| 項目 | 値 |
|---|---|
| 圧縮の印 | 116 件（auto 98・manual 18） |
| 理由の欄の値 | auto・manual の 2 つだけ |
| auto の直前の間 | 中央値 1.3 分・最大 3.34 分 |
| auto の前の量 | 中央値 569,348・98 件すべて 20 万以上 |
| 放置の候補（線 40・50・60 分） | 0・0・0 |
| 放置で走ったと確定 | 判定不能 |

- auto の圧縮は、どれも直前の発言の 3.4 分未満に走っていました。なぜその時点で走ったかは、記録から確かめていません。
- 同じ記録に、発言の間が 54 分以上あいて量が 20 万以上のまま続きが書かれた回が 203 回ありました（入口はすべて claude-desktop）。その間に圧縮の印が入った回は 0 です。席を外したのか窓を閉じて開き直したのかは、記録からは区別できません。
- 設計の前に見た数（印の行 auto 140・manual 22・refusal 4）とは合いません。今回は印の行が auto 142・manual 22 で、refusal の値は 0 でした。理由は調べていません。

## 要約のあとに残った決まり（有無だけ）

要約のあとに、決まりがどれだけ残るかも数えました。決まりは 6 つ（作業フォルダの CLAUDE.md の 3 つ・会話の途中で本人が言った 3 つ）です。**(a) 要約の文に決まりの語が入っていたか**と、**(b) 要約のあと次の本人の発言までの操作で、その決まりに触れる最初の操作が守った形か**を、別の列にしました。(a) があっても (b) とは言いません。

![要約のあとに残った決まりの表。決まり 6 つについて、対象の印の数・要約の文に語が入っていた数・次の操作で守った数・守らなかった数・触れなかった数](/images/claude-code-compaction-count-own-logs/fig2_rules_after_summary.png)

- 決まりの注入（記録の頭の決まり）は、auto 98 件中 96 件で要約のあとに付きました。付かなかった 2 件の理由は調べていません。
- 要約の文に語が入っていた割合は、決まりによって違いました（0／96 から 11／11 まで）。語が入っていても、次の操作が守った形かどうかは別でした（M3 は語が 11／11 で入っていて、次の操作は commit か push。ただし 2 本の会話だけで、本人があとから許したかは見ていません）。
- 判定は正規表現による語の有無で、決まりの意味は読んでいません。C2・C3 は 96 件すべてが「触れず」で、効いたかどうかは言えません。

## 止める・遅らせる 3 通り（公式の逐語）

更新履歴（https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md）の 2.1.299 と 2.1.302 に、次のように書かれています。

- 設定のファイル: "`"idleCompaction": false` in settings.json turns it off"（"Both need v2.1.290 or later"）
- 環境変数: "`CLAUDE_CODE_IDLE_COMPACT_MIN_TOKENS` to change idle compaction's 200K-token minimum"（止めるのではなく、最小の量を変える）
- 設定の画面: "Added an `Idle compaction` row to `/config` for turning idle compaction off or back on"（2.1.302）

元の機能の説明は "a 200K+ token conversation left idle for about 54 minutes is compacted before its one-hour prompt cache expires, so your next message doesn't reprocess it all" です。

## 試験: 重い決まりを要約だけに任せない

ここは**試験の運用**で、効き目は測っていません。要約に決まりが入るかどうかは、上の表のとおり決まりによってばらつきました。そこで、守らせたい重い決まりは会話の中で言うだけにせず、ファイルに置いて、要約のあとに読み直させる形にするのが 1 つの案です。当方はこの運用で圧縮のあとの守られ方が良くなったかを測っていません。

## 測っていないこと・言わないこと

- 放置圧縮が得か損かは言いません。費用は測っていません。
- ほかの人の記録・ターミナル入口の記録・設定を変えたときの圧縮の回数は測っていません。
- 放置を起こし直す実験はしていません（数える物は、既に記録に在る物だけです）。
- 「予測が外れた」の意味は、手元の 1 回の走査で候補が 0 件だった、までです。

### AI の利用について

記録を読む道具の実装・数えること・間と量で分けること・手で選んだ 3 件との照合・この記事の下書きは、AI（Claude Code）がしました。測った対象も Claude Code で、圧縮と要約をしたのはその Claude Code です。人がしたのは、記事に出すかどうかの判断です。

### 関連

この記事の本家（予測・道具の確かめ・表・詳しい版の道具）は Sumitsuke Lab → [Claude Code の放置圧縮は自分の記録で何回あったか](https://sumitsuke.jp/via/zenn/lab/claude-code-idle-compaction-count/)
