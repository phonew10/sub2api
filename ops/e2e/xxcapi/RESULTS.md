# xxcapi.top gpt-image-2 test — 2026-09-09

Relay: https://xxcapi.top  (key in ops/.env as XXCAPI_KEY). Re-run with ./ops/e2e/xxcapi/run.sh gen|edit|mask.
Samples (jpeg-compressed copies of the PNG results) are in samples/; full-size PNGs were kept out of git.
Source image: https://m.media-amazon.com/images/I/71dl4X30QOL.jpg (original.jpg, 1400x1400)
Requested on every call: size=2048x2048, output_format=jpeg, output_compression=80

| Test | Model | Result | Time | File |
| --- | --- | --- | --- | --- |
| generate (reverse prompt) | gpt-image-2-medium | 200, PNG 2048x2048 via URL, 5.4 MB | 78 s | gen_medium.png |
| edit (beige wall + oak table) | gpt-image-2-medium | 200, PNG 2048x2048 via URL, 4.5 MB | 58 s | edit_medium.png |
| generate | gpt-image-2-high | 500 get_channel_failed "no available channel in group default" x2, then 403 insufficient balance (¥0.045 left, ¥0.07 needed) | - | - |
| edit | gpt-image-2-high | 502 upstream temporarily unavailable, then 403 insufficient balance | - | - |
| generate | gpt-image-2 + quality=high | 500 get_channel_failed | - | - |
| edit | gpt-image-2 + quality=high | 503 "No available compatible accounts" | - | - |

Findings
- size=2048x2048 is honored (both outputs are exactly 2048x2048).
- output_format=jpeg and output_compression=80 are NOT honored: the relay returns a PNG
  hosted at loimg.code2alita.com via `url`, with no size/quality/output_format/usage
  metadata in the response. Convert to jpeg locally if needed.
- Response always uses `url` + `task_id` (new-api style), not b64_json, even without response_format.
- gpt-image-2-high and plain gpt-image-2 had no serving channel during the test window;
  only the -medium alias worked. Retry later or ask the relay operator.
- Balance after two 2K medium images: ¥0.045. Billing usage endpoint reports total_usage 15.5.
- Quality of the medium outputs is good: generation reproduces the infographic layout,
  text and six-layer diagram faithfully; edit keeps product/text and swaps background as asked.

Reverse prompt used: see reverse_prompt.txt
| generate, response_format=b64_json | gpt-image-2-medium (1024x1024) | 200, b64_json returned, but still PNG 1024x1024 (1.1 MB) — jpeg/compression ignored even with b64 | see gen_b64jpeg.png |

## Round 2 (after top-up)
| generate, size=1536x864 (non-preset) | gpt-image-2-medium | 200, PNG exactly 1536x864, 1.9 MB, 40 s | gen_wide.png |
| edit with mask (mask_wall.png, plant on wall) | gpt-image-2-medium | 403 insufficient_user_quota, balance ¥0 — top-up covered only the wide image | pending |

Exact 1536x864 output = arbitrary WIDTHxHEIGHT honored. Web ChatGPT/Codex paths cannot do that; this points to a real Images API (OpenAI or Azure) behind the relay, with the relay stripping output_format/compression and re-hosting as PNG.
| edit with mask (retry) | gpt-image-2-medium | first try 502 "Upstream request failed" after 76 s (not charged); retry 200, PNG 2048x2048, 54 s | edit_mask.png, edit_mask_diff.jpg |

Mask result: plant + shelf placed in the masked wall area; rest of the image preserved in content but the whole frame is re-rendered (mean pixel diff 9.8 outside mask vs 42.5 inside; 5.8% of outside pixels changed >40, mostly the shelf spilling ~120 px left of the mask edge, text/edges re-rasterised). Mask is honored as guidance, not as a hard pixel lock — same as OpenAI's own behaviour.

## Round 3 (2026-09-09 06:44 UTC): gpt-image-2-high retest
| generate | gpt-image-2-high | 500 get_channel_failed "no available channel in group default" (1.5 s, not charged) | - |
| edit | gpt-image-2-high | 503 "No available compatible accounts" (1.8 s, not charged) | - |
Same two errors as round 1, ~10 h later: the high tier has no backing channel on this relay. Model list still advertises it.

## Round 4 (2026-09-10): decisive mask probe — VERDICT: mask is IGNORED

The round-2 "mask honored" call was a false positive: its prompt said "on the wall", so the model
could place the plant without reading the mask. Correct design (`mask-probe.sh`): the hole sits on a
plain wall patch the prompt never mentions (1000,240)-(1360,420) of the 1400px original, and the prompt
only says "Fill the editable region with solid pure red. Change nothing else." Control = same prompt, no mask.

| Call | Red inside hole | Red outside hole | Where the red went |
| --- | --- | --- | --- |
| WITH mask (gpt-image-2-medium, 1024) | 0.0% | 4.85% | layer panel 1 painted red; hole untouched |
| NO mask (control) | 0.0% | 5.54% | same behaviour |

Masked and unmasked calls are indistinguishable, so the relay drops the `mask` part before it
reaches the model (a real OpenAI Images API call with this mask paints the hole). Agrees with the
other agent's measurement (1–2% of hole with mask vs 66% unmasked on their probe).
Re-run: `./ops/e2e/xxcapi/mask-probe.sh` (2 x 1K medium edits, ~¥0.09). Samples: samples/probe_mask.jpg,
samples/probe_nomask.jpg, samples/mask_probe_compare.jpg.

## Round 5 (2026-09-10): gpt-image-2.5-flare / gpt-image-2.5-sunburst — mask probe NOT possible, both aliases down
| Call | gpt-image-2.5-flare | gpt-image-2.5-sunburst |
| --- | --- | --- |
| edit + mask (probe) | 408 `openai_error / bad_response_status_code` after 209 s | 502 "Upstream request failed" after 204 s; retry 502 after 9 s |
| edit, no mask (control) | 408 same, 54 s | 502 same, 8 s and 19 s |
| generate 1024x1024 | 408 `adobe throttled: status 408 … {"error_code":"timeout_error","message":"system under load"}` (rate_limit_error), 25 s | 502 "Upstream request failed", 7 s |

Zero images produced in 8 calls, so no mask verdict for either alias. The flare error body leaks the
backend: "adobe throttled" + an Adobe-style `timeout_error` payload, i.e. the relay serves this alias
through an Adobe (Firefly) upstream that hosts OpenAI's GPT Image as a partner model, and that
upstream is overloaded. Sunburst's channel is simply failing. Re-run later with
`PROBE_OUT=ops/e2e/xxcapi/out/<name> ./ops/e2e/xxcapi/mask-probe.sh <alias> 1024x1024`.
