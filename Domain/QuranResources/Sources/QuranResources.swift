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

    /// The gapless reciter whose word-by-word timings ship with the app, named the way
    /// `Reciter.audioType` names it. Kept beside the database so the two cannot drift.
    public static let wordSegmentsReciterDatabaseName = "husary"

    /// Word-by-word recitation timings for `wordSegmentsReciterDatabaseName`
    /// (Mahmoud Khalil Al-Husary, gapless), already expressed in the same audio
    /// timeline the app plays.
    public static let wordSegmentsDatabase = Bundle.module
        .url(forResource: "Databases/husary_word_segments.db", withExtension: "")!
}
