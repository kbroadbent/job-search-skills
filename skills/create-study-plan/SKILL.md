---
name: create-study-plan
description: >
  Generate a customized study plan for an upcoming job search through a short interview, then write the plan files into study-plans/{slug}/. Use this skill when the user wants to "create a study plan", "set up a study plan", "plan my prep", "make a 4-week plan for staff backend interviews", or any variation indicating they want a structured prep plan written down. Also use this when the user wants to modify an existing active study plan ("extend my study plan", "add more topics to my plan", "shift my plan to focus on system design"). The skill reads profile.md, insights.md, Story Bank.md, and study-plans/index.md to tailor the plan to the user's strengths, weaknesses, and prior work. It writes plan.md plus per-week files plus an empty progress tracker, updates the study roster, and optionally creates calendar events.
---

# create-study-plan

Build a customized study plan via interview, then write the plan files. Reads existing context to tailor the plan; writes per-week files at the right topic granularity; optionally syncs to calendar.

## Overview

After this skill runs:

- `study-plans/{slug}/plan.md` — overview: target role, duration, weekly themes, daily structure, curated resources, success criteria
- `study-plans/{slug}/week-1.md` through `week-N.md` — per-week breakdowns in **hybrid format**: weekly goals + pacing + topics organized by daily-block category, with checkboxes
- `study-plans/{slug}/progress.md` — empty progress tracker mirroring the plan structure
- `study-plans/index.md` — new row appended for this study
- `config.yaml` — `active_study` set to the new slug
- (Optional) Google Calendar events for each study day

## Step 0 — Verify directory and load context

Before anything else, confirm the job-search directory is set up. Verify these files exist at the target root (use bash with the mounted target path):

- `config.yaml`
- `profile.md`
- `insights.md`
- `Story Bank.md`
- `study-plans/index.md`

If any are missing, the directory hasn't been initialized. Tell the user and offer to run `job-search-init` first. Stop until init completes.

If all present, read each and hold the contents:

- `profile.md` — for target role, strengths, weaknesses, goals, comm style, avoiding
- `insights.md` — for prior learnings (so the plan doesn't reintroduce things already locked in)
- `Story Bank.md` — for category coverage (so early-week story work is sized to fill gaps)
- `study-plans/index.md` — for prior studies (so a new plan complements rather than duplicates)
- `config.yaml` — for `active_study` pointer (drives Step 1)

If `config.yaml` exists but fails to parse as YAML, stop and tell the user the config is malformed — show the parse error and ask them to fix it before re-running. Don't try to repair it automatically; corrupt config could indicate other directory issues.

## Step 1 — Mode detection

Check `config.yaml` for `active_study`.

**If `active_study` is null** → standard create mode. Continue to Step 2.

**If `active_study` is set** → ask the user with AskUserQuestion:

- Question: "You have an active study `{slug}`. Modify it, or create a new plan and archive the current one?"
- Options:
  - "Modify current study" (description: "Adjust durations, topics, or weighting in place")
  - "Create new" (description: "Archive the current study and start fresh")
  - "Cancel" (description: "Stop the skill")

If "Modify current study" → jump to Step 7 (Modify mode flow).

If "Create new" → ask whether to archive the prior study as `Complete` (you finished it) or `Abandoned` (you're switching gears). Use AskUserQuestion. Update study-plans/index.md to set the prior study's status accordingly. Then continue to Step 2.

If "Cancel" → stop cleanly.

## Step 2 — Conduct the interview

Ask each question as a separate user turn. Free-form unless noted.

### Q1: Target role specifics

> Your profile says you're targeting `{profile.target_role}`. Anything to add or refine for this study? Specific company types, infra-heavy vs product-heavy, IC vs management track, etc.

Free-form. Captured into plan.md's overview.

### Q2: Duration

> How long do you have? Number of weeks, or a date range. If you've got a specific interview deadline, give me that and I'll work backward.

Parse the answer into a week count and start/end dates. Default start date is the next weekday. If the user gives a deadline, end date = deadline; start date = deadline minus N weeks (using Q3 schedule for which days count). If they give weeks only, start date = next weekday, end date = computed.

### Q3: Weekly schedule

> Which days of the week? Hours per day? Weekends in or out?

Free-form. Capture as a day-of-week pattern (e.g., "Mon-Fri", "Mon-Thu plus short Fri") and hours-per-day total.

### Q4: Daily structure

> How do you want each day broken up? A common shape is three blocks (algorithms, system design, behavioral / leadership) but I can adapt — fewer blocks, different splits, just one focused block, etc.

Free-form. If the user says "default" or "the common one," use three blocks: Algorithms (90 min) / System Design (105 min) / Behavioral or Leadership (105 min). Otherwise capture what they say.

### Q5: Weighting

> What do you want to weight heavily? Common options: algorithms, system design, behavioral stories, domain depth (AWS / cloud / specific area), leadership / staff-level skills, mock interviews. Or describe in your own terms.

Free-form. This biases the weekly themes — heavier-weighted areas get more weeks of focus.

### Q6: Specific topics or asks (optional, skippable)

> Anything specific you want to cover? Particular companies you're prepping for, specific topics that have come up, weak spots you want to drill?

Skippable.

### Q7: Calendar integration (constrained)

Use AskUserQuestion:

- Question: "Want me to add the daily blocks to your Google Calendar? I'll create events for each study day."
- Options:
  - "Yes — add to calendar" (description: "Requires Google Calendar via gws CLI")
  - "Skip — just write the plan files" (description: "I can add to calendar later if I want")

### Q8: Slug confirmation (constrained)

Auto-generate a slug from role + duration. Examples:

- "staff backend at infra-heavy companies" + 4 weeks → `staff-backend-4wk`
- "senior frontend, consumer products" + 6 weeks → `senior-frontend-6wk`
- "engineering manager, midstage startup" + 8 weeks → `em-midstage-8wk`

**Check uniqueness against `study-plans/index.md` before showing the question.** If the auto-slug collides with any existing slug (active, complete, or abandoned), append `-2`, `-3`, etc. until unique. Reflect the deduplicated slug in the AskUserQuestion text.

Use AskUserQuestion:

- Question: "I'll save this plan as `{auto-slug}`. Use that name, or pick something different?"
- Options:
  - "Use suggested slug" (description: "{auto-slug}")
  - "Pick a different name" (description: "I'll prompt for a custom slug")

If "Pick a different name", prompt the user for a slug. Validate:

- Lowercase
- No spaces (hyphens instead)
- No slashes
- Not already in `study-plans/index.md` (collision check; if it collides, tell the user and re-prompt)

## Step 3 — Generate the plan

Use Claude's training plus the loaded context (profile, insights, Story Bank, study-plans/index) to generate the plan content. Follow the procedure below — it's load-bearing for plan quality.

### Generation procedure

1. **Compose role context.** Combine `profile.md` Target Role + Q1 specifics into a single role description sentence. This shapes everything downstream. Example: "Staff backend engineer at infrastructure-heavy companies, IC track, distributed systems focus."

2. **Score prep dimensions.** For each of: algorithms, system design, behavioral stories, domain depth, leadership. Weight by:
   - Q5 (user-stated weights) — primary signal
   - profile.md Weaknesses — adds weight to weak dimensions
   - insights.md Areas Needing Attention (if non-empty from prior studies) — adds weight to recurring weak spots
   
   Heavier-scored dimensions get more weeks of focus.

3. **Compute weekly distribution.** For N weeks:
   - W1 = Foundation (baselines, story bank inventory, core DS&A categories, SD primer fundamentals)
   - W2 through W(N-2) = Deep dives on the heavy-weighted dimensions, one or two dimensions per week
   - W(N-1) = Staff-level depth + leadership polish
   - W(N) = Mock interviews + gap fill + polish
   
   For short durations (≤3 weeks), compress: combine foundation and one deep-dive into W1, push mocks earlier. For tracks like EM where leadership is primary, leadership starts W1 instead of W(N-1).

4. **For each week, assign topics to block-categories from Q4.**
   - Use the Topic granularity table — topics at the **right level** column.
   - Each block within a week gets 4-7 topic checkboxes. More than 7 overstuffs the week; fewer than 4 underuses the time.
   - Foundation week algorithm topics: classic categories like two pointers, sliding window, BFS/DFS, binary search, hashmaps.
   - Deep-dive week SD topics: specific designs (distributed cache, rate limiter, notification system, etc.).
   - Staff-level week topics: org-scale design, cross-team influence scenarios, complex distributed systems (collab editing, payments, multi-region).
   - Mock week topics: specific mock formats (see Mock interviews section below).

5. **Wire story bank.** Read Story Bank.md status. If 0-3 of 12 categories are drafted, W1 includes a story-drafting block targeting 5-8 starter stories by week end. If 8+ are drafted, W1 focuses on delivery practice (3 reps with feedback) plus role-specific gap drafts.

6. **Pull resource list** from the per-role section below. Tweak based on what the user mentioned in Q6.

7. **Build mock week (W(N)).** Compute 4-5 specific mock dates working backward from the plan's end date, using Q3's day-of-week pattern. See Mock interviews section.

8. **Write success criteria** — 3-5 bullets reflecting role and weights. See Success criteria section.

### Topic granularity (load-bearing)

Topics are specific enough to be actionable but not so specific that they lock in the exact exercise. Study-session picks the concrete exercise at runtime.

| Too abstract | Right level | Too specific |
|--------------|-------------|--------------|
| "System Design" | "Distributed cache design" | "Design Facebook comments end-to-end" |
| "Algorithms" | "Heaps and priority queues — 2-3 problems" | "LC 215 Kth Largest Element" |
| "Stories" | "Draft 5 starter stories from the bank prompts" | "Write the Buildkite migration story" |
| "Backend skills" | "AWS deep dive: ECS vs EKS, Lambda cold starts, DynamoDB" | "Build an EKS cluster with Terraform" |

Generate at the **right level** column.

### Weekly themes

Distribute themes across N weeks. Default progression for engineering-track plans (adapt for other tracks):

- **W1: Foundation** — baselines, story bank inventory, core DS&A categories, SD primer fundamentals
- **W2 through W(N-2): Deep dives** — heavy-weighted areas from Q5
- **W(N-1): Staff-level depth and leadership** — multi-team influence, complex systems, behavioral polish
- **W(N): Mock interviews and polish** — pressure-test in interview-shaped sessions, gap fill

Adapt for shorter durations (compress foundation), other tracks (EM-track leads with leadership from W1), or weights that demand more depth time.

### Story bank wiring

Read Story Bank.md before writing W1:

- If most categories are empty → W1 includes a meaningful story-drafting block (target: cover at least 8-10 stories by end of W1).
- If categories are mostly drafted → W1 focuses on delivery practice (story reps with feedback) and only adds new drafts for role-specific gaps.

### Resources

Include a "Suggested resources" section in plan.md, curated and opinionated based on role and weights:

- **Staff backend / infra**: NeetCode 150, System Design Primer (donnemartin/system-design-primer), ByteByteGo, Designing Data-Intensive Applications, Staff Engineer's Path
- **Senior frontend**: NeetCode 150, frontend-specific system design references (Sandeep Kumar's "Frontend System Design"), build-tools deep dive
- **Engineering manager**: The Manager's Path, Resilient Management, Apprenticeship Patterns, Staff Engineer's Path (read selectively)
- **Senior product manager**: Decode and Conquer, Cracking the PM Interview, role-specific product sense practice
- **Founding engineer / CTO**: The Hard Thing About Hard Things, Building a Second Brain (knowledge management), targeted technical refresher

Generate role-appropriately. Include the line: "Swap any of these for a preferred alternative — these are starting points, not requirements."

### Mock interviews (final week)

Schedule explicit mocks in W(N), each on a specific day:

- Coding mock (45 min, NeetCode 150 hard or role-equivalent)
- System design mock (45 min, role-relevant scenario)
- Behavioral round (4-5 stories with debrief)
- Recruiter-screen simulation
- (Optional) full interview loop simulation

### Success criteria

3-5 bullets at the end of plan.md describing what "done" looks like for this study. Used by study-session to gauge progress. Examples:

- "All 12 story bank categories drafted with rehearsed delivery"
- "Comfort with 8 system design archetypes (cache, queue, rate limiter, notification, ride-sharing, payments, real-time collab, data pipeline)"
- "20+ algorithm problems solved across major patterns; one timed mock per week from W2 onward"

## Step 4 — Write the artifacts

Create the study directory:

```bash
mkdir -p "{bash-target}/study-plans/{slug}"
```

Write each file using the Write tool with the host filesystem path. Use the templates in `references/templates.md`. Substitute interview answers and generated content.

Order:

1. `study-plans/{slug}/plan.md`
2. `study-plans/{slug}/week-1.md` through `week-N.md` (one per week)
3. `study-plans/{slug}/progress.md` (initial empty tracker mirroring the plan)
4. `study-plans/index.md` — append a row for this study
5. `config.yaml` — set `active_study: "{slug}"`

If any Write fails, halt and report the failure; don't try to roll back.

### Template references

Inline templates follow. Substitute placeholders with interview answers and generated content. Lists with examples (resources, success criteria, mock days) get filled with the role-appropriate content from Step 3.

#### `study-plans/{slug}/plan.md`

```markdown
# {Plan Name}

**Slug:** {slug}
**Target role:** {Q1 answer + profile.target_role}
**Duration:** {N} weeks ({start date} – {end date})
**Schedule:** {Q3 — days, hours per day}
**Daily structure:** {Q4 — block list with target times}

## Focus areas

{Q5 weighted areas, plus inferred areas from profile.md weaknesses and insights.md weak spots}

## Weekly themes

| Week | Dates | Theme |
|------|-------|-------|
| W1 | {dates} | {theme} |
| W2 | {dates} | {theme} |
| ... | ... | ... |
| WN | {dates} | Mock interviews & polish |

## Suggested resources

{Curated role-appropriate resource list}

Swap any of these for a preferred alternative — these are starting points, not requirements.

## Success criteria

By the end of this study:

- {Criterion 1}
- {Criterion 2}
- {Criterion 3}

## Notes

{Q6 specific topics or asks, if any}

→ Per-week detail: `week-1.md`, `week-2.md`, ..., `week-{N}.md`
```

#### `study-plans/{slug}/week-N.md` (weeks 1 through N-1)

```markdown
# Week {N}: {Theme}

**Dates:** {start} – {end}
**Goals:** {1-2 sentences on what this week is meant to lock in}
**Pacing:** ~{D} days × {block list from Q4}

## {Block 1 name} (target: ~{X} hrs/day)
- [ ] {Topic 1 at right granularity}
- [ ] {Topic 2 at right granularity}
- [ ] {Topic 3 at right granularity}

## {Block 2 name} (target: ~{X} hrs/day)
- [ ] {Topic 1}
- [ ] {Topic 2}

## {Block 3 name} (target: spread across week)
- [ ] {Topic 1}
- [ ] {Topic 2}

## Weekly checkpoint

End-of-week reflection prompts:
- What landed?
- What didn't?
- What carries into next week?
```

#### `study-plans/{slug}/week-{final}.md` (the mock-interview week)

```markdown
# Week {N}: Mock Interviews & Polish

**Dates:** {start} – {end}
**Goals:** Pressure-test in interview-shaped sessions; close remaining gaps surfaced through prior weeks.

## Scheduled mocks
- [ ] {Weekday + date, e.g., "Mon, Mar 23"} — Coding mock (45 min, NeetCode 150 hard or role-equivalent)
- [ ] {Weekday + date} — System design mock (45 min, role-relevant scenario)
- [ ] {Weekday + date} — Behavioral round (4-5 stories with debrief)
- [ ] {Weekday + date} — Recruiter-screen simulation
- [ ] (Optional) {Weekday + date} — Full interview loop simulation

The {Weekday + date} placeholders are computed from the plan's end date working backward, using Q3's day-of-week pattern. Spread the mocks across the working days of the final week so the user has a clear schedule.

## Gap fill (target: spread across week)
- [ ] {Specific items pulled from insights.md weak spots and accumulated progress.md areas-needing-attention}

## Polish
- [ ] Story delivery dry runs for top 5 stories
- [ ] Resume final review
- [ ] Communication style review against profile.md
```

#### `study-plans/{slug}/progress.md`

```markdown
# Progress — {Plan Name}

**Status:** Active
**Started:** {start date}

## Weekly progress

### Week 1: {Theme}
{Same checkbox structure as week-1.md, all unchecked}

### Week 2: {Theme}
{Same checkbox structure as week-2.md, all unchecked}

...

### Week {N}: Mock Interviews & Polish
{Same checkbox structure as the final week file, all unchecked}

## Areas Needing Attention

(Empty — populated by study-session as recurring patterns and gaps surface. Cross-study durable items get promoted to insights.md.)

## Session log

| Date | Day | Activities | Observations |
|------|-----|------------|--------------|
| (empty) | | | |
```

#### `study-plans/index.md` — appended row

When appending, replace the placeholder row if it's still the only content:

```
| {slug} | {Plan Name} | Active | {start date} | {end date} | (empty until archived) |
```

If the index already has other rows, append to the bottom.

#### `config.yaml` — update active_study

Read the existing config.yaml, update only the `active_study` field, write back:

```yaml
active_study: "{slug}"
```

## Step 5 — Calendar integration (if Q7 was Yes)

If the user opted into calendar integration, the work is provider-specific. Read the `calendar` field from `config.yaml` first and dispatch on `provider`.

### Step 5a — Read calendar config and dispatch

Possible shapes (set by `job-search-init`):

- `calendar` is `null` → no provider configured. Tell the user briefly and offer one of: "Pick a provider for this plan only" / "Skip calendar for this plan" via AskUserQuestion. If they pick a provider for this plan, run the per-provider flow below but don't write back to config (one-off).
- `calendar.provider == "google"` → run the Google flow in Step 5b.
- `calendar.provider` is anything else (e.g., `"outlook"`, `"apple"`, a custom string) → tell the user: "Your config is set to `{provider}`, which I don't currently know how to write events to. Skipping calendar for this plan — the plan files are written and useful on their own." Skip the rest of Step 5.

When new providers gain support, add a branch here. The dispatch is the only place the skill cares about provider identity.

### Step 5b — Google Calendar flow

1. **Verify gws CLI is available**: bash `which gws`. If not, tell the user: "Calendar integration is set to Google but the `gws` CLI doesn't seem to be installed. The plan files are written and useful on their own — you can re-run once gws is set up." Skip the rest of this step but don't fail the skill.

2. **Determine the target calendar.**

   - **If `calendar.id` is set** (the normal case — picked during `job-search-init`): use it directly. Don't re-prompt the user. Mention `calendar.name` in the summary at the end of this step.
   - **If `calendar.id` is null** (user picked Google at init but skipped specific-calendar selection, or `gws` was unavailable then): run `gws calendar list` and present the calendars via AskUserQuestion. Option title = name, description = id. Always include a final option "Skip calendar for this plan." After the user picks, ask one follow-up with AskUserQuestion: "Save this calendar choice to `config.yaml` so other skills use it too?" with options "Yes — save" / "No — just for this plan." If yes, edit `config.yaml` to set `calendar.name` and `calendar.id` (preserve `calendar.provider`).
   - **If `gws calendar list` errors** (auth not set up, network failure): tell the user briefly and skip the rest of this step. Don't fail the skill.

3. **Generate the event list**. For each study day (computed from start date + Q3 day-of-week pattern), build an event:
   - Title: `{Plan Name} — W{n}D{m}: {Q4 block 1 short name}`
   - Date/time: study day + Q4 first block start time; duration covers all Q4 blocks for the day
   - Description: bulleted list of the week-N.md topics for that day's blocks (synthesized at this step from the topics distributed across the week)

4. **Create events** via `gws calendar create-event` (or equivalent), one per study day, targeting the calendar id from step 5b.2. Track successes and failures.

5. **Report**: "{X} events created on {calendar name}." If any events failed, list which ones and why; the user can retry or add manually.

## Step 6 — Summarize and finish

Print a short summary:

```
Study plan created: {Plan Name}

Slug: {slug}
Duration: {N} weeks ({start} – {end})
Daily structure: {block list}

Files written:
  study-plans/{slug}/plan.md
  study-plans/{slug}/week-1.md ... week-{N}.md
  study-plans/{slug}/progress.md
Updated:
  study-plans/index.md
  config.yaml (active_study set)

{If calendar integration ran:} Calendar events: {N} events on {calendar name}.

Next: run `study-session` to start your first session against this plan.
```

## Step 7 — Modify mode flow (when Q1 mode was "Modify")

Skip the standard interview. Instead ask:

> What do you want to change in `{active_slug}`? Adjust durations, drop or add topics, shift weighting, or something else?

Free-form. Then ask follow-ups based on what they said:

- **Extend duration** → "How many more weeks? What goes in those weeks — more depth on existing themes or new themes?"
- **Drop topics** → "Which topics? Skipping them entirely or moving to a future plan?"
- **Add topics** → "Which topics, and which weeks should they go in?"
- **Shift weighting** → "Which areas need more time, and what gets cut to make room?"
- **Out of scope** (target role change, fundamental restructure) → tell the user this is a "create new" case; offer to archive and start fresh with a regular create flow. If they agree, return to Step 1 with archive + create.

For in-scope changes, apply this algorithm:

1. **Read current state**: `study-plans/{active}/plan.md` (overview), each `week-N.md` (topic checkboxes), and `progress.md` (which checkboxes are already done).

2. **Compute the change set** based on the user's request:
   - **Extend duration by D weeks**: new total weeks = current N + D. New end date = current end + D × (working days per week from Q3's pattern). The new weeks slot in front of W(N) — i.e., the existing W(N) (mock week) stays last; the added weeks go in as W(N), W(N+1), etc., bumping the mock week to the new final position.
   - **Drop topic T from week W**: locate the checkbox in `week-W.md`. If unchecked, remove. If checked (already done in progress.md), leave the checkbox in week-W.md but note "(removed from plan)" inline so the work stays attributed.
   - **Add topic T to week W**: append a checkbox under the relevant block-category section of `week-W.md`. If `week-W.md` doesn't have that block-category, add it.
   - **Shift weighting from area A to area B**: for the remaining weeks (those not yet fully completed), re-balance topics — drop or compress A topics, add or expand B topics. Use the same right-level granularity rule.

3. **Apply the change set**:
   - Rewrite `plan.md` Weekly themes table to reflect new dates and themes.
   - Rewrite each affected `week-N.md` with the new topic list.
   - For added weeks, write fresh `week-N.md` files using the standard hybrid template.
   - **Do not touch `progress.md`** — completed checkboxes stay attributed. Append one row to its session log:

   ```
   | {today's date} | (modify) | Plan modified — {short description, e.g., "extended +2 weeks"} | {user rationale if given} |
   ```

4. **Update `study-plans/index.md`** row for the active study if the End date changed.

5. **Print a summary** of what changed: what was added, dropped, or shifted, and the new end date if applicable.

## Notes for implementation

- **Tone**: This is a planning conversation, not a coaching one. Keep prompts short. Accept short answers. Don't editorialize the plan as you generate it — just produce it.

- **Don't pre-cram week files**: Each week file is a topic outline, not a tutorial. Topics are at the right granularity (see Step 3 table). Aim for 4-7 checkboxes per block per week; more than that and the week is overstuffed.

- **Profile and insights are inputs to plan generation, not just retrieval targets**: A staff candidate with `Areas Needing Attention` in `insights.md` listing "Bloom filters unknown" should see "Bloom filter design and use cases" in W2 or W3 system design topics. Don't list weaknesses passively in plan.md — bake them into the topic selection.

- **Don't reload prior studies' progress.md unless asked**: study-plans/index.md gives the one-line summary of past studies. That's enough for plan generation. Reading every prior progress.md is overkill and will balloon context.

- **Slug uniqueness**: Before locking the slug in Step 2/Q8, check `study-plans/index.md` for collision. If `{auto-slug}` is taken, append `-2` or similar. If user picks a custom slug that collides, tell them and ask again.
