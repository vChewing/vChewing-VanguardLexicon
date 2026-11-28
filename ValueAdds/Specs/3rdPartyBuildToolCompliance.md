## 第三方建置工具遵循規範：VanguardTextMap 與逐表回退（定稿）

> 適用對象：第三方語料包發佈者、其建置工具作者，以及任何自行產製 `.txtMap` 的下游。
> 適用版本：唯音輸入法 **v5.1.0 版起**。更早的版本沒有逐表回退，只有全有全無的辭典切換。
> 本文只談「第三方在建置 VanguardTextMap 時必須遵守的行為」；格式欄位見 `VanguardTextMapSpec.md`，分數公式見 `CalculationMethod4NormAndWeights.md`。

### 一、Specs 目錄導覽

`ValueAdds/Specs/` 目前有四份文件（含本文）：

| 檔 | 內容 | 讀者與時機 |
|---|---|---|
| `VanguardTextMapSpec.md` | `.txtMap` 的位元組格式：HEADER／VALUES／KEY_LINE_MAP、型別 A／B／C／D、escaped-pipe 編碼、meta 與 EntryType 對照。 | 建置工具作者；**動手寫檔前必讀**。 |
| `CalculationMethod4NormAndWeights.md` | `VCDataBuilder` 如何算 `_NORM`、`weighten`、n-gram 分母、`DEFAULT_PROB` 與固定分數。 | 需要自行決定分數、`_NORM` 或 `DEFAULT_PROB` 時必讀。 |
| `ChtOrthographySpec.md` | 繁體中文用字與讀音的判定權威、異體字與又音處理。 | 提供 CHT 語料者；這是資料品質規範，不是二進位格式。 |
| `3rdPartyBuildToolCompliance.md`（本文） | 第三方可只提供部分 Table；空 Table 的判定、逐表回退、meta 與 `DEFAULT_PROB` 的遵循事項。 | 打包與驗收前。 |

建議閱讀順序：`VanguardTextMapSpec.md` → `CalculationMethod4NormAndWeights.md` → 本文 →（若提供 CHT）`ChtOrthographySpec.md`。

### 二、Table 與 Gram 的定義

- **Table**：同一個 `typeID` 的條目集合。現行 `typeID` 如下：

| typeID | 名稱 | 是否候選查詢表 | 備註 |
|---:|---|:---:|---|
| 2 | `meta` | 否 | `_NORM`、`_BUILD_TIMESTAMP`、`_VENDOR`、`_COMMIT_HASH` |
| 3 | `revLookup` | 否 | TextMap 不輸出；不是 Table id |
| 4 | `letterPunctuations` | 是 | 現行原廠 TextMap 為空（標點由 LibVanguard 供給） |
| 5 | `chs` | 是 | 簡體中文 |
| 6 | `cht` | 是 | 繁體中文 |
| 7 | `cns` | 是 | CNS 全字庫 |
| 8 | `nonKanji` | 是 | 非漢字 |
| 9 | `symbolPhrases` | 是 | 符號 |
| 10 | `zhuyinwen` | 是 | 注音文 |
| 11 | `gbex` | 是 | GB18030-2022 擴充字 |

- **Gram**：由 VALUES 區段實際解析出來的一筆 entry。型別 A（`>typeID`）、型別 B（`@` 的 CHS／CHT 格）、型別 C（`value\tprobability\ttypeID`）、型別 D（`!value\t…`）皆算；**header 行、`DEFAULT_PROB_?` 行、BEL 佔位（`\u{7}`）、空 cell 都不算 Gram**。
- **Table 存在性**：`TextMapTrie` 於 `init` 時掃描 VALUES，一次算定 `presentEntryTypes: Set<Int32>`；`hasEntries(ofType:)` 即「該 typeID 是否在集合內」。TextMap 沒有「宣告某 Table 但零筆」的表示法，故「空 Table」就是「該 typeID 一個 Gram 都沒有」。
- **技術背景（v5.1.0 版）**：v5.1.0 版的 `TextMapTrie` 於載入時算定 `presentEntryTypes`／`hasEntries(ofType:)`；`FactoryDictionary` 另以 `fallbackTrie` 與 `trie(for:)` 逐表選擇 primary 或 fallback。兩者合起來就是本文的逐表回退。

### 三、逐表回退（v5.1.0 版起）

v5.1.0 版的 `FactoryDictionary` 以 `trie`（primary）與 `fallbackTrie`（fallback）兩個實例運作；回退可為 `nil`（載入失敗時）：

- **primary**：第三方／外置辭典（你提供的 `.txtMap`）。
- **fallback**：輸入法同捆的內建 TextMap。

查詢時以 **單一 concrete typeID** 決定路由：

```text
trie(for: type):
  if primary != nil, primary.hasEntries(ofType: type):  return primary
  if fallback != nil:                                    return fallback
  return primary
```

四條硬規則：

1. **逐表、不是逐鍵**。primary 對該 typeID 有至少一筆 Gram，整個 Table 就用 primary；此後該 Table 的缺鍵**不會**回退到內建 Table，查無就是查無。
2. **primary 對該 typeID 零 Gram**，才整表落到 fallback。fallback 亦無該 Table 時，結果自然是空。
3. **反查是例外**：反查沒有 type 參數，故不走逐表回退，而是 primary 的讀音在前、fallback 補缺（同一讀音去重）。
4. **複合或空 `filterType` 不走逐表路由**：跨 type 查詢仍以 primary 為準；逐表回退只對單一 discrete type 生效（2、4、5、6、7、8、9、10、11；3 與 100 不是 Table id）。

macOS 宿主在正常發佈路徑會把「外置辭典」當 primary、「app 同捆者」當 fallback；顯式 `dbPath`（debug harness）不掛 fallback，以免測試資料摻入正式辭典。

### 四、第三方可只提供部分 Table

**可以。** 第三方語料包不必湊齊全部 Table；未提供的 Table 會由內建 TextMap 接手。但必須遵守：

> **未提供的 Table 必須連一筆 Gram 都不能有。**

「一筆 Gram」包含：一筆 type C 或 type D、`>typeID` 分組行中的任一個值、`@` 行中該語系格的一個值。**只要有任何一筆，該 Table 就算 present**，逐表回退即對它失效；之後該 Table 的缺鍵不會回退。

正確與錯誤做法：

| 你的資料 | 正確做法 | 錯誤做法 |
|---|---|---|
| 只提供 CHS | 只寫 type 5 的 Gram；`@` 行的 CHT 格一律 BEL（`\u{7}`）；沒有任何 type 6 的 Gram | 在 CHT 格放一筆「測試」值，期待其餘 CHT 由內建補 |
| 提供 CHS＋CHT | 兩表都給完整；CHT 依 `ChtOrthographySpec.md` 校對 | 只給 CHT 少數詞，其餘靠 fallback |
| 不提供 CNS | 完全沒有 type 7 的行；也不要寫 `DEFAULT_PROB_7` 或空的 `>7` | 寫一筆 type 7 佔位，期待 fallback |
| 不提供 GBEX | 完全沒有 type 11 的行 | 寫一筆 `>11` 空行或一筆測試字 |
| 不提供符號／注音文 | 完全沒有 type 9／10 的行 | 寫一筆 type 9／10 的佔位值 |
| 不提供標點 | 完全沒有 type 4 的行（原廠亦為空） | 寫一筆 type 4 佔位 |

三個容易誤判的邊界：

- **BEL 不是 Gram**。`@probability\tCHS 值\t\u{7}` 只建立 CHS（type 5）的 Gram；CHT（type 6）仍是空的，故 CHT 會整表回退。這是「只提供 CHS」的正確寫法。
- **空的 `>typeID` 行不是合法的空 Table 宣告**。在受信任的 bundled 掃描路徑，`>typeID` 行本身就可能被計為該 type 存在；在外部檔案的逐行驗證路徑，空 cell 會被判 malformed。只有 BEL 的 `>typeID` 行雖可能解出零筆，仍不應使用——它對「空 Table」沒有宣告效力。要省略 Table，就完全不要寫該行。
- **`DEFAULT_PROB_?` 不是 Table 存在訊號**。它只是 header 的預設機率；只寫 `DEFAULT_PROB_6` 而沒有任何 type 6 的 Gram，type 6 仍然是空的（但這行沒有意義，應一併省略）。反過來，有 type 6 的 Gram 但沒有 `DEFAULT_PROB_6`，type 6 仍是 present，只是那些列必須自帶機率（型別 C／D）。

### 五、`_BUILD_TIMESTAMP` 是 `timeIntervalSince1970`

`_BUILD_TIMESTAMP` 是 typeID 2 的 meta 條目，寫成型別 C：

```text
_BUILD_TIMESTAMP\t<seconds>\t2
```

- `<seconds>` 是 `Date().timeIntervalSince1970`：**Double、UTC 1970-01-01T00:00:00Z 起算的秒數**，可含小數。
- 不是毫秒、不是 `Date` 的字串、不是 locale 日期格式。
- 第一格是字面 `_BUILD_TIMESTAMP`；時間戳在**第二格**（probability）。不要顛倒。
- 例：`_BUILD_TIMESTAMP\t1795841268.42062\t2`。
- 消費端只把它當建置中繼資料；第三方仍應使用同一單位，否則診斷工具會把它讀成遙遠的未來或過去。

同族的 meta 條目有不同的 payload 位置，這是第三方最常寫錯的地方：

| meta | VALUE（第一格） | probability（第二格） | 說明 |
|---|---|---|---|
| `_NORM` | 字面 `_NORM` | 詞頻基準 `N` | 分數基準，不是分數 |
| `_BUILD_TIMESTAMP` | 字面 `_BUILD_TIMESTAMP` | `timeIntervalSince1970` 秒數 | 本文 §5 |
| `_VENDOR` | 產製者字串（可選） | `0` | 由建置管線蓋章 |
| `_COMMIT_HASH` | 資料指紋 HASH（可選） | `0` | 由建置管線蓋章 |

第三方建議提供 `_NORM` 與 `_BUILD_TIMESTAMP`；`_VENDOR`／`_COMMIT_HASH` 可選。若省略 `_NORM`，查詢仍可運作（分數已是絕對值），但除錯、跨語系降權與由分數逆推詞頻的工具會失去基準。

### 六、`DEFAULT_PROB_?` 的意義與現行預設值

`DEFAULT_PROB_<typeID>` 是 HEADER 的一行：

```text
DEFAULT_PROB_7\t-11
```

它的用途只有一個：讓同 typeID 的**無前文**條目以型別 A（`>typeID\t…`）分組、省略每列機率。它**不是** Table 的存在宣告，也不是「查無此 Table 時」的預設分數。

#### 6.1 Builder 的產生規則

- 只採計**無前文**、且 typeID 不是 CHS（5）／CHT（6）的條目；CHS／CHT 走 `@` 分組，不用 `DEFAULT_PROB`。
- 若某 typeID 的上述條目**全部共用同一個機率**，才寫 `DEFAULT_PROB_<typeID>`，並把那些條目併成 `>typeID` 行。
- 若同 typeID 有多個機率，就不寫 `DEFAULT_PROB`；該 type 的條目改以自帶機率的形式輸出（非 CHS／CHT 者為型別 C／D；CHS／CHT 為 `@`）。
- 型別 A 必須有對應的 `DEFAULT_PROB_<typeID>`；沒有的話，解析器會以 malformed 拒收。沒有預設值時，請改用型別 C 自帶機率。
- `DEFAULT_PROB` 值必須與 `>typeID` 行所代表的實際分數一致；否則 grouped rows 會得到錯的分數。

#### 6.2 現行原廠 TextMap 的預設值

2026-11-28 之建置快照：

| typeID | 名稱 | `DEFAULT_PROB` | 來源 |
|---:|---|---:|---|
| 7 | `cns` | `-11` | 固定分數 |
| 9 | `symbolPhrases` | `-13` | 固定分數 |
| 10 | `zhuyinwen` | `-1` | 固定分數 |
| 11 | `gbex` | `-11` | 固定分數 |

- typeID 2（meta）沒有 `DEFAULT_PROB_2`：`_NORM`、`_BUILD_TIMESTAMP`、`_VENDOR`／`_COMMIT_HASH` 並非全部共用同一機率。
- typeID 5／6 沒有 `DEFAULT_PROB`：CHS／CHT 以 `@` 行自帶機率。
- typeID 8（nonKanji）沒有 `DEFAULT_PROB`：各列機率不一。
- typeID 4（letterPunctuations）現行為空（標點由 LibVanguard 供給），故也沒有 `DEFAULT_PROB_4`。

第三方可以自訂自己的 `DEFAULT_PROB` 值（不必抄原廠的 −11／−13／−1），但必須遵守 §6.1 的三條：有 `>typeID` 行就要有對應的 `DEFAULT_PROB`、值要與實際分數一致、沒有預設值就用型別 C。`DEFAULT_PROB` 可以是 0 或負值；寫成十進位數字（整數亦可，如 `-11`），不要寫百分比或字串。

### 七、驗收清單

1. 依 `VanguardTextMapSpec.md` 產製 HEADER／VALUES／KEY_LINE_MAP；型別 A／B／C／D 的欄數與轉義正確。
2. 每個**要提供**的 Table 至少有一筆真實 Gram；每個**要省略**的 Table 是零筆 Gram，且完全沒有該 typeID 的 VALUES 行。
3. 沒有空的 `>typeID` 行；`@` 行的空 lane 一律用 BEL（`\u{7}`），不要用空 cell。
4. 每個 `>typeID` 行都有對應的 `DEFAULT_PROB_<typeID>`；其值與該 Table 的實際分數一致。
5. `_NORM` 與 `_BUILD_TIMESTAMP` 的 payload 在 probability 欄；`_VENDOR`／`_COMMIT_HASH` 的 payload 在 VALUE 欄、probability 為 0。
6. `_BUILD_TIMESTAMP` 是 `timeIntervalSince1970` 秒數（Double），不是毫秒、不是日期字串。
7. 以 v5.1.0 版實測：
   - `TextMapTrie(data:).hasEntries(ofType:)` 對你省略的 type 回 `false`、對你提供的 type 回 `true`；
   - 省略的 type 查詢會落到內建 Table；
   - 提供的 type 在缺鍵時**不會**回退（這是預期行為，不是 bug）；
   - 反查會 primary 在前、fallback 補缺。
8. 若提供 CHT，依 `ChtOrthographySpec.md` 校對用字與讀音。

### 八、常見誤解

| 誤解 | 事實 |
|---|---|
| 「我只給 CHS，CHT 留空 cell 就好」 | CHT 的空 lane 要用 BEL；空 cell 可能被判 malformed。 |
| 「我放一筆 CHT 測試詞，其餘 CHT 交給 fallback」 | 一旦有 CHT Gram，整個 CHT Table 就是你的；其餘鍵不會回退。 |
| 「`DEFAULT_PROB_6` 可以宣告空的 CHT Table」 | 不行；presence 只看實際 Gram，且這行沒有意義。 |
| 「空的 `>6\t` 行是合法的空 Table」 | 不是；要省略就完全不要寫該行。 |
| 「缺 `_NORM` 也能完整運作」 | 查詢可以；但分數基準、除錯與逆推工具會缺。 |
| 「`_BUILD_TIMESTAMP` 可以放毫秒或日期字串」 | 只收 `timeIntervalSince1970` 秒數。 |
| 「`_VENDOR` 放 probability 欄」 | 放 VALUE 欄，probability 為 0。 |
| 「所有 Table 都必須提供」 | 不必；未提供的 Table 由內建 fallback 接手，但必須零 Gram。 |
