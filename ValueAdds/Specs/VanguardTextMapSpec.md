## Vanguard Pragma TextMap 格式規格（定稿）

TextMap 現為**單一檔案格式**：**Typing TextMap**（`.txtMap`）。

> 自 2026-04-11 起，`vanguardTextMap` builder / plugin 不再生成 `VanguardFactoryDict4RevLookup.revlookup`。
> 過去的 dedicated RevLookup TSV 僅屬未曾推往 production 的草案產物，現已正式退出規格；需要反查時，應由 consumer 端直接從 MainTextMap 派生生成。

> [!WARNING]
> 為保持檔案整潔性與 git 歷史可讀性，建議將該格式（`.txtMap`）納入 .gitattributes 的 CRLF/LF 自動轉換例外忽略清單。雖然最新版 parser 已支援 CRLF 相容性，混雜的換行符仍會導致 git diff 雜訊且增加後續維護風險。幸運的是，因為 KEY_LINE_MAP 區段記載的起始位置是「行號」而非 data byte position 資訊的緣故，前述故障發生了也不會導致不可逆的資料損毀。

### Typing TextMap（`.txtMap`）

三段式 PRAGMA 結構。分隔符為 Tab (`\t`)。

#### HEADER 區段

```
#PRAGMA:VANGUARD_HOMA_LEXICON_HEADER
VERSION	1
TYPE	TYPING
READING_SEPARATOR	-
ENTRY_COUNT	871
KEY_COUNT	277
DEFAULT_PROB_4	0
DEFAULT_PROB_7	-11
DEFAULT_PROB_8	-13
DEFAULT_PROB_9	-13
DEFAULT_PROB_10	-1
```

| 欄位 | 說明 |
|------|------|
| `VERSION` | 格式版本號 |
| `TYPE` | `TYPING`（VanguardLexicon 產出）或 `TRIE_TEXTMAP`（LibVanguard `serializeToTextMap` 產出） |
| `READING_SEPARATOR` | 讀音分隔符（預設 `-`） |
| `ENTRY_COUNT` | VALUES 區段的總行數（含所有行型別） |
| `KEY_COUNT` | KEY_LINE_MAP 區段的讀音數量 |
| `DEFAULT_PROB_<typeID>` | 某 EntryType 全體條目共用的機率值；VALUES 中該 typeID 的條目可省略機率欄位 |

#### VALUES 區段

`#PRAGMA:VANGUARD_HOMA_LEXICON_VALUES` 之後的每一行代表一或多筆 Trie Entry。行型別有三種，按解析優先度排列：

**型別 A：合併行**（`>` 前綴）——具有 DEFAULT_PROB 的 typeID 條目按讀音合併為單行。

```
>7	鎄|埃|锿|嗳|哎|㶼|𡉓 ...
>4	，|。|、|！|？ ...
>9	🌳
```

格式：`>typeID\tencodedCell`。機率由 HEADER 中的 `DEFAULT_PROB_<typeID>` 提供。`encodedCell` 使用 escaped pipe 編碼：`|` 為分隔符，`\\` 表示反斜線、`\|` 表示字面 `|`、`\s` 表示空格、`\a` 表示 BEL (`\u{7}`)。

**型別 B：CHS/CHT 機率分組行**（僅限 `TYPE=TYPING`）——同讀音下同機率的簡體/繁體 values 按機率降冪排列（趨近 0 者行號在前）。

```
@-5.28	束	束
@-5.307	^G	豎
@-9.465	数|樹	數
```

格式：`@probability\tchsCell\tchtCell`。`@` 前綴明確標記此行為 TYPING grouped line，避免和一般三欄個體行混淆。`chsCell` / `chtCell` 與型別 A 共用同一套 escaped pipe 編碼。若某語種該機率下無條目，則以 **BEL (`\u{7}`)** 佔位。Parser 仍保留對舊版 bare numeric grouped line（`probability\tchs_values\tcht_values`）的相容，但 builder 不再輸出該舊格式。

CHS 對應 `EntryType.chs`（rawValue=5），CHT 對應 `EntryType.cht`（rawValue=6）。

**型別 C：個體行**——不符合型別 A/B 的條目以逐筆記錄。

```
value\tprobability\ttypeID[\tprevious]
```

第 4 欄 `previous`（可選）用於 Bigram。常見於 `meta`（typeID=2）條目。

#### KEY_LINE_MAP 區段

```
#PRAGMA:VANGUARD_HOMA_LEXICON_KEY_LINE_MAP
Su4	0	23
Su4-xiT	23	2
SuP3	25	2
...
```

每行：`readingKey\tstartLine\tcount`。`startLine` 為該讀音在 VALUES 區段中的起始行號（0-based），`count` 為該讀音佔的行數。讀音使用加密字元集（ㄅ→b 等拉丁替代），多音節以 `-` 分隔。

### RevLookup 派生規則（取代 dedicated `.revlookup`）

若 consumer 需要反查資料，應直接從 `.txtMap` 內文派生：

1. 掃描 `KEY_LINE_MAP` 取得讀音鍵對應的 VALUES 行範圍。
2. 解析 VALUES 行內容，僅納入真正的單字漢字條目。
3. 以「漢字 → line indices / data positions」建立索引，查詢時再按需還原讀音。

現行正式規格**不再定義** dedicated `.revlookup` 檔案，也不要求 builder 輸出任何反查 sidecar。

### EntryType rawValue 對照表

| rawValue | 名稱 | 說明 |
|----------|------|------|
| 2 | meta | 建構元資料（`_BUILD_TIMESTAMP`、`_NORM`） |
| 3 | revLookup | 保留給 legacy / 非 TextMap 反查資料結構；現行 `vanguardTextMap` 輸出不使用 |
| 4 | letterPunctuations | 標點符號 |
| 5 | chs | 簡體中文 |
| 6 | cht | 繁體中文 |
| 7 | cns | CNS 標準漢字（量大，可於查詢時以 `filterType` 篩除） |
| 8 | nonKanji | 非漢字條目 |
| 9 | symbolPhrases | 符號短語 |
| 10 | zhuyinwen | 注音文 |

$ EOF.
