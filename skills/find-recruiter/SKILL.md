---
name: find-recruiter
description: >
  Find a recruiter at a target company and draft a tailored outreach
  message. Records the recruiter at companies/{co}/contacts.md and, when
  a position is in scope, writes outreach at
  companies/{co}/{pos}/outreach.md. Searches LinkedIn via
  Chrome (with WebSearch fallback) using a 4-priority chain: recruiter
  on the posting, LinkedIn "Posted by" attribution, content search for
  the role, people search + activity scan. Use when the user says
  "find a recruiter at [Company]", "look up a recruiter for [Position]",
  "draft an outreach message", or any variant of recruiter search and
  cold outreach. Also called by apply-to-job when the user opts in on
  Apply intent.
---

# find-recruiter

Find a recruiter at a target company. Record what's known about them in
`companies/{co}/contacts.md`. When a position is in scope, draft a
tailored outreach message at `companies/{co}/{pos}/outreach.md`.

This skill runs in two modes:

- **Composed** — invoked by `apply-to-job`. Company name, slug, position
  name, slug, and paths to `posting.md` and `position-fit.md` are passed
  in via the invocation message. Skip identity discovery.
- **Standalone** — invoked directly by the user. Elicit company (required)
  and position (optional) from the invocation or by prompting.

This skill is a **leaf** — it does not call other skills. Exception: in
Standalone mode, when the user names a position whose folder doesn't
exist, the skill offers to bootstrap via `apply-to-job` first
(per Step 3).

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

If any are missing, tell the user the directory isn't fully initialized
and offer `job-search-init`. Stop until init completes.

Read all five files. Hold the contents for the rest of the session. Pay
particular attention in `profile.md` to any communication-style
preferences — they override the plugin defaults at Step 7.

---

## Step 1 — Detect mode (Composed vs Standalone)

Examine the user's invocation message.

**Composed mode** requires ALL of the following to be present in the
message (this is the exact shape `apply-to-job`'s Step 12 emits):

1. The phrase "Calling find-recruiter" (in any backtick form)
2. A `Company:` label followed by the company display name
3. A company slug appearing in the form `(slug: <co>)`
4. A `Position:` label followed by the position display name
5. A position slug appearing in the form `(slug: <pos>)`
6. At least one absolute host path ending in `posting.md` or
   `position-fit.md`

Reference shape (from `apply-to-job` Step 12):

> "Calling `find-recruiter`. Company: **{Company Name}** (slug: `{co}`).
> Position: **{Position Title}** (slug: `{pos}`). Posting: `{host path}`.
> position-fit.md: `{host path}`."

If ANY of those are missing, treat the invocation as Standalone — even
if the message *mentions* a company or position. A casual user message
like "find a recruiter at Stripe" does not trigger Composed mode.

If all six are present, parse the following from the message:

- Company name (display form)
- Company slug
- Position title (display form)
- Position slug
- Host path to `posting.md`
- Host path to `position-fit.md` (may be absent)

Hold them. Skip to Step 4.

Composed mode never triggers the Step 3 bootstrap branch — see Step 3
opening. This is the boundary that prevents any recursion between
`apply-to-job` and `find-recruiter`.

**Standalone mode** is anything else. Continue to Step 2.

---

## Step 2 — Identity capture (Standalone mode only)

Best-effort parse from the invocation message:

- **Company name** — look for an explicit name (e.g., "find a recruiter
  at Stripe", "look up a recruiter for the Staff Eng role at Block").
- **Position title** — look for a role phrase ("Staff Engineer", "Senior
  Backend Developer", "Engineering Manager, Data"). Position is
  optional.

### If company name is missing or ambiguous

Ask in plain prose (not AskUserQuestion — this is open-ended):

> "Which company would you like me to look up a recruiter at?"

Wait for the answer. Hold it.

### If position is missing

Ask in plain prose:

> "For a specific position at {Company}, or a general recruiter search?
> If a specific role, name the title."

Wait for the answer. Three valid responses:

- A specific title → hold it as the position title.
- "General" / "no specific role" / "just looking" → set the position
  state to **null**. Skip Step 3 entirely. All subsequent
  position-specific steps (Step 8 outreach.md) are skipped automatically
  when position is null. Step 6 runs P4 only (no role-specific P1–P3).
- Anything ambiguous → ask once more for clarification, then default to
  general (null) if still unclear.

### Slug derivation

Apply the same rules used by `apply-to-job`, `resume-tailor`, and
`company-research`:

- Lowercase
- Spaces → hyphens
- Strip all punctuation (commas, periods, apostrophes, parentheses,
  ampersands — drop them entirely; do NOT replace with hyphens)
- Preserve numbers

Examples (company): "Stripe" → `stripe`, "Block, Inc." → `block-inc`,
"O'Reilly Media" → `oreilly-media`.

Examples (position): "Staff Software Engineer, Billing" →
`staff-software-engineer-billing`, "Principal Engineer - Platform" →
`principal-engineer-platform`.

### Confirm with the user

Present the names and slugs:

> "I've got **{Company Name}** (`{company-slug}`){and "**{Position Title}** (`{position-slug}`)" if position is in scope}. Looks right, or should I adjust?"

Wait for explicit confirmation. If the user requests a correction, apply
it and repeat the confirmation with the updated values. Do not assume
silence is confirmation.

---

## Step 3 — Folder checks; bootstrap offer if position folder missing

**Composed mode skips this step entirely.** The position folder is
guaranteed to exist when called by `apply-to-job` (which created it at
its own Step 6 before invoking find-recruiter). If you arrived here
from Step 1's Composed-mode branch, jump to Step 4.

Otherwise (Standalone mode), continue.

### Company folder

Check whether `companies/{co}/` exists:

```bash
ls "{bash root}/companies/{co}" 2>/dev/null
```

If it does NOT exist, create it:

```bash
mkdir -p "{bash root}/companies/{co}"
```

This is fine even in Standalone mode — find-recruiter is allowed to
create the company folder for `contacts.md` to live in. (The position
folder is a different matter — see below.)

### Position folder (only if a position is in scope)

If a position is in scope, check whether the position folder exists:

```bash
ls "{bash root}/companies/{co}/{pos}" 2>/dev/null
```

**If it exists:** continue to Step 4.

**If it does NOT exist (Standalone mode only — Composed mode always has
the folder):** offer to bootstrap via `apply-to-job` first.

Use AskUserQuestion:

- Question: "No position folder for `{pos}` yet. Bootstrap one with
  `apply-to-job` first so I can pull the fit analysis into your
  outreach?"
- Options:
  - "Yes (Recommended) — run apply-to-job, then come back for the
    recruiter search"
  - "No — find a recruiter only; skip the outreach draft"

**If "Yes":**

Re-derive the path to apply-to-job:

```bash
APPLY_TO_JOB=$(find /sessions/*/mnt -path "*/job-search/skills/apply-to-job/SKILL.md" 2>/dev/null | head -1)
echo "$APPLY_TO_JOB"
```

If `$APPLY_TO_JOB` is empty: tell the user `apply-to-job` could not be
located, drop position from scope, and continue contacts-only. Note the
absence in the closing summary.

If found: read the SKILL.md and follow its instructions. Pass the
following invocation message:

> "Calling `apply-to-job`. Company: **{Company Name}**. Position:
> **{Position Title}**. The user wants to bootstrap the position folder
> so I can draft a tailored outreach. Ask the user for the posting
> (URL / paste / file path) and proceed with Track or Apply intent as
> they prefer."

After `apply-to-job` completes, verify the position folder now exists:

```bash
ls "{bash root}/companies/{co}/{pos}/posting.md" 2>/dev/null
ls "{bash root}/companies/{co}/{pos}/position-fit.md" 2>/dev/null
```

If either is present, the bootstrap succeeded. **Re-run Step 4 in
full** — the fresh `posting.md`, `position-fit.md`, and possibly
`company.md` need to be loaded before drafting outreach. Then continue
from Step 5.

If both are absent, the bootstrap aborted (user backed out, posting
fetch failed, etc.). Drop position from scope (set position state to
null) and continue contacts-only. Note in the closing summary.

**If "No":** drop position from scope. Set position-related state to
null. Continue to Step 4 in contacts-only mode.

---

## Step 4 — Read position and company context

Read whichever of these files exist. Use the Read tool (host path).

### posting.md

```bash
ls "{bash root}/companies/{co}/{pos}/posting.md" 2>/dev/null
```

If present, read it. Hold the content. Pay attention to:

- A recruiter, contact, or hiring contact field anywhere in the body
- Any embedded LinkedIn job URL (e.g., `linkedin.com/jobs/view/...`)
- Domain / product / mission language for the "why this company" hook

### position-fit.md

```bash
ls "{bash root}/companies/{co}/{pos}/position-fit.md" 2>/dev/null
```

If present, read it. This is the **primary source** for the outreach
draft. Hold these sections specifically:

- **Tailored angle** — opening framing
- **Why this role fits** — 2–3 anchors for "why I fit"
- **Snapshot → Stack** — concrete tech to name in the message

### company.md

```bash
ls "{bash root}/companies/{co}/company.md" 2>/dev/null
```

If present, read it. Pull the mission / product description for the
"why this company" hook if `posting.md` doesn't already have a strong one.

### contacts.md

```bash
ls "{bash root}/companies/{co}/contacts.md" 2>/dev/null
```

If present, read it. Hold the existing recruiter sections. They are used
at Step 7 for re-run logic (LinkedIn URL match → update vs append).

### Story Bank.md

Optional fallback — only consult if `position-fit.md` is missing or its
"Why this role fits" section is thin (fewer than 2 concrete anchors).
Read summary lines first; if a story matches the role's emphasis, lift
its summary as a fit anchor for the outreach.

---

## Step 5 — Determine browser tooling

Read `config.yaml`. Look for `linkedin.search_method`.

```bash
grep -A 1 "^linkedin:" "{bash root}/config.yaml" 2>/dev/null
```

Three cases:

### Case A — `linkedin.search_method: chrome`

Use the Chrome MCP for LinkedIn searches.

Verify the Chrome extension is connected this session:

- Use the `list_connected_browsers` tool from `mcp__Claude_in_Chrome__*`
  if available.
- If no browsers are connected, fall back to WebSearch with a one-line
  notice to the user:
  > "Chrome extension not connected this session — using WebSearch
  > fallback for LinkedIn searches."
- Continue without re-prompting.

### Case B — `linkedin.search_method: websearch`

Use WebSearch only. Do not invoke Chrome MCP at all.

### Case C — Field is missing or null

Lazy-prompt via AskUserQuestion:

- Question: "How would you like me to search LinkedIn for recruiters?"
- Options:
  - "Chrome MCP — live navigation, requires the Claude in Chrome
    extension"
  - "WebSearch — snippet-only results, works without any browser
    extension"

Apply the user's choice. Then write the answer back to `config.yaml`.

The block lives at the top level of `config.yaml`, alongside `version`,
`agent`, `user`, `resume`, `calendar`, and `active_study`. Place it
between `calendar` and `active_study` if both exist.

```yaml
linkedin:
  search_method: "chrome"
```

(Indentation is two spaces. Quotes around the value are required.)

**If the `linkedin:` block is absent**, use the Edit tool (host path)
with `old_string` set to the existing `active_study:` line and
`new_string` set to the new block followed by the original line. Example:

- old_string: `active_study: null`
- new_string:
  ```
  linkedin:
    search_method: "chrome"
  active_study: null
  ```

If `active_study:` is also absent (atypical for a properly initialized
config), anchor on the last existing top-level key — `calendar:` is the
next-best anchor; failing that, append to the end of the file.

**If the `linkedin:` block is present but `search_method` is null or
missing**, edit the value in place by matching the existing line.

Confirm the write:

```bash
grep -A 1 "^linkedin:" "{bash root}/config.yaml"
```

Output should show `linkedin:` and `  search_method: "chrome"` (or
`"websearch"`).

Then proceed using the chosen method (with the Case A runtime fallback
to WebSearch if `chrome` was picked but the extension isn't connected).

---

## Step 6 — LinkedIn search

Goal: the most-specific recruiter possible — ideally the person actually
filling this role. Specificity matters: a recruiter who recently posted
roles in the same team or domain is far more likely to respond than a
random name from a generic company search.

Work the priorities in order. **For P1–P3, stop as soon as you get a
definitive match.** For P4, **collect all candidates first, then compare
recent activity** before picking — don't stop at the first name.

Skip priorities that don't apply (e.g., P1 requires a position; P2
requires a LinkedIn job URL).

### P1 — Recruiter named on the posting itself

Only applies when a position is in scope and `posting.md` was read.

Scan the `posting.md` content for:

- A "Recruiter", "Contact", or "Hiring Contact" field
- A name in the page footer or application form
- An email address associated with the role

If found: this person is the target. Move to "Look up the LinkedIn
profile" below.

### P2 — LinkedIn "Posted by" attribution

Only applies when a position is in scope and `posting.md` contains a
LinkedIn job URL (matching `linkedin.com/jobs/view/...`).

If using Chrome MCP:

- Navigate to the LinkedIn job URL.
- Read the page. Look for a "Posted by" attribution near the title or
  in the right-hand sidebar.
- If found, capture name and profile URL directly from the page.

If using WebSearch: skip P2 (snippets don't reliably surface this
attribution); fall through to P3.

### P3 — LinkedIn content search for this specific role

Only applies when a position is in scope.

Build the search URL with the position title and company name:

```
https://www.linkedin.com/search/results/content/?keywords=%22{job_title_url_encoded}%22+%22{company_url_encoded}%22+hiring
```

If using Chrome MCP: navigate to the URL, scan results.

If using WebSearch: query

```
site:linkedin.com "{job title}" "{company}" hiring
```

In either case, **filter out job aggregator accounts.** The rule is:
the account must represent an individual human (a recruiter, employee,
or hiring manager), not a board or portal.

Filter heuristic — if the account name itself functions as a brand or
catch-all (rather than being a person's name with a title), skip it.
Concrete examples to skip (non-exhaustive): LinkedIn Jobs, Indeed
Hiring, Built In, Wellfound, Ladders, FlexJobs, Remote.co, RemoteOK,
We Work Remotely, Kickstart Remote, Remote Jobs Board, Tech Jobs
Central, anything ending in "Jobs", "Hiring", "Careers",
"Opportunities", or "Talent Network" as the entity name. A real
recruiter's title may *contain* the word "Talent" or "Hiring", but
their account name is their own name — that's the distinction.

When in doubt, click into the account and look at recent posts. A
human recruiter posts mostly about specific roles or about their work;
a board posts a stream of unrelated listings.

If a recruiter at the target company shared this exact role: that's
the pick. Capture name, title, profile URL, and quote the post that
made the match (you'll need the quote for "How found").

### P4 — Full candidate list, then activity comparison

Used when P1–P3 don't yield a clear match, OR when the skill is in
contacts-only mode (no position) — in that case, jump straight to P4.

**4a — Build the candidate list:**

If using Chrome MCP, navigate to:

```
https://www.linkedin.com/search/results/people/?keywords=technical+recruiter&company={company_url_encoded}
```

Also try variants:

```
https://www.linkedin.com/search/results/people/?keywords=engineering+recruiter&company={company_url_encoded}
https://www.linkedin.com/search/results/people/?keywords=senior+technical+recruiter&company={company_url_encoded}
```

If using WebSearch:

```
site:linkedin.com/in recruiter "{Company}" engineering
site:linkedin.com/in technical recruiter "{Company}"
```

Capture every recruiter you find — name, title, profile URL. Aim for
the full list (3–8 candidates is typical), not just the first two.

**4b — Inspect each candidate's recent posts** (Chrome MCP only):

Navigate to each candidate's activity page:

```
https://www.linkedin.com/in/{profile_slug}/recent-activity/all/
```

Read what they've posted. Note: which roles? Which teams or functions?
How recent is the activity? A recruiter who shared a role adjacent to
the target team last month is a much stronger signal than one who
hasn't posted in six months or works a different function.

If using WebSearch (no live activity scan), 4b is best-effort — the
snippets returned by WebSearch sometimes name recent posts. Scan them
for relevance, but be honest in "How found" if the signal is thin.

**4c — Pick the best domain match:**

Choose the recruiter whose recent activity is closest in domain to the
target role (or, in contacts-only mode, the most engineering-focused
generalist). Document the reasoning: quote the specific post or
activity signal that made them the pick. List 1–2 runners-up as backup
options with their LinkedIn URLs and a one-line reason each.

### Look up the LinkedIn profile (used after P1)

When P1 hits with a name (and possibly an email) but no LinkedIn URL:

If using Chrome MCP: search for the name + company on LinkedIn:

```
https://www.linkedin.com/search/results/people/?keywords={name_url_encoded}&company={company_url_encoded}
```

If using WebSearch:

```
site:linkedin.com/in "{Name}" "{Company}"
```

Capture the profile URL.

### What to capture from the chosen recruiter

Hold the following — you'll write them in Step 7:

- **Full name**
- **Title** (for context)
- **LinkedIn profile URL** — canonicalize using ALL of the following:
  - Replace `m.linkedin.com` with `www.linkedin.com`
  - Replace `linkedin.com/in/` (no subdomain) with `www.linkedin.com/in/`
  - Force `https://` (not `http://`)
  - Lowercase the entire URL
  - Strip everything after `?` (query string)
  - Strip everything after `#` (fragment)
  - Strip a trailing slash if present
  - Final shape: `https://www.linkedin.com/in/{slug}` with no trailing
    slash
  - Example: `https://m.LinkedIn.com/in/Jane-Doe-123/?miniProfileUrn=urn:li:fs_miniProfile:ABC#about`
    → `https://www.linkedin.com/in/jane-doe-123`
- **How found** — be specific. Don't say "people search". Say which
  priority hit and quote the evidence (post title, activity recency,
  field name on the posting). Example: "P3 LinkedIn content search —
  posted 'Senior Backend Engineer, Payments Platform' 3 weeks ago,
  matches the target team."
- **Backup options** — 1–2 alternates, each with name, profile URL, and
  one-line reason

### Login walls and total failure

LinkedIn often requires a logged-in session for useful results from
people and content searches. If Chrome MCP is being used and the
results are empty, blocked, or show a login wall:

- Fall back to WebSearch for one more attempt.
- If WebSearch also yields nothing useful, accept the failure: leave
  the recruiter name as `[Name]` and follow Step 7's stub-entry flow
  for `contacts.md` and Step 8's placeholder flow for `outreach.md`.

Do NOT attempt to log into LinkedIn on the user's behalf.

---

## Step 7 — Append or update contacts.md

### If the file exists, read it now (you already did at Step 4)

Hold the existing recruiter sections.

### If the file does not exist, write the header

Write the host path `companies/{co}/contacts.md` with this header:

```markdown
# Contacts — {Company Name}

*Last updated: {YYYY-MM-DD today}*

---

```

### Successful recruiter pick

Compose a section for the recruiter:

```markdown
## {Recruiter Name} — {Title}

- **LinkedIn:** [{Canonical URL}]({Canonical URL})
- **Recorded:** {YYYY-MM-DD today}
- **Last touched:** {YYYY-MM-DD today}
- **Identified for:** {Position Title (slug: `{pos}`) | "general (no specific position)"}
- **How found:** {Specific evidence — priority + quote / signal}
- **Notes:** {Anything else worth remembering, or "—"}

### Backup options
1. **{Name}** — [{URL}]({URL}) — {one-line reason}
2. **{Name}** — [{URL}]({URL}) — {one-line reason}

---
```

### Re-run logic (match on canonical LinkedIn URL)

Before appending, scan existing sections for a matching `**LinkedIn:**`
line. Match key is the canonicalized URL (lowercase, no trailing slash,
no query string).

- **Same URL already present:** update only the `Last touched` date and
  merge any new content into `Notes` (append, don't replace). Preserve
  `Recorded`, `How found`, `Title`, `Identified for`. Do not duplicate
  the section.
- **No URL captured (placeholder run):** match on name. If the name is
  also unique, treat it as new and append. If the name is ambiguous,
  append a fresh section.
- **No match anywhere:** append the new section before the trailing
  newline of the file.

### Stub when no recruiter found

If Step 6 ended without a chosen recruiter, write a stub section
instead:

```markdown
## Search attempted — no clear pick

- **Last touched:** {YYYY-MM-DD today}
- **For:** {Position Title (slug: `{pos}`) | "general (no specific position)"}
- **What was tried:** {Priorities attempted — e.g., "P3 content search and P4 people search via WebSearch — no relevant results."}
- **Manual search URLs:**
  - https://www.linkedin.com/search/results/people/?keywords=technical+recruiter&company={company_url_encoded}
  - https://www.google.com/search?q=site:linkedin.com/in+recruiter+%22{Company}%22+engineering

---
```

Stub re-run handling — the **scope** of a stub is whatever appears on
its `**For:**` line. A stub `**For:** general (no specific position)`
is distinct from a stub `**For:** {Position Title} (slug: \`{pos}\`)`.

- **New run is a stub, prior stub exists for the same scope:** update
  the prior stub's `Last touched` to today and append a new line to
  `What was tried`. Do not duplicate.
- **New run is a stub, prior stub exists for a different scope** (e.g.,
  prior stub was general; new run is for a specific position): append
  a new stub section. Both stubs coexist.
- **New run is a successful pick, prior stub exists for the same
  scope:** replace the stub section with the real recruiter section.
  The stub goes away.
- **New run is a successful pick, prior stub exists for a different
  scope:** leave the stub in place. Append the new recruiter section
  separately.

Stubs do not have a Backup options block — backups are only recorded
when a clear primary pick is made.

### Update the "Last updated" date in the file header

After writing, edit the `*Last updated:* ...` line to today's date.

### Confirm the write

```bash
head -3 "{bash root}/companies/{co}/contacts.md"
grep -c "^## " "{bash root}/companies/{co}/contacts.md"
```

The grep should return a non-zero count of recruiter sections (or one
stub section).

---

## Step 8 — Draft outreach.md (only when a position folder exists)

If no position is in scope, or the position folder does not exist, skip
this step entirely.

### Build the source anchors

Pull from (in priority order):

1. **`position-fit.md` "Tailored angle"** → opening framing
2. **`position-fit.md` "Why this role fits"** → 2–3 fit anchors
3. **`company.md`** → "why this company" hook (mission, product, scale)
4. **`posting.md`** → fallback for "why this role" if `position-fit.md`
   is missing
5. **`profile.md`** → general fit anchors only when `position-fit.md` is
   absent or thin (under 2 anchors)
6. **`Story Bank.md`** → only if step 5 also produces nothing

If `position-fit.md` is missing, the draft is degraded. Flag it in the
closing summary so the user knows to re-run after `apply-to-job`.

**Degraded fallback** — when `position-fit.md` is missing AND
`company.md` is also missing or thin (under 100 words of body content):

- "Why this company" hook → use a light frame: "I came across your
  posting for {position} and wanted to reach out directly."
- "Why this role" hook → name the position title only; do not
  fabricate role-specific reasoning.
- "Why I fit" anchors → pull 2–3 generic anchors from `profile.md`
  (current title, primary stack, one or two scale or domain facts).
- At the top of the file (immediately under the metadata lines and
  before the first `---` separator), add a clearly visible italic note
  reading: *Thin source anchors. Re-run after apply-to-job for a
  stronger draft.*

A degraded draft is still copy-paste-ready; it just won't have the
specificity a position-fit-backed draft would.

### Compose the LinkedIn message

**Length:** 150–200 words. Hard cap 300.

**Structure:**

1. **Opening** — address by name (or `[Name]` if no recruiter found).
   Say you came across the role and wanted to reach out directly rather
   than just submit into the queue.
2. **Why this company / role** — one specific reason pulled from
   `company.md` mission/product, or from a distinctive aspect of the
   posting. Not generic enthusiasm.
3. **Why I fit** — 2–3 concrete anchors from `position-fit.md` "Why this
   role fits". Use real numbers and technologies. Tight — not a resume
   dump.
4. **Soft close** — happy to share resume, would love to connect. Low
   pressure.

**Tone rules:**

- **No em-dashes** (`—` or `--`). Use commas, semicolons, parentheses,
  or sentence breaks instead.
- **No exclamation points.**
- **No buzzwords:** avoid "passionate about", "synergies", "leverage",
  "impactful", "drive results", "world-class", "top-of-funnel".
- Warm and direct. Reads like a person, not a cover letter.
- Override these defaults only if `profile.md` explicitly says
  otherwise — e.g., the user's `profile.md` Communication Style
  section names a different rule.

### Compose the email version

Same structure, +50–75 words allowed. Use the extra room for one more
supporting anchor, not for filler. Same tone rules.

**Email subject:** short, specific, mentions the role title and one
differentiator. Examples:

- "Staff Engineer, Billing Infra at Stripe — Kafka migration background"
- "Senior Backend, Payments — 50TB sharded MySQL experience"

### Write outreach.md

Use the host path `companies/{co}/{pos}/outreach.md`. Template:

```markdown
# Outreach — {Company Name} ({Position Title})

**Recruiter:** {Recruiter Name | "[Name]" if not found}
**LinkedIn:** [{Canonical URL}]({Canonical URL}) | "—" if not found
**Drafted:** {YYYY-MM-DD today}

---

## LinkedIn message

{The draft — copy-paste ready, 150–200 words.}

---

## Email subject

{Short, specific subject line.}

## Email version

{Slightly longer, +50–75 words. Same tone.}

---

## Source anchors (used in the draft)

- **Why this company:** {one line — pulled from company.md or posting}
- **Why this role:** {one line — pulled from position-fit.md tailored angle, or posting}
- **Why I fit:** {2–3 anchors — pulled from position-fit.md "Why this role fits"}

---

## Backup recruiter options

1. **{Name}** — [{URL}]({URL}) — {one-line reason}
2. **{Name}** — [{URL}]({URL}) — {one-line reason}

(If no backups: write "None — only one viable candidate found.")
```

### Placeholder draft when no recruiter found

Use the same template but:

- `**Recruiter:**` → `[Name]`
- `**LinkedIn:**` → `—`
- LinkedIn message opening → "Hi [Name],"
- Email subject and version → keep the role-specific framing; the only
  variable is the addressee
- Backup recruiter options → write "None found this session — see
  contacts.md for manual search URLs."

This gives the user a wired-up draft to copy-paste once they find a name.

### Confirm the write

```bash
head -5 "{bash root}/companies/{co}/{pos}/outreach.md"
```

If the head check returns empty, report the error and continue to
Step 9 — do not stop the skill over this.

---

## Step 9 — Append CLAUDE.md session log

Read `CLAUDE.md` using the Read tool (host path). Append one row to the
session log table:

```
| {YYYY-MM-DD} | find-recruiter: {Company}{ — {Position}} | {one observation — e.g., "P3 hit: posted target role 3 weeks ago. Outreach drafted." or "No clear recruiter; stub written, [Name] placeholder draft."} |
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
proceed to Step 10.

---

## Step 10 — Closing summary

Report concisely. The user can read the files for detail.

```
Recruiter search complete: {Company}{ — {Position Title} if in scope}

Recruiter: {Name | "Not found — manual search needed"}
LinkedIn:  {URL | "—"}
How found: {one line — priority + evidence}

Files written:
  contacts.md  ({appended | updated | stub})
  outreach.md  ({drafted | drafted with [Name] placeholder | skipped (no position)})

Backup options:
  - {Name} — {URL}
  - {Name} — {URL}
  (or "None")

Suggested next steps:
  - {1–2 short suggestions, e.g., "Send the LinkedIn DM today" or
    "Run apply-to-job to bootstrap the position before re-running this
    skill" or "Refresh company.md before the screen — research is N
    months old"}
```

Keep it short. Skip sections that don't apply.

---

## Edge cases

**Composed mode invocation message is malformed** (missing slugs or
paths): treat the invocation as Standalone and run identity capture at
Step 2 against whatever was provided. Don't fail.

**Company name resolves to an existing slug used by a different
company** (slug collision — same situation `apply-to-job` handles): use
AskUserQuestion to pick an alternate slug:

- Question: "A folder for a different company already uses the slug
  `{co}` ({existing company name from `company.md` heading}). What slug
  should this {new company name} use?"
- Options: "Use `{co}-2`" / "Use `{co}-{disambiguator}`"

Apply the chosen slug.

**`contacts.md` already has the same recruiter for a different position
within the same company:** that's normal — recruiters span positions.
Treat as a same-URL match per Step 7's re-run logic; update `Last
touched`, append the new position to a "Identified for" list (or to
`Notes` if "Identified for" was a single value).

**LinkedIn returns a login wall on every search** even with Chrome MCP:
fall back to WebSearch as documented at Step 6, then to the stub flow
if both fail. Do not retry against LinkedIn after a login wall — the
session won't change mid-run.

**WebSearch returns nothing useful even with Chrome unavailable:** stub
contacts.md (per Step 7), placeholder outreach (per Step 8), tell the
user the manual search URLs at Step 10.

**User aborts in the middle of the standalone bootstrap offer (Step 3)
or during identity capture (Step 2):** if no files have been created
yet, exit silently with a one-line note. If `companies/{co}/` was
created at Step 3 and is empty, remove it:

```bash
rmdir "{bash root}/companies/{co}" 2>/dev/null
```

`rmdir` only succeeds on empty directories — safe.

**`config.yaml` write fails when persisting `linkedin.search_method`**
(Step 5): proceed using the chosen method this session. The next
invocation will lazy-prompt again. Note the write failure briefly to
the user but do not stop.

**Resume the skill after `apply-to-job` bootstrap:** when find-recruiter
chains to `apply-to-job` at Step 3, control returns here after that
skill finishes. Re-read context files (Step 4 again — the fresh
`position-fit.md` is now available), then continue from Step 5.

---

## Principles

**Specificity over volume.** A recruiter whose recent activity matches
the target team is worth more than five names from a generic company
search. The "How found" reasoning is a load-bearing field — write it
with a concrete quote or signal, not a generic attribution.

**Leaf, with one exception.** find-recruiter does not call sibling
skills, with the single exception of the `apply-to-job` bootstrap offer
at Step 3. It reads what other skills have produced (`position-fit.md`,
`company.md`, `posting.md`) and writes its own outputs.

**Honest about gaps.** When `position-fit.md` is missing, the outreach
draft is degraded. Surface that in the closing summary. Don't fake
specificity by inventing anchors; lift from real source files only.

**Honest about failure.** If no recruiter is found, write a stub —
documenting the attempt is more useful than silence. Provide the manual
search URLs.

**No log-in attempts.** If LinkedIn requires login and Chrome isn't
already authenticated, fall back. Don't try to drive a login flow.

**No em-dashes** in any user-facing message or written content. **No
exclamation points** in outreach drafts. Override only when `profile.md`
explicitly specifies a different rule.

**Path translation matters.** Use host paths for file tools (Read, Write,
Edit). Use bash-mounted paths for shell commands. Re-derive the bash
root in each bash block; environment does not persist.
