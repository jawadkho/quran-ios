# Audio Word Follow-Along

While a reciter plays, the word highlight tracks the exact word being recited, and that
word's translation appears in a popover above it.

Only **Mahmoud Khalil Al-Husary** (gapless, reciter id 1) has word timings today. Every
other reciter is a no-op, and playback behaves exactly as it did before this feature.

---

## Using it

Five things must all be true, and four of them are already the defaults:

1. **Reading is `hafs_1405`.** This is the default. It is the only reading with word
   frames, so it is the only one where an individual word can be drawn.
2. **Arabic mushaf mode**, not translation mode. Only the image page draws single words.
3. **Word pointer is on** in the ⋯ (More) menu. This is the on/off switch for the whole
   feature — see [The toggle](#the-toggle).
4. **Al-Husary is the selected reciter.**
5. **The sura is covered by the data** — suras **1, 2 and 78–114**. See
   [Coverage](#coverage-and-known-gaps).

Outside those conditions nothing breaks; the highlight simply does not appear.

### Running it

```bash
cd quran-ios
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
make run-example-no-sync
```

---

## How the pieces fit together

```
QueuePlayer.Player                 one AVPlayerItem per sura mp3
   |
QuranAudioPlayer.currentFileTime   position inside that sura file, in seconds
   |
RecitationWordFollower             polls ~33 Hz, finds the span covering that instant
   |                               emits only when the word changes
AudioBannerViewModel               listener?.highlightRecitedWord(word)
   |
QuranInteractor                    gated on the word pointer switch
   |-- contentViewModel.highlightWord(word)   -> QuranHighlights.pointedWord -> tinted rect
   `-- PopoverView on presenter.pagesView     -> the word's translation
```

### The files

| File | Role |
|---|---|
| `Domain/QuranResources/Sources/Databases/husary_word_segments.db` | The timings. Bundled by SPM, so no `.xcodeproj` edit is needed. |
| `Domain/QuranResources/Sources/QuranResources.swift` | `husaryWordSegmentsDatabase` URL. |
| `Data/AudioTimingPersistence/Sources/GRDBWordSegmentPersistence.swift` | `WordSegment` and `WordSegmentPersistence.segments(forSura:)`. |
| `Domain/QuranAudioKit/.../QuranAudioPlayer.swift` | `currentFileTime`, the playhead inside the current sura file. |
| `Features/AudioBannerFeature/Sources/RecitationWordFollower.swift` | The follower itself. |
| `Features/AudioBannerFeature/Sources/AudioBannerViewModel.swift` | `AudioBannerListener.highlightRecitedWord(_:)`, lifecycle wiring. |
| `Features/QuranViewFeature/Sources/QuranInteractor.swift` | The toggle gate, and the popover. |
| `Features/QuranPagesFeature/Sources/PageGeometryActions.swift` | `wordRect`, the inverse of `word`. |
| `Features/QuranImageFeature/Sources/ContentImageViewModel.swift` | `globalRectForWord`, and the highlight colour choice. |
| `UI/NoorUI/Sources/Theme/QuranHighlights+Theme.swift` | `recitedWordHighlightColor`. |

### Why it polls the clock

The follower reads the player's real position rather than starting a timer at each ayah
boundary. **Pause, resume, seek, repeat and playback rate all stay correct for free**,
because the clock is the source of truth rather than something derived from it. Verified
working at 1.5× without any rate-specific code.

For a gapless reciter each file is one sura, so `AVPlayerItem.currentTime()` is the
position in that sura's mp3 — exactly the timeline the segments are keyed on.

### Why lookup is by time range, not by position

A word can legitimately have **more than one span**, when the reciter repeats or
elongates a passage. 191 such extra spans exist, all in sura 2. So the follower asks
"which span contains this instant", via a binary search on `start_ms`. Spans never
overlap, so at most one matches.

When no span matches — the pause between two ayahs — the follower **holds the last
highlight** rather than flickering it off.

---

## The toggle

The **word pointer** switch in the More menu turns follow-along on and off. There is no
separate setting, because that switch already:

- means "I want to work with individual words",
- persists across launches, and
- is hidden for readings without word positions, which is exactly when follow-along
  cannot work either.

`QuranInteractor.highlightRecitedWord(_:)` returns early while the switch is off.
Turning it off mid-recitation clears the highlight and popover directly, because that
early return would otherwise swallow the clear.

**Side effect worth knowing:** the same switch also shows the draggable pointer arrow.
If follow-along should hide the arrow during playback, that is a deliberate change to
`onIsWordPointerActiveUpdated` / `showWordPointer`, not something you get for free.

### Why the audio path has its own listener method

`AudioBannerListener.highlightRecitedWord(_:)` is deliberately **not** the same method as
`WordPointerListener.highlightWord(_:)`, even though `QuranInteractor` could satisfy both
with one implementation. Dragging the pointer drives its own popover and magnifier;
recitation must not. Keeping them separate means the drag feature is untouched by
construction.

---

## Colours

`pointedWord` and the ayah reading highlight are drawn into the same
`[WordFrame: Color]` dictionary, so the recited word paints **on top of** its own verse
highlight.

Originally both were `appIdentity` at `0.3` opacity — the same colour at the same
opacity — so the word was drawn correctly and was **completely invisible**. This is the
one real bug this feature hit, and it looked exactly like the follower being broken.

Now:

| Layer | Colour |
|---|---|
| Ayah being recited | `appIdentity` @ 0.30 (unchanged) |
| Word being recited | `systemOrange` @ 0.55 |
| Word under the drag pointer | `appIdentity` @ 0.30 (unchanged) |
| Popover background | charcoal `rgb(38,38,40)`, white label |

`ContentImageViewModel` picks the recited colour only when the word's verse is in
`highlights.readingVerses`, so **dragging keeps the original lighter colour**.

The popover background is applied *after* `show(...)`, because `PopoverView` sets its own
style background during show. The library only offers white or a fixed teal, so the
charcoal is an override.

---

## The data

### Schema

```sql
CREATE TABLE word_segments(sura int, ayah int, position int,
                           start_ms int, end_ms int,
                           primary key(sura, ayah, position, start_ms));
```

`start_ms` and `end_ms` are **already in the app's own audio timeline** — no conversion
at runtime. `position` is the mushaf glyph position, which is what `Word.wordNumber` is.

### Where it came from

quran.com's API exposes word segments for recitation id 6 (Al-Husary Murattal):

```
https://api.quran.com/api/qdc/audio/reciters/6/audio_files?chapter=N&segments=true
```

That API describes a **different encode** of the same recitation from the one the app
plays — re-trimmed and re-encoded, roughly 0.99× the length. So the generator anchors
every ayah to the app's own start/end times from `husary.db` and linearly rescales the
segments inside it. Ayah boundaries land exactly, and the sub-1% scale error over a
3–10 s ayah is well under one word.

The `husary.db` this was built against is byte-identical to the one the app downloads
from `files.quran.app`, so there is no version skew at runtime.

**Word index → glyph position:** the API counts real words; the mushaf also counts waqf
marks and the ayah-end marker. The rule is *API word N maps to the Nth glyph position
whose `words.db` translation is non-NULL*. This was verified exact on 856 of 857 ayahs.

### Regenerating it

The generator lives **outside this repo**, in the research workspace:

```
prep/build_word_segments.py
```

It needs a `User-Agent` header — the quran.com API returns 403 without one.

---

## Coverage and known gaps

**8,627 segments across 39 suras: 1, 2 and 78–114.** The bound is the bundled `words.db`,
which only carries those suras. Word *translations* have the same bound, so the popover
covers exactly the same range.

Gaps inside that range, all of which degrade to "no highlight":

- **2:181** is absent entirely. The mushaf splits `بَعْدَ مَا` across two glyph positions,
  so `words.db` counts 14 words against quran.com's 13. It is the only such case in the
  dataset.
- **2:245** has no span for word 1.
- **2:249** has no spans for words 25–27.

### Timing accuracy

Measured against the decoded mp3s the app actually plays:

- **Words 2..n are essentially exact** — median error under 10 ms, and only 1 of 184
  mid-ayah words is off by more than 250 ms.
- **Word 1 of each ayah lights up 170–650 ms early.** This is not a rescaling error:
  upstream, word 1's span begins at the *ayah boundary*, so it covers the pause before
  the ayah. quran.com behaves the same way.

> Do not "fix" word 1 with a global offset. Shifting every span would push the other
> 8,000+ words — currently accurate to a few milliseconds — that much late. Clamp only
> the first span of each ayah if it matters.

Sura 1 has a further quirk: its first word starts at **5,664 ms**, because the mp3 opens
with a lead-in. Nothing highlights for the first ~5.6 seconds, which is correct.

---

## Adding another reciter

1. Generate segments for that reciter, rescaled against **its** timing DB, and append
   them to the table (or ship a second DB).
2. Relax the gate in `RecitationWordFollower.supports(_:)`, which currently matches
   `.gapless(databaseName: "husary")` exactly.
3. Coverage stays bounded by `words.db` until that ships more suras.

## Package dependencies added

- `AudioBannerFeature` → `AudioTimingPersistence`, `QuranResources`
- `QuranViewFeature` → `WordTextService`, `Popover_OC`

## Build hygiene

A no-sync build **rewrites `Package.resolved`**, stripping the `QURAN_SYNC`-only
dependencies. Run `git checkout Package.resolved` before committing.
