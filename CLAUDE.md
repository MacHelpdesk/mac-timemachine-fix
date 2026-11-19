# CLAUDE.md

MacHelpdesk 系列的時光機工具。整個系列共用的規則（公開 repo 不寫任何人的環境、只寫實測過的行為、會改設定的動作寫明界線、`/bin/bash` 3.2 相容、Git 流程）在 umbrella repo `MacHelpdesk/mac-helpdesk` 的 CLAUDE.md，這裡不重抄。

## 這個工具特有的

- `tm-fix.sh` 的每個子命令都只讀。要加會改設定的子命令，先在 SKILL.md 的四張界線表裡決定它屬於哪一類。
- 系統輸入都有 `TM_FIX_*` 覆寫（設定檔、目的地資訊、本機快照、log、來源卷、現在時間），測試只用 `tests/fixtures/` 的合成資料。新增訊號時同時加 fixture 與測試。
- log 只比對 backupd 以英文寫出的識別字（錯誤碼、`BACKUP_FAILED_*`、`consistencyScan`、`does not have an expected snapshot`）。不要比對 `File name too long` 這種會被翻譯的錯誤說明，用 `Code=63`。
- `timeout` 不是 macOS 內建（Homebrew coreutils 才有），腳本不能用。
- 知識庫的 `evidence` 只有看到備份完成才能寫 `verified`。`not_fixes` 只放真的試過無效的做法，推論不算。
- 個人的排除清單、`exclude-system.sh`、量測紀錄在 `~/.config/mac-timemachine-fix/`，`.gitignore` 已擋這些檔名。
