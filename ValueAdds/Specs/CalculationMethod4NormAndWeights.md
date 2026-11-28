## VCDataBuilder：NORM 與對數權重之計算方法（定稿）

> 本文說明 `VCDataBuilder` 如何計算 `Collector.norm`（即 `.txtMap` 之 `_NORM`）與各輸出所用之 `log10` 權重。
> 適用範圍為 `vanguardTextMap` 與 `textKVSTableCHS`／`textKVSTableCHT` 兩條產製路徑；`chewingRustCHS`／`chewingRustCHT` 與 `chewingCBasedCHS`／`chewingCBasedCHT` 只取原始頻次，不經本文之對數折算（見 §5.3）。
> 本文之數值皆是**策展參數**：詞頻來源為 NAER 多分類疊加、對數壓縮與多年逐詞手調，不是單一語料之樣本數。公式是排序裝置，不是統計估計；為解決特定排序問題而手調詞頻或 n-gram，屬正當手段。
>
> 本文以 2026-11-28 之 `VCDataBuilder` 原始碼為準。若公式變動，除本文外，`VanguardTextMapSpec.md`、`VanguardLexiconDebugger`、`VanguardLexiconCorpusMiner` 與 `Yukuaki` 之對位處亦須同步（見 §7）。

### 一、符號與基本約定

| 符號 | 定義 |
|---|---|
| `w` | 一筆詞條的 VALUE（`Unigram.value`） |
| `len(w)` | `w.count`，即 Swift `String.count` 之 `Character` 數（grapheme cluster 數；**不是** UTF-8 byte 數、也不是 Unicode scalar 數） |
| `c(w)` | 該列之 `count`（`Unigram.count`）；`#NERFED` 者恆為 0 |
| `L(w)` | 長度因子：`exp(len(w) / 3 − 1)` |
| `N` | `Collector.norm`；`.txtMap` 之 `_NORM` |
| `D` | n-gram 之分母（見 §4） |
| `score` | `log10(…)` 之權重；負值，愈大愈優先，0 為上限 |

三條基本約定：

1. **`score` 不是機率**。它是 `log10` 尺度的排序分數，全體不會加總為 1；把它當成「機率」再正規化一次會得到錯誤結果。
2. **`weighten` 之結果四捨五入至小數三位**。`Double.rounded(toPlaces: 3)` 之實作為 `(x × 1000).rounded() / 1000`，預設捨入規則為 `toNearestOrAwayFromZero`。因此由 `score` 逆推 `count` 時只能得到近似值（見 §6）。
3. **固定分數不經 `weighten` 的常規分支**：CNS／GBEX 之 −11、符號之 −13、注音文之 −1 由建構時直接指定；`#NERFED` 之 −114.514 由 `weighten` 的專屬分支直接賦值（見 §3.4）。

### 二、NORM 的組成

#### 2.1 公式

設 `lang ∈ {chs, cht}`，且 `normDelta(w) = L(w) × c(w)`（只對可計入的類別與列；見 §2.3）：

```text
C_lang = Σ normDelta(w)                    # char-kanji-core 之該語系欄
P_lang = max(Σ_macv, Σ_tabe, Σ_moe)        # 該語系各詞類之和取最大
N      = max(C_chs, C_cht) + max(P_chs, P_cht)   # 雙語系（isCHS == nil）
N      = C_lang + P_lang                          # 單語系（isCHS == true/false）
```

用一句話說：**NORM ＝ 漢字核心之（跨語系最大）和 ＋ 詞類之（類別最大、再跨語系最大）和**。它不是語料總量，也不是所有 `count` 的總和。

#### 2.2 程式路徑

1. `VCDataBuilder.Collector.init` 依序讀非漢字、漢字核心、注音符號。`prepareRawUnweightedUnigramsForCoreKanjis` 逐列解析 `char-kanji-core`，對 CHS／CHT 各累加 `normCHS`／`normCHT`；`norm += max(normCHS, normCHT)`，寫入 `temporaryNormShared`。
2. 對每個語系呼叫 `prepareRawUnweightedUnigramsForPhrases`：
   - 逐類別（`macv`／`tabe`／`moe`／`custom`／…）累加 `currentNorm`；
   - 每個類別之 `currentNorm` 收進 `norms`，最後 `norm += norms.max()`；
   - 產出該語系之 `temporaryNorm`，收進 `Collector` 的 `norms` 陣列。
3. `Collector` 以 `normValue = temporaryNormShared + (norms.max() ?? 0)` 定案，賦予 `self.norm`。
4. `prepareTrie()` 把 `_NORM` 寫成 typeID 2 之 meta 條目，`probability` 即 `data.norm`；其 VALUE 也是 `_NORM`，不是分數。
5. `propagateWeights()` 把 `norm` 傳給所有 `Unigram.weighten(norm:)`；n-gram 則在 `Collector.init` 內以各自的分母折算（見 §4）。

#### 2.3 哪些列計入 NORM

`Unigram.normDelta` 的守門條件：

- `isNerfed == true` ⇒ `nil`（`#NERFED` 無權參與盤點）。
- 類別為 `.custom`、`.misc`、`.cns`、`.gbex` ⇒ `nil`。
- `keyCells.count` 不在 `1...6` ⇒ `nil`（七音節以上之詞條不計入 NORM，但仍會計分）。
- 其餘：`L(w) × c(w)`。

| 來源 | 類別 | 計入 NORM | 說明 |
|---|---|:---:|---|
| `char-kanji-core` | `.kanji` | 是 | 取該語系欄位；雙語系時取 `max` |
| `phrases-vchewing-*` | `.macv` | 是 | 該類別之和；與其他詞類取 `max` |
| `phrases-tabe-*` | `.tabe` | 是 | 同上 |
| `phrases-moe-*` | `.moe` | 是 | 同上 |
| `phrases-custom-*` | `.custom` | 否 | `normDelta` 回 `nil`；仍參與計分 |
| `char-misc-nonkanji` | `.misc` | 否 | `normDelta` 回 `nil`；仍以 `weighten` 計分 |
| `char-misc-bpmf` | `.bpmf` | 否 | 不累加進 NORM；`weighten` 仍以 `N` 計分；`count` −1／−2 為假名哨兵 |
| `char-kanji-cns` | `.cns` | 否 | 固定 −11 |
| `char-kanji-gbex` | `.gbex` | 否 | 固定 −11 |
| `data-symbols` | `.misc` | 否 | 固定 −13 |
| `data-zhuyinwen` | `.misc` | 否 | 固定 −1 |
| `phrases-ngram-*` | — | 否 | 條件機率，另用分母 `D` |

補充：

- **`count == 0` 仍「參與」盤點，只是量為 0**：`normDelta` 回 0，不是 `nil`。這與 `#NERFED` 的「不參與」不同。
- **`#NERFED` 之 `count` 在建構時即被強制為 0**，`normDelta` 另以旗標擋下；不得只靠「乘出來剛好是 0」排除，否則頻次政策一改，`_NORM` 就會靜默膨脹。
- **七音節以上之列**不計入 NORM。這是刻意上限：長詞若全數計入，少數長句會主導基準；其分數仍照 §3 計算。
- **負 `count` 只應出現在假名哨兵**（−1／−2），而那些類別（`.misc`／`.bpmf`）不計入 NORM；計入 NORM 的類別，其 `count` 應為非負整數。
- **取 `max` 之設計意圖**：同一批詞可能在 CHS／CHT 兩軌、或在不同詞類（如 MOE 與 Tabe）重複出現；若直接把各軌、各類別相加，重複列會被多次計入。取最大值使 NORM 成為穩定的基準，而不是語料總量。這個結構是刻意的，不是漏加。

#### 2.4 語言模式與 `_NORM`

- `vanguardTextMap` 以 `Collector(isCHS: nil, …)` 建置 ⇒ 同時讀 CHS／CHT，`N` 為 `max(C_chs,C_cht) + max(P_chs,P_cht)`。
- `textKVSTableCHS` 以 `isCHS: true` 建置 ⇒ `N = C_chs + P_chs`。
- `textKVSTableCHT` 以 `isCHS: false` 建置 ⇒ `N = C_cht + P_cht`。
- **因此同一詞在 `.txtMap` 與兩份 KVS 中的 `score` 不保證相同**：三者各自以自己的 `N` 折算。KVS 不含 `_NORM` 等 meta，消費端無法從檔案本身還原基準；跨表比較分數時必須先確認其 `N`。
- `_NORM` 之數值不經三位四捨五入：`.txtMap` 直接寫 `Double.description`（例如 `374372341.7170592`）。

### 三、單元圖之對數權重

#### 3.1 `weighten(norm:)`

```text
weighten(norm N):
  if isNerfed:
    score = -114.514
  else switch count:
    case -2, -1:
      score = -13                         # 假名哨兵，非真實頻次
    case 0:
      score = log10(L(w) × 0.25 / N)      # 零頻次之偽計數
    default:
      score = log10(L(w) × count / N)
  score = round(score, 3)
```

- 單元圖之 `N` 即 `Collector.norm`。
- `count > 0` 時，分子就是 `normDelta(w)`，故 `score = log10(normDelta / N)`。
- `count == 0` 時，`normDelta` 為 0（不膨脹 NORM），但計分改用 `0.25` 作為偽計數；這是「墊底但仍可被選」的設計。以現行 `N` 計，單字零頻次約得 −9.465。
- `count == -1`／`-2` 是假名專用哨兵，不是「負一次」；一律給 −13，且不套長度因子與 NORM。
- `#NERFED` 直接給 −114.514，不經 NORM、不經 0.25、不再捨入。此值遠低於任何真實單元圖，故除「唯一結果」外不會被組句器取用。
- 捨入至小數三位是為了控制 `.txtMap` 體積；由 `score` 逆推 `count` 時只能得到近似值。

#### 3.2 分支速查

| 情況 | `score` | 備註 |
|---|---|---|
| `#NERFED` | `-114.514` | `Unigram.nerfedWeight` |
| `count == -1`／`-2` | `-13` | 假名哨兵 |
| `count == 0` | `log10(L(w) × 0.25 / N)` | 零頻次墊底 |
| `count > 0` | `log10(L(w) × count / N)` | 一般詞條 |
| CNS／GBEX | `-11` | 固定，不經 `weighten` |
| 符號（`data-symbols`） | `-13` | 固定，不經 `weighten` |
| 注音文（`data-zhuyinwen`） | `-1` | 固定，不經 `weighten` |
| meta `_NORM` | `N`（不是分數） | `probability` 即基準 |
| meta `_BUILD_TIMESTAMP` | UNIX 時間戳（不是分數） | `Date().timeIntervalSince1970` |
| meta `_VENDOR`／`_COMMIT_HASH` | `0` | 佔位符；由消費端建置管線蓋章 |

#### 3.3 固定分數為何不經 `weighten`

- CNS／GBEX 的條目由 `loadSupplementaryKanjiRows` 以 `score: -11` 建構，`propagateWeights()` **不處理** `tableKanjiCNS`／`tableKanjiGBEX`，故它們保持 −11。
- 符號由 `getSymbols()` 以 `score: -13` 建構、注音文由 `getZhuyinwen()` 以 `score: -1` 建構；兩者都是獨立的 `[Unigram]`，不在 `propagateWeights()` 的表中。
- 這些固定值是「不參與語言模型競爭、只作供應」的排序定位；把它們改成 `weighten` 會讓 CNS／GBEX 依長度與 NORM 浮動，破壞既有的層級。

#### 3.4 實例

以 2026-11-28 之建置快照 `N ≈ 374372341.7170592` 為例（數值會隨資料變動，公式不變）：

| 詞條 | `len` | `count` | 計算 | `score` |
|---|---:|---:|---|---:|
| `測試` | 2 | 510 | `log10(exp(2/3−1) × 510 / N)` | `-6.010` |
| `測` | 1 | 4477 | `log10(exp(1/3−1) × 4477 / N)` | `-5.212` |
| 單字零頻次 | 1 | 0 | `log10(exp(1/3−1) × 0.25 / N)` | `-9.465` |
| `再`（bigram，D＝6528） | 1 | 5 | `log10(exp(1/3−1) × 5 / 6528)` | `-3.405` |

第一列在 `.txtMap` 中對應 `@-6.01` 之 CHS／CHT 分組行；第三列即 `VanguardTextMapReader` 所稱之零頻次權重。

### 四、n-gram 之條件機率分數

#### 4.1 公式

n-gram 沿用同一個 `weighten`，差別只在分母：

```text
score = log10(L(w) × c(w | context) / D)
```

- `w` 是 n-gram 的詞值；`c(w | context)` 是該列第 2 欄的次數。
- `D` 是「前文」本身的詞頻，不是 `N`；只有完全取不到前文詞頻時才退回 `N`。
- `L(w)` 只取詞值長度，不取前文長度。
- 分數同樣四捨五入至小數三位。
- 因為多了 `L(w)`，這個分數**不是**完整的條件機率 `c(w|context)/D`；它是同一套排序尺度下的加長版權重。

#### 4.2 分母 `D` 的決定

`resolveNgramDenominator` 的規則：

| 情況 | `D` | `denominatorSource` |
|---|---|---|
| 第 5 欄給出正整數 | 該整數 | `.fullContext` |
| bigram、無第 5 欄、`count(y)` 可得 | `count(y)` | `.legacyUnigramCount` |
| bigram、無第 5 欄、`count(y)` 不可得 | `N` | `.normalizedFallback` |
| trigram、無第 5 欄 | **報錯** | — |

- 第 5 欄是「完整前文的原始詞頻」：bigram 為 `count(y)`、trigram 為 `count(x, y)`、缺口列為 `count(x, ·)`。
- `count(y)` 由 `makeCountTable` 取得：同一個詞值可能有多讀音、多類別，取其 `count` 的**最大值**；這是原始頻次，不是 `score`。
- trigram 缺第 5 欄一律報錯。退回 `count(y)` 或 `N` 只是把錯誤的分母當成正確答案，故不允許。
- `NgramRecord` 會保留 `count`、`score`、`contextCount`（`nil` 代表退回 `N`）與 `denominatorSource`，供除錯與逆推。
- 缺口列 `[x, *]`：`*` 只准居兩格前文鏈之末，且第 5 欄必填 `count(x, ·)`；分數公式不變。`*` 以哨兵字串儲存，不存 `nil`，否則鏈長會掉回 1。
- `#NERFED` 不適用於 n-gram 列：n-gram 的權重是條件機率，沒有「頻次 0、權重 −114.514」的語義；該旗標出現在第 6 欄註解位亦一律報錯。

#### 4.3 與 NORM 的關係

- n-gram 的 `D` 是前文詞頻（或 `N` 作為最後退路），不是 NORM 的組成部分；n-gram 列也不參與 NORM 盤點。
- 這意味著 n-gram 分數與單元圖分數雖然共用 `L(w)` 與 `log10`，但分母不同，數值不可直接相加或互相比較絕對值。
- `weighten` 的 `count == 0`／`-1`／`-2` 分支在 n-gram 路徑同樣會生效，但正常的 n-gram 列之次數應為正整數。

### 五、分數如何進到輸出

#### 5.1 `vanguardTextMap`

- Trie 條目之 `probability` 即上述 `score`。
- HEADER 的 `DEFAULT_PROB_<typeID>` 只在「該 typeID 所有無前文條目共用同一個機率」時才寫出；CHS／CHT 不參與此判定。
- 無前文且機率等於 `DEFAULT_PROB` 的條目，按 typeID 合併成 `>typeID\t…` 行；CHS／CHT 則按機率分組成 `@probability\tchsCell\tchtCell`。
- 其餘條目逐筆寫成 `value\tprobability\ttypeID[\tcontext]`；同值同型別的多筆前文條目可聚合成 `!value\t…` 行。
- meta（typeID 2）因 `_NORM`／`_BUILD_TIMESTAMP` 之機率與 0 不同（`_VENDOR`／`_COMMIT_HASH` 皆為 0），不會有 `DEFAULT_PROB_2`，而是逐筆 C 行。`_NORM` 行的第二欄是 `N`，不是分數。
- 機率字串由 `formatProbability` 輸出：整數值去掉 `.0`（故 `0.0` 寫成 `0`、`-13.0` 寫成 `-13`）。
- 現行快照之固定預設值可見到 `DEFAULT_PROB_7 -11`（CNS）、`DEFAULT_PROB_9 -13`（符號）、`DEFAULT_PROB_10 -1`（注音文）、`DEFAULT_PROB_11 -11`（GBEX）。

#### 5.2 `textKVSTableCHS`／`textKVSTableCHT`

- 單元圖列：`key value score`；帶 `#NERFED` 者另附第 4 欄 `#NERFED`。
- n-gram 列：`key value score #NGRAM:前文鏈`（`|` 分隔、由舊至新）。
- 使用同一條 `weighten` 公式；但 `N` 是該語系單獨的 NORM（見 §2.4）。
- `getAllUnigrams` 預設 `omitCNS: true`，故 KVS 不含 CNS／GBEX；另追加 `getSymbols()` 與 `getZhuyinwen()`。
- KVS **不輸出** `_NORM` 等 meta；需要基準時只能由建置參數或另附資訊得知。

#### 5.3 `chewingRust*`／`chewingCBased*`

- 這兩族 builder 只取 `gram.count`（原始頻次）、`gram.key`／`gram.keyCells` 與詞值，輸出 `tsi.src`／`word.src` 或 `dictionary.dat`／`index_tree.dat`；它們**不取** `gram.score`，也不輸出 `_NORM`。
- 它們另以 `keyCells.count == value.count` 過濾「音節數與字數不符」的條目；這是格式限制，與本文的對數公式無關。
- 因此本文的 NORM 與 `weighten` 不適用於這兩族輸出；把它們的頻次當成 `score` 會混淆兩套語義。

### 六、消費端之同式推導（非產製）

以下公式不在 `VCDataBuilder` 內，但直接依賴本文的尺度；改動產製公式時必須一併檢查。

| 落點 | 公式 | 用途 |
|---|---|---|
| `VanguardTextMapReader.crossLaneWeight` | `min(log10(L × 0.25 / N), lineProbability)` | 另一語系軌之詞條降權；只降不升，`#NERFED` 不會被抬升 |
| `VerifyRunner.analyticProbability` | `log10(L × count / D)` | 以語料次數重建 n-gram 機率；非法輸入回 `-8.164` |
| `CorpusMiner` | `log10(L × corpusCount / denominator)` | 由語料共現計算候選 n-gram 的機率，再與既有 gate 比較 |
| `UnigramSegmenter.unknownCharacterProbability` | `log10(0.5 / N)` | 詞表外單字之固定罰分 |
| `TxtMapUnigramIndex` | `count = N × 10^p / L` | 由 `.txtMap` 的 `score` 逆推詞頻；因三位捨入，僅為近似 |
| `Yukuaki` 之 `requiredCount` | 由同一條 `L × count / D` 反解 | 逆推「至少要多大的 count 才能勝出」 |

### 七、維護清單

改動 NORM 或 `weighten` 時，至少檢查：

1. `Sources/LibVanguardChewingData/SubCodes/BaseTypes/Unigram.swift`：`normDelta`、`weighten`、`nerfedWeight`。
2. `Sources/LibVanguardChewingData/SubCodes/Collector/Collector_Core.swift`：`Collector.init`、`prepareRawUnweightedUnigramsForCoreKanjis`、`prepareRawUnweightedUnigramsForPhrases`、`propagateWeights`。
3. `Sources/LibVanguardChewingData/SubCodes/Collector/Collector_Ngram.swift`：`resolveNgramDenominator`、`makeCountTable`、`parseNgramLines`。
4. `Sources/LibVanguardChewingData/SubCodes/Builders/DataBuilder_Protocol.swift` 與 `DataBuilder_VanguardTextMap.swift`／`DataBuilder_TextKVSTable.swift`：meta 與序列化。
5. `Sources/VanguardLexiconDebugger/`、`Sources/VanguardLexiconCorpusMiner/`、`Sources/Yukuaki/`：§6 之同式推導。
6. 測試：`Tests/LibVanguardChewingDataTests/PhraseNerfFlagTests.swift`（NORM 排除與零頻次）、`Tests/LibVanguardChewingDataTests/LibVanguardChewingDataTests.swift`（n-gram 分數與詞類模板）、`Tests/VanguardLexiconDebuggerTests/VanguardLexiconDebuggerTests.swift`（`analyticProbabilityMatchesCollector`）、`Tests/VanguardLexiconCorpusMinerTests/CorpusMinerTests.swift`（`countInversionFollowsWeighten`）、`Tests/VanguardLexiconDebuggerTests/NGramVerifyTests.swift`。

四個最容易改錯的點：

- **不要把 `value.count` 改成 `utf8.count`**。公式用的是 `Character` 數；含 `ZWJ` 的 emoji 等多 scalar 字元只算 1。
- **不要對 `score` 再做一次正規化**。`score` 已是 `log10` 尺度，且全體不會加總為 1。
- **不要移除 `1...6` 之音節上限或把 `max` 改成 `+`**。前者影響長詞對 NORM 的貢獻，後者會讓跨語系／跨類別的重複列被重複計入。
- **不要把 `#NERFED` 之 −114.514 改成 `weighten` 的 count 0 分支**。那會把它抬成約 −9 的普通低頻詞，懲戒失效。
