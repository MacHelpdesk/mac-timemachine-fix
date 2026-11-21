---
name: timemachine-fix
description: 時光機（Time Machine）備份一直失敗、好幾天沒有成功、要備份的東西太多時，量測時光機的設定、本機快照、兩邊的剩餘空間與 backupd 的 log，對照已知問題的知識庫找出原因，並幫使用者決定哪些資料夾要排除。使用者說「時光機一直失敗」「Time Machine 備份不完」「備份卡在準備中」「好久沒備份成功」「要備份的東西太多」「時光機要排除哪些」「時光機只要備份哪些目錄」時使用。只處理 macOS 內建的時光機；其他備份軟體、iCloud、雲端硬碟的同步都不在範圍。
allowed-tools:
  - Read
---

# timemachine-fix：時光機一直失敗時，先量測，再對照已知問題

時光機失敗時，系統設定只會顯示「備份失敗」或一直停在「準備中」。真正的原因寫在 backupd 的 log 與時光機的設定檔裡。這個 skill 先把它們量出來，再拿量到的訊號去對一份已知問題的清單；最常見的處理是排除可以重建的大資料夾，讓一次備份能完整跑完。

**實測範圍**：知識庫每一筆都是 `unverified`。2026-11-19 在 macOS 27.3 上實際觀察到其中五筆的訊號與 log，但解法還沒有看到備份成功。跟使用者說明時，把這個狀態一起說出來。

## Step 0：建立任務清單

用 TaskCreate 建立下面六個 task（subject 直接複製），一次建完。做完一個就標 completed。

| # | subject | 類型 |
|---|---|---|
| 1 | 量測時光機的狀態 | 機械 |
| 2 | 對照知識庫，讀出失敗的路徑 | 機械 |
| 3 | 量排除候選的大小 | 機械 |
| 4 | ⚠️ 向使用者說明原因，提出排除清單並一次問完 | **判斷** |
| 5 | 依界線處理 | **判斷** |
| 6 | 再量一次並記錄 | 驗證 |

第 4 步不能省：看到一長串大資料夾很容易直接全部排除，但被排除的東西之後就不在備份裡，哪些可以不要只有使用者知道。第 6 步也不能省：改完排除清單不等於備份成功，要等一次備份完成才算。

## 腳本與知識庫的位置

- 腳本：`${CLAUDE_PLUGIN_ROOT}/scripts/tm-fix.sh`。讀不到時，改用載入本 skill 時顯示的 base directory 往上兩層的 `scripts/tm-fix.sh`。下文寫成 `tm-fix.sh <子命令>`。
- 知識庫：`${CLAUDE_PLUGIN_ROOT}/data/problems.json`；排除候選：`${CLAUDE_PLUGIN_ROOT}/data/candidates.tsv`。都隨 plugin 發布，不要改它們。
- 使用者自己的條目：`~/.config/mac-timemachine-fix/problems.local.json`。
- 這次的紀錄與使用者的排除清單：`~/.config/mac-timemachine-fix/records/`。

## 先講清楚的一件事

時光機**沒有「只備份這幾個資料夾」的模式**，只有排除清單。使用者問「只要備份哪些」時，先講這一句，再把答案做成一份排除清單：要留的列出來，其餘的大東西逐項排除。

## 行為界線

下面四張表是封閉列舉，不得依性質相似類推。知識庫的 `class` 與這裡不一致時，以比較嚴的那一邊為準。

### 直接做，做完回報：只有這五件

| # | 動作 |
|---|---|
| 1 | `tm-fix.sh` 的 `probe`、`match`、`list`、`show`、`validate`、`failing-paths`、`sizes`（都只讀） |
| 2 | `tmutil isexcluded -X <路徑>`、`tmutil status`、`tmutil destinationinfo -X`、`tmutil listlocalsnapshotdates /`（都只讀） |
| 3 | `du -sxk`、`df -k`、`ls` 量使用者點名的資料夾 |
| 4 | 在 `~/.config/mac-timemachine-fix/records/` 寫這次的紀錄 |
| 5 | 在 `~/.config/mac-timemachine-fix/problems.local.json` 新增條目（見〈新增條目〉），寫完跑 `validate` |

### 先問，使用者在這次對話同意才做：只有這兩件

| # | 動作 | 問的時候要說的 |
|---|---|---|
| 1 | `tmutil addexclusion <路徑>`，路徑在使用者的家目錄或屬於使用者 | 每個路徑的大小、為什麼可以排除、排除後它就不在備份裡；撤回指令是 `tmutil removeexclusion <路徑>`；資料夾被刪掉重建時排除會失效 |
| 2 | `tmutil startbackup --auto` | 會在背景跑很久，備份碟要一直接著、Mac 最好接電源 |

排除要一次問完：把 `sizes` 的結果分成 `regenerable` 與 `personal` 兩組列給使用者，`regenerable` 那組標「建議排除」，`personal` 那組逐項寫出你的建議與理由，請使用者一次回覆。使用者同意的是列出來的那幾個路徑，不是「這一類」。

### 只說明步驟，由使用者自己做：只有這四件

| # | 動作 | 原因 |
|---|---|---|
| 1 | 需要 `sudo` 的排除：`sudo tmutil addexclusion -p <路徑>`（固定路徑），以及家目錄以外、不屬於使用者的路徑（`candidates.tsv` 的 `system`） | 要輸入管理者密碼。把指令寫成一支腳本放在 `~/.config/mac-timemachine-fix/`，在「終端機」視窗執行（見 Step 5）。不要請使用者用 Claude Code 的 `!` 執行：`!` 沒有終端機，`sudo` 讀不到密碼就失敗 |
| 2 | 整理本機磁碟騰出空間 | 刪什麼是使用者的決定 |
| 3 | 接上備份碟、接電源、讓 Mac 不睡眠直到備份完成 | 實體操作 |
| 4 | 在系統設定裡加入備份磁碟、開啟自動備份 | 系統設定的畫面 |

### 不做

`tm-fix.sh show <id>` 的最後一段會印出知識庫的 `never` 清單，一共四項：不碰備份碟上的任何東西（舊備份、`.interrupted`、`tmutil delete`）、不刪這台 Mac 上的檔案（包括 log 點名的超長路徑）、不關閉時光機或換目的地或抹除磁碟、不代替使用者執行 `sudo`。

沒有比對到條目時，也不拿「看起來相近」的條目的解法來試。

### 路徑怎麼放進指令

`failing-paths` 與 `sizes` 印出的路徑來自檔案系統與 log，資料夾名稱由建立它的人或程式決定。

- 放進任何指令時一律用單引號包住整個路徑（`tmutil addexclusion '<路徑>'`），寫進 sudo 腳本時放在陣列元素裡加引號。
- 種類欄是 `unsafe_` 開頭的路徑含 shell 特殊字元或控制字元，已用 `printf %q` 跳脫。不要把它放進任何指令；把原樣給使用者看，說明為什麼不處理，請他自己判斷。

## Step 1：量測

```bash
tm-fix.sh probe
```

要讀 24 小時的 log，約需半分鐘。把輸出原樣給使用者看。最常用的四個訊號：

| 訊號 | 看什麼 |
|---|---|
| `days_since_last_backup` | 距上次成功幾天。沒有這一行表示從來沒成功過 |
| `reference_snapshot` | `missing` 表示每次都要整個重掃，這是「一直失敗」最常見的背景 |
| `log_name_too_long`、`log_copy_stage_failed` | 讓掃描或複製中途失敗的單一路徑，下一步用 `failing-paths` 找出是哪些 |
| `source_free_pct` | 本機剩不到 5% 時，參考快照很容易被系統回收 |

`log_result=failed` 表示讀不到 log，四個 `log_` 訊號都不會出現。照實說，只用其他訊號比對。

log 實際保留的範圍可能比 24 小時短（系統會輪替），所以 `log_` 計數是 0 只代表「讀得到的那段沒有」，不代表沒失敗過。更早的失敗看目的地上 `.interrupted` 的數量與日期。

## Step 2：對照知識庫，讀出失敗的路徑

```bash
tm-fix.sh match
tm-fix.sh failing-paths
```

`match` 每行一筆：`id`、驗證狀態、來源、標題。對每個 `id` 跑 `tm-fix.sh show <id>`。比對到 `name-too-long-in-scan` 或 `copy-stage-source-error` 時，`failing-paths` 會列出 log 點名的路徑（超長的只印前六層）。對每個路徑找出**不會被刪掉重建**的最近一層資料夾（例如 `~/.cache`、某個工具的 `jobs` 資料夾），那才是要排除的對象。

結束碼 3（沒有比對到）：照實說知識庫裡沒有這種情況，把訊號給使用者，只做唯讀的查證。

## Step 3：量排除候選

```bash
tm-fix.sh sizes 5
```

每行是 `大小(GB)`、`是否已排除`、`種類`、`路徑`、`理由`，大的在前。這份清單只涵蓋常見位置，使用者自己的大資料夾不一定在裡面：另外用 `du -sxk` 量家目錄第一層與 `~/Library` 的大項目，把 `candidates.tsv` 沒有的大東西也放進 Step 4 的清單，種類自己判斷，看不出能不能重建的一律當 `personal`。

## Step 4：向使用者說明並一次問完

動手之前，用幾句話說清楚：

1. 量到什麼（引用訊號），比對到哪幾筆、原因是什麼。
2. 這幾筆驗證到哪裡（目前全部 `unverified`）。
3. 排除清單：先寫「時光機只能排除、不能只選要備份的」，再列 `regenerable`（建議排除）與 `personal`（逐項給建議），以及排除後預估每次要備份的量。
4. 需要 `sudo` 的部分：說明會寫成腳本，由使用者自己執行。

## Step 5：依界線處理

使用者同意哪些路徑，就只排除那些。每排除一個，用 `tmutil isexcluded -X` 確認 `IsExcluded` 是 1；把成功的路徑寫進 `~/.config/mac-timemachine-fix/records/` 的紀錄，撤回時用得到。

需要 `sudo` 的寫成 `~/.config/mac-timemachine-fix/exclude-system.sh`，每一行附理由與撤回指令。使用者同意執行之後，開一個「終端機」視窗並帶入指令，密碼由使用者在那個視窗輸入：

```bash
osascript -e 'tell application "Terminal"' -e 'activate' \
  -e 'do script "sudo bash ~/.config/mac-timemachine-fix/exclude-system.sh"' -e 'end tell'
```

告訴使用者：輸入密碼時畫面不會顯示字元；跑完會印出「固定路徑排除：成功 N，失敗 M」，請他把那一行告訴你。

- 不用 `sudo -S`、不把密碼寫進檔案或環境變數：密碼不能經過對話。
- 不請使用者在 Claude Code 輸入 `! sudo …`：`!` 執行的指令沒有終端機，`sudo` 會回 `a terminal is required to read the password` 而失敗。
- 腳本跑完後，用 `defaults read /Library/Preferences/com.apple.TimeMachine SkipPaths` 確認固定路徑排除已寫入。
- 腳本裡的變數一律寫成 `${變數}`。在 UTF-8 語系下（使用者的終端機通常是），`$ok，` 這種變數後面緊接全形字的寫法，bash 會把全形字的第一個位元組讀成變數名稱的一部分；腳本有 `set -u` 時就以「未綁定的變數」中止。系統的 bash 3.2 與 Homebrew 的 bash 5.3 都是這樣，C 語系下則不會。

## Step 6：再量一次並記錄

排除不會讓正在跑的備份變快；要等下一次備份。使用者同意開始備份時跑 `tmutil startbackup --auto`。之後再跑 `tm-fix.sh probe`，`days_since_last_backup=0` 而且 `reference_snapshot=present` 才算解決。

備份還沒完成就照實說「設定改了，還沒看到成功」，不要說已經修好。

紀錄寫到 `~/.config/mac-timemachine-fix/records/`，檔名 `YYYY-MM-DDTHHMM±HHMM_<地點>.md`：處理前後的訊號、比對到的條目、排除了哪些路徑、結果。這份紀錄只留在使用者的電腦上。

## 新增條目

遇到知識庫沒有的問題，解決之後記進 `~/.config/mac-timemachine-fix/problems.local.json`：

```json
{
  "schema_version": 1,
  "problems": [
    {
      "id": "kebab-case-的名稱",
      "title": "一句話",
      "symptoms": ["使用者看得到的現象"],
      "match": { "all": [ { "signal": "log_copy_stage_failed", "op": "gte", "value": 1 } ] },
      "cause": "原因",
      "fixes": [
        { "id": "做法的名稱", "action": "做什麼", "class": "ask", "command": "指令（可省略）",
          "side_effects": "副作用（可省略）", "verify": "怎樣算解決（可省略）", "evidence": "verified" }
      ],
      "not_fixes": [ { "action": "試過的做法", "observed": "看到的結果" } ],
      "evidence": { "status": "verified", "date": "YYYY-MM-DD", "macos": "版本", "note": "實測了什麼、沒測什麼" }
    }
  ]
}
```

- `signal` 只能用知識庫 `signals` 列出的名稱；`op` 只有 `equals`、`not_equals`、`gte`、`lte`；`class` 只有 `direct`、`ask`、`user`；`evidence` 只有 `verified`、`reported`、`unverified`。`validate` 會擋下不在清單裡的值。
- 只有看到備份完成的解法才寫 `verified`。`not_fixes` 只放真的試過無效的做法。
- 條目裡不要有這台電腦的識別資訊：家目錄路徑、磁碟名稱、UUID、量測的時間。
- 個人條目裡的指令，不論 `class` 寫什麼，一律先給使用者看、同意才執行。

## 驗證到哪裡

| 行為 | 狀態 |
|---|---|
| `probe` 讀出目的地、上次成功、參考快照、兩邊空間與四種 log 訊號 | 已實測一次（macOS 27.3，2026-11-19），結果與手動讀 log 相同，約 27 秒 |
| `failing-paths` 列出超長路徑與複製失敗的檔案 | 已實測一次（同上） |
| `sizes` 展開 `~` 與含空白的萬用字元 | 只在 `tests/test_sizes.sh` 驗過 |
| 用 `!` 執行 `sudo` | 已實測：失敗，`sudo` 讀不到密碼（Claude Code，macOS 27.3） |
| 用 `osascript` 開終端機視窗帶入 sudo 指令 | 已實測一次（macOS 27.3）：使用者輸入密碼後腳本執行，固定路徑排除寫入 SkipPaths。當時腳本最後一行的 `$ok，` 觸發上一段的 UTF-8 問題而中止，排除本身在那之前已完成 |
| 排除可重建的資料夾之後，備份能完整跑完 | 未驗證 |
| 其他 macOS 版本 | 未驗證。設定檔的欄位與 log 的訊息沒有公開文件，版本不同時訊號可能缺少；缺少的訊號不會被當成比對到 |
