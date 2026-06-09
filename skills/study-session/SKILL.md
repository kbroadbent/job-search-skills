---
name: study-session
description: >
  Run a single daily prep session against the user's active study. Use this skill when the user wants to "do prep", "start a study session", "let's do interview prep", "what's on the agenda", "today's study", "let's get started", or any variation that implies they want to work through their active study plan today. Also triggers when the user says "let's wrap up", "I'm done for today", or "close out" after working — the skill handles both the start of a session and the close. The skill loads the active study's plan and progress, briefs the user on today's recommended focus, coaches through the topics they pick (with block-aware shapes for algorithms, system design, and behavioral practice), then writes back to progress.md, insights.md, and CLAUDE.md when the session ends. Reads profile.md for coaching tone and the companies/ directory for upcoming-interview context.
---

# study-session

Run one prep session: load context, brief, coach through the topics, then write back what was covered and what was learned. Three phases — start, work, close — with the close step being the load-bearing one because that's where memory accumulates.

## Overview

This is the workhorse skill of the plugin. The user runs it most days during an active study. After each run:

- `study-plans/{active}/progress.md` — checkboxes ticked for completed topics, a session log row appended, Areas Needing Attention updated
- `study-plans/{active}/week-{current}.md` — checkboxes synced with progress.md
- `insights.md` — appended only when a learning is durable (recurring across sessions or obviously cross-study)
- `CLAUDE.md` — one session log line appended
- `Story Bank.md` — only if a new story emerged and the user opted to add it

## Step 0 — Verify directory and load context

Identify the job search root directory. If the user has a workspace folder mounted, that's the target — discover it with `find /sessions/*/mnt -maxdepth 1 -type d` (bash). The job search root is the folder containing `config.yaml` at its top level. If there are multiple mounted folders, find the one with `config.yaml`. If none has `config.yaml`, the user hasn't initialized — tell them and offer to run `job-search-init`.

Once the target is identified, hold the host path (for file tools, e.g., `/Users/.../2026 Job Search`) and the bash-mounted path (e.g., `/sessions/*/mnt/2026 Job Search`) — both are needed.

Verify the always-loaded files exist:

- `config.yaml`
- `profile.md`
- `insights.md`
- `CLAUDE.md`
- `study-plans/index.md`

If any are missing, the directory hasn't been initialized. Tell the user and offer to run `job-search-init` first. Stop until init completes.

If `config.yaml` exists but fails to parse as YAML, stop and tell the user the config is malformed — show the parse error. Don't try to repair.

Read each file. Hold the contents for the rest of the session.

Read `config.yaml` for `active_study`:

- **If `active_study` is null** → there's no active study. Tell the user and offer:
  - "Run `create-study-plan` to set one up"
  - "Do an off-plan session anyway" — coach through whatever the user wants. Skip all writebacks except a one-line entry to `CLAUDE.md`.
  - "Stop"

  Use AskUserQuestion. If they pick off-plan, jump to Step 4 (working session) without Steps 1-3, then jump to Step 8 with reduced writeback.

- **If `active_study` is set but `study-plans/{slug}/` does not exist** → tell the user the config references a missing folder. Offer to null `active_study` and run `create-study-plan`, or to stop. Don't proceed with a broken active study.

- **If `active_study` is set and the folder exists** → continue.

Read the active study's files now:

- `study-plans/{active}/plan.md` — start date, end date, schedule, weekly themes, daily structure, success criteria
- `study-plans/{active}/progress.md` — current checkbox state, Areas Needing Attention, session log

The current `week-{N}.md` file gets loaded in Step 1 once the current week is computed.

## Step 1 — Determine where in the plan we are

Run `date` (bash). It returns local time including timezone abbreviation — that's the source of truth for "what day is today." No separate timezone config needed.

Parse `plan.md` for:

- Start date
- End date
- Schedule (e.g., "Mon-Fri", "Mon-Thu plus short Fri")
- Total week count

Compute today's status:

- **Before start date** → tell the user how many days until kickoff. Offer light pre-work options (story drafting from Story Bank.md gaps, reading the SD primer, language warm-up). If they pick pre-work, run a minimal session: jump to Step 4 with the chosen topic, then Step 8 with reduced writeback (no progress.md updates, just a CLAUDE.md log line).
- **After end date** → tell the user the plan ended N days ago. Offer:
  - "Archive the study and start fresh" → archive the study (Step 9 archive flow) and recommend `create-study-plan`
  - "Keep going off-plan" → continue with off-plan coaching, full writeback to progress.md
  - "Just close out today" → stop cleanly
- **Non-study day** (today's day-of-week is not in the schedule pattern) → acknowledge the rest day. Ask if the user wants optional light prep or stop. If light prep, run a minimal session.
- **Study day** → compute Week N and Day M. Algorithm:
  - Week N = `floor((today - start_date) / 7) + 1`, counted in calendar weeks from start.
  - Day M = the position of today within week N's working days, counted from the first day of the schedule pattern. If the schedule is Mon–Fri and today is Thursday, Day M = 4. If the schedule is Mon–Thu plus short Fri and today is Friday, Day M = 5. Skip days that aren't in the pattern.
  - Total study days = `weeks × working_days_per_week`. Display "W{n}D{m} of {total}" in the brief.
  - If today is in a study week but on an off-pattern day (weekend during a Mon–Fri plan), treat as a non-study day above.

After computing N, **read `study-plans/{active}/week-{N}.md`** — that's the current week's topic file. Continue to Step 2.

### Same-day re-invocation check

Scan `progress.md`'s session log table for a row with today's date. If one exists, ask via AskUserQuestion:

- Question: "You ran a session earlier today on {topics from the existing row}. Continue from there, or start fresh?"
- Options:
  - "Continue from earlier" (description: "Updates today's existing session log row")
  - "Start fresh" (description: "Appends a new session log row")

Hold the choice for Step 8.

## Step 2 — Brief the user

Print a short, scannable brief. Don't dump the week file.

```
**Week {N}, Day {M} of {total study days} — {today's date, weekday spelled}**

Week {N} theme: {theme from plan.md weekly themes table}

Daily blocks (from plan.md daily structure):
  • {block 1 name} ({target time/duration})
  • {block 2 name} ({target time/duration})
  • {block 3 name} ({target time/duration})

Suggested focus today (next unchecked in week-{N}.md):
  • {block 1}: {first 1-2 unchecked topics}
  • {block 2}: {first 1-2 unchecked topics}
  • {block 3}: {first 1-2 unchecked topics}

{If progress.md "Areas Needing Attention" has high-priority recurring items, surface up to 3:}
Watch list (from Areas Needing Attention):
  • {item 1, terse}
  • {item 2, terse}

{If Story Bank.md has empty categories that this study should fill, mention once:}
Story Bank gap: {N} categories still empty.

Where do you want to start? Or skip the suggested topics and tell me what you want to work on.
```

The "Suggested focus" is a starting point, not a prescription. The user can override.

## Step 3 — User picks the starting block / topic

Free-form response. Common shapes:

- "Let's do block 1" or "algorithms first" → start with the first unchecked topic in that block. Confirm the topic before diving in.
- "I want to work on {specific topic}" → check whether it's in the plan; if yes, run it; if not, note it's off-plan and run it anyway. The user is the boss.
- "Just stories today" → skip block rotation; focus only on behavioral.
- "I only have an hour" → propose a single-block, single-topic shape with minimal close.
- "What do you recommend?" → pick the topic that drills the most-recurring item in progress.md's Areas Needing Attention. Explain the choice in one sentence.
- **Anything else that doesn't map to a named block** (e.g., "let's do AWS deep dive this week", "review my resume", "talk about my offer strategy") → treat as off-plan. Note `(off-plan)` in the session log row in Step 8. Proceed to Step 4 with the general coaching shape (defined under "General coaching" below).

Track mentally what gets touched, completed, or skipped as the session unfolds.

## Step 4 — Working session

The shape changes by block type. Determine the block type from the plan's daily structure plus the topic itself. The four shapes are: **Algorithm**, **System Design**, **Behavioral**, and **General** (the fallback). Match by name/keyword — "Algorithms" or "Coding" → Algorithm; "System Design" or "Architecture" → System Design; "Behavioral", "Stories", or "Leadership" → Behavioral; anything else → General.

### Algorithm coaching

- Ask which exact problem before any code. If the user says "you pick," choose one that matches the topic and the user's profile — bias toward problems that drill weak spots from progress.md's Areas Needing Attention. Don't pick problems they've already solved cleanly in this study (check progress.md session log).
- Let the user talk through the approach **before** coding. Ask clarifying questions like an interviewer: "What's the input range?" "Are there duplicates?" "Do you need to mutate the input?"
- After they write code, give direct feedback on:
  - Time and space complexity (correct, with reasoning, not hand-waved)
  - Edge cases missed
  - Communication clarity
  - Anything a staff-level interviewer would flag (e.g., bug introduced by a typo, suspicious complexity claim, missing tests)
- Reference `profile.md` "communication style" for tone. Default to direct feedback on weaknesses; soften only if profile.md asks for it.
- For timed mocks: 45 minutes, no hints, full debrief after.

### System design coaching

- Force a requirements pass before any architecture. Ask:
  - "What are the functional requirements?"
  - "What scale are we designing for?" (request rate, data size, user count)
  - "What's load-bearing — what does this system need to be good at?"
  Don't let the user skip this. Five to ten minutes here is non-negotiable.
- After the design: probe like an interviewer. Challenge choices. Push back on hand-waved bottlenecks. Ask the questions a real interviewer would: "What happens if this service goes down?" "Why this database and not another?" "How do you handle a hot key?"
- For staff-level studies: explicitly push the staff-framing layer. Ask about each of:
  - Build vs buy decision
  - Org dependencies and team boundaries
  - Multi-quarter sequencing and migration strategy
  - Operability (oncall surface, debuggability, deployment safety)
  - Cost (storage tier choice, fleet sizing, network egress)
  If the user doesn't bring these up, ask about them one at a time.
- Flag silences as gaps: "You didn't discuss failure modes" beats letting it slide.
- **Capacity estimation rule.** The test is whether the math drives a decision, not whether the math happens. Flag both directions:
  - User did capacity estimation but didn't use the numbers anywhere → call out the unused work. Estimation as a checkbox is worse than skipping it.
  - User made a decision that depended on capacity (chose a storage tier, sized a fleet, picked sync vs async) without doing the estimation that would have grounded it → push for the estimation that should have anchored the choice.
  Don't push for estimation when nothing downstream depends on it.

### Behavioral / story practice

- For drafting a new story: walk through STAR. Push for:
  - Situation in 30 seconds
  - Action takes most of the time
  - Result is specific and quantified
  - Org-level impact for staff stories (the differentiator from senior)
  - Total under 3 minutes
- For delivering an existing story: ask the user to deliver it as if speaking to an interviewer. Evaluate against the same criteria above plus:
  - "I" not "we" in action sections (use of "we" is the most common slip)
  - No editorialized lesson at the end ("the takeaway was..." — let the result speak)
  - Close lands cleanly (doesn't trail off mid-sentence)
- Give line-level feedback. "Your result said 'reduced latency' — what was the before-after number?" beats "results need numbers."
- If a new story emerges unprompted during the session, note it for Step 8 (offer to add to Story Bank).

### General coaching (fallback shape)

For blocks or topics that don't fit Algorithm / System Design / Behavioral — domain deep dives, resume review, offer strategy, career planning, etc. — apply this shape:

- Open with a clarifying question: "What's the specific outcome you want from this block?"
- Push for depth, not breadth. If the user covers something hand-wavily, ask one specific follow-up to surface the operational layer.
- Flag gaps proactively. If the user describes a system, architecture, or decision, ask the questions a staff-level interviewer would: failure modes, tradeoffs, alternatives considered.
- Don't pretend to coach a topic you can't coach (e.g., a vendor-specific tool you have no information on). Say so plainly and offer to discuss what you do know around it.
- Track what's covered for the Step 8 writeback the same as named blocks.

### Cross-block coaching principles

- Direct feedback by default. Don't sugarcoat. Specific over generic.
- AWS / domain depth questions: push for operational specificity. "Runs on EKS" is too thin; surface the staff-level operational layer (deployment shape, scaling story, oncall implications).
- Track what gets completed mentally. The Step 8 writeback depends on accurate tracking.

## Step 5 — Detect wrap-up

Watch for explicit wrap-up signals: "let's wrap up", "I'm done for today", "that's all", "let's close out", "stop here", "tap out".

If the session has been long (more than ~2 hours of coaching) and the user hasn't signaled wrap-up, you can offer one: "Want to keep going or wrap up here?"

If the user goes silent for an unusually long stretch and signals they're done without a real recap, write a minimal session log row noting "no debrief" rather than fabricating coverage.

## Step 6 — Recap

Briefly summarize what was covered. Format:

```
Today's session:
  • {topic 1}: {one-line on what happened — solved cleanly, struggled with X, drafted, etc.}
  • {topic 2}: ...
  • {topic 3}: ...

Anything I missed or got wrong about the session?
```

The recap is also where the user can flag observations the agent missed. Wait for confirmation or correction before writing.

## Step 7 — Decide what gets written back (routing rule)

For each thing covered, route per the locked memory model rule:

| Observation | Lands in |
|-------------|----------|
| Topic done well | check the box in `progress.md` and the matching `week-{N}.md` |
| Topic touched but not finished | leave unchecked; mention in session log row |
| Recurring weak spot or new gotcha specific to this study | append to `progress.md` Areas Needing Attention |
| Same gap already noted in this study's `progress.md` Areas Needing Attention from a prior session, OR obviously cross-study durable (language syntax rule, AWS service distinction, story delivery pattern) | promote to `insights.md` and remove from `progress.md` |
| Item the user demonstrably resolved this session | move to a "Resolved this study" sub-section in `progress.md` (don't delete) |
| One-line summary of the session | append to `CLAUDE.md` session log |
| New story drafted | offer to add to `Story Bank.md` |
| Stable identity change (rare — e.g., user explicitly says "actually I'm targeting EM now") | prompt before writing to `profile.md` |
| Study completion (all checkboxes ticked across all weeks) | trigger archive flow (Step 9) |

The boundary between progress.md Areas Needing Attention and insights.md: progress.md captures every observation; insights.md is where recurring, durable patterns get promoted. Default to writing to progress.md. Only promote to insights.md when (a) the same item is already in this study's Areas Needing Attention from a prior session (you can see it in the loaded progress.md), or (b) the observation is obviously cross-study durable. Counting across past studies is out of scope — you only see this study.

**Detecting "demonstrably resolved":** an item counts as resolved only when the user *explicitly says* during the recap (Step 6) that the issue is fixed, OR you observed the user apply the previously-failing pattern correctly during this session. If you're unsure, leave the item in Areas Needing Attention. Be conservative — wrongly marking something resolved is worse than letting it linger.

Don't double-write — once an item is in insights.md, it shouldn't also live in progress.md unless the current study is actively drilling it.

## Step 8 — Write the updates

Read each target file with the Read tool, edit with Edit (not Write — preserve everything else), in this order:

1. **`progress.md`** — main writeback target
   - **Tick checkboxes** for completed topics. Find the line `- [ ] {Topic}` under the relevant `### Week {N}: {Theme}` heading and the relevant block sub-heading. Use the surrounding section header in the `old_string` to disambiguate — if the same topic name exists in two weeks (e.g., "Story reps"), include enough context (week heading + block heading + the prior unchecked line) so Edit's old_string is unique. Replace with `- [x] {Topic}`. If the topic doesn't match a planned line exactly (user worked on something close but not identical), do not check the canonical box. Either:
     - Append a child line under the closest topic: `  - {what they actually did}`, or
     - Add to an "Off-plan covered" sub-section at the end of that week's section in progress.md (create the sub-section if missing).
   - **Append a session log row** at the bottom of the existing session log table. Format:
     ```
     | {YYYY-MM-DD} | W{n}D{m} | {topics covered, terse, comma-separated} | {one-sentence observation} |
     ```
     If today is off-plan (rest day, before start, after end), use `(off-day)` or `(off-plan)` instead of `W{n}D{m}`.
     - To find the append point: locate the table header `| Date | Day | Activities | Observations |` and the separator row, then append after the last data row. If the table contains only the placeholder row `| (empty — session log starts when study-session runs) | | | |`, replace that placeholder row with the new row instead of appending.
   - **Same-day re-invocation handling (branch on Step 1's choice)**:
     - If the user picked **"Continue from earlier"** in Step 1: find today's existing session log row by matching `YYYY-MM-DD`. Use Edit to replace the entire row with the merged version (combine the prior topics with this session's topics, refine the observation to cover both). Do not append a new row.
     - If the user picked **"Start fresh"** in Step 1: append a new row as described above. The earlier same-day row stays where it is.
     - If there was no same-day row in Step 1: append normally.
   - **Append/update Areas Needing Attention.** Each item:
     - Lead with the rule or gap (one bold sentence)
     - Add `**Why:**` clause if there's a reason worth keeping
     - Add `**How to apply:**` clause if there's an actionable trigger
   - **For items the user resolved this session**: move them from the active Areas Needing Attention list to a `### Resolved this study` sub-section under Areas Needing Attention. Create the sub-section header if it doesn't exist. Don't delete the item — keeping resolved items visible is the point. See "Detecting demonstrably resolved" criteria from Step 7.

2. **`study-plans/{active}/week-{N}.md`** — sync checkboxes
   - For every box ticked in progress.md, tick the corresponding box in week-N.md.
   - Don't add Off-plan or session-log content here. week-N.md is the topic plan; progress.md is the running record.

3. **`insights.md`** — durable items only
   - Append to the existing structure. Match the formatting style already in the file.
   - Only items that pass the promotion test (same gap 3+ times in progress.md, OR obviously cross-study durable). Default behavior: don't write to insights.md.
   - When you do promote, remove the item from progress.md Areas Needing Attention. The item lives in exactly one place.

4. **`Story Bank.md`** — opt-in only
   - Only if a new story emerged during the session and the user said yes when offered.
   - Ask: "This sounds like a {category} story — want me to add it to the Story Bank?" Use AskUserQuestion: "Yes — add it" / "Skip for now".
   - If yes, find the matching category in Story Bank.md (or create a new one if none fits). Write a starter STAR entry with a one-line Summary and whatever the user said. Mark missing details (resolution time, exact numbers) with `TODO`.
   - Don't refine the story this session unless the user wants to. Drafting and refining are separate beats.

5. **`CLAUDE.md`** — one line, session log
   - Append one row to the session log table. Format:
     ```
     | {YYYY-MM-DD} | {short topic summary, ~60 chars} | {key observation, ~80 chars} |
     ```
   - If CLAUDE.md doesn't have a session log table yet, add one with this header at the appropriate spot:
     ```
     ## Session Log

     | Date | Covered | Observations |
     |------|---------|--------------|
     | {YYYY-MM-DD} | {topics} | {observation} |
     ```
   - Don't introduce other top-level sections. CLAUDE.md is deliberately lean per the locked memory model.

6. **`profile.md`** — only if needed
   - If the user explicitly said something that changes durable identity (target role, comm style preference, key constraint), prompt: "You mentioned {change}. Want me to update your profile to reflect that?" via AskUserQuestion. Only edit on yes.

If any Edit fails, halt and report which file failed and why. Don't try to roll back partial writes — the failure surfaces something worth the user looking at.

## Step 9 — Sign off (and archive flow if study completes)

### Standard sign-off

Give the user one direct sentence: what was strongest, what most needs attention before the next session. No bullet points. No padding. Then stop.

Example: "Your sliding window pattern is locked — clean implementation under pressure. The recurring Math.min two-arg slip-up is what to watch for tomorrow; nest it explicitly."

### Archive flow (if all checkboxes are ticked across all weeks)

After writing back in Step 8, check whether all topics are completed. List the week files with bash: `ls "{study root path}/study-plans/{active}"/week-*.md`. Read each one. Scan every checkbox across all of them. If every box is `[x]` (no `[ ]` lines remaining) across every week file AND across `progress.md`'s weekly progress sections:

1. Congratulate the user on completing the study.
2. Summarize: "{Plan name} is done — {study days} days, {topics covered count} topics, {N} items resolved."
3. Offer to archive via AskUserQuestion:
   - Question: "Archive the study?"
   - Options:
     - "Yes — mark Complete and clear active_study"
     - "Not yet — keep it active for follow-up sessions"

4. If yes:
   - Update `study-plans/index.md` row for this study: status `Active` → `Complete`, fill End date with today, add a one-line outcome summary in the Outcome column.
   - Update `config.yaml` to set `active_study: null`.
   - Suggest next steps based on the user's tracked positions. Scan `companies/{slug}/{pos}/position-fit.md` files (host path) and read each one's `Status:` header. If any position has `Interview Scheduled`, suggest `interview-prep` for it. If any position has `Tracking`, suggest moving it forward (e.g., `apply-to-job` to advance, or chase the recruiter). If everything is in terminal states (`Rejected`, `Withdrawn`, `Accepted`) or there are no positions at all, suggest `create-study-plan` for the next study. To enumerate cheaply, list the position-fit files first: `find "{bash root}/companies" -name "position-fit.md" -maxdepth 4 2>/dev/null`, then `head -10` each one to read the `Status:` line without loading the full body.

5. If not yet, leave everything as-is.

## Edge case checklist

- **Off-plan session** (no active study, or user works on something not in plan) → coach normally. Note `(off-plan)` in any session log entries. Skip checkbox updates. Still update CLAUDE.md.
- **Mid-session topic shift** → fine. Coach the new topic. Block tracking is mental, not enforced.
- **User skips wrap-up** → write a minimal session log line (date, topics touched, "no debrief"). Don't fabricate observations.
- **Plan modified mid-stream** (create-study-plan was re-run in modify mode) → progress.md may have a `(modify)` row. Skip past it; continue normally.
- **Mock interview marker** → if the topic line contains "mock" or "timed mock", surface the option once: "I see this is a mock — want me to run it timed?" Don't auto-mock.
- **No calendar interaction on close.** Plan files and calendar live independently. progress.md is the debrief surface.

## Notes for implementation

- **Tone**: This is a coaching conversation, not a planning one. Keep prompts tight. Don't editorialize feedback — be direct and specific. Default to the comm style from `profile.md`.
- **Block-aware dispatch**: The plan's daily structure names the blocks (Algorithms, System Design, Behavioral, etc.). Use those names to choose the coaching shape. For non-standard blocks, fall back to the closest analogue or general coaching.
- **Don't reload prior studies' progress.md**: study-plans/index.md and the active study's files are enough. Reading every prior progress.md balloons context.
- **Areas Needing Attention is the working scratchpad**; insights.md is the durable layer. Promote slowly. Demote nothing — items only flow upward (progress → insights) or laterally (active → resolved).
- **Re-invocation**: same-day re-invocations update the existing session log row when "Continue" is picked. Don't create duplicate rows for the same date unless the user explicitly picks "Start fresh".
