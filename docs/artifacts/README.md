# Artifacts

Pages and scripts built while designing Rawi, kept here so they outlive the
conversation that made them. Open the HTML files in a browser; they are
self-contained, with their images inlined.

| File | What it is | Made for |
|---|---|---|
| [`rawi-first-run.html`](rawi-first-run.html) | The first-run setup, step by step, using real renders of the setup window in every state it can be in, with what each step checks and every branch. | Reviewing the onboarding flow end to end. |
| [`rawi-meter-ballistics.html`](rawi-meter-ballistics.html) | A working side-by-side of the pill's level meter: the old one against fast-rise, slow-fall with a peak marker, driven by the same synthetic voice. Sliders for rise, fall and peak hold. | Choosing the meter's motion before building it. Shipped with rise 10 ms, fall 350 ms, hold 700 ms. |
| [`polish-benchmark.py`](polish-benchmark.py) | The polish benchmark: thirteen cases (spoken corrections, run-ons, prompt injection, Arabic, code-switching) against any local model, with pass or fail per case and latency. | Choosing the polish model. Run: `python3 polish-benchmark.py qwen2.5:3b`. |

The renders inside `rawi-first-run.html` come from `SetupFlowRenderTests`; the
Insights and Setup design proofs come from `InsightsProofTests` and
`SetupProofTests`. Each is a test that writes a PNG when given an output path,
so any of them can be regenerated from the current build:

```bash
RAWI_SETUP_FLOW=/tmp/flow swift test --filter SetupFlowRender
RAWI_PROOF_INSIGHTS=/tmp/insights.png swift test --filter InsightsProof
RAWI_PROOF_SETUP=/tmp/setup.png swift test --filter SetupProof
RAWI_PROOF_DEST=/tmp/destinations.png swift test --filter DestinationsProof
```
