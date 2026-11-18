# Arabic and mixed-speech evaluation

Synthetic speech (macOS `say`, voices Majed and Samantha) through Groq, scored by
character error rate against the sentence that was spoken. Run from this folder:

    python3 build.py                      # makes audio/*.wav
    python3 compare_transcription.py      # before and after the mixed-speech policy
    python3 compare_polish.py             # polish checks on 23 Arabic and mixed dictations

Needs `GROQ_API_KEY` in `~/.config/rawi/.env`. Each run spends real Groq quota.
Synthetic speech reads dialect in formal pronunciation, so treat dialect numbers as
a floor for regressions, not a measure of how real people sound.
