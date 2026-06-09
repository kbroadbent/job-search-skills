---
name: apply-to-job
description: >
  Add a position to the user's pipeline. Captures the job posting, derives
  company and position slugs, and writes a fit analysis at
  companies/{co}/{pos}/position-fit.md (with a Status header).
  On Apply intent, also auto-runs company-research if needed, calls
  resume-tailor, and offers find-recruiter. Use when the user says
  "add this to my pipeline", "track this job", "apply to this", "help me
  apply to [Company]", or shares a job posting URL alongside any intent
  to capture or apply.
---

# apply-to-job

Add a position to the user's pipeline. This skill is the entry point for
moving a posting from "I saw this somewhere" to "this is in my pipeline,
the resume is ready, and I know how I'd talk about it."

Two intents land here:

- **Track** — capture the posting and write a fit analysis. No resume edits,
  no recruiter outreach. Status: `Tracking`.
- **Apply** — full workflow: posting capture, fit analysis, company research
  (if missing), tailored resume, recruiter outreach offer. Status:
  `Applied` (or `Tracking` if any composition steps are skipped).

This skill orchestrates other skills — it does not duplicate their work:

| Concern | Owner |
|---------|-------|
| Researching the company | `company-research` |
| Tailoring the resume | `resume-tailor` |
| Finding a recruiter, drafting outreach | `find-recruiter` |
| Per-round interview prep | `interview-prep` |

apply-to-job calls into the first three on Apply intent (per the rules in
Steps 7, 10, 11). It always writes `posting.md` and `position-fit.md`.
Position status lives in the `position-fit.md` header (`Status:` field) —
there's no separate pipeline file. Status enum:
`Tracking`, `Applied`, `Screening`, `Interview Scheduled`, `Interviewing`,
`Offer`, `Accepted`, `Rejected`, `Withdrawn`, `On Hold`.

---

## Step 0 — Verify directory and load context

### Find the job search root

```bash
find /sessions/*/mnt -maxdepth 2 -name "config.yaml" 2>/dev/null | head -5
```

The job search root is the directory containing `config.yaml` at its top
level. Hold both path forms — you will need both throughout this skill:

- **Host path** (for Read/Write/Edit tools): e.g., `/Users/.../2026 Job Search`
- **Bash-mounted path** (for shell commands): e.g., `/sessions/*/mnt/2026 Job Search`

If no `config.yaml` is found, tell the user the plugin hasn't been
initialized and offer to run `job-search-init`. Stop until init completes.

### Verify required files exist

Check that all five are present:

- `config.yaml`
- `profile.md`
- `insights.md`
- `CLAUDE.md`
- `study-plans/index.md`

If any are missing, tell the user the directory isn't fully initialized and
offer `job-search-init`. Stop until init completes.

Read all five files. Hold the contents for the rest of the session.

### Locate sibling skills

Find the SKILL.md paths for the skills this one composes with. Run all three
now and store the results:

```bash
COMPANY_RESEARCH=$(find /sessions/*/mnt -path "*/job-search/skills/company-research/SKILL.md" 2>/dev/null | head -1)
RESUME_TAILOR=$(find /sessions/*/mnt -path "*/job-search/skills/resume-tailor/SKILL.md" 2>/dev/null | head -1)
FIND_RECRUITER=$(find /sessions/*/mnt -path "*/job-search/skills/find-recruiter/SKILL.md" 2>/dev/null | head -1)
echo "company-research: $COMPANY_RESEARCH"
echo "resume-tailor:    $RESUME_TAILOR"
echo "find-recruiter:   $FIND_RECRUITER"
```

If any are empty, note which. Each composition step (7, 11, 12) handles
absent siblings gracefully — apply-to-job's core work (posting capture, fit
analysis, pipeline row) does not depend on them.

Because each bash call runs in isolation, re-derive these paths inline in
the bash blocks that need them rather than assuming they persist.

---

## Step 1 — Detect intent (Track vs Apply)

Examine the user's invocation message.

**Default to Apply** if the message contains any of: "apply", "submit",
"send my application", "help me apply", "apply to this".

**Default to Track** if the message contains any of: "track this", "add to
my pipeline", "capture this", "for later", "keep an eye on", "add this
position".

**If neither pattern is clear, ask via AskUserQuestion:**

- Question: "What would you like to do with this posting?"
- Options:
  - "Apply — capture, fit analysis, tailor resume, offer recruiter outreach"
  - "Track — capture and fit analysis only"

Hold the resolved intent. After Step 3 (slug confirmation), restate the
intent in the confirmation message so the user can correct it before
expensive work happens:

> "Got it. I'll **{Apply / Track}** {Position Title} at {Company}. Continuing."

---

## Step 2 — Get the posting

The posting may arrive as:

- A URL in the user's message
- Pasted text in the user's message
- A path to a file in the workspace

If none of those is present, ask:

> "Please share the job posting — a URL, pasted text, or a path to a saved
> file all work."

### URL

```
WebFetch(url)
```

If the fetch is paywalled, login-gated, or otherwise fails, ask the user
to paste the description as text. If they decline, stop — the skill cannot
add a position without knowing what the role requires.

### Pasted text

Use the text as-is. Strip any obvious HTML tags before processing.

### File path

If the user gives a path:

- `.md` or `.txt`: read directly with the Read tool (host path).
- `.pdf`: use the `pdf` skill if it is available. Try:
  ```bash
  find /sessions/*/mnt -path "*/skills/pdf/SKILL.md" 2>/dev/null | head -1
  ```
  If found, read its SKILL.md and follow its instructions to extract text
  from the PDF. If not found, ask the user to paste the description as
  text instead.
- Other formats: ask the user to convert or paste.

Hold the resulting posting content as plain text. You will write it to
`posting.md` in Step 6.

---

## Step 3 — Extract company + position; derive slugs; confirm

From the posting, extract:

- **Company name** as displayed (e.g., "Stripe", "Capital One", "Block, Inc.")
- **Position title** as listed (e.g., "Staff Software Engineer, Billing
  Infrastructure")

If the company name is ambiguous or absent (e.g., the posting is on a
generic ATS page that doesn't name the company), ask the user.

### Slug rules

Same rules used by `resume-tailor` and `company-research`. Apply identically
so paths line up across skills:

- Lowercase
- Spaces → hyphens
- Strip all punctuation (commas, periods, apostrophes, parentheses,
  ampersands — drop them entirely; do NOT replace with hyphens)
- Preserve numbers

**Company slug examples:**

- "Stripe" → `stripe`
- "Block, Inc." → `block-inc`
- "O'Reilly Media" → `oreilly-media`
- "A9.com" → `a9com`
- "Scale AI" → `scale-ai`

**Position slug examples:**

- "Staff Software Engineer, Billing Infrastructure" →
  `staff-software-engineer-billing-infrastructure`
- "Principal Engineer - Platform" → `principal-engineer-platform`
- "Engineering Manager, Data" → `engineering-manager-data`

### Confirm with the user

Present the names and slugs:

> "I've got **{Company Name}** (`{company-slug}`) and **{Position Title}**
> (`{position-slug}`). Looks right, or should I adjust either?"

Wait for the response. If the user requests a correction, apply it and
repeat the confirmation with the updated values:

> "Updated: **{Company Name}** (`{corrected-company-slug}`) and
> **{Position Title}** (`{corrected-position-slug}`). Good to go?"

Do not proceed until the user explicitly confirms. Do not assume silence
is confirmation.

After confirmation, restate the intent from Step 1 (per the format in
Step 1).

---

## Step 4 — Slug collision check

Before creating the company folder, check whether `companies/{co}/` already
exists with a different company recorded:

```bash
ls "{bash root}/companies/{co}/company.md" 2>/dev/null
```

If `company.md` exists, read its first heading line:

```bash
head -1 "{bash root}/companies/{co}/company.md"
```

Compare against the company name from Step 3.

- **Same company:** proceed. The folder already exists — that's fine.
- **Different company** (e.g., the slug `block` already belongs to
  Block, Inc., and this posting is from a different "Block"): use
  AskUserQuestion:
  - Question: "A folder for a different company already uses the slug
    `{co}` ({existing company name from company.md heading}). What slug
    should this {new company name} use?"
  - Options:
    - "Use `{co}-2`"
    - "Use `{alternate-suggestion}`" (e.g., disambiguating with a domain
      qualifier like `block-tech` vs. `block-finance`)

Apply the user's choice. From this point on, use the chosen slug as the
company slug.

If `companies/{co}/` exists but `company.md` is absent, treat it as the
same company (assume it's a partially populated folder from a prior
position add).

---

## Step 5 — Existing-position check

Check whether the position folder already exists:

```bash
ls "{bash root}/companies/{co}/{pos}/posting.md" 2>/dev/null
ls "{bash root}/companies/{co}/{pos}/position-fit.md" 2>/dev/null
```

If either file is present, the position has been added before. Use
AskUserQuestion:

- Question: "This position already exists at `companies/{co}/{pos}/`.
  How would you like to proceed?"
- Options:
  - "Overwrite — re-fetch posting and rewrite position-fit.md"
  - "Stop here — keep the existing files"

If the user picks "Stop here": jump to Step 12 (session log) with a brief
note, then close out.

If the user picks "Overwrite": continue. The `position-fit.md` Status header
is updated in place when the file is rewritten at Step 9 — do not duplicate
the position folder.

---

## Step 6 — Create folder structure; write posting.md

Create the position folder:

```bash
mkdir -p "{bash root}/companies/{co}/{pos}"
```

Write the posting content to `posting.md` using the Write tool (host path).

- Format: plain markdown. If the posting has clear sections (Responsibilities,
  Requirements, Qualifications, About the company), preserve them as
  markdown headers. If it's a text blob, write it as-is with no
  reformatting.
- Strip HTML tags. Decode HTML entities (e.g., `&amp;` → `&`).
- At the top of the file, write a metadata block:

```markdown
*Source: {URL or "Pasted in chat" or "File: {filename}"}*
*Captured: {YYYY-MM-DD}*

---
```

Confirm the write:

```bash
head -5 "{bash root}/companies/{co}/{pos}/posting.md"
```

If the head check returns empty, report the error and stop.

---

## Step 7 — Composition: company-research (auto-run if Apply + missing)

This step runs only if **both** conditions are true:

1. Intent from Step 1 is **Apply**
2. `companies/{co}/company.md` does not exist

If intent is **Track**, skip this step entirely and go to Step 8 — Track
intent never auto-runs company-research.

If intent is **Apply**, verify whether `company.md` exists:

```bash
ls "{bash root}/companies/{co}/company.md" 2>/dev/null
```

If the file IS listed, skip to Step 8 — research already exists.

If the file is NOT listed, continue with this step.

### Tell the user what's happening

Before invoking the skill, surface the detour clearly so the user is not
surprised when web searches start running:

> "No `company.md` for {Company} yet. Running `company-research` first so
> the fit analysis has the right context. This will take a few minutes."

### Invoke company-research

Re-derive its path (environment does not persist between bash calls):

```bash
COMPANY_RESEARCH=$(find /sessions/*/mnt -path "*/job-search/skills/company-research/SKILL.md" 2>/dev/null | head -1)
echo "$COMPANY_RESEARCH"
```

If `$COMPANY_RESEARCH` is empty: tell the user `company-research` could not
be located and proceed without it. Note the absence in the closing summary.
This is degraded but non-fatal.

If found: read the SKILL.md and follow its instructions, passing the
following context inline:

> "Calling `company-research`. Company: **{Company Name}**. Posting: see
> `{host path}/companies/{co}/{pos}/posting.md`. Use a depth
> tier appropriate for an Apply-intent invocation — Standard is the
> default; ask the user only if the company looks unusual."

The default depth recommendation is **Standard** (per the existing
`company-research` decision tree). If `company-research` asks the user to
pick a depth tier, the user makes that call.

After `company-research` completes, verify its output:

```bash
ls "{bash root}/companies/{co}/company.md" 2>/dev/null
```

If `company.md` is now present, continue to Step 8. If absent (skill failed
or was aborted by the user), proceed without it and note in the closing
summary.

---

## Step 8 — Read company.md and Story Bank.md

### company.md

```bash
ls "{bash root}/companies/{co}/company.md" 2>/dev/null
```

If present, read it using the Read tool (host path). Hold the contents.
Pay particular attention to:

- **Tech Stack** — confirmed languages, frameworks, cloud, databases.
- **Compensation** — for the level mapping section of `position-fit.md`.
- **Culture & Reviews** — for the red flags section.
- **Interview Process** — informs what the user should expect, useful
  for the application notes.

**If absent** (Track intent skipped Step 7, or Step 7 ran company-research
and it failed to produce the file): proceed without company.md. The fit
analysis quality will be lower but still useful. In the position-fit.md
template (Step 9), explicitly note the gap rather than silently leaving
sections empty:

- Snapshot → Compensation: write `"Not listed (no company.md available)"`
  if the posting also doesn't list it.
- Snapshot → Level: derive what you can from the posting title; do not
  claim a level mapping you can't source.
- Red flags / Sources sections: write `"Company context: not researched
  yet — run company-research before final round prep."`

Also note the absence in the closing summary at Step 13.

### Story Bank.md

```bash
ls "{bash root}/Story Bank.md" 2>/dev/null
```

If present, read it. Scan only the **summary lines** of each story (one-line
descriptions just under each story heading). Identify 1–3 stories whose
summary maps directly to the posting's emphasis.

If no story has a clear summary match, do a deeper read on the top 2
candidates by their headings — read the full STAR body and assess fit. If
still no match, surface that in `position-fit.md` as a story-bank gap.

If `Story Bank.md` is absent, write a one-line note in the relevant section
of `position-fit.md` ("Story Bank not found — add stories with the bank
prompts to make fit analyses richer next time").

---

## Step 9 — Confirm status, build gap analysis, write position-fit.md

### Confirm the position status

The status enum lives in the `position-fit.md` header — it is the source
of truth for "where is this position in the pipeline". Default to the
user's intent (Apply → `Applied`, Track → `Tracking`), but ask before
writing — `Applied` is load-bearing and shouldn't be set just because the
user said "apply" if they haven't actually clicked Submit on the
company's portal.

Use AskUserQuestion:

- Question: "What status should I set for this position?"
- Options (recommended option first, marked):
  - **{Apply intent}**:
    - "Applied (Recommended) — I've submitted the application"
    - "Tracking — not submitted yet"
  - **{Track intent}**:
    - "Tracking (Recommended) — capture only, not applied"
    - "Applied — already submitted"

Apply the user's choice as the `Status:` header value when writing the
file below.

The full status enum (so later skills like `interview-prep` can advance
the status): `Tracking`, `Applied`, `Screening`, `Interview Scheduled`,
`Interviewing`, `Offer`, `Accepted`, `Rejected`, `Withdrawn`, `On Hold`.
At creation time, only `Tracking` and `Applied` are valid choices —
later transitions are owned by other skills or by the user editing the
file.

### Build the gap analysis

Compare the posting against the user's `profile.md`, the resume (read
`resume.filename` from `config.yaml` if needed for context), and the
context loaded in Step 8.

### Sections to fill

**Snapshot:**
- Level (Staff, Senior, Principal, etc.) — pull from posting title and
  responsibilities; cross-check against `company.md` Compensation level
  mapping if available.
- Stack — top 3–5 technologies/domains the posting names.
- Location / Remote — what the posting says.
- Compensation — the posting's range if listed; "Not listed" otherwise.
  If not listed but `company.md` has a range for the level, write
  "Not listed (company range: {range from company.md})".

**Why this role fits** — 2–4 bullets pulling concrete anchors from
`profile.md` and the resume that map directly to what the posting asks
for. Use real numbers and technologies. No resume dump.

**Gap analysis** — three subsections:

- **Strong matches:** requirement ↔ where the user has it, specifically.
- **Present but lighter than required:** requirement ↔ what's there +
  what's missing in framing or depth.
- **Genuine gaps:** requirement ↔ whether to probe with the user or flag
  for interview prep.

**Relevant stories** — 1–3 from Story Bank.md. Format: title, one-line
summary, why it lands for this role. If Story Bank had no matches, write:
> "No strong matches in the current Story Bank — consider drafting one for
> {capability the role emphasizes that the user lacks a story for}."

**Tailored angle** — one sentence describing the framing the resume and
outreach should lead with.

**Red flags / things to clarify** — anything that doesn't match: location,
comp, seniority mismatch, weird signal in the JD, sentiment trends from
`company.md`. Be honest. Better to flag now than be surprised later.

**Application notes** — anything the user should remember when actually
submitting (referral required, deadline, custom essay questions, application
portal quirks).

**Sources** — link to the posting and to `company.md` if it exists.

### Write the file

Write `position-fit.md` to the position folder (host path) using this
template:

```markdown
# {Position Title} — {Company}

*Status: {Tracking | Applied}*
*Date added: {YYYY-MM-DD}*
*Last touched: {YYYY-MM-DD}*
*Source: {URL or "Pasted" or "File: {filename}"}*

## Snapshot

- **Level:** {seniority signal}
- **Stack:** {top 3–5}
- **Location / Remote:** {what the posting says}
- **Compensation:** {range or "Not listed" with company.md context}

## Why this role fits

- {Anchor 1 — concrete, with numbers and technology}
- {Anchor 2}
- {Anchor 3}
- {Anchor 4 if material}

## Gap analysis

**Strong matches** (resume already covers these well):
- {Requirement} ↔ {Where the user has it — be specific}

**Present but lighter than required:**
- {Requirement} ↔ {What's there + what's missing in framing or depth}

**Genuine gaps:**
- {Requirement} — {Probe the user, or flag for interview prep}

## Relevant stories (from Story Bank)

1. **{Story title}** — {one-line summary} → {why it lands here}
2. ...
3. ...

## Tailored angle

{One sentence on the framing the resume and outreach should lead with.}

## Red flags / things to clarify

- {What doesn't match — be honest}

## Application notes

- {Things to remember when actually submitting}

## Sources

- Posting: {URL or note}
- Company context: {link to company.md or "Not researched"}
```

Confirm the write:

```bash
head -5 "{bash root}/companies/{co}/{pos}/position-fit.md"
```

### Re-run handling

On re-run (Step 5 detected an existing folder and the user picked
"Overwrite"), preserve `Date added` from the previous file. Always set
`Last touched` to today. The `Status:` header takes the user's freshly
confirmed value. Read the existing `position-fit.md` to lift the original
`Date added` before writing the new file.

---

## Step 10 — Composition: resume-tailor (auto on Apply, skip on Track)

If intent from Step 1 is **Track**, skip this step.

If intent is **Apply**, call `resume-tailor`.

Re-derive its path:

```bash
RESUME_TAILOR=$(find /sessions/*/mnt -path "*/job-search/skills/resume-tailor/SKILL.md" 2>/dev/null | head -1)
echo "$RESUME_TAILOR"
```

If `$RESUME_TAILOR` is empty: tell the user `resume-tailor` could not be
located. Note the absence in the closing summary and skip to Step 11.

If found: read the SKILL.md and follow its instructions in **Mode B** by
passing the following invocation message:

> "Calling `resume-tailor` in Mode B. company slug: `{co}`, position slug:
> `{pos}`, posting: `{host path}/companies/{co}/{pos}/posting.md`."

This triggers `resume-tailor`'s Mode B detection (all three required
pieces present). It will skip slug confirmation, read the posting from
the path, run its own gap analysis, edit the resume, generate the PDF,
and save both files to the position folder.

After `resume-tailor` completes, verify the resume files exist:

```bash
ls "{bash root}/companies/{co}/{pos}/"*Resume.docx 2>/dev/null
ls "{bash root}/companies/{co}/{pos}/"*Resume.pdf 2>/dev/null
```

If the `.docx` is missing, note the failure in the closing summary. The
`.pdf` is best-effort; missing PDF is not a failure of this step.

---

## Step 11 — Composition: find-recruiter (offer on Apply)

If intent from Step 1 is **Track**, skip this step.

If intent is **Apply**, ask the user via AskUserQuestion:

- Question: "Find a recruiter at {Company} and draft an outreach message
  now?"
- Options:
  - "Yes (Recommended) — search LinkedIn and draft outreach"
  - "Skip — I'll handle outreach later"

If "Skip": continue to Step 12 with a note in the closing summary.

If "Yes": re-derive the path:

```bash
FIND_RECRUITER=$(find /sessions/*/mnt -path "*/job-search/skills/find-recruiter/SKILL.md" 2>/dev/null | head -1)
echo "$FIND_RECRUITER"
```

If `$FIND_RECRUITER` is empty: tell the user `find-recruiter` could not be
located, the user can run it later when available. Note the absence in
the closing summary.

If found: read the SKILL.md and follow its instructions, passing:

> "Calling `find-recruiter`. Company: **{Company Name}** (slug: `{co}`).
> Position: **{Position Title}** (slug: `{pos}`). Posting: `{host path}`.
> position-fit.md: `{host path}`."

`find-recruiter` writes `companies/{co}/contacts.md` and may write
`companies/{co}/{pos}/outreach.md`. After it completes, do not
re-verify those files — `find-recruiter` is responsible for its own output.

---

## Step 12 — Append CLAUDE.md session log

Read `CLAUDE.md` using the Read tool (host path). Append one row to the
session log table:

```
| {YYYY-MM-DD} | apply-to-job: {Company} — {Position Title} ({Track | Apply}) | {one observation — e.g., "Strong tech stack match; gap: no Kafka direct experience. Resume tailored. Recruiter outreach offered."} |
```

If no session log table exists in `CLAUDE.md`, add one before appending:

```markdown
## Session Log

| Date | Covered | Observations |
|------|---------|--------------|
```

Write the updated `CLAUDE.md` back using the Write tool at the host path.

Confirm:

```bash
head -5 "{bash root}/CLAUDE.md"
```

If the head check returns empty, report the error but do not stop —
proceed to Step 13.

---

## Step 13 — Closing summary

Report concisely. The user can read the files for detail.

```
Position added: {Company} — {Position Title}
Intent: {Track | Apply}
Status: {Tracking | Applied} (in position-fit.md header)
Folder: companies/{co}/{pos}/

Files written:
  posting.md
  position-fit.md
  {resume files if resume-tailor ran — list both .docx and .pdf}
  {contacts.md / outreach.md if find-recruiter ran}

Composition:
  company-research: {ran (depth) | skipped (already had company.md) | skipped (Track intent) | not located}
  resume-tailor:    {ran | skipped (Track intent) | not located | failed: {reason}}
  find-recruiter:   {ran | declined | skipped (Track intent) | not located}

Strongest fit anchors:
  - {Pull 2–3 from position-fit.md "Why this role fits"}

Gaps to know about:
  - {Pull 1–3 from position-fit.md "Genuine gaps"}

Suggested next steps:
  - {1–2 short suggestions, e.g., "Run find-recruiter when ready to send
    outreach" or "Refresh company.md before the screen — research is N
    months old"}
```

Keep it short. Skip sections that don't apply (e.g., omit "Suggested next
steps" if there's nothing material to suggest).

---

## Edge cases

**Posting fetch blocked or fails:** ask the user to paste the description
as text. If they decline, stop the skill — there's nothing useful to do
without the posting content.

**Posting is for a position already in the user's tracked set
(`companies/{co}/{pos}/` already exists):** that's the re-run
path. Step 5 handles overwrite confirmation; Step 9 rewrites
`position-fit.md` in place, preserving `Date added` and refreshing
`Status` and `Last touched`.

**Posting is for a company that already has other tracked positions:**
not a collision. Two folders under `companies/{co}/`. Proceed
normally.

**`resume.filename` is null in `config.yaml`:** `resume-tailor` handles
that case — it will prompt the user. apply-to-job does not need to check.

**User aborts mid-flow** (e.g., declines the slug confirmation, picks
"Stop here" on overwrite check): write what you've done so far to the
session log with a note about where it stopped.

**Two distinct sub-cases:**

- **User picks "Stop here" at Step 5 (existing position).** The folder
  and its files were created by a previous invocation. Do NOT delete
  anything. Skip to Step 12 to log the session and close out.
- **User aborts before Step 9 (e.g., declines slug confirmation, or
  the posting fetch fails).** Step 6 may have already created an empty
  position folder. If you created the folder in this invocation and
  haven't yet written `position-fit.md`, remove the empty folder:

  ```bash
  rmdir "{bash root}/companies/{co}/{pos}" 2>/dev/null
  rmdir "{bash root}/companies/{co}" 2>/dev/null
  ```

  Both `rmdir` calls only succeed on empty folders — they will not
  delete user content. The second call removes the company folder if
  it was also newly created and is now empty; if other positions exist
  there, it fails silently and that's correct.

**`Story Bank.md` is absent or empty:** include a one-line note in the
"Relevant stories" section of `position-fit.md` and continue.

**Multi-position application** (user says "I want to apply to these three
roles at Stripe"): handle one position per skill invocation. Tell the user
you'll do the first one and ask which to do next when finished. Do not
try to batch.

---

## Principles

**Orchestrator, not duplicator.** This skill does not research the
company, tailor the resume, or find a recruiter. It calls the skills that
do. If a sibling skill does its own slug derivation, posting fetch, or
folder creation, defer to it. Don't duplicate that work in this skill.

**One folder per position.** `companies/{co}/{pos}/` is the
canonical home for everything tied to a single application. Status lives
in the `position-fit.md` header (current state, not a log). The session
log in `CLAUDE.md` is the historical trail.

**Honest about gaps.** The resume is honest (no fabrication). The fit
analysis is honest (genuine gaps are flagged, not papered over). The user
needs accurate signal to decide whether to apply, prep, or pass.

**Track is narrow.** Track intent does not run company-research,
resume-tailor, or find-recruiter. Capture, fit, pipeline row, done. The
user can re-invoke with Apply intent later.

**Apply is the full workflow.** If the user said apply, do the work. Don't
ask for permission to run resume-tailor on Apply intent — the auto-call
is the point.

**No em-dashes** in any user-facing message or written content.

**Path translation matters.** Use host paths for file tools (Read, Write,
Edit). Use bash-mounted paths for shell commands. Re-derive the bash root
in each bash block; environment does not persist.
