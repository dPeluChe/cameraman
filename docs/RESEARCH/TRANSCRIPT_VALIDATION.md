# Is the transcript real and credible? (2026-10-05)

Before building cut-by-transcript we measured what the on-device transcription (WhisperKit, model `base`, Apple M1 Max) actually delivers. Method, numbers, and what they mean for the feature.

## It is real

`TranscriptionEngine` runs WhisperKit (CoreML) through `WhisperKitTranscriber`; nothing is simulated (an old backlog note said it was). The first run downloads the model, so the first transcription is slow (about 58 s for 27 s of audio including the download; 5 s once cached).

## Method

1. **Known text, known timing.** `scripts/make-transcript-reference.py` builds a 27 s recording from six sentences read by the macOS `say` voice, separated by silences of known length, plus `truth.json` with where each sentence starts and ends. It is transcribed through the real `WhisperKitTranscriber`, and compared by word error rate (WER) and by timing.
2. **Real speech.** Two microphone recordings from the project library (12.6 s of Spanish narration, 10.4 s with no speech), reporting only aggregates.

## Results

| Check | Result |
|---|---|
| Word error rate on the reference | **3.0%** (2 of 66 words) |
| Sentence start vs truth | within **0.04 s** (6 of 6) |
| Sentence end vs truth | **0.10 to 0.22 s early** (6 of 6) |
| Pauses longer than 1 s | all three found, with correct lengths (2.70 s, 3.18 s, 1.28 s) |
| Real Spanish speech | language detected correctly, text coherent, mean word probability **0.76**, 5 of 24 words under 0.5 |
| Recording with no speech | **0 words** returned (no text invented over silence) |

**Word timing is precise enough to cut on**, and the per-word probability is a usable credibility signal: the doubtful words are the ones with low probability.

## What it does not do: fillers

On the reference, Whisper wrote down **1 of 3** fillers. "and uh here's" came out as "and up here's", and "er" came out as "or"; the one it kept ("um") was fused to the next word ("um-new") with probability 0.17. Whisper tends to normalise hesitations away.

- We tried the usual fix, conditioning the decoder with a disfluent prompt (`promptTokens`, English and Spanish). It made **no difference in any of 6 runs**, so it was not shipped.
- The reference cannot settle this: a synthetic voice reads "uh" as a clean word, not a natural hesitation. Only real speech with real fillers can, and the two real recordings available had none.

## Consequences for the feature

- **Cutting chosen words and trimming long pauses are reliable** (precise times, pauses measured from word gaps).
- **Filler-word removal from the text alone will miss fillers Whisper does not write.** Present it as "fillers the transcript contains", never as "all fillers", and let the user review every cut.
- Show low-probability words as uncertain in the transcript view, so a wrong word is visible before it is cut around.
- The two ways to find fillers Whisper skips (acoustic detection of short non-speech bursts, or a larger model) are untested.

## Limits of this check

One model (`base`), one synthetic voice, about 50 s of audio in total. A larger and more varied set (other voices, noise, a second language, a long recording) is still needed before claiming accuracy in general.
