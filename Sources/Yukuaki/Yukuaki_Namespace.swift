// (c) 2025 and onwards The vChewing Project (MulanPSL-2.0 License).
// ====================
// This code is released under the SPDX-License-Identifier: `MulanPSL-2.0`.

/// Yukuaki 模組的命名空間。
///
/// Yukuaki 是 Homa 的功能子集。命名典故：《原神》的「Homa」取自胡桃的「護摩之杖」，
/// 「Yukuaki」則取自行秋（日文配音的讀音）。
///
/// 這個套件只保留兩件事所需的機制：
///
/// 1. 在給定讀音鏈（注音符號，或 ASCII 數字標調的漢語拼音）的前提下，以動態規劃完成組句；
/// 2. 組句結果與期望結果不符時，在撇開審字因素的前提下，逆推需要追補哪些
///    bigram／trigram，以及這些 gram 需要多大的等效詞頻。
///
/// 與 Homa 的差異：不含行為感知（POM）、游標編輯、節點覆寫鏡像、候選字輪替、
/// 輸入法 session 狀態等「只有輸入法才會用到」的控制 API。
public enum Yukuaki {}
