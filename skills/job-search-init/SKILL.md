---
name: job-search-init
description: >
  Initialize a job search directory with the artifacts every other skill in the job-search plugin reads from and writes to. Use this skill when the user wants to "set up a job search", "initialize a job search folder", "start a new job search system", "bootstrap my job search workspace", or otherwise stand up the scaffolding for a fresh search. This is a one-time setup skill — it walks the user through a short interview, then writes config.yaml, CLAUDE.md, profile.md, insights.md, Story Bank.md, and an empty study-plans/ structure. After init, the directory is ready for create-study-plan, apply-to-job, company-research, and the rest of the plugin to use.
---

# job-search-init

Stand up a new job search directory. Conduct a short interview with the user, then write the full set of artifacts the other plugin skills depend on.

## Overview

This skill runs once at the start of a job search. After it completes, the target directory contains:

- `config.yaml` — system configuration (resume filename, user info, active study pointer)
- `CLAUDE.md` — lean session entrypoint pointing at the other files
- `profile.md` — durable user context (identity, target role, strengths, weaknesses, goals, constraints, avoiding, communication style)
- `insights.md` — empty file for accumulating cross-study memory
- `Story Bank.md` — empty story bank with a starting set of categories
- `study-plans/index.md` — empty study roster
- `companies/` — empty directory
- `study-plans/` — empty directory
- `{user's resume filename}.docx` — copied from source, original filename preserved

The interview is interactive but deliberately short. Most of what makes the system valuable accumulates from `study-session` and `interview-prep` runs, not from heavy upfront introspection.

## Step 0 — Determine the target directory

Find the target directory:

1. Discover available workspace mounts with `find /sessions/*/mnt -maxdepth 1 -type d` (bash). Each result corresponds to a folder the user has access to in this session.
2. If exactly one workspace folder is selected, propose its absolute host path (visible to the file tools as `/Users/.../{folder name}`). Use AskUserQuestion with options "Use this folder" / "Pick a different path".
3. If multiple workspace folders are mounted, list them and ask which (or "Pick a different path").
4. If none, or the user picks "different path", prompt for an absolute path with a plain conversational question.

Once the target is identified:

- Verify the directory exists with `ls -d "{target}"` (bash, with the bash-mounted path). If it doesn't, ask the user whether to create it; if yes, run `mkdir -p`.
- Check for existing artifacts this skill would write: `config.yaml`, `CLAUDE.md`, `profile.md`, `insights.md`, `Story Bank.md`, `study-plans/index.md`. List which ones exist (any subset, including just one).
- If any exist, ask with a single AskUserQuestion: question text "These files already exist: {comma-separated list}. Overwrite all of them, or cancel?", options "Overwrite all" / "Cancel". If they cancel, stop the skill cleanly without writing anything.

Save the absolute target path. Every later step uses it. Note the bash-mounted path equivalent too (under `/sessions/*/mnt/`) — Step 3's resume copy needs it.

## Step 1 — Conduct the interview

Ask each question as a separate user turn. Use plain conversational prompts for free-form questions. Use AskUserQuestion only for the constrained-choice questions noted below.

Frame the optional questions explicitly so the user knows skipping is fine. Don't lecture or pad — keep the prompts short.

### Q1: Name (required)

> What name should I use? This goes in your resume tailoring, outreach messages, and profile.

Free-form. Capture as a single string.

### Q2: Email (required)

> What email address?

Free-form.

### Q3: Resume path (required)

> Where is your resume? Give me a file path (absolute, or drop the file into Cowork and tell me the filename).

After the user responds, resolve the source location. The user could provide:

- An absolute path on their host filesystem (e.g., `/Users/foo/Resume.docx`)
- A filename that was uploaded into the Cowork session — find it via `find /sessions/*/mnt/uploads -name "*.docx"`
- A path relative to the target directory or workspace folder

Verify the file exists and is a `.docx`. If not, explain briefly (resume-tailor needs `.docx` to edit) and ask again. Don't loop the rest of the interview — just re-ask Q3 until you have a valid path or the user gives up.

Record the original filename (basename of the source path). This goes into `config.yaml`.

The actual file copy happens in Step 3.

### Q4: Target role (required)

> What kind of role are you targeting? Free-form — level, function, industry, company size or stage. Whatever shape that takes for you.

Capture verbatim. Goes into `profile.md` under Target Role.

### Q5: Strengths (optional, skippable)

> Anything you already know about your strengths going in? Skip if you'd rather let these emerge as you work — there'll be plenty of opportunities to capture them later through study sessions and interviews.

Free-form. If the user skips or says "skip" / "not yet" / similar, mark as empty. Do not push.

### Q6: Weaknesses (optional, skippable)

> Anything you already know about your weak spots or areas you want to shore up? Same deal — skip if nothing specific comes to mind. The useful version of this list usually accumulates from study sessions and interview prep, not from cold introspection.

Free-form. Skippable.

### Q7: Goals (required)

> What does a successful job search look like for you? One paragraph is plenty.

Free-form.

### Q8: Constraints (optional, skippable)

> Any hard constraints — runway, geography, comp floor, role types to exclude, anything that's a hard no?

Free-form. Skippable.

### Q9: Avoiding (optional, skippable)

> Anything you want to avoid in a role? Tech stacks, industries, work patterns, responsibilities, company characteristics — both hard no's and soft preferences. Severity can be noted inline (e.g., "defense industry (hard no)", "legacy COBOL (prefer not)"). Skip if nothing specific comes to mind.

Free-form. Skippable. Read by `position-fit` later to flag matches against postings.

### Q10: Communication style (optional, skippable)

> Anything about how you want communication to sound? Tone, voice, do's, don'ts. For example: "warm but direct, no corporate-speak, no em-dashes in outreach, no exclamation points."

Free-form. Skippable. If skipped, the section in `profile.md` will note that defaults will be used.

### Q11: Calendaring system and calendar selection (constrained)

Several skills in this plugin can write events to a calendar — `create-study-plan` for daily study blocks, `interview-prep` and `apply-to-job` for interview reminders, etc. The exact tooling depends on which calendaring system the user uses, so we capture both the provider and (where applicable) the specific calendar inside it. Pick once here; every skill reads from `config.yaml`.

#### Step 11a — Pick a provider

Use AskUserQuestion:

- Question: "What calendaring system do you use, if any? Skills will write events to whatever you pick here."
- Options:
  - "Google Calendar" (description: "Uses the gws CLI for events")
  - "Other" (description: "Tell me which — I'll record it; integration kicks in once support is added")
  - "Skip — don't use calendar integration" (description: "Skills won't write to any calendar; you can change this later by editing config.yaml")

#### Step 11b — Provider-specific follow-up

Dispatch on the answer:

**If "Google Calendar":**

Check whether the `gws` CLI is available:

```bash
which gws
```

- If `gws` is **not** available: tell the user briefly — "Google Calendar selected, but `gws` doesn't seem to be installed. I'll record the provider in `config.yaml` so the choice survives; the next skill that needs the calendar will prompt to pick one once `gws` is set up." Set `provider: "google"` with `name: null` and `id: null`.
- If `gws` **is** available: run `gws calendar list` and parse the output. Each calendar has a name (e.g., "Planning") and an id (a long Google-issued string). Use AskUserQuestion:
  - Question: "Which Google calendar should job-search skills use?"
  - Options: one per calendar (option title = name, description = id). Include a final option: "Skip for now — pick later" (description: "I'll save the provider only; skills will prompt for a specific calendar when needed").

  Capture both name and id. If the user picks "Skip for now," leave them as null but still set `provider: "google"`.
- If `gws calendar list` errors (auth not set up, network failure, etc.): tell the user the error briefly and record `provider: "google"` with `name: null` and `id: null`. Don't fail the skill.

**If "Other":**

Plain conversational prompt: "Which calendaring system? Outlook, Apple Calendar, Fastmail, something else?"

Capture the user's answer as the `provider` value (normalize to lowercase, replace spaces with hyphens — e.g., `outlook`, `apple`, `fastmail`). Set `name` and `id` to null. Tell the user: "Recorded as `{provider}`. I don't currently have tooling for that, so skills will note the preference and skip calendar writes until support is added. You can edit `config.yaml` directly anytime."

**If "Skip":**

Write `calendar: null` (single-line null, not the nested form) into `config.yaml`. Skills that need a calendar will treat this as "not configured" and either prompt or skip.

### Q12: LinkedIn search method (constrained)

`find-recruiter` searches LinkedIn for recruiters and the user might
prefer one of two approaches. Capture the preference here so
`find-recruiter` doesn't have to ask later.

Use AskUserQuestion:

- Question: "How should `find-recruiter` search LinkedIn for recruiters?"
- Options:
  - "Chrome MCP — live navigation" (description: "Higher-fidelity recruiter search with activity scans. Requires the Claude in Chrome extension to be installed and connected.")
  - "WebSearch — snippet-only" (description: "Works without any browser extension. Lower fidelity but no setup needed.")

Capture the answer. Goes into `config.yaml` under `linkedin.search_method`
in Step 2 (`chrome` or `websearch`).

Note: `find-recruiter` will fall back to WebSearch at runtime if `chrome`
is configured but the Chrome extension isn't connected in a given
session — this preference is the *default*, not a hard requirement.

### Q13: Mail label root (free-form, optional)

`label-job-search-emails` files job-search emails into Gmail sublabels under a
single parent label. Capture the parent label name here so the user
doesn't have to set it later, and so it stays consistent across runs.

Plain conversational prompt:

> What top-level Gmail label should the label-job-search-emails skill use to file job-search mail? Sublabels go under it, like `{Job Search}/Stripe`. Default is `Job Search`. Press enter to accept the default, or give me your own label.

Capture the answer as a string. If empty / "default" / "skip", record
`Job Search`. Goes into `config.yaml` under `mail.label_root` in Step 2.

Note: `label-job-search-emails` will lazy-prompt and write back if `mail.label_root`
is missing (handles older configs created before this question existed).

### Q14: Mail skip senders (free-form, optional)

`label-job-search-emails` skips classification for senders in this list — useful
for former employer domains or internal newsletters that mention
"engineering interview" but aren't actually job-search mail.

Plain conversational prompt:

> Any sender domains or substrings the label-job-search-emails skill should skip when triaging mail? For example, a former employer's domain, or a newsletter that mentions interviews but isn't recruiter mail. Comma-separated, or skip.

Free-form. Skippable. Parse into a list of trimmed strings (split on
comma, drop empty entries). If skipped, record an empty list. Goes
into `config.yaml` under `mail.skip_senders` in Step 2.

### Q15: Bootstrap a study plan now? (constrained)

Use AskUserQuestion with this question and these options:

- Question: "Want to bootstrap a study plan now?"
- Options:
  - "Yes — set up a study plan" (description: "Chain into create-study-plan after init finishes")
  - "Not now" (description: "Just finish init; I can run create-study-plan later")

## Step 2 — Write the artifacts

Create the empty subdirectories first (Write only creates files, not directories). Use the bash-mounted target path:

```bash
mkdir -p "{bash-target}/companies" "{bash-target}/studies"
```

Then write each file using the Write tool with the host filesystem target path, in this order:

1. `config.yaml`
2. `CLAUDE.md`
3. `profile.md`
4. `insights.md`
5. `Story Bank.md`
6. `study-plans/index.md`

If any Write fails, halt the skill and report which file failed and the error. Don't try to roll back partial writes — leave them in place and tell the user what's there. They can re-run after fixing the issue.

Use the templates below. Substitute interview answers where placeholders indicate. For skipped optional questions, use the italicized fallback text shown — don't leave the section empty.

### Template: `config.yaml`

```yaml
version: 1
agent: claude
user:
  name: "{Q1 answer}"
  email: "{Q2 answer}"
resume:
  filename: "{original resume filename, e.g. 'Latest Resume.docx'}"
calendar:
  provider: "{Q11 provider, e.g. 'google', 'outlook', 'apple', or any user-provided string}"
  name: "{specific calendar name, or null if not selected/applicable}"
  id: "{provider-specific calendar id, or null if not selected/applicable}"
linkedin:
  search_method: "{Q12 answer — 'chrome' or 'websearch'}"
mail:
  label_root: "{Q13 answer, default 'Job Search'}"
  skip_senders:
    {Q14 list — one entry per line as `- "{value}"`, or `[]` if empty}
active_study: null
```

The `mail` block is read by `label-job-search-emails`. `label_root` is the parent
Gmail label that all `{label_root}/{Company}` sublabels live under.
`skip_senders` is a list of sender substrings or domains to skip during
triage. Both fields are user-tunable; the skill never auto-writes to
them after init.

Mail field shapes:

- `mail.label_root` always populated (default `Job Search` when the user
  skipped Q13).
- `mail.skip_senders` is a YAML list. Empty list (`[]`) is fine when the
  user skipped Q14; the skill treats it as "no skip rules". One entry per
  line, e.g.:

  ```yaml
  skip_senders:
    - "squareup.com"
    - "internal-newsletter@example.com"
  ```

Calendar field shapes by Q11 outcome:

- **User picked "Skip"**: write `calendar: null` (single-line null, not the nested form).
- **User picked "Google Calendar" and selected a specific calendar**: nested form with all three fields populated (`provider: "google"`, `name`, `id`).
- **User picked "Google Calendar" but skipped specific calendar (or `gws` was unavailable)**: nested form with `provider: "google"`, `name: null`, `id: null`.
- **User picked "Other"**: nested form with `provider: "{normalized string}"`, `name: null`, `id: null`.

Skills that read this field should handle all four shapes:
- `calendar` is null → no calendar configured; skip or prompt depending on the skill.
- `calendar.provider` set, `id` populated → use it directly with the matching tooling.
- `calendar.provider` set, `id` null → provider is known but no specific calendar yet; prompt within that provider if possible, else skip.
- `calendar.provider` is something the skill doesn't know how to drive → skip calendar integration for this run with a brief note.

### Template: `CLAUDE.md`

```markdown
# Job Search — Memory

Read this file at the start of every session. It's a lean pointer — full context lives in the referenced files.

## Profile
See `profile.md` for who I am, target role, strengths, weaknesses, goals, constraints, avoiding, and communication style. Read this before producing any user-facing output (outreach, resume copy, prep docs).

## Insights
See `insights.md` for the running collection of patterns, gotchas, weak spots, and habits surfaced across studies and interviews. Load this every session — it's the agent's accumulated memory about how I work. Don't re-learn what's already here.

## Positions
Positions in flight live under `companies/{company-slug}/{position-slug}/`. Each position folder holds the posting, tailored resume, `position-fit.md` (gap analysis with status header — Tracking, Applied, Screening, Interview Scheduled, Interviewing, Offer, Accepted, Rejected, Withdrawn, On Hold), outreach, prep docs, and interview notes. Recruiter contacts live at `companies/{company-slug}/contacts.md`. Scan the `companies/` directory to see what's currently tracked.

## Studies
See `study-plans/index.md` for all study plans past and present. The active study (if any) is named in `config.yaml`. When active, load `study-plans/{active-slug}/plan.md` and `progress.md` for current-plan context.

## Story Bank
See `Story Bank.md` for behavioral stories. Used by `apply-to-job` (when generating `position-fit.md`), `interview-prep`, and `study-session`.

## Skills in this plugin
- `job-search-init` — initial setup (already run)
- `create-study-plan` — create a new study plan
- `study-session` — run a daily prep session against the active study
- `interview-prep` — prep for a specific upcoming scheduled interview
- `company-research` — research a company (optionally with a posting)
- `resume-tailor` — tailor resume to a posting
- `apply-to-job` — add a new position to the pipeline (tailored resume + position-fit analysis)
- `find-recruiter` — find a recruiter and draft outreach

## Session Log
| Date | Activity | Notes |
|------|----------|-------|
```

### Template: `profile.md`

For each section, substitute the user's interview answer. For skipped optional sections, use the explicit fallback text shown in italics — do not leave the section empty.

```markdown
# Profile

> Durable context every skill in this plugin reads. Edit directly anytime. Study sessions may prompt to add stable items here, but most observations go to `insights.md`.

## Identity
- Name: {Q1}
- Email: {Q2}

## Target Role
{Q4}

## Strengths
{Q5, OR if skipped: "_Empty — will populate as studies and interviews surface what's working well._"}

## Weaknesses / Areas to Shore Up
{Q6, OR if skipped: "_Empty — will populate as studies and interviews surface recurring patterns. See also `insights.md` for the detailed running list._"}

## Goals
{Q7}

## Constraints
{Q8, OR if skipped: "_None noted._"}

## Avoiding
{Q9, OR if skipped: "_Empty — add role characteristics, tech stacks, industries, or work patterns you want to avoid as they come up. Used by position-fit to flag matches against postings._"}

## Communication Style
{Q10, OR if skipped: "_Defaults will be used. Add do's and don'ts as you notice them in output you like or don't like._"}

> Skills that produce user-facing text (resume-tailor, apply-to-job, find-recruiter, interview-prep) read this section before generating.

## Notes
_Empty — user and skills append durable items over time._
```

### Template: `insights.md`

```markdown
# Insights

Running collection of patterns, gotchas, weak spots, and habits observed during prep and interviews. This is the agent's accumulated memory — what Claude has already learned about how I work, so it doesn't have to re-learn it every session.

Appended to by `study-session` and `interview-prep`. Edit directly anytime: add entries, reword, prune what's no longer relevant.

## How this file is used

- Loaded at the start of every session by every skill in this plugin
- Cross-study — entries survive when you switch study plans or finish one
- Organized by topic as it grows (headers added as needed)
- Prune freely — if an insight is no longer a weak point, strike it out or remove it

## Insights

_Empty — populated as you work through studies and interviews._
```

### Template: `Story Bank.md`

```markdown
# Story Bank

STAR-format stories for behavioral interviews.

## Categories

The categories below are a starting set — **add, remove, or rename them** to fit your target role. Staff engineering, EM, design, PM, and founder roles all probe different story shapes. `create-study-plan` can add role-specific categories when it generates a plan. `interview-prep` can add a category if a specific interview type calls for one.

| Category | Status | Notes |
|----------|--------|-------|
| Technical failure I owned |  |  |
| Major project under ambiguity |  |  |
| Conflict with peer or manager |  |  |
| Decision with incomplete info |  |  |
| Influenced without authority |  |  |
| Mentorship or coaching moment |  |  |
| Biggest technical win |  |  |
| System design requiring tradeoffs |  |  |
| Pushed back on product or business decision |  |  |
| Improved engineering process or culture |  |  |
| System that didn't go as planned |  |  |
| Leadership beyond my role |  |  |

## Surfacing new stories during practice

When you tell a story during study-session or interview-prep practice and it lands well — or even surfaces something you hadn't thought of as a story — the skill will offer to capture it here. Say yes and the skill will help you refine it into STAR shape over subsequent sessions. The bank should grow organically from what you're actually good at talking about, not just from cold-brainstorming at init.

---

## How to write a story

Use STAR: Situation, Task, Action, Result. Keep Action as the longest section. Use "I" for individual actions, "we" only when describing team outcomes in Result.

### Template

**Title:** {short name — used to reference the story across prep docs}

**Category:** {one or more from the list above}

**Summary:** {one sentence — what the story is about and the punchline. Used by position-fit and interview-prep to scan for relevance without reading the whole story.}

**Situation:**
Context. Company, team, scope, timeframe. One paragraph.

**Task:**
What was the problem? Why did it need solving? Why you?

**Action:**
What YOU did. Specific, first-person, single-threaded. This is the longest section.

**Result:**
Outcome. Quantify where possible. What changed for the team, company, users?

**What I'd do differently:** (optional — staff-level candidates usually have something)

**Most likely to come up in:** {recruiter screen | tech screen | leadership | system design | behavioral}

---

## Stories

(Stories go here. Add one at a time. Update the Status column in the table above as you draft and polish each.)
```

### Template: `study-plans/index.md`

```markdown
# Studies

All study plans, past and present. The active study (if any) is named in `config.yaml`.

| Slug | Plan Name | Status | Start | End | Summary |
|------|-----------|--------|-------|-----|---------|
| _(empty — run `create-study-plan` to add one)_ | | | | | |

Status values: `Planned`, `Active`, `Complete`, `Abandoned`.

The `Summary` column holds a one-line description of what the study covered — populated when a study is archived. This is what future studies see as the "study history" without needing to load each plan's full progress file.
```

## Step 3 — Copy the resume

Copy the resume from its source location into the target directory, preserving its original filename. Use bash `cp` with both paths translated to their bash-visible (mounted) equivalents.

Path translation:

- **Source** — find the bash path:
  - If the user uploaded the file into Cowork: `find /sessions/*/mnt/uploads -name "{filename}"` returns the bash path directly.
  - If the user gave a host filesystem path inside a workspace folder (e.g., `/Users/foo/MyJobSearch/Resume.docx`): the bash equivalent replaces the host prefix with the matching `/sessions/*/mnt/{folder name}/` mount. Use `find /sessions/*/mnt -name "{filename}" -path "*{folder name}*"` to locate it concretely.
- **Target** — the bash-mounted target path you saved in Step 0.

Run the copy:

```bash
cp "{bash-source}" "{bash-target}/{original filename}"
```

Verify with `ls -la "{bash-target}"` afterward. If the copy fails or the source can't be located, tell the user explicitly: "I couldn't find the resume at `{path}` — please drop it into `{target}` directly and I'll continue." Don't guess the path or skip this silently.

## Step 4 — Summarize and (optionally) chain

Print a short summary to the user:

```
Job search initialized at {target path}.

Created:
  config.yaml
  CLAUDE.md
  profile.md
  insights.md
  Story Bank.md
  study-plans/index.md
  companies/ (empty)
  study-plans/ (empty)
  {resume filename} (copied from {source})

Next:
  - {if Q15 was Yes:} Setting up your first study plan now via create-study-plan.
  - {if Q15 was Not now:} Run create-study-plan when you're ready to build a study plan, or apply-to-job when you have a posting to track.
```

If Q15 was "Yes — set up a study plan", chain directly into the `create-study-plan` skill. Don't ask for confirmation; the user already said yes.

## Notes for implementation

- **Idempotency**: This skill is intended to run once. On re-run with existing artifacts, the overwrite confirmation in Step 0 protects the user from accidental data loss. Don't try to merge new answers with existing files — that's complex and error-prone. If the user wants to update specific fields after init, they should edit `profile.md` directly.

- **Skip handling**: When the user says "skip", "not yet", "no", "next", or otherwise indicates they don't want to answer an optional question, accept the skip without prompting again. The fallback text in templates handles the empty case.

- **Resume validation**: If the resume isn't a `.docx`, the user should know up front because resume-tailor depends on `.docx` for editing. Tell them and ask for a `.docx` version.

- **Tone**: This is a setup wizard, not a therapist. Keep prompts short, accept short answers, don't editorialize. The user is here to get the system stood up so they can start using it.
