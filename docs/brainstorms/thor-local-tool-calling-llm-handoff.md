# Handoff: Local tool-calling LLM for AYN Thor emulator frontend

## User context

The user is investigating which local LLM with tool-calling can run directly on an **AYN Thor 16GB model** running **NixOS**. The intended application is **not active coding**; it is a **custom emulator frontend** where the model acts as an intent/router layer for user-facing actions.

The user passed this focus/path for the next session:

- `../rocknix-nix-guest/docs/brainstorms/`

Use that as the likely place to look for or create brainstorm/spec notes in the adjacent `rocknix-nix-guest` project, if continuing the design discussion.

## Conversation summary

We searched online for AYN Thor specs and local tool-calling model options.

Confirmed from web results:

- AYN Thor Lite: Snapdragon 865, 8GB RAM.
- AYN Thor Base/Pro/Max: Snapdragon 8 Gen 2, up to 16GB RAM.
- User clarified they have the **16GB model**, so recommendations should assume Snapdragon 8 Gen 2 + 16GB RAM.

For the emulator-frontend use case, the best current recommendation is:

1. **Qwen3 4B / Qwen3 4B Instruct** as the default candidate.
   - Good balance of local responsiveness and tool/intent quality.
   - Better fit for frontend natural-language routing than code-specialized models.
2. **Phi-4-mini 3.8B** as the strongest comparison/fallback.
   - Official function-calling support; likely cleaner tool-call behavior.
3. **Llama 3.2 3B Instruct** as the fast/simple option.
4. **Qwen2.5 7B Instruct** only if higher reasoning quality is needed and latency is acceptable.
   - Avoid coder models unless the frontend will generate scripts/config.

Recommended runtime direction:

- Prefer **llama.cpp `llama-server`** over Ollama for an appliance/frontend integration because it is easier to embed/control, has a smaller dependency surface, has OpenAI-compatible APIs, and is Nix-friendly.
- Suggested starting config:
  - Quant: `Q4_K_M`
  - Context: `4096–8192`
  - Temperature: `0.1–0.3`
  - Bind to localhost only.

Example command shape discussed:

```sh
llama-server \
  -m /var/lib/models/qwen3-4b-instruct-q4_k_m.gguf \
  --jinja \
  -c 4096 \
  -t 8 \
  --host 127.0.0.1 \
  --port 8080
```

Important architectural point:

- The LLM should only emit tool calls. The emulator frontend still needs a small local agent/wrapper to validate and execute allowed tools, then feed results back to the model.

Example tool surface for the frontend:

- `launch_game(system, rom_path, core)`
- `search_library(query, filters)`
- `get_game_metadata(game_id)`
- `set_frontend_setting(key, value)`
- `open_collection(name)`
- `explain_controls(system)`
- `resume_last_game()`

Recommended validation approach:

- Run a bake-off of Qwen3 4B, Phi-4-mini 3.8B, and Llama 3.2 3B against 30–50 real frontend commands.
- Choose based on clean valid tool calls and latency, not chat quality.

Follow-up: image recognition / vision support:

- User asked about image recognition for the same Thor/NixOS/emulator-frontend context.
- Recommendation: treat image recognition as a **separate perception module**, not as the same model that does tool-calling.
- Best default local vision candidate: **Qwen2.5-VL 3B** / `qwen2.5vl:3b`.
  - Good edge-AI fit.
  - Handles screenshots, OCR-like tasks, visual Q&A, localization/bounding boxes, and structured JSON reasonably well.
  - Small enough for Thor 16GB.
- Secondary candidate: **Gemma 3 4B** / `gemma3:4b`.
  - Good general image understanding; test JSON/tool-adjacent reliability.
- Heavier candidate: **Qwen2.5-VL 7B** only if 3B misses too much and latency is acceptable.
- Avoid relying on native vision-model tool-calling. Vision+tools support is inconsistent; safer pattern is:

```text
screenshot / box art / camera image
        ↓
Qwen2.5-VL 3B
        ↓
structured observation JSON
        ↓
Qwen3 4B or Phi-4-mini tool router
        ↓
validated frontend action/tool call
```

Example structured vision output:

```json
{
  "screen_type": "emulator_pause_menu",
  "visible_text": ["Resume", "Restart", "Save State", "Load State"],
  "game_guess": "Chrono Trigger",
  "confidence": 0.82,
  "suggested_intent": "resume_game"
}
```

Potential emulator-frontend vision use cases:

- Recognize box art / screenshots: use CLIP/SigLIP embeddings first, VLM fallback.
- Read visible menu text: OCR or Qwen2.5-VL.
- Understand current screen: screenshot → Qwen2.5-VL → structured observation.
- Identify a game from box art/screenshot: image embedding search + metadata lookup.
- Explain controls or next action from screen state: VLM observation → text/tool router.

Vision-model bake-off additions:

- Test `qwen2.5vl:3b`, `gemma3:4b`, and optionally `qwen2.5vl:7b`.
- Score on structured JSON validity, OCR/menu-text accuracy, screen-state classification, image-to-game identification, and latency.

## Current repo/project state

Current working directory during this session was:

- `/home/simonwjackson/code/sandbox/rocknix`

Auto-context showed untracked local markdown artifacts in this repo:

- `base-architecture-minimum.md`
- `base-safety-review.md`
- `base-scout-packages.md`
- `base-scout-sm8550.md`
- `rebase-plan-learnings.md`
- `rebase-plan-repo-research.md`

The handoff file was moved into the adjacent repo at:

- `../rocknix-nix-guest/docs/brainstorms/thor-local-tool-calling-llm-handoff.md`

## Suggested next-session skills

Use these if continuing beyond a quick answer:

- `se-brainstorm`: if turning the model/runtime idea into requirements for the emulator frontend.
- `se-agent-native-architecture`: if designing the local tool-calling wrapper/agent loop as a first-class feature.
- `se-plan`: if producing an implementation plan for NixOS service packaging + frontend integration.
- `web-search`: if checking latest model/runtime support or exact llama.cpp/Ollama flags.
- `se-architecture-improvement`: if reviewing how this should fit into the existing ROCKNIX / nix guest architecture.

## Likely next steps

1. Inspect `../rocknix-nix-guest/docs/brainstorms/` for existing brainstorm notes before creating new artifacts.
2. Decide whether the output should be a brainstorm doc, requirements doc, or implementation plan.
3. If designing implementation, define:
   - NixOS service for `llama-server`.
   - Model storage/update path.
   - Local HTTP API contract between frontend and model runner.
   - Tool schema and strict validation layer.
   - Safety boundaries: whitelisted tools only, no shell/code execution by default.
   - Latency target and model bake-off script.
