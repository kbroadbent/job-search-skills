---
name: company-research
description: >
  Research a company and write a structured reference document used by interview-prep,
  apply-to-job, and find-recruiter. Use when the user says "research [Company]", "look
  into [Company] for me", "I'm interviewing at [Company]", "prep me for [Company]",
  "add [Company] to my companies folder", or shares a job posting URL and wants context
  on the company. Also called by apply-to-job as part of a full position workflow. Writes
  companies/{co}/company.md — the foundation other skills build on.
---

# company-research

Research a company thoroughly and write `companies/{co}/company.md`. This is the single
output of this skill. No position-specific content, no scripts, no per-round prep — those
belong to other skills. The quality of this document directly determines how well
interview-prep and apply-to-job perform.

## Step 0 — Verify directory and load context

Identify the job search root directory. Discover mounted folders with:
```
find /sessions/*/mnt -maxdepth 1 -type d
```

The job search root is the folder containing `config.yaml` at its top level. If none found,
tell the user the plugin hasn't been initialized and offer to run `job-search-init`. Stop
until init completes.

Hold both path forms for later:
- Host path (for file tools): e.g., `/Users/.../2026 Job Search`
- Bash-mounted path (for shell): e.g., `/sessions/*/mnt/2026 Job Search`

Verify these files exist:
- `config.yaml`
- `profile.md`
- `insights.md`
- `CLAUDE.md`
- `study-plans/index.md`

If any are missing, tell the user the directory isn't fully initialized and offer
`job-search-init`. Stop until init completes.

Read all five files. Hold the contents for the rest of the session.

## Step 1 — Identify the company and any provided posting

Extract from the user's message:
- **Company name** — required
- **Job posting** — optional. May be a URL, pasted text, or absent entirely.
- **Position title** — optional, may be implied by the posting

If the company name is ambiguous (e.g., "Block" could be Block Inc. or another company),
confirm with the user before proceeding.

Derive the **company slug**: lowercase, spaces → hyphens, strip all punctuation (commas, periods, apostrophes, parentheses — drop them entirely; don't replace with hyphens), preserve numbers.
Examples: "Stripe" → `stripe`, "Block, Inc." → `block-inc`, "Datadog" → `datadog`, "O'Reilly Media" → `oreilly-media`, "A9.com" → `a9com`, "Scale AI" → `scale-ai`.
If the slug would be ambiguous (e.g., "Block" matches multiple companies), confirm which company with the user before deriving the slug.

Check whether `companies/{slug}/company.md` already exists using bash:
```
ls "{bash root}/companies/{slug}/company.md" 2>/dev/null
```

If the file exists, use AskUserQuestion:
- Question: "company.md already exists for {Company} (research date visible in the file header). What would you like to do?"
- Options:
  - "Refresh — run new research and overwrite" (description: "Re-runs all research; replaces the existing file")
  - "Use existing — skip research" (description: "Skips to the handoff offer without re-running research")

If the user picks "Use existing": if a posting was provided in the user's message, still run Step 3 to extract posting context (it takes one fetch, no searches), then jump to Step 12 (handoff offer). If no posting was provided, jump directly to Step 13 (sign off). Otherwise continue to Step 2.

## Step 2 — Choose research depth

Use AskUserQuestion:
- Question: "How thorough should the research be?"
- Options:
  - "Quick — recruiter screen ready (~10 searches)" (description: "Company basics, tech stack, comp range, culture overview, interview format")
  - "Standard — technical round ready (~20 searches)" (description: "Full depth on all sections: engineering blog reads, Glassdoor review pages, per-round interview patterns")
  - "Thorough — final round / target company (~30 searches)" (description: "Everything in Standard plus targeted deep dives, trend analysis in reviews, architecture content")

Hold the chosen tier. In Steps 4–9, each research step lists searches under **Required (all tiers)**, **Standard/Thorough adds**, and **Thorough adds** headings. Run only the searches listed for your tier. Stop when you've completed that tier's searches for a section — don't continue into the next tier's searches unless you upgraded. A Quick run totals roughly 11 searches across all sections; Standard roughly 23; Thorough roughly 35.

## Step 3 — Extract posting context (if a posting was provided)

If the user provided a posting URL, fetch it:
```
WebFetch(url)
```

If fetch fails, ask the user to paste the text instead.

From the posting (URL or pasted), extract:
- Job title
- Key responsibilities (the top 3–5)
- Required qualifications
- Tech stack explicitly mentioned
- Seniority signals (years of experience, scope language, leadership expectations)

Hold this as **posting context**. Use it throughout research to:
- Focus tech stack searches on mentioned technologies
- Prioritize interview pattern searches for the specific role level
- Tailor the "Notes for this role/level" section in company.md

Do not write any position-specific output files at this step. Posting analysis beyond
what's needed to focus research belongs to `apply-to-job`.

## Step 4 — Research: company basics

Run searches in this order. Stop early if you have confident data; run all for Thorough.

**Required (all tiers):**
1. `"{Company}" site:en.wikipedia.org` OR `"{Company} Wikipedia"`
2. `"{Company} Crunchbase"` OR `"{Company} funding valuation {year}"`
3. `"{Company} recent news {year}"` — look for layoffs, reorg, acquisitions, IPO, leadership changes in the last 12 months

**Standard/Thorough adds:**
4. `"{Company} employees headcount {year}"`
5. `"{Company} revenue earnings"` (if company appears to be public)

Capture: founding year, HQ, employee count, public/private status (ticker if public),
revenue or valuation, total funding (last round if private), any significant recent events.

Note any recent events (layoffs, reorgs, acquisitions) prominently — the user needs this
context before any interview conversation.

## Step 5 — Research: tech stack

**Required (all tiers):**
1. `"{Company} engineering blog"` — if found, WebFetch 1–2 posts. Selection priority: (a) posts matching technologies from the posting context or the user's background in profile.md, then (b) the most recent architecture or infrastructure posts. Pull specific details — architectural decisions, scale challenges, technology choices — not just the URL.
2. `"{Company} tech stack" OR "{Company} stackshare"`

**Standard/Thorough adds:**
3. `"{Company} infrastructure" AWS OR GCP OR Azure OR Kubernetes`
4. `"{Company} engineering blog" architecture OR microservices OR platform` — target architecture-specific posts

**Thorough adds:**
5. `"{Company}" "we use" OR "built with" site:linkedin.com OR site:medium.com`
6. If a posting was provided, search for each major technology named in it: `"{Company} {tech}"` — understand how they actually use it

When you read engineering blog posts, capture: languages, frameworks, cloud provider,
databases, CI/CD, observability tooling, notable architectural patterns or decisions.

If data is sparse or inferred from job postings rather than confirmed sources, note it
inline: `(inferred from job postings — not confirmed)`.

## Step 6 — Research: compensation

Read `profile.md` for the user's target role level and use it to focus searches. If profile.md doesn't specify a target role level, default to "staff engineer" in searches and note the assumption inline in company.md's Compensation section.

**Required (all tiers):**
1. `"{Company} {target role} salary levels.fyi"` — WebFetch if the page loads
2. `"{Company} staff engineer compensation blind"` OR `"{Company} {target role} salary blind"`

**Standard/Thorough adds:**
3. `"{Company} engineering levels"` OR `"{Company} level system"` — understand internal level mapping
4. `"{Company} RSU equity refresh"` — equity structure, vesting, refresh cycles

**Thorough adds:**
5. `"{Company} {target role} salary glassdoor"`
6. `site:levels.fyi "{Company}"` — any additional data points

Capture: base salary range, equity details (RSU vs. options, vesting schedule, refresh
policy), bonus structure if any, total comp range, internal level mapping (e.g., "Staff = L6").

If a data point isn't findable after genuine effort, write "Not found in public sources"
rather than approximating. Compensation data is used for negotiation — accuracy matters.

If sources give conflicting ranges (e.g., Glassdoor shows $180–$210k, Blind shows $200–$240k),
present both with source attribution rather than averaging: "Glassdoor: $180–$210k; Blind: $200–$240k."

## Step 7 — Research: culture and reviews

Goal: identify **trends** across multiple sources, not one-off data points. A complaint
that appears in 6 of 10 recent reviews is signal; a single bitter review is noise.

**Required (all tiers):**
1. `"{Company} glassdoor reviews engineering"` — WebFetch if it loads; read for recurring themes
2. `"{Company} blind reviews"` OR `site:teamblind.com "{Company}"`

**Standard/Thorough adds:**
3. `"{Company} engineering culture reddit"` OR `site:reddit.com "{Company}" software engineer`
4. `"{Company} work life balance engineer"`
5. `"{Company} management culture engineering"`

**Thorough adds:**
6. `"{Company} pros cons working engineer"`
7. `"{Company} career growth promotion transparency"`
8. Look at review dates — has sentiment shifted in the last 12 months? Search for any catalyst: `"{Company} layoffs {year}"` or `"{Company} reorg {year}"` if not already found in Step 4

When reading Glassdoor or Blind pages:
- Note the overall rating and number of reviews
- Identify recurring pros (themes appearing across multiple reviews)
- Identify recurring cons (same)
- Flag engineering-specific sentiment separately from general employee sentiment
- Flag any red flags the user should probe in interviews

## Step 8 — Research: interview process

Run separate searches for each interview type. Use posting context (if available) to
weight which round types to research most deeply.

**Coding rounds (required for Standard/Thorough; for Quick, only run if posting context explicitly mentions a coding/technical screen):**
1. `"{Company} technical phone screen questions glassdoor"`
2. `"{Company} coding interview" questions OR format OR platform`
3. `site:leetcode.com "{Company}" interview`

**System design rounds (required for Standard/Thorough; skip for Quick):**
4. `"{Company} system design interview questions glassdoor"`
5. `"{Company} system design interview" staff OR senior`

**Behavioral/leadership rounds (all tiers):**
6. `"{Company} behavioral interview questions glassdoor"`
7. `"{Company} culture values engineering"`

**General process (all tiers):**
8. `"{Company} interview process engineering"`
9. `"{Company} interview experience" site:reddit.com OR site:teamblind.com`

**Thorough adds:**
10. WebFetch Glassdoor interview reports for this company if available — read for specific questions and candidate observations

Capture per round type: format (platform, duration, number of problems), commonly
reported question topics, staff-level expectations where noted.

## Step 9 — Research: targeted deep dives (Standard and Thorough only)

Based on what surfaced in Steps 4–8, run 2–4 (Standard) or 4+ (Thorough) targeted
follow-up searches on anything particularly relevant:

- A recent migration or infrastructure project mentioned in the engineering blog → dig in
- A technology from the posting or the user's background → search how the company uses it and what challenges they've faced
- A recent news event (acquisition, reorg) that would affect the interview context → understand it
- A specific engineering talk, paper, or postmortem that came up → WebFetch and read it

The goal is to surface one or two things the user can reference in an interview that
signal genuine engagement with the company's technical work.

## Step 9.5 — Synthesize engineering blog findings

Before writing, consolidate all technical content found during research (Step 5 blog
reads and any Step 9 deep dives) into a list of findings for the Engineering Blog &
Technical Depth section. Each entry must be specific — an architectural decision, a
scale challenge, a technology choice — not "they have a blog". If nothing substantive
was found, prepare the note "No public engineering blog or architecture content found."

## Step 10 — Write company.md

**Path clarification:** use the bash-mounted path for shell commands (mkdir, head) and
the host path for the Write tool. Both were captured in Step 0.

Create the folder if it doesn't exist (bash path):
```bash
mkdir -p "{bash-mounted root}/companies/{slug}"
```

Write `companies/{slug}/company.md` using the Write tool at the host path:
`{host root}/companies/{slug}/company.md`

Use this template, filling every section from the research. Where data isn't available,
write "Not found in public sources" rather than leaving the section blank or approximating.

For the Sentiment shift section: if you only ran Quick or Standard tier culture searches
and didn't specifically research historical sentiment, write "Not researched at this depth
tier." Don't fabricate a trend.

```markdown
# {Company Name}

*Research date: {YYYY-MM-DD}. Compensation and review data is point-in-time — refresh if more than 3 months old.*

## Overview
{2–3 sentences: what the company does, why it matters, current stage (startup / growth / public / enterprise).}

## Key Facts
| Detail | Info |
|--------|------|
| Founded | {year} |
| Headquarters | {location} |
| Employees | {count or range} |
| Public / Private | {status; ticker if public} |
| Revenue / Valuation | {if available} |
| Funding | {total raised + last round if private} |
| Recent events | {layoffs, reorg, acquisition, IPO — last 12 months; "None noted" if clean} |

## Tech Stack
{Synthesized from engineering blog, job postings, StackShare, talks. Note the source and confidence for each category if inferred rather than confirmed.}

- **Languages:** ...
- **Frameworks:** ...
- **Infrastructure / Cloud:** ...
- **Databases:** ...
- **CI/CD & Tooling:** ...
- **Notable architecture patterns:** ...

Sources: {links}

## Compensation
{Data for the target role level from profile.md. Use "Not found in public sources" for any missing data point — never approximate for negotiation purposes.}

- **Base range:** $X–$Y
- **Equity:** {RSU or options; vesting schedule; refresh policy}
- **Bonus:** {if applicable; "Not found" if not}
- **Total comp range:** $X–$Y
- **Level mapping:** {how this company's levels map to the target role — e.g., "Staff = L6"}
- **Data confidence:** {note data sources and freshness}

Sources: {links to levels.fyi, Glassdoor, Blind, etc.}

## Culture & Reviews
{Identify trends across multiple sources. A theme appearing in multiple reviews is signal; a single data point is noise. Cite how frequently a theme appears when possible.}

**Overall ratings:**
- Glassdoor: {X/5 (N reviews)}
- Blind / other: {if available}

**Positive trends:**
- {trend} — {evidence: how many reviews / sources mention it}

**Negative trends:**
- {trend} — {evidence: how many reviews / sources mention it}

**Engineering-specific sentiment:**
- {What engineers say, distinct from general employee sentiment}
- {Management quality for engineering teams}
- {Career growth and promotion transparency}
- {Work-life balance}

**Sentiment shift (recent vs. historical):**
- {Has sentiment changed in the last 12 months? Catalyst if known.}
- {"No notable shift detected" if sentiment appears stable.}

**Red flags to probe in interviews:**
- {Anything worth asking about directly — or "None noted" if clean}

Sources: {links}

## Interview Process
{Synthesized from Glassdoor, Blind, Reddit, LeetCode. Treat as signal, not ground truth — specifics vary by team and hiring manager.}

**General process:**
- Rounds: {list in order — e.g., recruiter screen → tech screen → system design → behavioral → ...}
- Timeline: {typical duration from first contact to offer}

**Coding rounds:**
- Format: {platform (CoderPad, HackerRank, etc.), duration, number of problems}
- Difficulty: {easy / medium / hard; typical LeetCode equivalent}
- Common topics reported: {e.g., arrays, trees, DP — with frequency if known}
- Language restrictions: {if any; "None reported" otherwise}

**System design rounds:**
- Format: {whiteboard / shared doc / presentation}
- Domain: {company-specific vs. generic; which if specific}
- Staff-level expectations: {what differentiates a strong staff answer at this company}
- Common topics reported: {list}

**Behavioral / leadership rounds:**
- Who conducts: {HM, cross-functional, skip-level, etc.}
- Format: {structured rubric vs. conversational}
- Common questions reported: {list}
- Values that inform answers: {what they reward — connect to company values}

**Notes for this role / level:**
{Any specifics found for the role level in scope, or "No role-specific data found."}

Sources: {links}

## Engineering Blog & Technical Depth
{Key findings from engineering blog posts, talks, or public architecture content. Each entry should surface something specific — an architectural decision, a challenge at scale, a technology choice — not just "they have a blog".}

- {Post title or topic}: {1–2 sentences on what it reveals}
- {Post title or topic}: {1–2 sentences}

{If no public technical content was found, write: "No public engineering blog or architecture content found."}

Sources: {links}
```

After writing, confirm the write succeeded by reading the first 10 lines back (bash path):
```bash
head -10 "{bash-mounted root}/companies/{slug}/company.md"
```

If the read fails or returns empty, report the error and stop. Do not proceed to Step 11.

## Step 11 — Append CLAUDE.md session log

Read `CLAUDE.md`, then append one row to the session log table:

```
| {YYYY-MM-DD} | company-research: {Company} ({depth tier}) | {one observation — e.g., "strong engineering blog; comp data sparse"} |
```

If CLAUDE.md has no session log table yet, add one with the header:
```markdown
## Session Log

| Date | Covered | Observations |
|------|---------|--------------|
```

## Step 12 — Handoff offer (if a posting was provided)

If the user provided a job posting in Step 1 (URL or pasted text), offer a handoff:

> "Company research is done — `companies/{slug}/company.md` is written. You also shared a job posting for {position title if known, else 'a position'}. Want me to continue with `apply-to-job` to add this to your pipeline, generate a position-fit analysis, and tailor your resume?"

Use AskUserQuestion:
- Question: "Continue with apply-to-job for this position?"
- Options:
  - "Yes — add to pipeline and generate position-fit" (description: "Runs apply-to-job: posting analysis, pipeline row, position-fit.md, resume tailoring")
  - "Not now — just the company research" (description: "Stops here")

If the user picks yes, hand off to apply-to-job with the following context already in hand — do not ask apply-to-job to re-derive these:
- Company name and slug (e.g., "Stripe", `stripe`)
- Host path to company.md (e.g., `{host root}/companies/stripe/company.md`) — tell apply-to-job company research is complete and the file is ready
- The raw posting: if it was a URL, pass the URL; if it was pasted text, pass the text
- Position title (from Step 3, or "(unknown)" if not extractable)

Invoke apply-to-job with a brief handoff message: "Company research for {Company} is complete — company.md is written. Continuing with apply-to-job for {position title}. Posting: {URL or 'pasted text, held in context'}."

If no posting was provided, skip this step and go straight to Step 13.

## Step 13 — Sign off

Report what was written and flag any material gaps at a summary level — don't repeat
what's already documented as "Not found in public sources" inside the file, but do
surface anything the user should act on before their first conversation:

```
company.md written → companies/{slug}/company.md

Research quality: {one sentence — e.g., "Strong engineering blog and comp data; interview
patterns thin (few Glassdoor reports found)."}

{If any section is missing data that would meaningfully affect prep — e.g., no comp data
at all, no interview process found — say so here and suggest what to do: "Comp data not
found — ask the recruiter directly in the first call."}
```

Don't list every gap; only flag ones that change how the user should approach the process.

---

## Edge cases

- **WebFetch blocked (Glassdoor, Blind, Levels.fyi):** These sites frequently block scraping. If WebFetch fails, fall back to search snippet data and note it: "(from search snippets — full page unavailable)". Do not retry with different tools or fabricate data.
- **Company not in English sources:** If the company is primarily covered in non-English sources, note this and search for English-language content from their engineering blog or English-language review sites.
- **Very small or private company with little public data:** Write what's available, leave gaps as "Not found in public sources", and note in the sign-off that the research is thin. Don't pad with guesses.
- **User-provided posting fetch fails:** Ask the user to paste the text. If they decline, proceed without posting context (treat as standalone research).
- **Slug collision:** If `companies/{slug}/` already exists but its company.md header shows a different company name, tell the user: "A folder for a different company already uses the slug `{slug}`. Suggest a different slug (e.g., `{slug}-2` or `{full-name-slug}`)." Prompt via AskUserQuestion with a suggested alternative. Once the user confirms a new slug, use it for all subsequent steps and re-run the existence check from Step 1.

---

## Notes for implementation

- **Pure research output.** company.md contains facts, patterns, and synthesized observations — no scripts, no coaching notes, no "how to answer this question". Those belong to interview-prep.
- **Trends over data points.** In the culture section especially, one negative review is noise. Five reviews saying the same thing is a trend. Synthesize; don't transcribe.
- **Source every section.** Every section in the template has a Sources line. Fill it. The user needs to be able to verify data and check for staleness.
- **profile.md drives targeting.** The user's target role level, domain background, and goals in profile.md should shape which sections get the most research depth and which technologies to dig into.
- **Company-level only.** This skill writes one file: `companies/{co}/company.md`. Position folders, fit analyses, and contacts are owned by other skills (`apply-to-job`, `find-recruiter`).
- **No contacts.md.** Even if recruiter names surface during research (e.g., from LinkedIn), don't write contacts.md. That's find-recruiter's output.
