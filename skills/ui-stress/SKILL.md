---
name: ui-stress
description: Autonomous UI stress-test session — Playwright-driven RECURSIVE CRAWL (frontier queue, not a fixed route list) + click-storm + edge cases + responsive + a11y on lagente.ai. Discovery-first (no pinned selectors), classifies every affordance before touching it (catches blank-page api-anchors), recurses into drawers/modals/sub-tabs, dispatches structural fix plans to background agents as findings arrive. Use during frontend revisions to hammer the whole surface in one pass.
---

# /ui-stress — Autonomous UI Stress-Test Session

Plays the role of a hostile-curious QA who **crawls everywhere** — every button, nested tab, sub-page, drawer, modal, and edge input — autonomously, via Playwright. Not a fixed route list: a **recursive frontier crawler** (see `references/recursive-crawl.md`) that grows its frontier from discovered links/tabs/overlays, classifies each affordance before touching it, and recurses into opened overlays. Captures findings as they fire and dispatches rich-context fix plans to background agents in parallel. The founder watches.

> **v2 (2026-05-24):** evolved from route-visitor → recursive crawler after missing A-007 (Impostazioni sub-tab "Collega" → blank page). The crawl engine, link-class taxonomy, the **api-anchor / blank-page rule**, overlay recursion, the CSP-safe a11y auditor, and budgets all live in `references/recursive-crawl.md` — read it before Phase 3.

Sister skill to `/test-session`: shares `findings.jsonl` schema, `references/dispatch-rules.md`, `templates/background-worker-prompt.md`, and the Haiku→confidence-gate→Opus classifier pipeline. Distinct purpose: **`/test-session` is pair-mode founder-driven WhatsApp flows** (artigiano receiving appointments); **`/ui-stress` is autonomous Playwright-driven frontend surface stress**.

---

## Read before starting

These feedback memories shape every decision in this skill:

- `feedback_macro_fixes_not_prompt_patches.md` — fixes must be structural (primitives + contracts), never aria-label-per-button
- `feedback_quality_over_token_economy.md` — never trim subagent context; founder time > compute
- `feedback_plan_execution_autonomous.md` — plans must be self-contained, executable by bypass-permissions shell
- `feedback_no_keyword_routing_ever.md` — Haiku always primary for cluster classification
- `feedback_import_haiku_opus_pattern.md` — Haiku → confidence gate → Opus for any AI parsing
- `feedback_lagente_ui_language.md` — labels in artigiano Italian, not poetry

---

## When to use

Invoke when the founder:

- Types `/ui-stress` (default: autonomous, full scope against `https://lagente.ai`)
- Types `/ui-stress --scope click-storm,a11y` (subset)
- Types `/ui-stress --target localhost` (run against `http://localhost:3000`)
- Types `/ui-stress --tenant <id>` (use a specific tenant instead of default sarto)
- Types `/ui-stress --resume` (resume most recent interrupted session)
- Says "stressa l'interfaccia", "proviamo tutti i bottoni", "click storm", "over-stimolare la UI"

Do **NOT** invoke:

- For single-bug quick fixes → `/test-fix` directly
- For WhatsApp artigiano flows → `/test-session artigiano`
- For pure E2E backend seeding → `/lagente-e2e-artigiano`

## Command surface

- `/ui-stress` — full autonomous session, all 7 phases (~60-90 min)
- `/ui-stress --scope click-storm,edge,responsive,a11y,mutative` — phase filter
- `/ui-stress --target {online|localhost}` — default: online
- `/ui-stress --tenant {tenant_id}` — default: `070b732e-1a5c-4d0b-9780-09dfba86d967` (Bernardi, home_bottega_enabled)
- `/ui-stress --viewports 375,768,1280,1920` — default: all four
- `/ui-stress --crawl {exhaustive|fast}` — default: exhaustive (recurse into overlays + edge inputs). `fast` = nav+tabs+api-anchor-probe only
- `/ui-stress --max-states N` — frontier cap (default 120) · `--max-depth N` — overlay recursion cap (default 3) · `--max-actions N` (default 600)
- `/ui-stress --cap 4` — in-flight agent cap (default 4)
- `/ui-stress --mode interactive` — override default autonomous → pause for founder per finding
- `/ui-stress status` — show tracker (current phase, findings count, in-flight agents)
- `/ui-stress abort` — graceful shutdown, save state for `--resume`
- `/ui-stress done` — finalize + generate report

---

## Pre-flight

Run each check in order. Any failure → STOP with remediation suggestion. Never start on a broken environment.

### 1. Target reachable

```bash
curl -sf -o /dev/null -w "%{http_code}" https://lagente.ai
curl -sf -o /dev/null -w "%{http_code}" https://api.lagente.ai/health
```

Both should return `200`. For `--target localhost`, replace with `http://localhost:3000` and `http://localhost:8000/health`.

### 2. Playwright MCP available

The skill relies on the Playwright MCP tools (`playwright_navigate`, `playwright_click`, `playwright_fill`, `playwright_evaluate`, `playwright_screenshot`, `playwright_resize`, `playwright_press_key`, `playwright_console_logs`, `playwright_get_visible_html`). If any are missing in the current environment, STOP — this skill cannot run without Playwright.

### 3. Target tenant exists + onboarding complete

```bash
ssh root@5.161.213.45 "docker exec lagente-lagente-db-1 psql -U lagente -d lagente -tAc \"SELECT id, onboarding_completed_at FROM tenants WHERE id = '070b732e-1a5c-4d0b-9780-09dfba86d967'\""
```

Expected: row with `COMPLETED` or `onboarding_completed_at` set. If missing, ask founder to run the tenant seed script or pick another tenant.

### 4. Clerk ticket mint script reachable

```bash
ls ~/lagente/platform/api/tests/e2e/auth/clerk_session.py
ls ~/lagente/tasks/e2e-deep-artigiano/mint_sarto_cookie.py
```

Both must exist. The skill uses `mint_sarto_cookie.py` (or equivalent per tenant) to produce a sign-in ticket URL.

### 5. Session directory writable

```bash
mkdir -p ~/lagente/tasks/test-sessions && touch ~/lagente/tasks/test-sessions/.preflight && rm ~/lagente/tasks/test-sessions/.preflight
```

### 6. Shared test-session infrastructure present

```bash
ls ~/.claude/skills/test-session/references/dispatch-rules.md
ls ~/.claude/skills/test-session/templates/background-worker-prompt.md
```

Both must exist — `/ui-stress` reuses them. If missing, STOP — `/test-session` skill is the infrastructure owner.

### 7. test-fix plan output directory writable

```bash
mkdir -p ~/lagente/tasks/test-fix && touch ~/lagente/tasks/test-fix/.preflight && rm ~/lagente/tasks/test-fix/.preflight
```

### 8. Bg agent file-write permissions

Known issue: sandboxed subagents cannot write files to `~/lagente/tasks/test-fix/`. The skill compensates by:
- Instructing bg agents to return full plan content **inline** in their result
- Parent skill persists each plan with `Write` after each bg completes

No pre-flight command — just remember the pattern.

If all 8 checks pass, announce:
**"✓ Pre-flight OK. Target: {target}. Tenant: {tenant}. Viewports: {viewports}. Starting autonomous stress-test in 10s (say 'stop' to pause)."**

---

## Session initialization

```bash
SESSION_ID="$(date +%Y-%m-%d)-$(date +%H%M)-ui-stress"
SESSION_DIR="$HOME/lagente/tasks/test-sessions/$SESSION_ID"
mkdir -p "$SESSION_DIR"
```

Initialize `session.json`:

```json
{
  "session_id": "2026-04-18-1530-ui-stress",
  "skill": "ui-stress",
  "target": "https://lagente.ai",
  "tenant_id": "070b732e-1a5c-4d0b-9780-09dfba86d967",
  "viewports": [375, 768, 1280, 1920],
  "phases_selected": ["public", "auth", "click-storm", "edge", "responsive", "a11y", "mutative"],
  "current_phase": "public",
  "routes_visited": [],
  "started_at": "...",
  "status": "running",
  "findings_count": 0,
  "findings": [],
  "agents_in_flight": [],
  "agents_done": [],
  "agents_queued": [],
  "in_flight_cap": 4
}
```

Persist after every state change. Append-only log at `$SESSION_DIR/findings.jsonl`.

The recursive crawler keeps its frontier in `$SESSION_DIR/crawl_state.json` (resumable):

```json
{
  "queue": [{"url": "/oggi/impostazioni", "depth": 0, "via": "seed"}],
  "visited": { "<state-fingerprint>": {"url": "...", "actions_done": 0, "findings": []} },
  "budgets": { "max_states": 120, "max_actions": 600, "max_depth": 3, "states_done": 0, "actions_done": 0 },
  "denylist_hits": []
}
```

`tenant_id` note: the only auth-mint that works is `mint_sarto_cookie.py` → tenant `e2e-sarto-2026` (Sartoria Bianchi). Use it for all authenticated phases; it is also the **only** tenant safe for Phase-7 mutations. Do NOT mutate the founder tenant Bernardi (`070b732e…`, real prod) — pre-flight may reference it but auth + mutative phases run on sarto.

### Finding id scheme

`A-NNN` (UI-stress findings). Start at `A-001`. Resume picks up from `max(findings[].id) + 1`. Reserves `B-NNN` for a hypothetical paired `/ui-stress-b` partner run.

### Finding schema (shared with /test-session)

```json
{
  "id": "A-013",
  "phase": "click-storm",
  "route": "/dashboard/lavoro/clienti",
  "viewport": 1280,
  "element": "button.\"Nuovo cliente\"",
  "symptom": "button clicks but no slide-over opens; OmnipresentChatBar overlaps z-50",
  "severity": "high",
  "reproducibility": "consistent",
  "cluster_hint": "dead_affordances",
  "classification_confidence": 0.88,
  "screenshot": "screenshots/A-013.png",
  "console_errors": [],
  "dispatched_to_bg": "bg#2",
  "captured_at": "..."
}
```

---

## Phase runbook

Each phase runs autonomously. After every meaningful action, capture screenshots and console logs. Dispatch findings as they accumulate (do not batch until end of phase).

### Phase 1 — public routes (no auth)

Routes to visit at viewport 1280x800:

- `/` — landing
- `/prenota` — lead chat widget
- `/privacy`
- `/termini`
- `/sign-in`
- `/sign-up`

For each route:
1. `playwright_navigate` → wait for networkidle
2. `playwright_evaluate` to enumerate all visible interactive elements (see "Discovery-first enumeration")
3. For each element: click or fill (see click-storm rules below)
4. `playwright_console_logs` — capture any errors/warnings
5. `playwright_screenshot` → `screenshots/P1-{route-slug}.png`
6. Record route in `routes_visited`

### Phase 2 — auth (Clerk ticket bypass)

```bash
cd ~/lagente && python tasks/e2e-deep-artigiano/mint_sarto_cookie.py --print-ticket-url
```

Extract the `__clerk_ticket=<token>` URL. Use `app.lagente.ai/sign-in?__clerk_ticket=...` (not `accounts.` — Cloudflare bot protection).

`playwright_navigate` → the ticket URL → wait for load → verify `networkidle`. For tenants with `home_bottega_enabled`, expect redirect to `/bottega`; for others expect `/dashboard`. Verify visible `<main>` with workspace content.

If redirected to `/onboarding`: that is finding **`onboarding_redirect_loop`** cluster. Capture, dispatch, then click "Continua senza WhatsApp" to proceed (temporary workaround until fix ships).

Store the resulting storage state in-memory for subsequent Playwright calls.

### Phase 3 — recursive interaction crawl (the engine)

**Read `references/recursive-crawl.md` first.** This is NOT a fixed route list — it is a frontier
crawler that grows from discovered links/tabs/overlays and classifies every affordance before
touching it. The route list below is only a **seed + priority hint**; the crawler must reach
*everything reachable*, including nested sub-tabs (e.g. `/oggi/impostazioni/*`), drawers, and modals.

**Seed the frontier** (authenticated home + known high-value roots — actual paths vary by tenant/vertical; the home is `/oggi`):
- `/oggi` (home — VoiceSlot Punto/Diario/Studio carousel: tap each voice pill/dot)
- `/oggi/lavoro`, `/oggi/cassa`, `/oggi/archivio`, `/oggi/impostazioni` (+ **every** sub-tab: profilo/soul/team/integrazioni/canali/tiles/privacy/notifiche)
- `/dashboard/agenda`, `/dashboard/persone` (toggle Chat|Banco), `/dashboard/cose-da-fare`, `/dashboard/centralino`
- Then **let the crawler expand** — every internal-nav link discovered becomes a new frontier state.

**Per-state loop** (full algorithm in the reference):
1. Navigate (`domcontentloaded`), clear console buffer, run the **Universal Probe** (one `playwright_evaluate` → landmarks + a11y audit + classified interactive list).
2. Skip if state-fingerprint already visited; else audit + screenshot + mark visited.
3. Act per affordance **klass**:
   - **internal-nav** → enqueue target. **api-anchor** → probe with authenticated fetch (the **A-007 rule**: 404/5xx/JSON on a user CTA = `raw_endpoint_anchor` finding). **external** → record, don't follow.
   - **tab/segmented** → click every option, audit each panel (this is the A-007 surface).
   - **overlay-opener** → click, recurse into the drawer/modal (enumerate+audit interior → `state_gated_a11y`), close, pop. Depth cap `--max-depth`.
   - **mutator** → Phase-7-only happy-path. **destructive** → open confirm then cancel. **cost-action** → HARD BLOCK (Studio "Chiedi"/"Genera", pay, bulk-send — never click).
   - **dead-candidate** → click; no DOM change + no network + no console in 1500ms → `dead_affordances`.
4. Persist `crawl_state.json`. Respect budgets (`--max-states`/`--max-actions`/wall-clock). HUD line.

### Phase 4 — edge inputs (per-state during the crawl)

For every `input`, `textarea`, and `contenteditable` discovered at any crawled state (including those that only mount inside opened drawers/modals — that's where the misses hide):

Cycle through the edge payloads (save each result + screenshot if unexpected):
- Empty string submission
- Single space
- `" OR 1=1 --` (SQL injection probe — must not hit backend unsanitized, must not break client)
- `<script>alert(1)</script>` (XSS — must be escaped on render)
- `{{7*7}}` (template-injection probe — must render literal)
- 10,000-char paste (`'a'.repeat(10000)`) — check clip/scroll behavior, character counter
- Emoji + zero-width joiners (`'👨‍👩‍👧‍👦🇮🇹'`)
- `\n` multi-line in a single-line field
- Double-click submit button rapidly (debounce probe — cluster `silent_throttle` if second submit silently drops, `input_limits` if no rate message)
- Tab-navigate through the form checking focus ring visibility

### Phase 5 — responsive sweep

For each viewport in `session.viewports` (default `[375, 768, 1280, 1920]`):
1. `playwright_resize` to `{viewport}x900`
2. Re-visit the top 5 hit routes (whichever had the most findings in Phase 3, or default: `/`, `/dashboard`, `/agenda`, `/clienti`, `/centralino`)
3. Check for:
   - Horizontal scroll (document.documentElement.scrollWidth > viewport width)
   - Overflow-cut content (clipped text without ellipsis)
   - Bottom nav vs OmnipresentChatBar z-index collision
   - Tap targets < 44x44 px (iOS a11y)
   - Tailwind `lg:` breakpoint is 1024 — iPad portrait 768 still renders mobile nav; confirm expected behavior
4. Screenshot each viewport+route combo: `screenshots/P5-{viewport}-{route-slug}.png`

### Phase 6 — a11y (runs per-state inside the crawl, not as a separate route pass)

⚠️ **axe-core from CDN is blocked by the app's CSP** (`script-src` rejects the external script — confirmed 2026-05-24). Do NOT inject axe. Use the **CSP-safe manual auditor** baked into the Universal Probe (`references/recursive-crawl.md`) — it runs at every crawled state, including opened drawers/tab-panels, and reports: nameless controls, inputs without label (placeholder-as-label fails WCAG 1.3.1/4.1.2), duplicate ids, heading-order skips, dangling `aria-controls`, missing h1/landmark.

1. The auditor already runs in step 1 of the per-state loop → no separate pass needed.
2. Violations only visible after an interaction (drawer/modal/tab) → `cluster_hint: "state_gated_a11y"`. Static ones → `a11y_*` slugs.
3. Skip Clerk-owned violations on `/sign-in` — note upstream.
4. Aggregate recurring a11y misses into ONE structural finding (e.g. "N unlabeled inputs across M states → use the `<Field>` primitive / `aria-label` for chromeless controls"), not one finding per element (macro-fix rule).

### Phase 7 — mutative actions (founder scope: "tutto")

**CAUTION**: Phase 7 writes to the tenant DB. The seeded tenant (`e2e-sarto-2026`) is the only safe target — announce in the running HUD each mutation before it fires.

**HARD BLOCK — never click, even in Phase 7 (cost/irreversible):** Lo Studio "Chiedi"/"Genera" (~$3.20/run Opus+web_search), any pay/incassa/fattura-elettronica, "invia a tutti"/bulk send, account deletion. The crawler's `cost-action` and `destructive` classes catch these — log a `denylist_hits` entry and move on.

For each **mutator** affordance the crawl discovered, perform the happy-path:
- Create a client ("Nuovo cliente" → fill name + phone → save)
- Create an appointment ("Nuovo appuntamento" → fill → save)
- Create an invoice ("Nuova fattura" → fill line → save)
- Create an expense / magazzino item
- Edit an existing row
- Delete an existing row (expect confirmation modal → confirm)

Capture:
- Loading states (button shows spinner? disabled? silent?)
- Success feedback (toast? redirect? optimistic UI?)
- Error recovery (what happens if backend returns 500 — trigger by creating with duplicate ID if possible)

Double-click submits → `silent_throttle` / `input_limits` cluster.

---

## Discovery-first enumeration

Never hard-code CSS selectors. Each time you enter a new DOM state, enumerate via `playwright_evaluate`:

```js
Array.from(document.querySelectorAll(
  'button, a[href], input, textarea, select, [role="button"], [role="tab"], [role="menuitem"], [contenteditable="true"], [onclick]'
))
  .filter(el => {
    const rect = el.getBoundingClientRect();
    return el.offsetParent !== null && rect.width > 0 && rect.height > 0;
  })
  .map((el, i) => ({
    idx: i,
    tag: el.tagName,
    type: el.type || '',
    text: (el.innerText || el.textContent || '').trim().slice(0, 80),
    label: el.getAttribute('aria-label') || el.getAttribute('title') || '',
    testid: el.getAttribute('data-testid') || '',
    href: el.getAttribute('href') || '',
    disabled: el.disabled || el.getAttribute('aria-disabled') === 'true',
    rect: { x: rect.x|0, y: rect.y|0, w: rect.width|0, h: rect.height|0 },
  }));
```

Interact by `idx`, not selector. Re-enumerate after each click that mutates the DOM.

---

## Finding intake & dispatch

Same pipeline as `/test-session`:

### 1. Capture
Append to `findings.jsonl` verbatim + update `session.json.findings[]`.

### 2. Haiku classify
Call Haiku with `references/dispatch-rules.md`'s classification prompt + the finding + `bug_patterns_to_watch` from the current phase. Expected: `{cluster_hint, confidence, rationale}`.

### 3. Confidence gate
- `>= 0.70` → use Haiku verdict
- `< 0.70` → escalate to Opus
- Opus `< 0.50` → mark `unknown`, continue phase, batch review at end

### 4. Overlap check
Compare `cluster_hint` to `agents_in_flight[*].cluster_hint`. If match → add finding to sibling's `finding_ids[]`, send an update via `SendMessage` to include new context (if agent is still running). Do NOT spawn a duplicate.

### 5. Dispatch (when new cluster)
Check `len(agents_in_flight) < in_flight_cap`. If at cap → enqueue; dispatch on next completion.

Render context bundle from `~/.claude/skills/test-session/templates/background-worker-prompt.md` with these UI-stress-specific additions:

- `{{viewport}}` — the viewport at capture
- `{{route}}` — the route under test
- `{{screenshot_path}}` — path to the PNG capture
- `{{console_errors}}` — captured console output
- `{{dom_snippet}}` — the enumerated element that fired the finding (tag, text, testid)
- `{{sibling_findings_in_cluster}}` — all other findings with the same cluster_hint in this session (bullet list)
- `{{recent_commits_frontend}}` — output of `git log --oneline -20 -- frontend/src/`
- `{{file_likely_touched}}` — heuristic by cluster:
  - `dead_affordances` → `frontend/src/components/` + `frontend/src/app/dashboard/`
  - `a11y_*` → `frontend/src/components/shared/` + the specific route file
  - `formatting_creep` → soul YAMLs + `frontend/src/components/chat/`
  - `input_limits` / `silent_throttle` → form component + API router
  - `missing_subroutes` / `copy_link_mismatch` → `frontend/src/app/` + link source
  - `raw_endpoint_anchor` / `unreachable_subroute` → the page component holding the `<a href>` (grep the bad path) + the real backend router (find the actual route: it's almost never `/api/oauth/<x>/start`) + any Next proxy under `frontend/src/app/api/`
  - `state_gated_a11y` → the overlay/drawer/tab component that mounts on interaction
  - `onboarding_redirect_loop` → `frontend/src/app/dashboard/layout.tsx` + `frontend/src/app/onboarding/page.tsx` + `platform/api/routers/onboarding.py`

**Subagent sandbox reminder in prompt:** explicitly instruct the bg agent to **return the full plan inline in its result** — parent agent will persist to `~/lagente/tasks/test-fix/YYYY-MM-DD-<cluster>.md`. Otherwise permission denials silently eat plans.

Spawn:
```python
Agent(
    description=f"fix: {cluster_hint}",
    subagent_type="general-purpose",
    run_in_background=True,
    prompt=rendered_bundle,
)
```

Update `session.json.agents_in_flight[]` with `bg_id`, `cluster_hint`, `finding_ids`, `started_at`, `files_likely_touched`.

### 6. On bg completion
When notification arrives (background-task event):
1. Read the task output file
2. Extract plan content — it should be a full markdown doc
3. `Write` to `~/lagente/tasks/test-fix/{date}-{cluster_slug}.md`
4. Move entry from `agents_in_flight` → `agents_done` in tracker
5. Log inline in the running HUD:
   ```
   ✓ bg#2 done (dead_affordances, 8 min) → tasks/test-fix/2026-04-18-dead-affordances.md
   ```
6. If `agents_queued` non-empty: dequeue the first and dispatch.

---

## Cluster hints (UI-stress vocabulary)

Prefer known slugs for overlap detection:

- `dead_affordances` — element clicks but produces no observable effect (DOM unchanged + no network + no console)
- `a11y_missing_label` — icon-only button without accessible name
- `a11y_missing_h1` — route missing `<h1>` landmark
- `a11y_missing_landmark` — no `<header>` / `<main>` / `<nav>`
- `a11y_missing_skip_link` — no skip-to-content anchor
- `a11y_contrast` — text fails WCAG contrast ratio
- `a11y_keyboard_trap` — focus cannot escape a modal
- `a11y_focus_ring` — interactive element has no visible `:focus-visible` state
- `input_limits` — field accepts pathological input without feedback (10k chars, XSS, very long paste)
- `silent_throttle` — submit fires silently on rapid double-click
- `formatting_creep` — agent response uses markdown bold/italic in WA-style messages
- `untranslated_enum` — English status string leaks to UI ("PENDING", "COMPLETED")
- `missing_subroutes` — nav link targets a route that 404s
- `raw_endpoint_anchor` — **(A-007 class)** a user-facing CTA is an `<a href>` to an API/raw endpoint (`/api/...`, api host) that returns 404 / 5xx / `application/json` instead of a navigable page → blank page on click. Fix = fetch-then-redirect (button) or correct page route, never a bare anchor to an authenticated/JSON endpoint.
- `unreachable_subroute` — a nav/tab target that loads blank or errors (distinct from 404: page route exists but renders nothing)
- `state_gated_a11y` — a11y violation (unlabeled input, dangling aria-controls, focus trap) only present after opening a drawer/modal/tab — invisible to a static-DOM audit
- `copy_link_mismatch` — link text implies one destination, href goes elsewhere
- `loading_state` — mutation has no loading indicator between click and response
- `empty_state_clarity` — empty list/table shows no CTA to add first item
- `responsive_overflow` — horizontal scroll at a given viewport
- `responsive_tap_target` — tap target < 44x44 px on mobile
- `responsive_z_collision` — chat bar / bottom nav overlaps primary UI at small viewport
- `clerk_i18n_brand` — Clerk sign-in shows English labels + default "Your Application"
- `onboarding_redirect_loop` — `/dashboard` redirects to `/onboarding` for completed tenants

Add new slugs only when no existing slug fits; never sub-slug a single finding.

---

## Inline HUD

After each meaningful step, print a compact single-line update:

```
[P3 /dashboard/lavoro/clienti] A: 13 findings | bg#1:onb bg#2:dead_aff bg#3:a11y bg#4:clerk | queued: 2
```

Format: `[{phase} {route}] A: {count} findings | {in_flight_summary} | queued: {n}`.

On bg completion:

```
✓ bg#2 done (dead_affordances, 8 min) → tasks/test-fix/2026-04-18-dead-affordances.md
  Files: frontend/src/components/ui/EmptyState.tsx, frontend/src/components/ui/ListRowButton.tsx, ...
  Summary: {first line of plan summary}
```

---

## Abort & resume

`--resume`:
1. Scan `~/lagente/tasks/test-sessions/*-ui-stress/`
2. Pick most recent with `status in {running, aborted}`
3. Read tracker, announce:
   `"Resuming {session_id} from phase {current_phase}. {N} bg still flying, {M} queued."`
4. Continue phase loop from `current_phase`

`abort`:
1. Mark `status = "aborted"` in tracker
2. Do NOT kill in-flight bg agents — they finish and write plans
3. Announce: `"Aborted. Resume with /ui-stress --resume."`

---

## Session completion

On `/ui-stress done` or end of last phase:

1. Wait up to 2 minutes for in-flight agents (with countdown HUD)
2. If any still running, ask: `"bg#N still flying. Wait / proceed / abort?"`
3. Generate `$SESSION_DIR/report.md`:

```markdown
# UI Stress Report — {session_id}

**Target:** {target}
**Tenant:** {tenant}
**Duration:** {duration}
**Viewports:** {viewports}

## Summary
- Findings: {count} ({severity_breakdown})
- Clusters: {cluster_list}
- Plans dispatched: {plans_count}
- Plans persisted: {plan_paths}

## By phase
### Phase 1 — public
...
### Phase 2 — auth
...

## Findings table
| ID | Phase | Route | Severity | Cluster | Plan |

## Open clusters (no plan yet)
...

## Next actions
- Merge plans in priority order: critical > high > medium
- Suggested merge queue: {ordered list}
```

4. Mark `status = "completed"` in tracker.

---

## Founder interaction

**Default mode (autonomous):** skill runs without prompting. Inline HUD after each step. Founder can interrupt any time with `stop` / `pause` / `--mode interactive` mid-session.

**Interactive mode (`--mode interactive`):** pauses after each finding for y/split/merge/cancel before dispatch. Same contract as `/test-session` finding intake.

**Quiet corrections:** if founder types a one-line instruction mid-session (e.g., "skip phase 7", "focus on clienti", "add mobile 430 viewport"), honor it, acknowledge with one line, continue. Never derail into a conversation.

---

## Non-goals

- Not a replacement for `/test-session` (that's WhatsApp flows)
- Not an E2E smoke test (that's the `tests/` suite)
- Not a visual regression tool (no screenshot diffing)
- Does not merge PRs — only drafts plans. Founder decides merge order.
- Does not mutate non-test tenants. Phase 7 strictly requires the seeded tenant.

---

## Operational notes (learned 2026-05-24 — save re-discovery time)

- **Env:** Windows + git-bash for POSIX; repo at `C:\Users\mbern\lagente`. SSH to VPS works. `jq` is NOT installed — analyze big JSON (console logs) with `python -c`.
- **`playwright_evaluate`** rejects top-level `return` → wrap every script in an **IIFE** `(() => ({...}))()` (or `(async () => {...})()`).
- **Auth:** `python tasks/e2e-deep-artigiano/mint_sarto_cookie.py` prints a one-shot ticket URL (TTL 3600s, consumed on use → re-mint per browser session). Navigate to it with `waitUntil: domcontentloaded`; auth lands on `/oggi`. **Never split the ticket URL across lines** (a stray `\`/newline corrupts the token).
- **`networkidle` never settles** (the app long-polls) → always use `domcontentloaded` + an explicit `await new Promise(r=>setTimeout(r, 1500-2500))`.
- **`playwright_console_logs`** buffer is **cumulative across navigations and persists stale entries from prior sessions** → `--clear` at the start of each state; a 429/error storm in the buffer may be stale (confirm it reproduces live before dispatching).
- **Route status ≠ working.** A 200/`opaqueredirect` on a route means the page loads, not that its CTAs work — only the api-anchor probe / a real click reveals blank-page hazards.
- **Big tool outputs** (console logs) can exceed the token cap and get spilled to a file — analyze with python, never re-Read whole.

## Files

- `SKILL.md` (this file) — pre-flight, workflow, dispatch, completion
- `references/recursive-crawl.md` — **(v2 core)** frontier crawler algorithm, affordance taxonomy, the A-007 api-anchor rule, overlay recursion, CSP-safe Universal Probe script, budgets, denylists
- `references/dispatch-rules.md` — shared with `/test-session` (symlink or re-used path)
- `templates/background-worker-prompt.md` — shared with `/test-session`
- `references/auth-bypass.md` — Clerk ticket bypass details (to be written on first run if needed)

On first run, if `references/dispatch-rules.md` and `templates/background-worker-prompt.md` are missing from this skill's directory, **symlink** to the `/test-session` canonical versions rather than forking — they must stay in sync.
