# Dispatch Rules — /test-session Cluster Classification and Background Dispatch

Referenced by `SKILL.md`. Defines how every finding captured during an
interactive session is classified, clustered, and dispatched to a
background `/test-fix` worker.

## Cluster classification

Every finding goes through a two-stage classifier:

1. **Stage 1 — Haiku (claude-haiku-4-5-20251001).** Fast and cheap. Given
   the finding's symptom, verbatim, module, and step, produce a stable
   slug `cluster_hint` plus a confidence score in [0, 1].
2. **Stage 2 — Opus (claude-opus-4-6) fallback.** If Haiku confidence is
   below the confidence gate, escalate to Opus for re-classification.
   Opus returns the same fields.

The classification result is shown inline to the founder immediately, so
he can override ("merge with bg#1" / "split them") before dispatch.

### Known cluster_hint slugs

The system uses a free-form string but defaults to one of the following
slugs when Haiku recognizes a known pattern:

- `formatting_creep` — agent uses markdown (bold, headers, bullets)
  despite the soul constraint. Historical cousins: FINDING-002.
- `dashboard_briefing_empty` — appointment booked in DB but artigiano
  dashboard (La Vista, AgendaStrip) doesn't reflect it.
- `multi_intent_voice_partial` — a voice note with N intents ends up
  executing only M < N of them. Historical cousin: FINDING-007.
- `reschedule_missing` — reschedule intent detected but no tool exists
  to fulfill it. Historical cousin: FINDING-004.
- `tone_drift` — agent's tone drifts (corporate, casual, inconsistent)
  across a multi-turn conversation.
- `material_markup_default` — agent asks the artigiano for the markup
  percentage instead of using the configured default (20%). Historical
  cousin: FINDING-003.

Novel clusters get a newly-minted slug (snake_case, under 30 chars).

## Haiku-first classification

The classifier prompt, simplified:

```
Given this finding from an interactive test session of L'Agente:

- Module: {module_id} — {module_title}
- Step: {step_id} — {step_description}
- Founder's verbatim: "{founder_verbatim}"
- Step's known bug patterns: {bug_patterns_to_watch}

Classify into one of these known cluster slugs (or mint a new one if
none fit): formatting_creep, dashboard_briefing_empty,
multi_intent_voice_partial, reschedule_missing, tone_drift,
material_markup_default.

Return JSON: { "cluster_hint": "<slug>", "confidence": 0.0..1.0,
"rationale": "<one sentence>" }.
```

## Confidence gate

- **Gate threshold:** 0.70.
- If Haiku confidence ≥ 0.70 → use Haiku result.
- If Haiku confidence < 0.70 → escalate to Opus for re-classification.
- If Opus confidence is still < 0.50 → mark the cluster as `unknown`
  and flag inline to the founder before dispatching. Ask the founder
  for a slug suggestion.

This matches the Haiku+Opus import pattern used elsewhere in L'Agente
(see `feedback_import_haiku_opus_pattern.md`).

## Dispatch decision table

Applied after classification, in order:

| # | Condition | Action |
|---|-----------|--------|
| 1 | Severity is **critical** | Spawn immediately with priority queue bump + VPS live log attachment |
| 2 | `in_flight_count >= 4` (configurable) | Queue the finding; show queue position to founder |
| 3 | Cluster hint matches an **in-flight** agent, and `files_likely_touched` overlap | **Serialize** — queue this agent until the in-flight one finishes (avoid plan conflicts) |
| 4 | Cluster hint matches an **in-flight** agent, no file overlap | Spawn a sibling agent with the new finding only, link to the in-flight plan in the prompt |
| 5 | Cluster hint matches a **completed** agent | Spawn a follow-up agent that references the completed plan in its rich-context bundle |
| 6 | Cluster is **novel** | Spawn a new background agent with full rich-context bundle |
| 7 | Reproducibility is **uncertain** | Ask the founder to retest ONCE before dispatching (override allowed) |

## Overlap detection for rule #3

Two agents are said to "overlap" if their `files_likely_touched` sets
have any intersection. `files_likely_touched` is computed from the
cluster_hint:

| cluster_hint | files_likely_touched |
|--------------|----------------------|
| `formatting_creep` | `souls/artigiano-cluster-a.yaml`, `platform/api/services/channel_adapters/whatsapp.py` |
| `dashboard_briefing_empty` | `platform/api/services/briefing.py`, `frontend/src/vista/AgendaStrip.tsx`, `platform/api/services/unified_agent.py` |
| `multi_intent_voice_partial` | `platform/api/services/voice_intent_router.py`, `platform/api/services/unified_agent.py`, `platform/api/services/tool_registry.py` |
| `reschedule_missing` | `platform/api/services/tool_registry.py`, `souls/artigiano-cluster-a.yaml`, `platform/api/services/appointment_crud.py` |
| `tone_drift` | `souls/artigiano-cluster-a.yaml`, `platform/api/services/unified_agent.py` |
| `material_markup_default` | `souls/artigiano-cluster-a.yaml`, `platform/api/services/tool_registry.py` |

For novel clusters, Claude picks a best-guess set from the symptom
before dispatch. This is imprecise by design — overlap rules are a
safety net, not a perfect guarantee.

## Background agent lifecycle

- **Spawn:** `Agent(subagent_type="general-purpose",
  run_in_background=true, description="fix: {cluster_hint}",
  prompt=rendered_template)`.
- **In-flight cap:** 4 concurrent agents. Over the cap, the finding
  goes to the queue; dispatch happens when a slot frees.
- **Timeout:** 20 minutes wall-clock. On timeout, kill the agent, mark
  as `timeout`, save partial state to the session tracker.
- **Completion:** Agent returns `PATH: ...\nSUMMARY: ...\nFILES: ...\nMINUTES: ...`.
  SKILL.md parses this, updates the tracker, notifies the founder
  inline with `✓ bg#N done → plan: {path}`.
- **Failure:** Two consecutive agent failures in the same cluster
  trigger an escalation prompt asking the founder for clarifying
  context before retry.
- **Abort:** `/test-session abort` kills all in-flight agents via the
  agent ID tracker and saves state. `--resume` picks up from the last
  committed step.
