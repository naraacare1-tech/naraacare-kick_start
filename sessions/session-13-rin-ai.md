# Session 13 — Rin AI (STAR)

## Goal and scope
Deliver Rin AI: the STAR-only health chat assistant with suggested prompts, streaming replies, meal/drink logging by chat with confirmation (Add to Avatar / Edit / Not Now), conversation search, delete chat, memory summaries the user can clear, help + disclaimer, daily token allowance with usage %, guardrails and evaluation. Also finalise AI metering for the drink estimator (S09) and voice-parse fallback (S08).

**In:** `ai` schema, `/rin/*`, Claude integration, metering, guardrails, eval harness, mobile `features/rin_ai`.
**Out:** report AI insights (S14 uses the same client and metering).

## Prerequisites
S05, S08, S09, S11. **Blocking decision: OQ-37** (vendor/model, data scope, allowance, cross-border transfer approval) and `ai_processing` consent (S05). Anthropic organisation with separate staging/prod workspaces and spend limits.

## Model and API choices (default; confirm in OQ-37)
- **Claude API (first-party)**, Python SDK `anthropic` 2.3.0, model **`claude-opus-5-5`** (configurable via `RIN_MODEL`).
- `thinking` omitted (adaptive is the default on this model; it cannot be disabled). `output_config.effort = "low"` for chat (cost/latency), `"medium"` for meal parsing if evals show a quality gain.
- **Streaming** for chat (`client.messages.stream(...)`), relayed to the app via SSE.
- **Server-side refusal fallback** enabled by default (`betas=["server-side-fallback-2026-07-01"]`, `fallbacks="default"`); every response is checked for `stop_reason == "refusal"` before reading content, with a friendly fallback message.
- **Prompt caching**: stable system prompt + tool definitions first with `cache_control`; user context (profile summary, 7-day aggregates, memory) after the breakpoint; verify `usage.cache_read_input_tokens` > 0 in staging.
- **Tools** (`strict: true`, `tool_choice: auto`): `propose_meal_log(items[{food_name, quantity, unit}])`, `propose_drink_log(drink, volume_ml)`, `get_today_summary()`, `get_week_summary()`. The server executes only read tools; propose-tools create `ai.pending_action` rows and never write logs directly.
- **Metering**: record `usage.input_tokens`, `output_tokens`, `cache_creation_input_tokens`, `cache_read_input_tokens` per call into `ai.usage_event`; the allowance counts input + output + cache-write tokens. Pre-check with `messages.count_tokens` only when the remaining allowance is low.
- Data handling: the Anthropic commercial API does not train on API data by default; retention per the org's configuration. `inference_geo` is available on the first-party API; document the transfer in the privacy notice.

## Files to create / modify

### naraacare-database
```
migrations/V0xx__ai_tables.sql   # conversation, message (P), memory_summary, pending_action, usage_event (P) + RLS + partition config
functions/R__20_ai.fn_conversations.sql fn_messages.sql fn_usage_today.sql fn_pending_action.sql
procedures/R__30_ai.pr_create_conversation.sql pr_append_message.sql pr_record_usage.sql pr_create_pending_action.sql pr_resolve_pending_action.sql pr_delete_conversation.sql pr_upsert_memory.sql pr_delete_memory.sql
tests/700_ai.sql
```

### naraacare-backend
```
app/integrations/anthropic_client.py     # single client; timeouts; typed error chain (RateLimitError → retry with backoff; APIStatusError; APIConnectionError)
app/domain/ai/prompting.py               # system prompt (frozen, versioned), context builder (own data only), memory summariser
app/domain/ai/tools.py                   # tool schemas (strict), server-side execution of read tools, proposal validation against food DB
app/domain/ai/guardrails.py              # pre-filter (emergency keywords → fixed safe response with 112/108/14416), post-filter (no HTML/markup → SafeChatMessage validation of model output; strip disallowed formatting to plain text)
app/domain/ai/metering.py                # allowance check (Redis counter + DB truth), usage %, reset at local midnight
app/domain/ai/titles.py                  # conversation title generation (short, encrypted)
app/api/v1/routers/rin.py  app/schemas/rin.py
app/domain/hydration/drink_estimator.py  (switch to shared client + metering)
app/domain/nutrition/voice_parser.py     (LLM fallback for unmatched phrases, STAR, metered)
tests/unit/domain/ai/test_guardrails.py test_context_builder.py test_metering.py
tests/integration/test_rin_flow.py (recorded responses)
tests/evals/rin_eval.yaml + run_eval.py  # 60+ cases: nutrition Q&A, meal logging accuracy, Hinglish, refusals, emergencies, prompt injection, cross-user exfiltration attempts
```

### naraacare-mobile
```
lib/features/rin_ai/presentation/screens/{rin_locked, rin_start, rin_conversation, rin_search, rin_help}.dart
lib/features/rin_ai/presentation/widgets/{suggested_prompt_chips, message_bubble (plain Text), action_card, usage_meter, delete_chat_dialog}.dart
lib/features/rin_ai/data/sse_client.dart
test/features/rin_ai/**
```

## Step-by-step tasks
1. Tables + RLS + partitions; encryption of titles/messages/memory.
2. Context builder: age band, sex, goals, today's targets and totals, 7-day averages, memory summary. Never other users' data, email, full name or exact DOB (OQ-37).
3. Chat endpoint: consent check (`ai_processing`), STAR check, allowance check → guardrail pre-filter → stream from Claude → post-filter each delta (plain text) → persist encrypted message + usage → SSE events `delta`, `action`, `done{usage_pct}`.
4. Meal logging: `propose_meal_log` → server maps names to food DB via alias search → `ai.pending_action` with structured items → app shows the action card (Calories/Protein/Carbs/Fat + "all values" link) → Add to Avatar (`/rin/actions/{id}/accept` → `pr_log_meal` with `source='rin'`, counts toward the meal limit) / Edit (opens the meal editor prefilled) / Not Now (dismiss). Expires after 24 h.
5. Search conversations (decrypt titles server-side for the user's last 500 conversations, match `SafeSearchQuery`), delete chat (dialog + toast), clear memory.
6. Usage meter: `GET /rin/usage`; at 100 % show "You've used today's Rin allowance — resets at midnight".
7. Help screen + disclaimer (FIG copy).
8. Kill switch `RIN_ENABLED`; on vendor outage show "Rin is resting, try again soon".
9. Eval harness run in CI nightly against staging (live calls, small budget); pass threshold set with the product owner.

## DB objects
`ai.*` tables, functions, procedures.

## API endpoints
`GET/POST /rin/conversations`, `GET /rin/conversations/{id}/messages`, `POST /rin/conversations/{id}/messages` (SSE), `POST /rin/actions/{id}/accept`, `POST /rin/actions/{id}/dismiss`, `DELETE /rin/conversations/{id}`, `DELETE /rin/memory`, `GET /rin/usage`.

## Screens (Figma frames)
`Rin AI-1` (Unlock Rin AI), `Rin AI/Start` (greeting + suggested prompts), conversation frames ("How am I doing today?", dinner ideas), meal estimate card (Add to Avatar / Edit / Not Now), menu (Search History / Delete Chat / Help), delete dialog + toast, `Search in Rin AI`, `Rin AI help`.

## Security checks
T20 prompt injection: user text only in user turns; the system prompt instructs that user/tool content is data; tools are read-only or proposals; no tool takes URLs; output validated as plain text (no markup rendered; `Text` widget only). Privacy: own data only, consent-gated, encrypted at rest, no logging of prompts/responses (only token counts); API key in the secret manager; spend limits per workspace; allowance prevents cost abuse; guardrails for emergencies/medical advice; refusal handling.

## Input-validation checklist
| Field | App validator | Max | API type | DB |
|---|---|---|---|---|
| Chat prompt | `chatMessage(2000)` | 2000 | SafeChatMessage | ciphertext |
| Conversation search | `search()` | 64 | SafeSearchQuery | — |
| Edited action items | same as meals (S08) | — | meal item schema | — |
| Model output (stored/displayed) | — | 8000 | validated with SafeChatMessage rules (markup → replaced by plain text) before storage | ciphertext |
| Tool arguments from the model | — | — | Pydantic strict models (food_name SafeShortText(80), quantity range) | — |
- [ ] Payload sweep includes chat prompts; eval set includes XSS/HTML-output attempts → no markup stored or displayed.

## Tests to write
Guardrails (emergency phrases in English/Hinglish → fixed response, no model call); context builder excludes other users and PII; metering (allowance reached → 403 `DAILY_LIMIT_REACHED`; reset at local midnight; cache tokens accounted); pending action lifecycle (accept → meal logged with source rin; limit enforced; dismiss; expiry); STANDARD → 403; consent missing → 403 `CONSENT_REQUIRED`; SSE stream handling incl. refusal and mid-stream error; IDOR on conversations/actions; widget tests; eval thresholds (meal mapping accuracy ≥ 85 % on the set, 100 % emergency handling, 0 cross-user leaks, 0 markup outputs).

## Acceptance criteria / Definition of done
- [ ] STAR user can chat with streaming replies (first token ≤ 3 s p95 on staging) and log a meal via chat with confirmation.
- [ ] No log is created without the user tapping Add to Avatar.
- [ ] Allowance enforced and displayed as %.
- [ ] Prompts/responses never appear in logs or Sentry; stored encrypted.
- [ ] Eval suite passes agreed thresholds; refusal fallback verified.
- [ ] Privacy notice updated with the AI processor and the transfer (OQ-37 approved).

## Estimated effort
10–12 developer-days (+ ongoing eval tuning).
