# Changelog

## 0.1.1 — 2026-11-20

### Fixed

- skill 改在「終端機」視窗執行需要 sudo 的排除腳本（用 `osascript` 開視窗帶入指令）。原本請使用者用 Claude Code 的 `!` 執行，但 `!` 沒有終端機，`sudo` 讀不到密碼而失敗（#1）。
- skill 要求 sudo 腳本裡的變數寫成 `${變數}`：UTF-8 語系下，變數後緊接的全形字會被讀成變數名稱的一部分，`set -u` 時中止（bash 3.2 與 5.3 實測）（#1）。

## 0.1.0 — 2026-11-19

第一版。

### Skill

- `timemachine-fix`：量測 → 對照知識庫 → 量排除候選 → 向使用者說明並一次問完 → 依界線處理 → 再量一次並記錄。行為界線是四張封閉列舉的表。

### Scripts

- `plugin/scripts/tm-fix.sh`：`probe`、`match`、`list`、`show`、`validate`、`failing-paths`、`sizes`，全部只讀。
- `failing-paths` 與 `sizes` 把含 shell 特殊字元或控制字元的路徑標成 `unsafe_<種類>`，以 `printf %q` 跳脫後印出。
- `plugin/scripts/kb.js`：知識庫的讀取與比對，取自 mac-dropbox-fix，拿掉 Dropbox 專用的欄位。

### 知識庫

- 八筆：`reference-snapshot-lost`、`name-too-long-in-scan`、`copy-stage-source-error`、`source-disk-nearly-full`、`destination-nearly-full`、`destination-not-connected`、`no-destination`、`auto-backup-off`。全部 `unverified`。
- `candidates.tsv`：常見的排除候選，分 `regenerable`、`personal`、`system`。

### 實測範圍

- macOS 27.3（2026-11-19）：`probe` 實跑一次約 27 秒，比對到五筆，與手動讀 log 的結論相同；`failing-paths` 實跑一次。
- 排除之後備份能否完成：未驗證。
