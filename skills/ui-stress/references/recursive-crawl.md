# Recursive Crawl Engine (v2) — click everywhere, not a fixed route list

> Motivazione: nel run 2026-05-24 la skill mancò A-007 (Impostazioni → Integrazioni →
> "Collega" → pagina vuota) perché Phase 3 visitava una **lista fissa di route** e lo sweep
> controllava solo lo *status HTTP* degli href, mai l'effetto di un click né i sotto-tab.
> Questo motore sostituisce il "route visitor" con un **crawler ricorsivo della frontiera**.

## Modello a stati

- Uno **stato** = `(route normalizzata + firma degli overlay aperti)`. `/persone` con un
  drawer aperto è uno stato diverso da `/persone` chiuso.
- **Frontier queue** `queue[]` + **visited set** `visited{}` in `crawl_state.json` (persistito
  dopo ogni stato → resumable via `--resume`).
- **State fingerprint** (chiave di dedup): `normURL + "|" + sha(sorted(elementSignatures))`
  dove `normURL` rimuove id/uuid/query volatili (`/[0-9a-f]{8,}/ → :id`, `?focus=…`, `?new=…`)
  e `elementSignature` = `role|testid|label|text[:40]`. Due stati strutturalmente identici
  collassano anche con dati diversi → niente loop su liste di N righe uguali.
- **Action fingerprint** = `stateFingerprint + "::" + elementSignature` → ogni affordance si
  tocca **una volta per stato**, mai in loop.

## Loop di crawl (per stato estratto dalla coda)

1. `playwright_navigate` (waitUntil `domcontentloaded` — NON networkidle, l'app fa polling).
   `playwright_console_logs --clear` per azzerare il buffer (è cumulativo/stale tra navigazioni).
2. Esegui **un solo** `playwright_evaluate` con lo *Universal Probe* (sotto) → ritorna:
   landmarks, violazioni a11y, e l'elenco interattivi **già classificati** (`klass` + `href` + meta).
3. Se `fingerprint ∈ visited` → skip. Altrimenti audit (a11y/landmark/h1), screenshot, marca visited.
4. Per ogni affordance, agisci secondo la sua **classe** (vedi taxonomy). Ad ogni azione:
   wait ~250ms, ricontrolla console, screenshot su errore.
5. Persisti `crawl_state.json`. Rispetta i budget (sotto). HUD a fine stato.

## Taxonomy delle affordance (predici PRIMA di toccare)

| klass | come si riconosce | azione |
|-------|-------------------|--------|
| **internal-nav** | `<a href>` o role=link verso una route app same-origin (`/...` che non è `/api/...`) | enqueue il target come nuovo stato (dedup per fingerprint). Non navighi subito: accodi. |
| **api-anchor** ⚠️ | `<a href>` verso `/api/*`, `api.<host>`, o un path che **non è una route di pagina** | **MAI navigare il browser**. Probe con fetch autenticata `redirect:manual` e classifica la risposta (vedi *regola A-007*). |
| **external** | `mailto:` `tel:` o origin diverso (accounts.google.com, t.me, wa.me) | registra il target + sanity-check della forma URL. **Non** seguire (uscirebbe dall'app). |
| **tab/segmented** | `[role=tab]`, segmented control, side-nav delle Impostazioni | **idempotente e safe** → clicca **ogni** opzione; ogni pannello risultante è uno stato da auditare. (Questa è la superficie di A-007.) |
| **overlay-opener** | bottone senza nav che apre drawer/modale/sheet/popover | clicca → diff DOM per nuovo container overlay → **ricorri dentro** (enumera+audit l'interno) → chiudi (Esc o close-btn) → pop. Cap profondità = `--max-depth` (default 3). |
| **oauth-connect** | `<button>` con label `collega|connetti` il cui handler fa `fetch(auth-url)` → redirect | **safe da cliccare** (non muta il DB, naviga verso il consenso OAuth). Valida: dopo il click ci si aspetta un redirect a un origin **allowlisted** (accounts.google.com, t.me) **oppure** un errore inline (503 "non configurato"). Se invece → pagina vuota / 404 / nessun feedback = finding. *Non* è Phase-7-gated. |
| **mutator** | label/testid match `crea|nuovo|aggiungi|salva|modifica` (escl. `collega/connetti`) | solo in scope `mutative`/Phase 7 e solo **happy-path create** sul tenant seedato. Apri il form, verifica che si apra (no dead-affordance), compila e salva SOLO se autorizzato. |
| **destructive** | match `elimina|cancella|delete|rimuovi|archivia|disconnetti` | **denylist** — apri al massimo il dialog di conferma e poi **annulla**; non confermare mai in autonomo. |
| **cost-action** | match `chiedi a lo studio|genera|crea preventivo studio|invia a tutti|paga|incassa|fattura elettronica|sblocca` | **HARD BLOCK** — non cliccare mai (Lo Studio costa ~$3.20/run Opus+web_search; bulk-send/pagamenti hanno costi/effetti reali). |
| **dead-candidate** | bottone senza nav, senza overlay, non mutator | clicca → dead-affordance detector: nessun cambiamento DOM in 1500ms **AND** nessuna network **AND** nessun console → finding `dead_affordances`. |

### Regola A-007 (api-anchor) — la singola regola che prendeva il bug

**SCOPE CRITICO (raffinato dal dry-run 2026-05-24):** questo verdetto si applica **SOLO agli
elementi di klass `api-anchor`** — cioè un **`<a href>` (o role=link) il cui href punta a un
endpoint API**, perché cliccarlo **naviga il browser** verso quell'URL. NON applicarlo agli
endpoint che vengono chiamati da un handler `fetch` di un `<button>`: quelli ritornano JSON
*per design* (es. `/calendar/auth-url`→`{url}`, `/api/auth/gmail`→`{auth_url}`) e sono corretti —
validali **cliccando il bottone** (vedi `oauth-connect` nella taxonomy), non sondando l'endpoint.
Sondare un fetch-endpoint e gridare "JSON!" è un falso positivo.

Per ogni `api-anchor` (e per ogni `internal-nav` di cui dubiti), fai una fetch autenticata e
classifica:

```js
// in-browser, con il token Clerk — SOLO per href di klass api-anchor
const r = await fetch(href, { headers:{Authorization:`Bearer ${token}`}, redirect:'manual' });
// VERDETTI:
//  - 200 + content-type text/html ............... OK (pagina navigabile)
//  - 0/opaqueredirect/3xx → Location verso origin allowlisted (accounts.google.com, t.me, wa.me) .. OK (OAuth/deeplink)
//  - 404 / 5xx .................................. FINDING raw_endpoint_anchor (HIGH) — blank page
//  - 200 + application/json ...................... FINDING raw_endpoint_anchor (HIGH) — un <a href> qui mostra JSON nudo
//  - 401/403 su endpoint che richiede solo Bearer  → riprova col token; se persiste, nota (può essere atteso)
```

Un CTA utente ("Collega/Apri/Scarica/Connetti/Vai") **reso come `<a href>` verso un endpoint** il
cui href **non produce una pagina navigabile** = `raw_endpoint_anchor`. Questo copre l'intera
classe di "pagina vuota". (Il fix tipico: trasformarlo in un `<button>` che fa fetch-then-redirect.)

## Universal Probe (un solo evaluate, CSP-safe)

`playwright_evaluate` non accetta `return` top-level → **avvolgi in IIFE**. axe-core da CDN è
**bloccato dalla CSP** → NON iniettarlo; usa l'auditor manuale qui sotto (copre le violazioni
WCAG ad alto valore senza dipendenze esterne).

```js
(() => {
  const vis = el => { const r = el.getBoundingClientRect(); return el.offsetParent !== null && r.width > 0 && r.height > 0; };
  const accName = el => (el.getAttribute('aria-label') || el.getAttribute('title')
    || (el.getAttribute('aria-labelledby') && document.getElementById(el.getAttribute('aria-labelledby'))?.innerText)
    || el.innerText || el.value || '').trim();
  const PAGE_ORIGIN = location.origin;
  const klassOf = (el) => {
    const href = el.getAttribute('href') || '';
    const txt = (accName(el) || '').toLowerCase();
    if (/^(mailto:|tel:)/.test(href)) return 'external';
    if (href) {
      let u; try { u = new URL(href, location.href); } catch { u = null; }
      if (u && u.origin !== PAGE_ORIGIN) return 'external';
      if (/^\/api\//.test(href) || /\bapi\./.test(href)) return 'api-anchor';
      if (u && u.pathname.startsWith('/')) return 'internal-nav';
    }
    if (el.getAttribute('role') === 'tab') return 'tab';
    if (/\b(chiedi a lo studio|genera|invia a tutti|paga|incassa|fattura elettronica|sblocca)\b/.test(txt)) return 'cost-action';
    if (/\b(elimina|cancella|delete|rimuovi|archivia|disconnetti)\b/.test(txt)) return 'destructive';
    if (/\b(collega|connetti)\b/.test(txt)) return 'oauth-connect';
    if (/\b(crea|nuov|aggiungi|salva|modifica)\b/.test(txt)) return 'mutator';
    return 'dead-candidate';
  };
  const interactive = Array.from(document.querySelectorAll(
    'button, a[href], input, textarea, select, [role="button"], [role="tab"], [role="menuitem"], [role="switch"], [contenteditable="true"], [onclick]'
  )).filter(vis).map((el, i) => ({
    idx: i, tag: el.tagName, type: el.type || '',
    text: (el.innerText || el.textContent || '').trim().slice(0, 60),
    label: el.getAttribute('aria-label') || el.getAttribute('title') || '',
    testid: el.getAttribute('data-testid') || '', href: el.getAttribute('href') || '',
    role: el.getAttribute('role') || '', disabled: el.disabled || el.getAttribute('aria-disabled') === 'true',
    klass: klassOf(el),
  }));
  // a11y manuale (CSP-safe)
  const nameless = interactive.filter(e => (e.tag === 'BUTTON' || e.href || e.role === 'button') && !e.text && !e.label && !e.disabled);
  const inputsNoLabel = Array.from(document.querySelectorAll('input,textarea,select')).filter(el => {
    if (!vis(el)) return false;
    if (el.getAttribute('aria-label') || el.getAttribute('aria-labelledby')) return false;
    if (el.id && document.querySelector(`label[for="${CSS.escape(el.id)}"]`)) return false;
    if (el.closest('label')) return false;
    return true;
  }).map(el => `${el.tagName}[${el.type || 'area'}] ph=${el.getAttribute('placeholder') || ''}`);
  const ids = {}; document.querySelectorAll('[id]').forEach(e => ids[e.id] = (ids[e.id] || 0) + 1);
  const dupIds = Object.entries(ids).filter(([, n]) => n > 1).map(([k]) => k);
  const hs = Array.from(document.querySelectorAll('h1,h2,h3,h4,h5,h6')).map(h => +h.tagName[1]);
  const headingSkips = []; for (let i = 1; i < hs.length; i++) if (hs[i] - hs[i - 1] > 1) headingSkips.push(`${hs[i - 1]}->${hs[i]}`);
  const danglingAriaControls = Array.from(document.querySelectorAll('[aria-controls]'))
    .flatMap(el => (el.getAttribute('aria-controls') || '').split(/\s+/))
    .filter(id => id && !document.getElementById(id));
  const overlay = document.querySelector('[role="dialog"],[aria-modal="true"],[class*="heet"],[class*="rawer"],[data-state="open"]');
  return {
    url: location.href,
    landmarks: { header: !!document.querySelector('header'), main: !!document.querySelector('main'), nav: !!document.querySelector('nav') },
    h1count: document.querySelectorAll('h1').length,
    lang: document.documentElement.getAttribute('lang'),
    overlayOpen: !!overlay,
    a11y: { nameless: nameless.map(e => e.testid || e.text || e.tag), inputsNoLabel, dupIds, headingSkips, danglingAriaControls },
    interactive,
  };
})()
```

## Boundedness (così "ovunque" non è "per sempre" né "$$$")

- `--max-states` (default 120), `--max-actions` (default 600), wall-clock cap (default 75 min).
- `--max-depth` overlay (default 3). `--crawl fast` = solo internal-nav + tab + api-anchor probe
  (niente overlay-recursion / edge-input); `--crawl exhaustive` (default) = tutto.
- Dedup per state-fingerprint impedisce i revisit; action-fingerprint impedisce i re-click.
- **Idempotenti** (nav, tab, overlay-open/close, api-anchor probe) → esauriscili liberamente.
- **Mutator/destructive/cost** → razionati o bloccati (vedi denylist). Annuncia ogni mutazione
  nell'HUD prima che parta.

## Phase integration

Le vecchie "phase per route fissa" diventano **check applicati ad ogni stato scoperto dal crawl**:
- **a11y** → l'Universal Probe gira ad ogni stato (incl. drawer/tab-panel aperti) → cattura
  `state_gated_a11y` (violazioni visibili solo dopo un'interazione).
- **edge** → su ogni input scoperto (anche dentro overlay), cicla i payload (XSS/`{{7*7}}`/10k/emoji)
  **senza submit** se il submit è un mutator non autorizzato.
- **mutative/Phase 7** → happy-path create per ogni mutator scoperto, sul tenant seedato.
- **responsive** → ri-esegui il crawl (o i top-N stati per findings) ai viewport 375/768/1280/1920.

Phase 1 (public) e Phase 2 (auth) restano i **seed** della frontiera (le route pubbliche + la home
autenticata). Da lì la frontiera cresce sola dai link/tab/overlay trovati — niente lista hardcoded.
