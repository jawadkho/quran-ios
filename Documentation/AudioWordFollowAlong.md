# Audio Word Follow-Along

While a reciter plays, the word highlight tracks the exact word being recited, and that
word's translation appears in a popover above it.

Word timings are read from the **reciter's own timing database**, the one the app already
downloads. A reciter whose database carries no word segments is a silent no-op, and
playback behaves exactly as it did before this feature. No reciter is named in the code.

> **Status:** no published reciter database carries the table yet, so the feature is dark
> until one does. See [What is needed](#what-is-needed).

---

## Using it

Five things must all be true, and four of them are already the defaults:

1. **Reading is `hafs_1405`.** This is the default. It is the only reading with word
   frames, so it is the only one where an individual word can be drawn.
2. **Arabic mushaf mode**, not translation mode. Only the image page draws single words.
3. **Word pointer is on** in the ⋯ (More) menu. This is the on/off switch for the whole
   feature — see [The toggle](#the-toggle).
4. **The selected reciter's timing database carries word segments.**
5. **The sura is covered by that data.** See [What is needed](#what-is-needed).

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
   `-- WordPointerViewController              -> the word's translation, in a popover
```

The popover lives in `WordPointerFeature` rather than in `QuranInteractor`, because that
feature already owns a `PopoverView` and the `WordTextService` lookup behind it. Following
the reciter reuses both instead of standing up a second copy, which is why
`QuranViewFeature` needs neither `Popover_OC` nor `WordTextService` as a dependency.

### The files

| File | Role |
|---|---|
| `Data/AudioTimingPersistence/Sources/GRDBWordSegmentPersistence.swift` | `WordSegment` and `WordSegmentPersistence.timeline(forSura:)`. |
| `Data/AudioTimingPersistence/Sources/WordSegmentTimeline.swift` | One sura's spans, and the playhead lookup over them. |
| `Domain/QuranAudioKit/.../QuranAudioPlayer.swift` | `currentFileTime`, the playhead inside the current sura file. |
| `Features/AudioBannerFeature/Sources/RecitationWordFollower.swift` | The follower itself. |
| `Features/AudioBannerFeature/Sources/AudioBannerViewModel.swift` | `AudioBannerListener.highlightRecitedWord(_:)`, lifecycle wiring. |
| `Features/QuranViewFeature/Sources/QuranInteractor.swift` | The toggle gate, and the hand-off to the word pointer. |
| `Features/WordPointerFeature/Sources/WordPointerViewController.swift` | `showRecitedWord(_:rect:)`, the popover itself. |
| `Model/QuranAnnotations/Sources/QuranHighlights.swift` | `recitedWord`, the highlight slot the drag pointer does not share. |
| `Features/QuranPagesFeature/Sources/PageGeometryActions.swift` | `wordRect`, the inverse of `word`. |
| `Features/QuranImageFeature/Sources/ContentImageViewModel.swift` | `globalRectForWord`, and drawing both word highlights. |
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

`AudioBannerViewModel` asks the listener's `followsRecitedWord` before it starts the
follower at all, so a reader with the switch off pays nothing — no polling, no database
read. `QuranInteractor.highlightRecitedWord(_:)` also returns early, for the case where
the switch goes off while an emission is already in flight. Turning it off mid-recitation
clears the highlight and popover directly, because that early return would otherwise
swallow the clear.

**Side effect worth knowing:** the same switch also shows the draggable pointer arrow.
If follow-along should hide the arrow during playback, that is a deliberate change to
`onIsWordPointerActiveUpdated` / `showWordPointer`, not something you get for free.

### Why the audio path has its own listener method

`AudioBannerListener.highlightRecitedWord(_:)` is deliberately **not** the same method as
`WordPointerListener.highlightWord(_:)`, and — more importantly — the two write to
**different fields**: `QuranHighlights.recitedWord` and `QuranHighlights.pointedWord`.

Separate methods alone would not have been enough. An earlier revision had both paths end
at `highlightWord(_:)`, so they shared one slot: dragging during playback made the tint
jump away from the arrow, and stopping playback wiped the reader's own selection. Separate
state is what actually keeps the drag feature untouched.

Both protocol methods have default no-op implementations, so adding them does not break
conformances outside this package.

---

## Colours

`recitedWord`, `pointedWord` and the ayah reading highlight are drawn into the same
`[WordFrame: Color]` dictionary, so the recited word paints **on top of** its own verse
highlight. The recited word is written last, so it wins the rare frame where the reader
has dragged the pointer onto the word being recited.

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

The colour follows from *which field* holds the word, not from guessing whether its verse
is being recited, so **dragging always keeps the lighter colour**.

The popover background is applied *after* `show(...)`, because `PopoverView` sets its own
style background during show. The library only offers white or a fixed teal, so the
charcoal is an override.

---

## The data

### Where the segments live

Word segments live **in the reciter's own timing database** — the file the app already
downloads and unzips for every gapless reciter (`husary.db`, and so on, from
`files.quran.app`). Nothing is bundled into the app.

That choice follows from what the alternative costs. Shipping a separate
`husary_word_segments.db` in `QuranResources` put **471 KB into every install**,
including the majority of readers who never select Al-Husary, and hardcoded one
reciter's name into the feature. Reading from the reciter database instead means:

- no app-size cost, for anyone;
- any gapless reciter gains follow-along the moment its database carries the table —
  **no code change**;
- the data version can never skew from the audio it describes, because they are the
  same download.

The cost is that the feature is **inert until the server ships an updated database**.
`WordSegmentPersistence` checks for the table and treats its absence as "no timings",
so today every reciter is silently a no-op. See [What is needed](#what-is-needed).

### Schema

The app expects exactly this table inside the reciter database:

```sql
CREATE TABLE word_segments(sura int, ayah int, position int,
                           start_ms int, end_ms int,
                           primary key(sura, ayah, position, start_ms));
CREATE INDEX seg_idx on word_segments(sura, ayah);
```

`start_ms` and `end_ms` are **already in the app's own audio timeline** — no conversion
at runtime — and are treated as half-open, so a word ends exactly where the next starts.
`position` is the mushaf glyph position, which is what `Word.wordNumber` is.

The primary key includes `start_ms` on purpose: a reciter who repeats or elongates a
passage produces **several spans for one word**, which is why lookup is by time range
rather than by position. Spans must not overlap; the binary search assumes it.

### Where it comes from

quran.com's API exposes word segments for recitation id 6 (Al-Husary Murattal):

```
https://api.quran.com/api/qdc/audio/reciters/6/audio_files?chapter=N&segments=true
```

It needs a `User-Agent` header — the API returns 403 without one.

That API describes a **different encode** of the same recitation from the one the app
plays — re-trimmed and re-encoded, roughly 0.99× the length. So the generator anchors
every ayah to the app's own start/end times from the reciter database's `timings` table
and linearly rescales the segments inside it. Ayah boundaries land exactly, and the
sub-1% scale error over a 3–10 s ayah is well under one word.

**Word index → glyph position:** the API counts real words; the mushaf also counts waqf
marks and the ayah-end marker. The rule is *API word N maps to the Nth glyph position
whose `words.db` translation is non-NULL*. This was verified exact on 856 of 857 ayahs.

---

## What is needed

### Coverage is not limited by the audio data

The prototype covered **39 suras (1, 2, 78–114)**, and that was widely assumed to be a
data limit. It is not. Two separate things caused it:

1. **The generator's default sura list was hardcoded** to `[1, 2] + range(78, 115)`.
2. **The `words.db` used to build it covers only those 39 suras** — it is the sample
   database bundled with the Example app, not the one the real app ships.

Checked directly against the sources:

| Source | Coverage | Limits us? |
|---|---|---|
| quran.com segments API | all 114 suras (sura 36 returns 83/83 ayahs, 735 segments) | no |
| `husary.db` ayah timings | all 114 suras | no |
| Example app's `words.db` | 39 suras | **yes** |

So **full-Quran coverage needs a `words.db` covering all 114 suras**, and nothing else.
`words.db` is supplied by the host app through `AppDependencies.wordsDatabase`; the
engine never downloads it. The production Quran.com app supplies its own, so this may
already be solved outside this repo — that is the question to put to the team.

I checked whether the API could replace `words.db` for the glyph mapping. **It cannot.**
The QDC verses endpoint exposes `position` and `char_type_name`, but `char_type_name` is
only `word` or `end` — it does not model waqf marks, which the mushaf gives their own
glyph positions. For sura 2 the API and the mushaf agree on the word *count* but differ
on the *positions* in 212 of 286 ayahs, so the API cannot tell you where the gaps fall.

### The process, end to end

1. Get a `words.db` covering the suras you want (the only real blocker).
2. Copy the reciter database — never edit the downloaded one in place.
3. Run the generator, which writes `word_segments` into that copy:

```bash
cp husary.db husary-with-segments.db
python3 prep/build_word_segments.py words.db husary-with-segments.db
```

   With no sura list it attempts all 114 and reports which it could not do and why.
4. Sanity-check the result before shipping:

```sql
-- must all return 0
select count(*) from word_segments where end_ms <= start_ms;
select count(*) from word_segments a join word_segments b
  on a.sura = b.sura and a.rowid <> b.rowid
 and b.start_ms < a.end_ms and b.start_ms > a.start_ms;   -- overlaps
```

5. Zip it and publish it where the app already fetches reciter databases.

**How hard is it?** The generator is ~150 lines and already written; a full run is a few
minutes of API calls. The engineering is done. The open item is entirely about **which
`words.db` to build against, and who publishes the updated reciter database** — a data
and release question, not a code one.

### Trying it locally

The feature is dark until an updated reciter database ships. To demo it, run the
generator against the `husary.db` the simulator has already downloaded and drop the
result back in place.

---

## Known gaps

Gaps within the generated range, all of which degrade to "no highlight":

- **2:181** is absent entirely. The mushaf splits `بَعْدَ مَا` across two glyph positions,
  so `words.db` counts 14 words against quran.com's 13. It is the only such case.
- **2:245** has no span for word 1.
- **2:249** has no spans for words 25–27.

A sura with no segments at all is the *normal* case, not an error: the follower loads an
empty timeline, logs it, and stops polling until the next sura.

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

There is nothing to change in the app. Generate segments for that reciter, rescaled
against **its** timing database, and publish the database with the `word_segments` table
in it. The follower reads whatever the selected reciter's database offers.

---

## Tests

| Target | Covers |
|---|---|
| `AudioTimingPersistenceTests` | `WordSegmentTimeline` lookup — boundaries, gaps, repeated words, unordered input — and `WordSegmentPersistence` against fixture DBs, including an uncovered sura and a reciter database with no `word_segments` table at all. |
| `AudioBannerFeatureTests` | `RecitationWordFollower` — gapped/gapless reciters, a reciter database without segments, advancing through words, emitting each word once, holding the highlight through silence, and stop/pause/resume. |

Both use small real SQLite fixtures under `Tests/Resources/` rather than doubles,
following `LinePagePersistenceTests`. The fixtures are duplicated across the two test
targets because the layer rules in `Package.swift` forbid a `Data` target's tests from
depending on `Domain/TestResources`.

The follower tests drive `tick()` directly and pause the poll loop, so no assertion
depends on wall-clock timing. That leaves the poll loop's own scheduling uncovered; it is
three lines around `Task.sleep`, and covering it would mean either sleeping in tests or
injecting a clock.

Two paths are deliberately not covered, because reaching them needs more scaffolding than
the behaviour is worth: the toggle gate in `QuranInteractor` (its `Deps` struct wants a
dozen builders) and the background/foreground pause in `AudioBannerViewModel`. Both are a
single conditional over state that is itself tested.

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
make test-no-sync TARGET=AudioTimingPersistence
make test-no-sync TARGET=AudioBannerFeature
```

## Package dependencies added

- `AudioBannerFeature` → `AudioTimingPersistence`, `QuranAudio`
- `WordPointerFeature` → `QuranKit` (explicit; it was already there transitively)

`QuranViewFeature` **lost** `Popover_OC` and `WordTextService`, because the popover moved
to the feature that already owned one.

`AudioTimingPersistence` and `AudioBannerFeature` gained test targets, so both are now
listed in `QuranEngine-Package.xctestplan`.

## Build hygiene

A no-sync build **rewrites `Package.resolved`**, stripping the `QURAN_SYNC`-only
dependencies. Run `git checkout Package.resolved` before committing.
