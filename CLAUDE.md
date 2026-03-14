# Claude Code — Master Configuration
# MarcicraM | xXMarcicraMXx

---

## Session Start Checklist
At the start of every session:
1. Read `tasks/lessons.md` if it exists in the current project
2. Read `tasks/todo.md` if it exists — pick up where we left off
3. Identify which gstack skills are relevant for this session's work

---

## Execution Mindset

### Planning
- Enter plan mode for ANY non-trivial task (3+ steps or architectural decisions)
- Write detailed specs upfront — reduce ambiguity before writing a single line
- If something goes sideways, STOP and re-plan immediately. Do not keep pushing.
- Use plan mode for verification steps, not just building

### Subagents
- Use subagents liberally to keep the main context window clean
- Offload research, exploration, and parallel analysis to subagents
- For complex problems, throw more compute at it — one task per subagent
- Subagents receive only the context they need. No pollution.

### Verification
- Never mark a task complete without proving it works
- Ask yourself: "Would a staff engineer approve this?"
- Run tests, check logs, demonstrate correctness
- Diff behavior between main and your changes when relevant

### Code Quality
- **Simplicity First**: Make every change as simple as possible. Minimal code impact.
- **No Laziness**: Find root causes. No temporary fixes. Senior developer standards.
- **Minimal Impact**: Only touch what is necessary. Do not introduce new surface area.
- For non-trivial changes: pause and ask "is there a more elegant way?"
- If a fix feels hacky: "Knowing everything I know now, implement the elegant solution."
- Skip elegance checks for simple, obvious fixes — do not over-engineer.

### Bug Fixing
- When given a bug report: just fix it. No hand-holding required.
- Point at logs, errors, failing tests — then resolve them autonomously.
- Fix failing CI without being told how.

### Self-Improvement
- After ANY correction from the user: update `tasks/lessons.md` with the pattern
- Write rules that prevent the same mistake from recurring
- Review lessons ruthlessly until mistake rate drops

---

## Task Management Protocol

Every non-trivial task follows this sequence:

1. **Plan First** — Write plan to `tasks/todo.md` with checkable items
2. **Verify Plan** — Check in with user before starting implementation
3. **Track Progress** — Mark items complete as you go
4. **Explain Changes** — High-level summary at each meaningful step
5. **Document Results** — Add a review section to `tasks/todo.md` when done
6. **Capture Lessons** — Update `tasks/lessons.md` after any correction

---

## gstack Skills

gstack is installed at `~/.claude/skills/gstack`

Call these explicitly when entering a new phase of work:

| Command | Role | When to use |
|---|---|---|
| `/plan-ceo-review` | Founder / product lens | Before committing to a plan or direction |
| `/plan-eng-review` | Engineering Manager | Architecture decisions, PR reviews |
| `/review` | Staff Engineer | Code review before shipping |
| `/ship` | Release Manager | Automated PR creation and release |
| `/qa` | QA Engineer | Testing and edge case coverage |
| `/retro` | Team retrospective | After completing a feature or session |
| `/browse` | Browser agent | All web browsing — never use MCP Chrome tools directly |

> If gstack skills are not responding: `cd ~/.claude/skills/gstack && ./setup`

---

## Superpowers Skills

Superpowers is installed via the Claude Code plugin marketplace.
Skills trigger **automatically** based on context — let them run before acting.

Key automatic behaviors:
- Brainstorming activates before writing code
- Planning workflow activates when a feature is requested
- Debugging follows a 4-phase root cause process
- Verification runs before marking anything complete

> Do not skip Superpowers skill invocations to save time. They save more time than they cost.

---

## Project Context

This config is maintained at: `github.com/xXMarcicraMXx/claude-config`

To replicate this environment on any machine or the VPS:
```bash
git clone https://github.com/xXMarcicraMXx/claude-config.git ~/claude-config
bash ~/claude-config/setup.sh
```
