# Timeline review (engine and UI), 2026-10-05

Two independent read-through reviews, because the timeline and element handling is a core strength and has to be trustworthy. One covered the **engine and model** (clip math, ripple, undo, composition); one covered the **UI, interaction and performance**. "Test" = confirmed with a throwaway probe test; "Read" = confirmed by reading the code only; "Reasoned" = needs a runtime check. Paths are relative to `EngineKit/Sources/EngineKit/` or `App/Sources/Cameraman/`.

Status column: **fixed** (with PR), **open**.

## Engine and model

| # | Severity | Finding | Verified | Status |
|---|---|---|---|---|
| E1 | Data loss | Writing `timeline.segments` (zoom, speed, volume, mute, camera edits) rebuilds every primary-track clip via `fromSegment`, dropping `adjustments`, `opacity` and `position` (`Project+Timeline.swift:122-135`, `Project+TimelineTrack.swift:300-315`) | Test | open |
| E2 | Data loss | Split at playhead uses the old `split(segmentId:)`: drops adjustments/opacity/position and gives both halves new ids (`EditorModel+SegmentOps.swift:101-129`). `splitClip` already slices correctly | Test | open |
| E3 | Wrong output | The primary track is laid end to end from a running time and **ignores clip start times** (`CompositionBuilder.swift:285-380`), while overlays, subtitles, adjustments, volume ramps and other tracks use absolute times. Gaps (MCP `delete_clip` leaves one) collapse | Read | open |
| E4 | Wrong output | Speed change skips the engine (`ProjectEditor+Extensions.swift:334`): nothing ripples, duration not recalculated | Test | open |
| E5 | Stale timing | Ripple edits (`deleteRange`, `delete`, `trimIn`, `trimOut`) do not move or clip **overlays, subtitles, chapters, zoom keyframes, legacy mediaItems**, and `delete/trim` shift only the primary track | Test | open |
| E6 | Data loss | Undo and redo never schedule autosave; neither do chapters, segment zoom, media items, or canvas changes other than camera position | Read | open |
| E7 | Wrong output | Image and color clips render differently in preview and export; any static clip sends the whole export down the static path and drops the camera | Read | open |
| E8 | Wrong output | After a merge, recording audio always comes from `primarySources`, so project B plays project A's audio (`CompositionBuilder.swift:132,143`) | Read | open |
| E9 | Wrong output | Overlapping clips are accepted on one track (`EditorModel.swift:161-306`) | Test | open |
| E10 | Broken edits | The segment inspector allows volume 0...3 through `mutateSegment` (no validation); later trims then fail validation (volume must be 0...1) | Test | open |
| E11 | Wrong output | Trims and speed changes do not adjust effect windows | Test (speed), Read (trim) | open |
| E12 | Wrong output | Source ranges are not checked against the media length | Test | open |
| E13 | Wrong output | A missing screen source desyncs the tracks | Read | open |
| E14 | Minor | Undo gaps: gradient preset clears history; zoom keyframe drag records no snapshot; extension ops skip the agent-freeze guard | Read | open |
| E15 | Minor | `deleteRange` leaves emptied tracks behind; locked-track clips do not shift | Test | open |
| E16 | Minor | Float seams after many splits (about 2e-16) | Test | open |
| E17 | Data loss | Merge drops subtitles, subtitle style, manual zoom keyframes, synthetic cursor (`ProjectStore+Merge.swift:91-104`); originals untouched | Read | open |

Not covered by any test: `CompositionBuilder`, the `segments` setter, timed items under ripple edits, and "undo results get saved".

## UI, interaction, performance

| # | Severity | Finding | Verified | Status |
|---|---|---|---|---|
| U1 | Wrong behaviour | Trim, change speed or move a screen segment and the preview keeps playing the old cut: a full rebuild happens only when the primary clip **count**, canvas format or non-primary tracks change (`PreviewEngine.swift:276-300`) | Read | open |
| U2 | Wrong behaviour | After split, delete, import or B-roll move the playhead jumps to 0:00 and playback stops while the button still shows "pause" (the app drives AVPlayer directly; the engine's own time stays 0) | Read | open |
| U3 | Data loss | Rename, tag or an agent finishing reloads the editor: cancels the pending autosave without saving, wipes undo, resets track volumes and overlay toggles, and likely leaves the preview on "unavailable" (the `isLoading` guard never blocks) | Read | partly fixed in the agent-freeze work |
| U4 | Data loss | Media item, segment zoom and chapter edits are never autosaved (same cause as E6) | Read | open |
| U5 | Wrong behaviour | Screen/camera/audio/video rows sit 6pt right of the ruler and playhead (`TimelineTrackRow.swift:64-66`); at fit zoom on a 30-min recording that is about 13 s | Read | open |
| U6 | Wrong behaviour | With a B-roll clip selected, Cmd+B splits the screen segment under the playhead, not the selected clip | Read | open |
| U7 | Wrong behaviour | Selecting a segment then a B-roll clip then Delete deletes the **segment**; a selected video clip cannot be deleted from the keyboard | Read | open |
| U8 | Wrong behaviour | Segment trim shows nothing while dragging and can only shrink; cannot be dragged back out | Read | open |
| U9 | Wrong behaviour | Thumbnails and waveforms never appear (relative path not joined to the project directory, errors swallowed); and are keyed by source time but looked up by timeline time | Read | open |
| U10 | Jank | Every 50 ms playback tick re-runs `CenterPanel` and the whole `TimelineView` (tracks, overlay rows, chips) | Read | open |
| U11 | Jank | A 1-hour project at max zoom is 864,000 pt wide with nothing lazy (about 18,000 ruler ticks, about 25,000 thumbnail cells) | Reasoned | open |
| U12 | Minor | Ruler labels drop at 1 s and 2 s spacing (`time += 0.2` drifts; 479 of 600 labels dropped in simulation); no hours | Simulated | open |
| U13 | Wrong behaviour | Audio Reset fires two Tasks from the same old project; a volume slider records one undo step per tick, which can push 50 real edits out of history | Read | open |
| U14 | Undo loss | Applying zoom suggestions clears the undo stack, is not autosaved, ignores freeze | Read | open |
| U15 | Wrong behaviour | Manual zoom keyframe drag records no undo snapshot | Read | open |
| U16 | Wrong behaviour | Only `performEdit`, undo and redo check the agent freeze; overlay nudges and segment/media/subtitle/keyframe edits mutate while frozen | Read | open |
| U17 | Wrong behaviour (likely) | Moving or trimming a B-roll clip probably also scrubs the playhead; subtitle trim handles probably lose to the chip's drag | Reasoned | open |
| U18 | Minor | Delete and Cmd+Z are button shortcuts that may fire while typing in an inspector field; no nudge, frame step, J/K/L, Home/End, zoom shortcuts; range selection is drawn but unused | Read | open |
| U19 | Minor | Rejected edits fail silently (20 `_ = await` call sites); Finder file drops onto the timeline do nothing | Read | open |
| U20 | Minor | Timeline height ignores the inspector bars; no VoiceOver labels on chips, playhead, ruler or handles; chip flashes back before the async edit lands | Read | open |

**First things a user hits:** play after trim/split shows the old cut or jumps to 0:00 (U1, U2); clicking a clip's start seeks inside it (U5); segment trim shows nothing and cannot be undone by dragging (U8); no follow-playhead while zoomed; Cmd+B and Delete act on the wrong item (U6, U7); thumbnails and waveforms do not show (U9).

## What is solid

Clip validation (finite times, speed > 0, ranges) with rejected input leaving the project unchanged; locked tracks enforced; `splitClip` and `deleteRange` slice effects and shift every unlocked track consistently; overlay validation; `TimelineLayout` time-to-x conversion and clip snapping; video-clip trim respecting speed and real duration; the live re-read of the selected video clip; preview refresh dedup and debounce; overlay drag throttled to 30 fps with one commit.

## Order of work

1. Data loss and wrong output in the engine: E1, E2, E6/U4, E5 (E5 also decides whether subtitles and captions survive cut-by-transcript), E4, E10.
2. Preview and playback correctness: U1, U2, U3.
3. Selection and keyboard: U6, U7, U8, U5.
4. Composition: E3, E7, E8, E9, E12, E13.
5. Performance and polish: U10, U11, U12, U9.
