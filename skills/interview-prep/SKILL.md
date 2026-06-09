---
name: interview-prep
description: >
  Prep for a specific upcoming interview or debrief after one. Use when the user says
  "I have an interview with [Company]", "prep me for my [Company] interview", "prep me
  for tomorrow's system design round", "I just finished my interview", "let's debrief",
  "what stories should I use for [Company]", or any variation that implies an interview
  is imminent or just completed. Does NOT replace daily study sessions — this skill is
  position-specific, not a general prep drill.
---

# interview-prep

Two modes: **Prep** (before an interview) and **Debrief** (after one). Dispatch based
on the user's trigger phrase. If ambiguous, use AskUserQuestion:

- Question: "Are you preparing for an upcoming interview or debriefing after one?"
- Options:
  - "Preparing — I have an interview coming up"
  - "Debriefing — I just finished one"

---

## Step 0 — Verify directory and load context

Identify the job search root directory:
```bash
find /sessions/*/mnt -maxdepth 1 -type d
```

The job search root is the folder containing `config.yaml` at its top level. If none
found, tell the user the plugin hasn't been initialized and offer `job-search-init`. Stop
until init completes.

Hold both path forms:
- Host path (for file tools): e.g., `/Users/.../2026 Job Search`
- Bash-mounted path (for shell): e.g., `/sessions/*/mnt/2026 Job Search`

Verify these files exist:
- `config.yaml`
- `profile.md`
- `insights.md`
- `CLAUDE.md`
- `study-plans/index.md`

If any are missing, tell the user and offer `job-search-init`. Stop until init completes.

Read all five files. Hold their contents for the rest of the session.

---

## PREP MODE

### Step P1 — Identify the interview

**Gather the minimum required inputs:**

**Company:** Extract from the user's message. If ambiguous, confirm before proceeding.

**Interview type:** Extract from the message if stated. If not, use AskUserQuestion:
- Question: "What type of interview is this?"
- Options: "Phone / recruiter screen", "Technical / coding screen", "System design",
  "Behavioral / leadership", "Hiring manager", "Team fit", "Bar raiser / final round",
  "General / not sure"

**Type slug mapping** (used in filenames and logging):

| User-facing label | Type slug |
|-------------------|-----------|
| Phone / recruiter screen | `phone-screen` |
| Technical / coding screen | `tech-screen` |
| System design | `system-design` |
| Behavioral / leadership | `behavioral` |
| Hiring manager | `hiring-manager` |
| Team fit | `team-fit` |
| Bar raiser / final round | `final-round` |
| General / not sure | `general` |

Hold the resolved type slug — it's used in the prep doc filename and the CLAUDE.md log.

**Calendar lookup (optional):** Read `config.yaml` for `calendar.provider`. If a
provider is configured, attempt to look up upcoming calendar events matching the company
name to pre-fill date, time, and round details. If the lookup succeeds, confirm with
the user: "Found a {Company} event on {date} at {time} — is this the interview you're
prepping for?" via AskUserQuestion (Yes / No, specify a different one). If the lookup
fails or returns no match, proceed without calendar data — do not block or ask the user
to fix it.

**Interviewer name (always optional):** If the calendar event or the user's message
includes an interviewer name or role, capture it. Do not ask for it explicitly.

**Date (fill from calendar or skip):** If calendar lookup failed and no date was
mentioned, leave it as "(date not specified)" in the prep doc. Do not ask.

**Date slug** (used in filenames): format as `YYYY-MM-DD` when known. When no date
is available, use `undated` as the date slug. Example filenames:
- `2026-05-12-system-design.md`
- `undated-behavioral.md`

### Step P2 — Match to a tracked position and load position context

Derive the **company slug**: lowercase, spaces → hyphens, strip all punctuation
(commas, periods, apostrophes, parentheses — drop them, don't replace with hyphens),
preserve numbers.
Examples: "Stripe" → `stripe`, "Block, Inc." → `block-inc`, "O'Reilly Media" → `oreilly-media`,
"Scale AI" → `scale-ai`.

Derive the **position slug** (when needed): same rules applied to the position title.
Examples: "Staff Software Engineer" → `staff-software-engineer`,
"Principal Infrastructure Engineer" → `principal-infrastructure-engineer`.

Look up tracked positions for this company by listing the directory:

```bash
ls -d "{bash root}/companies/{co-slug}/"*/ 2>/dev/null
```

- **One position folder** → that's the match. Hold the position slug.
- **Multiple position folders** → use AskUserQuestion to pick one. List the
  folder names as options; for each option, prefer the position title from
  the `# {Position Title} — {Company}` heading inside `position-fit.md` over
  the slug if the file exists.
- **No position folders** (folder absent or empty) → see "If the
  company+position is not tracked yet" below.

**If the company+position is not tracked yet:** Prompt the user for the
position title (free-form, one question). Then:

1. Derive a position slug: same rules as company slug.
2. Create the folder: `mkdir -p "{bash root}/companies/{co-slug}/{pos-slug}"`
3. Write a minimal `position-fit.md` stub with just the header so later
   skills (and humans) can find it:

   ```markdown
   # {Position Title} — {Company}

   *Status: Interview Scheduled*
   *Date added: {YYYY-MM-DD today}*
   *Last touched: {YYYY-MM-DD today}*
   *Source: Added by interview-prep — run apply-to-job to fill in posting + fit analysis.*
   ```

4. Tell the user once: "Created a stub position folder and `position-fit.md`
   with status `Interview Scheduled`. Run `apply-to-job` afterwards to fill
   in the posting, fit analysis, and tailored resume." Do not block on it.
5. Continue with prep using whatever context is available.

Once the position is resolved, hold the position path:
`companies/{co-slug}/{pos-slug}/`

**Load position context files (on demand):**

Check which files exist using bash:
```bash
ls "{bash root}/companies/{co-slug}/company.md" 2>/dev/null
ls "{bash root}/companies/{co-slug}/{pos-slug}/position-fit.md" 2>/dev/null
```

- **`company.md` exists** → read it. Hold for question generation and company-specific notes.
- **`company.md` missing** → note it. The prep doc will be less tailored.
- **`position-fit.md` exists** → read it. Hold strengths, gaps, and relevant stories list.
- **`position-fit.md` missing** → tell the user once:
  > "I don't see a position-fit analysis for this role. Running `apply-to-job` first
  > would give me your gap analysis and story matches — the prep doc will be more
  > targeted. Want to do that now, or continue with what's available?"
  Use AskUserQuestion: "Run apply-to-job first" / "Continue with available context".
  If they choose to continue, synthesize strengths and gaps from `profile.md` and
  `company.md` instead. Do not block.

Read `Story Bank.md`. If it doesn't exist, note it and continue — story suggestions
will be limited to what's inferrable from `profile.md`.

### Step P3 — Generate prep content

Synthesize prep content from everything loaded. Hold this content before writing
any file — it gets shown inline first (Step P4).

**Likely questions (8–12 total, tailored to interview type):**

Match the interview type to the question sets below. Include all sets marked for that
type. For each question, use `company.md` (Interview Process section) and `position-fit.md`
(role requirements) to make questions specific where possible.

| Interview type | Question sets to include |
|----------------|--------------------------|
| Phone / recruiter screen | Company/role fit + Behavioral (light) |
| Technical / coding screen | Technical (DS&A) + Company/role fit (light) |
| System design | System design + Technical depth + Company/role fit (light) |
| Behavioral / leadership | Behavioral + Leadership + Company/role fit |
| Hiring manager | Behavioral + Leadership + Company/role fit |
| Team fit | Behavioral (light) + Company/role fit |
| Bar raiser / final round | All sets |
| General / not sure | Behavioral + Company/role fit + Technical (light) |

Question sets:

*Technical (DS&A):* 3–4 questions on likely coding topics. Use `company.md` Interview
Process section if available; otherwise generate based on role level from `profile.md`.

*System design:* 2–3 design topics likely for this company and role. Use `company.md`
engineering blog findings and interview process patterns if available.

*Behavioral / leadership:* 4–6 questions. Bias toward categories with stories in
`Story Bank.md`. For staff-level roles (from `profile.md`): include at least one on
cross-team influence, one on technical direction, one on handling failure.

*Company / role fit:* Always include "Why {Company}?" and "Why this role?". Add 1–2
company-specific questions synthesized from `company.md` overview and recent events
if available.

**Story suggestions:**

For each behavioral and leadership question, find the best-matching story from
`Story Bank.md`. Match on: question category, keywords in the story summary, and role
relevance from `position-fit.md` or `profile.md`. Surface 4–6 stories maximum. For
each, write one sentence on why it fits this specific company/role — not a generic
"this story shows leadership" note.

If `Story Bank.md` is missing or empty, note it and skip this section rather than
fabricating story titles.

**Topics to refresh:**

Scan `insights.md` for items relevant to this interview type:
- For coding rounds: surface DS&A weak spots
- For system design: surface SD weak spots and any relevant architecture gaps
- For behavioral: surface story delivery patterns (e.g., "we" vs "I" habit, close trailing)

Scan `position-fit.md` gaps section (if available) for gaps relevant to this round type.

Pick the 3–5 most relevant items. Don't dump the entire insights.md — this is the
night-before list, not a study plan.

### Step P4 — Show inline summary, then write the prep doc

**Show inline first.** Before writing any file, display:

```
**{Company} — {Type} interview{, date if known}**

**Stories to lead with:**
| Question type | Story | Why |
|---------------|-------|-----|
| {e.g., Influence without authority} | {Story name} | {one sentence} |
| ... | ... | ... |

**Topics to refresh before this round:**
- {item 1}
- {item 2}
- {item 3}

Writing full prep doc → companies/{co-slug}/{pos-slug}/prep/{date}-{type}.md
```

Wait for the user to see this before proceeding. If they react (e.g., "swap that story",
"add X to the refresh list"), incorporate the change into the file write. Otherwise
proceed immediately.

**Write the prep doc** to `{host root}/companies/{co-slug}/{pos-slug}/prep/{date}-{type}.md`.

Create the `prep/` folder first if needed:
```bash
mkdir -p "{bash root}/companies/{co-slug}/{pos-slug}/prep"
```

Use this template:

```markdown
# Interview Prep — {Company} — {Type} — {Date}

*Generated: {YYYY-MM-DD}*

## Logistics
- **Date / Time**: {from calendar or "(not specified)"}
- **Format**: {phone / video / onsite — from calendar or "(not specified)"}
- **Interviewer**: {name/role if known, else "(not specified)"}
- **Round**: {e.g., "1st screen", "2nd technical", "final" — from calendar or "(not specified)"}

## Role Context
- **Position**: {title}
- **Key strengths for this role**: {from position-fit.md if available, else synthesized from profile.md + company.md}
- **Key gaps to be ready for**: {from position-fit.md if available, else synthesized; "position-fit.md not available — run apply-to-job for a full gap analysis" if synthesized}

## Likely Questions

{Include only the question sets relevant to this interview type — see Step P3 mapping.}

### Technical / DS&A
{Only if interview type includes Technical set}
- {question}
- ...

### System Design
{Only if interview type includes System Design set}
- {question}
- ...

### Behavioral / Leadership
{Only if interview type includes Behavioral or Leadership set}
- {question}
- ...

### Company / Role Fit
- Why {Company}?
- Why this role?
- {1–2 company-specific questions if company.md available}

## Story Suggestions

| Question type | Story | Why it fits |
|---------------|-------|-------------|
| {category} | {story name} | {one sentence specific to this company/role} |
| ... | ... | ... |

{If Story Bank.md was missing: "Story Bank not found — run job-search-init or add Story Bank.md to generate suggestions."}

## Topics to Refresh
- {item}: {one sentence on what to review}
- ...

{If insights.md was empty or no relevant items: "No items found in insights.md for this interview type."}

## Quick Notes
{Any additional context worth scanning 10 minutes before the call: tone guidance from
profile.md comm style, any red flags from company.md to probe, recent news about the
company that might come up.}
```

If the `prep/` folder or file already exists for this date + type, use AskUserQuestion:
- Question: "A prep doc for this interview already exists. Overwrite or keep the existing one?"
- Options: "Overwrite" / "Keep existing — just show me the inline summary"

Confirm the write succeeded:
```bash
head -5 "{bash root}/companies/{co-slug}/{pos-slug}/prep/{date}-{type}.md"
```
If it fails, report the error and stop.

### Step P5 — Offer interactive practice

After the prep doc is written, ask once:

> "Prep doc is ready. Want to run through some of these areas now, or take the doc and prep on your own?"

Use AskUserQuestion:
- Question: "Practice now or prep on your own?"
- Options:
  - "Practice now — let's run through some questions" (description: "I'll coach you through the question types for this round")
  - "I'll prep on my own" (description: "We're done here")

If the user wants to practice, ask which area to start with (free-form or AskUserQuestion
based on which sets are in the prep doc). Then apply the matching coaching shape:

**Algorithm coaching** (for Technical / coding rounds):
- Ask which topic before any code. If "you pick," choose one that matches the interview
  type and drills weak spots from `insights.md`.
- Let the user talk through the approach before coding. Ask clarifying questions as an
  interviewer would.
- After: give direct feedback on time/space complexity, edge cases, communication clarity.

**System design coaching** (for System Design rounds):
- Force a requirements pass first. Don't let the user skip to architecture.
- Ask scale questions: request rate, data size, what the system must be good at.
- After the design: probe like an interviewer. Challenge choices. Push for staff-level
  framing: failure modes, build vs buy, migration strategy, operability, cost.

**Behavioral coaching** (for Behavioral, HM, Team fit, Bar raiser rounds):
- Ask the user to deliver the story as if speaking to an interviewer.
- Evaluate: "I" not "we" in action sections, result is specific and quantified, org-level
  impact for staff stories, no editorialized lesson at the end, close lands cleanly.
- Give line-level feedback. "Your result said X — what's the before/after number?" beats
  generic notes.
- Reference profile.md for tone — look for a "communication style" or "feedback
  preference" field. If present, apply it (e.g., "direct" → give blunt feedback with
  no softening; "encouraging" → lead with what worked before gaps). If absent, default
  to direct feedback on weaknesses.

Run as many rounds as the user wants. Move to Step P6 when:
- The user signals done ("that's enough", "I'm good", "let's stop here"), or
- You've worked through all question sets listed in the prep doc and the user hasn't
  asked for another topic.
Do not stop unilaterally mid-session. If the user is still engaged, keep going.

### Step P6 — Sign off

Append one row to the `CLAUDE.md` session log:
```
| {YYYY-MM-DD} | interview-prep: {Company} {Type} ({date if known}) | {one observation — e.g., "story suggestions generated; no position-fit.md"} |
```

Give the user one direct sentence: what looks strongest going into the interview and
what one thing most needs attention. No bullet points. Then stop.

---

## DEBRIEF MODE

### Step D1 — Identify the interview

Extract company from the user's message. Match to a tracked position folder using the
same slug logic and folder-listing approach as Step P2:

```bash
ls -d "{bash root}/companies/{co-slug}/"*/ 2>/dev/null
```

If multiple positions exist at that company, use AskUserQuestion to pick one.

If no tracked position exists, prompt for the position title and create the folder +
stub `position-fit.md` (same flow as Step P2 stub creation), then continue. If the
user declines to provide a position title, use `unknown` as the position slug and
create the folder at `companies/{co-slug}/unknown/`. Note the missing
position context in the debrief doc but do not block the debrief.

Ask: "Which round was this?" — free-form response is fine.

### Step D2 — Run the debrief conversation

Guide the user through these areas in order. Free-form conversation — don't pepper them
with all questions at once. Let answers breathe.

1. **Overall read:** "How'd it go? Give me the high-level first."
   Capture the user's words verbatim. When writing the debrief doc, normalize to
   Strong / Mixed / Weak if the user's phrasing maps cleanly (e.g., "it went really
   well" → Strong, "hard to say" → Mixed). If it doesn't map cleanly, write it as-is
   in quotes.

2. **Questions asked:** "What questions came up?" — capture them verbatim where possible.
   These feed future prep docs for follow-up rounds at the same company.

3. **What landed well:** Any answer or topic the interviewer responded positively to.

4. **What fell flat:** Any answer that felt weak or got a muted response.

5. **What they seemed to care most about:** The interviewer's apparent priorities —
   useful signal for follow-up rounds.

6. **Next steps:** Timeline, next round type, any instructions given.

### Step D3 — Write the debrief doc

Create the `interviews/` folder if needed:
```bash
mkdir -p "{bash root}/companies/{co-slug}/{pos-slug}/interviews"
```

Write `{host root}/companies/{co-slug}/{pos-slug}/interviews/{date}-{type}.md`:

```markdown
# Interview Debrief — {Company} — {Type} — {Date}

*Debrief date: {YYYY-MM-DD}*

## Outcome
- **Overall read**: {Strong / Mixed / Weak}
- **Next steps**: {what was said — timeline, next round, any instructions}

## Questions Asked
- {question 1}
- {question 2}
- ...

## What Landed
- {answer or topic that went well — one line each}

## What Fell Flat
- {answer or topic that didn't land — one line + brief why if known}

## What They Seemed to Care About Most
- {observation}

## Notes for Follow-up Rounds
- {anything to remember for the next conversation with this company}
```

### Step D4 — Update position-fit.md status

Read `companies/{co-slug}/{pos-slug}/position-fit.md` (host path). Find the
`Status:` line in the header (it looks like `*Status: Interview Scheduled*`). If the
file doesn't exist (the user just bootstrapped a stub at Step D1 and the user declined
to name the position, or some other edge case), skip this step.

Ask which status to move the position to. Use AskUserQuestion with options relevant
to the current status:

- If current status is "Interview Scheduled" or "Interviewing":
  - "Interviewing — still in process"
  - "Offer received"
  - "Rejected"
  - "On hold"
  - "Withdrawn"
- If current status is "Offer received": "Accepted", "Rejected", "Withdrawn", "On hold"
- If current status is already "Rejected", "Accepted", "Withdrawn": offer
  "Update anyway" (with a free-form note field) or "Leave as-is"
- If the current status is any other value (unexpected): show all valid statuses —
  Tracking, Applied, Screening, Interview Scheduled, Interviewing, Offer, Accepted,
  Rejected, Withdrawn, On Hold — and let the user pick

Use the Edit tool to update only the `Status:` line and the `Last touched:` line
(set the latter to today's date, YYYY-MM-DD). Do not touch the rest of the file.

If the file has no `Last touched:` line (older stubs may not), add one immediately
after the `Status:` line. If the file has no header block at all, prepend the standard
header before any other content.

### Step D5 — Route observations

**Answers that fell flat:** For each item from Step D2 "What fell flat":
- Check `insights.md` for an existing entry on the same topic. Use a loose semantic
  match — if insights.md has an entry about "system design capacity estimation" and
  the debrief item is "skipped capacity math," treat that as a match. Exact string
  match is not required; the question is whether the same underlying gap is already
  captured.
- If a match exists → note the reinforcement in the debrief doc's "Notes for Follow-up
  Rounds" section, but don't add a duplicate to insights.md.
- If no match → use AskUserQuestion: "Want me to add '{topic}' to your insights for
  future prep?" Yes / No. If yes, append to `insights.md` following the existing
  formatting style in that file.

**New story:** If the user described a specific past experience in first-person detail
during the debrief (a named project, a decision they made, a concrete outcome with
numbers) that doesn't appear in `Story Bank.md`, offer once:
> "That answer sounds like a strong story — want me to add a starter entry to your
> Story Bank?"
Use AskUserQuestion: "Yes — add to Story Bank" / "Skip for now".
If yes, add a stub STAR entry with a one-line Summary and what was said. Mark
missing details with `TODO`.

### Step D6 — Sign off

Append one row to the `CLAUDE.md` session log:
```
| {YYYY-MM-DD} | interview-debrief: {Company} {Type} | {one observation — e.g., "system design round, mixed read, follow-up scheduled"} |
```

Give the user one direct sentence: the most useful thing to act on before any
follow-up round. Then stop.

---

## Edge cases

- **Calendar provider configured but lookup fails:** Proceed without calendar data.
  Do not tell the user to fix their calendar setup — it's optional context, not a
  requirement.
- **Story Bank.md exists but is empty or has no completed stories:** Note in the Story
  Suggestions section and skip the table. Don't fabricate story names.
- **company.md missing:** Continue. Note in the prep doc that company-research hasn't
  been run. The prep doc will be more generic.
- **Both company.md and position-fit.md missing:** Continue with profile.md only.
  Flag both gaps in the prep doc inline. The prep will be notably less tailored — say so.
- **Interview type is "General / not sure":** Use the Behavioral + Company/role fit +
  Technical (light) question set. Don't ask more questions to narrow it down — the user
  said they're not sure.
- **Same interview prepped twice (prep doc already exists for this date + type):**
  Use AskUserQuestion to offer overwrite or keep existing.
- **Debrief with no pipeline row and user declines to provide position title:** Create
  the debrief doc at `companies/{co-slug}/unknown/interviews/{date}-unknown.md`
  and note the missing position context. Don't block the debrief.

---

## Notes for implementation

- **No scripts in prep docs.** The prep doc contains questions, story suggestions, and
  topics to review — not "say this exact sentence." Coaching happens in the interactive
  practice step, not in the file.
- **Story suggestions must be specific.** "Story 5 is relevant because this role values
  cross-team influence and Story 5 is about shaping platform strategy across 4 business
  units" beats "Story 5 shows leadership."
- **Profile.md drives tone.** Reference the communication style field when coaching.
  Default to direct feedback on weaknesses.
- **Position-folder interaction is narrow.** This skill creates a stub position
  folder with a minimal `position-fit.md` only when the user is prepping for or
  debriefing an interview at a company that isn't tracked yet (Prep Step P2 / Debrief
  Step D1). It updates only the `Status:` and `Last touched:` lines in `position-fit.md`
  during debrief. It does not edit `posting.md`, the gap analysis body, or other
  positions' folders.
- **Debrief questions are never asked all at once.** The debrief is a conversation,
  not a form. Move through the areas naturally.
