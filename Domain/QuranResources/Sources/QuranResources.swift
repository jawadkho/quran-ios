//
//  QuranResources.swift
//
//
//  Created by Mohamed Afifi on 2023-06-24.
//

import Foundation

public enum QuranResources {
    public static let quranUthmaniV2Database = Bundle.module
        .url(forResource: "Databases/quran.ar.uthmani.v2.db", withExtension: "")!

    /// Word-by-word recitation timings for Mahmoud Khalil Al-Husary (gapless),
    /// already expressed in the same audio timeline the app plays.
    public static let husaryWordSegmentsDatabase = Bundle.module
        .url(forResource: "Databases/husary_word_segments.db", withExtension: "")!
}
