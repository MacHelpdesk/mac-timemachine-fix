# mac-timemachine-fix

時光機（Time Machine）備份一直失敗時，量測時光機的設定、本機參考快照、兩邊的剩餘空間與 backupd 的 log，對照一份已知問題的知識庫找出原因；再量出常見的可排除位置，幫你決定排除清單。

與 [`mac-printer-setup`](https://github.com/MacHelpdesk/mac-printer-setup)、[`mac-dropbox-fix`](https://github.com/MacHelpdesk/mac-dropbox-fix) 同一個系列：先量測，再判讀，最後才動手。

> **狀態：v0.1.1。** `probe` 與 `failing-paths` 在 macOS 27.3 上實跑過一次，結果與手動讀 log 相同。知識庫每一筆都是 `unverified`：訊號在那一次實際出現，但解法還沒有看到備份成功。

## 它解決什麼

| 你遇到的 | 原因 | 知識庫條目 |
|---|---|---|
| 好幾週沒有成功備份，每次跑好幾個小時才失敗，目的地累積很多 `.interrupted` | 上次成功時的本機參考快照被系統清掉，每次都要整個資料卷重掃，途中一個檔案出錯就整次作廢 | `reference-snapshot-lost` |
| log 有 `Failed to enumerate path … Code=63` | 某個程式造出超長路徑，掃描列舉不了 | `name-too-long-in-scan` |
| log 有 `BACKUP_FAILED_COPY_STAGE` | 複製時有一個檔案讀不到（被鎖住、沒有權限） | `copy-stage-source-error` |
| 本機或備份碟快滿 | 本機快滿時參考快照會被回收；要備份的量接近整顆碟時放不下 | `source-disk-nearly-full`、`destination-nearly-full` |
| 好幾天沒備份、從來沒備份過、只有手動才會備份 | 碟沒接、沒設目的地、自動備份關著 | `destination-not-connected`、`no-destination`、`auto-backup-off` |

**時光機只能排除，不能只選要備份的資料夾。** 「只要備份哪些」的答案是一份排除清單：要留的列出來，其餘的大東西逐項排除。

範圍是封閉的：macOS 內建的時光機。其他備份軟體、iCloud、雲端硬碟的同步都不處理。

## 四個部分

| 部分 | 位置 | 做什麼 |
|---|---|---|
| skill | `/mac-timemachine-fix:timemachine-fix` | 量測 → 對照知識庫 → 量排除候選 → 向你說明並一次問完 → 依界線處理 → 再量一次並記錄 |
| 知識庫 | `plugin/data/problems.json` | 每筆問題的症狀、訊號、原因、解法、驗證到哪裡，以及任何情況都不做的事 |
| 排除候選 | `plugin/data/candidates.tsv` | 常見可排除位置，分 `regenerable`、`personal`、`system` 三類 |
| 腳本 | `plugin/scripts/tm-fix.sh` | `probe`、`match`、`list`、`show`、`validate`、`failing-paths`、`sizes`，全部只讀 |

## 安裝

```bash
claude plugin marketplace add MacHelpdesk/mac-helpdesk
claude plugin install mac-timemachine-fix@mac-helpdesk
```

## 腳本

```bash
tm-fix.sh probe            # signal=value，一行一個；要讀 24 小時的 log，約半分鐘
                           # （系統保留的 log 可能更短，計數 0 不代表沒失敗過）
tm-fix.sh match            # 比對到的已知問題；結束碼 3 是沒有比對到
tm-fix.sh show <id>        # 一筆問題的完整內容
tm-fix.sh failing-paths    # log 點名的超長路徑（前六層）與讀不到的檔案
tm-fix.sh sizes [MIN_GB]   # 排除候選的大小與是否已排除
```

腳本不改任何設定、不刪任何檔案、不開始備份。排除與開始備份由 skill 依界線決定：家目錄裡的排除先問你；要 `sudo` 的排除寫成腳本，由你自己執行。

不解析會隨系統語言改變的文字：設定讀 property list（`plutil`、`tmutil … -X`），大小讀 `df -k`、`du -k`，log 只比對 backupd 以英文寫出的錯誤碼與訊息。

## 這個 repo 只放方法與工具

你的排除清單、量測紀錄、個人條目都放在 `~/.config/mac-timemachine-fix/`，不放在這個 repo 裡：

```
~/.config/mac-timemachine-fix/
├── problems.local.json     # 你自己的條目（選用）
├── exclude-system.sh       # skill 替你寫的 sudo 排除腳本
└── records/                # 每次處理的紀錄
```

## 驗證到哪裡

見 `plugin/skills/timemachine-fix/SKILL.md` 的〈驗證到哪裡〉。

## 開發

```bash
for t in tests/test_*.sh; do /bin/bash "$t"; done
/bin/bash scripts/check-privacy.sh
```

測試只用合成的設定檔與 log（`tests/fixtures/`），不讀這台 Mac 的時光機設定；`test_sizes.sh` 會對暫存資料夾呼叫只讀的 `tmutil isexcluded -X`。腳本維持 macOS 內建 `/bin/bash` 3.2 相容，不用 Homebrew 的 `timeout`。

## License

MIT
