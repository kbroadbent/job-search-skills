---
name: label-job-search-emails
description: >
  Triage recent inbox messages for the job search. Classify each by
  company, apply the matching {label_root}/{Company} Gmail sublabel
  (creating it if missing), and archive the message out of the inbox.
  Uses the companies/ directory as the authoritative list of tracked
  companies; routes ATS-forwarder mail (Greenhouse, Lever, Workday,
  Ashby, etc.) to the correct company; catches job-board aggregators
  and unaffiliated recruiters in two configurable catch-all sublabels.
  Read-and-label only — never deletes, replies, or modifies anything
  outside the {label_root}/* hierarchy. Use when the user says "triage
  my inbox", "process my job-search emails", "label my job emails",
  "clean up my inbox", "sync my emails", or any variation of wanting
  recent job-search mail organized and out of the inbox. Always
  runnable standalone.
---

# label-job-search-emails

Scan recent inbox messages, classify each by company, apply a
`{label_root}/{Company}` Gmail sublabel (creating it if missing), and
archive the message out of the inbox.

This skill is **read-and-label** against Gmail. It never deletes,
replies, marks read/unread, applies labels outside `{label_root}/*`,
or touches calendar.

This skill is a **leaf** — it does not call other skills.

---

## Step 0 — Verify directory and load context

### Find the job search root

```bash
find /sessions/*/mnt -maxdepth 2 -name "config.yaml" 2>/dev/null | head -5
```

The job search root is the directory containing `config.yaml` at its
top level. Hold both path forms — you will need both throughout this
skill:

- **Host path** (for Read/Write/Edit tools): e.g.,
  `/Users/.../2026 Job Search`
- **Bash-mounted path** (for shell commands): e.g.,
  `/sessions/*/mnt/2026 Job Search`

If no `config.yaml` is found, tell the user the plugin hasn't been
initialized and offer to run `job-search-init`. Stop until init
completes.

### Verify required files exist

Check that all five are present (`config.yaml` plus the four
memory files):

- `config.yaml`
- `profile.md`
- `insights.md`
- `CLAUDE.md`
- `study-plans/index.md`

If any are missing, tell the user the directory isn't fully initialized
and offer `job-search-init`. Stop until init completes.

Read all five files. Hold the contents for the rest of the session.

### Translate to host-path form

The `find` command above returns a bash-mounted path (e.g.,
`/sessions/.../mnt/2026 Job Search`). The Read/Write/Edit tools need
the host path. To translate, replace the `/sessions/<session-id>/mnt`
prefix with the host root from the `mount` table or — more simply —
look at the user's CLAUDE.md or any path Kent has shared in the
session (e.g., `/Users/.../Documents/2026 Job Search`). Hold both
forms.

If the host path can't be determined cleanly, ask Kent in plain
prose for the host path of the job-search directory. Do not guess.

### Read mail config from `config.yaml`

You need three fields:

- `calendar.provider` — used as the suite indicator (per Decision #1
  in the contracts doc; see Step 1 below)
- `mail.label_root` — the parent Gmail label name. Default: `Job Search`
- `mail.skip_senders` — a list of sender substrings or domains to skip
  during classification. May be missing or empty.

If `mail.label_root` is missing:

1. Ask the user via plain prose:
   > "I need to know your Gmail label root for job-search emails.
   > New users typically use `Job Search`. If you've already got an
   > existing hierarchy (for example `2026 Job Search`), tell me that
   > name. What should I use?"
2. Wait for the answer. Hold the value.
3. Write it back to `config.yaml` under `mail.label_root` so future
   runs don't re-prompt.

If `mail.skip_senders` is missing, treat it as an empty list. Do not
prompt or auto-populate.

---

## Step 1 — Provider dispatch

Read `config.yaml → calendar.provider`. This indicates the Google
Workspace suite for this user.

| Provider | Behavior |
|----------|----------|
| `google` | Proceed. Use `gws` for Gmail. |
| anything else (`outlook`, `apple`, `null`, missing) | **Hard stop.** Print: "Mail triage isn't supported for provider `{provider}` in v1. Only `google` is supported right now." Do not attempt any external calls. |

For `google`, continue.

---

## Step 2 — Verify `gws` is configured

### 2a — Ensure `gws-setup` has run this session

If you haven't already invoked `gws-setup` in this session, do so
now via the Skill tool: `gws-cowork:gws-setup` (or the equivalent
`gws-setup` skill name available in the user's environment). That
skill is responsible for placing `gws` on PATH and setting credentials
environment variables.

If `gws-setup` is not available as a skill in this environment, fall
through to 2b — the user may have configured `gws` manually.

### 2b — Check authentication status

Verify `gws` is on PATH and credentials are valid:

```bash
gws auth status 2>/dev/null | python3 -c "import sys,json; d=json.load(sys.stdin); print('Ready:', d.get('token_valid'), '|', d.get('user'))"
```

**If the command prints `Ready: True | <email>`,** continue to Step 3.

**If the command itself fails** (`gws: command not found`), tell the
user:
> "The `gws` CLI isn't set up in this session. Run the `gws-setup`
> skill first to configure Google Workspace credentials, then re-run
> `label-job-search-emails`."

**If `token_valid` is false,** tell the user:
> "Your `gws` credentials have expired. Re-authenticate via the
> `gws-setup` skill, then re-run `label-job-search-emails`."

Stop in either failure case. Do not attempt any Gmail API calls.

---

## Step 3 — Determine the lookback window

Default: **2 days** (`newer_than:2d`).

Parse the user's invocation message for an override. Recognize:

- "the last week", "past 7 days", "last 7 days" → 7 days
- "the last N days", "past N days" → N days (cap at 90)
- "since Monday", "since {weekday}" → compute days back to the most
  recent occurrence of that weekday (today doesn't count)
- "today", "today's", "since this morning" → 1 day
- "yesterday and today" → 2 days

Other recognized forms:

- "the last month" → 30 days
- "all of {month name}" → from the first of that month to today
  (capped at 90 days)

If you parsed a value, use it. Otherwise use 2 days.

If the user's wording was unclear ("a while", "recently", "lots"),
ask in plain prose:
> "How far back should I scan? (Default is the last 2 days.)"

If the user's reply is still unparseable, fall back to a constrained
prompt offering specific options: 1, 2, 7, 14, 30. Pick the answer
or default to 2.

Hold the lookback as `lookback_days`.

---

## Step 4 — Discover existing labels under `{label_root}`

Fetch all current Gmail labels:

```bash
gws gmail users labels list \
  --params '{"userId":"me"}' \
  --format json 2>/dev/null
```

Parse the result. Build:

- A map of `{Company display name} → {label id}` for every label whose
  name starts with `{label_root}/`. The display name is whatever
  follows the slash, verbatim ("Stripe", "Block, Inc.", "Job Boards",
  "Recruiters").
- The label ID for `{label_root}` itself (the parent). You'll need it
  when creating new sublabels — though Gmail accepts the slash notation
  in `name` directly, capturing the parent ID is useful for
  verification.

If `{label_root}` itself does not exist as a label, create it now:

```bash
gws gmail users labels create \
  --params '{"userId":"me"}' \
  --body '{"name":"<label_root>","labelListVisibility":"labelShow","messageListVisibility":"show"}' \
  --format json 2>/dev/null
```

Capture the returned label ID. (Gmail will reject creating a sublabel
under a nonexistent parent in some setups; creating the parent first
is safe either way.)

**Visibility choice (intentional, do not change):** the parent label
uses `labelShow` so the root is always visible in the Gmail sidebar.
Sublabels (created in Step 8) use `labelShowIfUnread` so they only
appear in the sidebar when there's unread mail there — keeps the
sidebar quiet on inactive companies.

**If `{label_root}` already exists** with different visibility
settings, leave it alone. Don't try to update it. The user may have
configured it deliberately.

---

## Step 5 — Build the tracked-companies map

List companies the user is tracking:

```bash
ls -1 "<bash path>/companies" 2>/dev/null
```

For each entry that's a directory, the entry name is the **slug**.
For each slug:

1. Try to read `companies/{slug}/company.md`.
2. If it exists, the **display name** is the first non-frontmatter
   heading (e.g., the first `# Heading` line below any YAML frontmatter
   block). Strip leading hashes and whitespace.
3. If `company.md` doesn't exist or has no heading, derive the display
   name from the slug: replace hyphens with spaces, title-case each
   word, then preserve any explicitly-cased patterns the user might
   have used (`block-inc` → `Block Inc`).
4. Read the `Email domain:` line(s) if present. There may be more than
   one — collect each domain into a list per company.
5. If multiple companies share a domain in their `Email domain:` lists,
   prefer the one whose folder mtime is most recent. Get folder mtime
   with:
   ```bash
   stat -c %Y "<bash path>/companies/<slug>"
   ```
   (the bash sandbox is Linux, so `-c %Y` works). Higher value =
   newer. Surface the collision in the closing summary as a one-line
   note under the Triaged section.

Build:

- `tracked_companies`: list of `{slug, display_name, domains[]}` entries.
- `domain_to_company`: map of `domain → {slug, display_name}` (one
  entry per `Email domain:` line, deduplicated as above).

Single-word display names get a stricter match later — set
`strict_match = True` for any company whose `display_name` is a
single word (no spaces, no punctuation that would split it). Multi-
word display names get `strict_match = False`. The strict match is
just a word-boundary regex (`\b{display_name}\b`, case-insensitive)
applied at classification time — it reduces false-positive matches
in `Subject` and `From` display-name searches.

This is a heuristic, not a guarantee. Word-boundary matching catches
the obvious ordinary-English collisions ("a stripe of paint",
"blocked the call") but won't catch every edge case. False positives
that slip through end up in the wrong sublabel; the user can move
them in Gmail directly.

If `companies/` is empty or doesn't exist, `tracked_companies` is an
empty list. The skill still runs — Step 7's classification falls
through to ATS forwarders, direct domain matches, and catch-alls.

---

## Step 6 — Search the inbox

```bash
gws gmail users messages list \
  --params '{"userId":"me","q":"in:inbox newer_than:<lookback_days>d","maxResults":100}' \
  --format json 2>/dev/null
```

Replace `<lookback_days>` with the value held from Step 3. Capture the
list of message IDs.

If the response includes `nextPageToken` and the page returned 100 IDs,
fetch additional pages until you've collected all messages in the
window or you've collected 500 IDs. Cap at 500 — beyond that, prompt
the user to narrow the window:

> "There are more than 500 messages in the last `{lookback_days}` days.
> Want me to process the most recent 500, or narrow the window?"

If the user picks "narrow the window," go back to Step 3 and ask for
a new `lookback_days`. Re-issue the search with the new value.

If the user picks "process the most recent 500," continue with the
500 IDs already collected.

Hold the message IDs as `inbox_ids`.

If `inbox_ids` is empty, skip to Step 11 (nothing to triage).

---

## Step 7 — Classify each message

For each message ID in `inbox_ids`, fetch its metadata headers only
(no body — saves quota and latency):

```bash
gws gmail users messages get \
  --params '{"userId":"me","id":"<messageId>","format":"metadata","metadataHeaders":["From","Subject","To"]}' \
  --format json 2>/dev/null
```

Parse `From`, `Subject`, `To`, and the `labelIds` array from the
response.

Apply the classification signal priority **in order**. Stop at the
first match.

### 7.1 — Existing label check

If `labelIds` contains any label whose name starts with
`{label_root}/`, mark this message as `already_labeled` and skip to
the next message. Do not touch it.

### 7.2 — Skip rules

For each entry in `mail.skip_senders`:

- If the entry contains an `@` (e.g., `notify@squareup.com`), match
  the full sender address (case-insensitive equality on the
  address-only portion of `From`, ignoring the display name and
  angle brackets).
- If the entry looks like a bare domain (e.g., `block.xyz` or
  `squareup.com` — no `@`, contains a `.`, no whitespace), match the
  sender address's domain only (case-insensitive). Do not match
  against the display name.
- If the entry is a substring without `@` and without a `.`, match
  the substring anywhere in the sender address only (not the display
  name). Use this form sparingly — substring matches are easy to
  over-trigger.

Always parse the `From` header into `(display_name, email_address)`
first; apply skip rules to the email_address portion (and its domain).
This avoids false positives on display-name text.

If any entry matches, mark this message as `skipped (skip_senders rule)`
and continue. Do not label or archive.

### 7.3 — Tracked-company match

For each `tracked_company` in `tracked_companies`:

- If the sender's domain is in the company's `domains[]` list, this is
  a match. Target sublabel = `{label_root}/{display_name}`.
- Otherwise, search both `Subject` and the `From` display-name portion
  for the company's `display_name`. Match rules:
  - If `strict_match = True`, require a regex word-boundary match
    (`\b{display_name}\b`, case-insensitive).
  - Otherwise, case-insensitive substring match.
  - For multi-word display names ("Block, Inc."), match the head form
    too — "Block Inc", "Block, Inc.", "BLOCK INC" all qualify.

If a tracked-company match is found, **also** record the sender's
domain (if not already in the company's domains list) for backfill in
Step 10.

If multiple tracked companies match (rare — e.g., subject mentions
both), pick the one with the strongest match in this priority order:

1. Domain match (Step 7.3 first bullet) beats name match.
2. Strict-name (word-boundary regex) beats substring-name.
3. Final tie-breaker: alphabetical by `display_name` (case-
   insensitive). This is deterministic across runs.

If two candidates are still tied after all three (extremely
unlikely), mark as `ambiguous (multiple tracked companies)` and
continue without labeling.

### 7.4 — ATS forwarder

If the sender's domain matches one of these known ATS forwarders:

- `greenhouse-mail.io`, `greenhouse.io`
- `lever.co`
- `myworkday.com`, `wd1.myworkdayjobs.com`, `wd5.myworkdayjobs.com`
- `ashbyhq.com`
- `rippling.com`
- `smartrecruiters.com`
- `applytojob.com`, `applyfyi.com`
- `bamboohr.com`
- `jobvite.com`
- `eightfold.ai`

extract the company name from the email using this algorithm in
order (stop at first hit):

1. **`From` display name leading token.** Parse the display name
   (the text before `<email>`). Strip leading/trailing whitespace
   and quotes. Split on common separators: ` - `, ` | `, `: `, `, `,
   ` (`, ` at `, ` via `. Take the first segment. If the first
   segment is one of `Recruiting`, `Hiring`, `Talent`, `Careers`,
   `Notifications`, take the **second** segment instead. Examples:
   - `"Stripe Recruiting - Talent Team"` → first segment
     `"Stripe Recruiting"` → strip trailing role word `Recruiting`
     (single trailing word from `{Recruiting, Hiring, Talent,
     Careers, Notifications, Team}`) → `"Stripe"`.
   - `"Greenhouse on behalf of Stripe"` → split on ` on behalf of `
     → take the right side → `"Stripe"`.
   - `"Notifications - Block, Inc."` → first segment `"Notifications"`
     is a generic word → take second segment → `"Block, Inc."`.
2. **Subject pattern match.** Search the subject (case-insensitive)
   for these patterns and capture the company name from each:
   - `application to ([A-Z][A-Za-z0-9&,. ]+?)\b(?:\s*(?:has|was|is|received|for|–|-)|$)`
   - `interview (?:with|at) ([A-Z][A-Za-z0-9&,. ]+?)\b`
   - `from ([A-Z][A-Za-z0-9&,. ]+?)(?:\s*(?:Recruiting|Talent|Hiring|Team)\b|$)`
   - `[Cc]areers? at ([A-Z][A-Za-z0-9&,. ]+?)\b`
   Use the first capture group that matches.
3. **Tracked-company name in subject.** Iterate `tracked_companies`
   and check if any `display_name` appears in the subject (apply
   `strict_match` rules). First hit wins.

After extraction, trim trailing punctuation and whitespace.

If the extracted company matches a tracked company (case-insensitive
display-name compare, with `strict_match` semantics), target sublabel
= that tracked company. If it doesn't match, target sublabel =
`{label_root}/{Extracted Name}` — preserve readable formatting
("Block, Inc." stays "Block, Inc.", not slugified). This is the
**untracked-company branch** from Decision #5.

If you can't extract a company name from any of the three sources,
mark as `ambiguous (ATS forwarder, no company name)` and continue.

### 7.5 — Direct company domain (untracked)

If the sender's domain didn't match any tracked company and didn't
match an ATS forwarder, but the message looks like job-search mail
(see "Job-search heuristics" below), use the sender's domain to derive
a display name:

- `someone@datadog.com` → "Datadog"
- `careers@example.com` → use the second-level domain, title-cased.
- For domain reduction: `careers.stripe.com` → `stripe.com` →
  `Stripe`.

Target sublabel = `{label_root}/{Derived Name}`.

**Job-search heuristics** (any one of these qualifies):

- `Subject` contains: "application", "interview", "hiring", "role",
  "position", "opportunity", "your resume", "candidate", "open
  position", "we'd love", "interested in your background", "talent
  team", "recruiting team", "career", "next steps", "phone screen",
  "onsite", "offer".
- The `From` display name contains: "Recruiting", "Talent", "People",
  "Hiring".

If neither qualifies, do NOT classify on direct domain alone — fall
through to catch-alls and then to ambiguous.

### 7.6 — Catch-alls

- If the sender's domain is in this set:
  `indeed.com`, `indeedapply.com`, `linkedin.com` (with
  `Subject` mentioning "jobs" or "alert" or "matched"),
  `glassdoor.com`, `dice.com`, `ziprecruiter.com`, `monster.com`,
  `wellfound.com`, `angel.co`, `builtin.com`
  → target sublabel = `{label_root}/Job Boards`.

- If the sender domain looks like a recruiting agency (substring
  "recruit", "talent", "staffing", "consult" in the domain or display
  name) and didn't match a more specific rule above
  → target sublabel = `{label_root}/Recruiters`.

### 7.7 — Default

If none of 7.1 through 7.6 hit, mark the message as `ambiguous (no
classification)`. Leave it in the inbox.

---

## Step 8 — Group classifications and create missing sublabels

You now have a list of `(message_id, target_sublabel)` pairs plus
counts of `already_labeled`, `skipped`, and `ambiguous`.

Group the classified messages by `target_sublabel`. For each unique
target sublabel:

- If it's already in the labels map from Step 4, you have its label ID.
- If it's new, create it:

```bash
gws gmail users labels create \
  --params '{"userId":"me"}' \
  --body '{"name":"<label_root>/<Display Name>","labelListVisibility":"labelShowIfUnread","messageListVisibility":"show"}' \
  --format json 2>/dev/null
```

Capture the new label's ID. Add it to the labels map so subsequent
groups in the same run don't try to recreate it.

Track every newly-created sublabel separately as `new_sublabels` —
you'll surface them in the closing summary (per Decision #5). Mark
each as either:
- **tracked** — the sublabel was created for a tracked company (rare;
  this happens only if the user added a `companies/{slug}/` folder
  but never labeled email for it before).
- **untracked** — no `companies/{slug}/` folder exists for this
  display name. These are the discovery-surface entries.

For the **untracked** new sublabels, the closing summary will
suggest running `apply-to-job` for them.

---

## Step 9 — Apply labels and archive

For each `(target_sublabel, [message_ids])` group, issue one
`batchModify` call:

```bash
gws gmail users messages batchModify \
  --params '{"userId":"me"}' \
  --body '{
    "ids": ["<id1>", "<id2>"],
    "addLabelIds": ["<sublabel_id>"],
    "removeLabelIds": ["INBOX"]
  }' \
  --format json 2>/dev/null
```

Notes:

- `removeLabelIds: ["INBOX"]` is what archives the messages — it
  removes them from the inbox without deleting them.
- `batchModify` returns no body on success (HTTP 204). An empty
  response is the expected case.
- Cap each call at 1000 message IDs (Gmail's limit). For larger
  groups, split into multiple calls.

If a `batchModify` call returns an error, capture the error message,
mark all messages in that group as `failed (label apply)`, and
continue with the next group. Do NOT abort the whole run.

---

## Step 10 — Backfill `Email domain:` in `company.md`

For each tracked company where Step 7.3 observed a new sender domain
(one not already in the company's `domains[]` list):

1. Read `companies/{slug}/company.md`.
2. Check whether the new domain is already recorded by grepping for
   exact-match lines (case-insensitive) of the form
   `^Email domain:\s*<domain>\s*$`. If a match exists, do nothing for
   this domain — it was already there and Step 5 missed it (rare; can
   happen with formatting variants).
3. If no exact-match line exists:
   - If at least one `Email domain:` line already exists, append a
     new `Email domain: <domain>` line directly below the last
     existing one. Do not modify any existing line.
   - If no `Email domain:` line exists, add one directly below the
     first heading (`# {Company}` line) of the file. Insert a blank
     line before and after the new field if neighboring content is
     prose (not another field). The line format is exactly:
     ```
     Email domain: <domain>
     ```
4. Save the file.

If `company.md` doesn't exist for a tracked company (rare — the user
created the folder manually), do nothing for that company. The
backfill is only safe when there's a file to extend.

---

## Step 11 — Append a session-log line to `CLAUDE.md`

Append a single line to the session-log section of `CLAUDE.md`. Format:

```
| YYYY-MM-DD | label-job-search-emails: <N> messages, <M> labeled, <K> new sublabels, <L> ambiguous |
```

Use today's date (run `date '+%Y-%m-%d'` in bash to get the local
date). Match the existing log-line format in `CLAUDE.md` if it
diverges from the above — re-read the bottom of the file before
appending and copy the column shape.

If `CLAUDE.md` has no session-log section, create one. Append this
block to the end of the file:

```
## Session Log

| Date | Activity |
|------|----------|
| YYYY-MM-DD | label-job-search-emails: <N> messages, <M> labeled, <K> new sublabels, <L> ambiguous |
```

(Substitute today's date and counts.) Do not add any other content
below the new section.

---

## Step 12 — Closing summary

Print a concise summary in this exact shape (omit empty subsections):

```
Triage complete: <N> messages processed in the last <lookback_days> days.

Triaged:
  <Display Name>     — <count> (<brief context phrase if obvious from subjects>)
  <Display Name>     — <count>
  Job Boards         — <count>
  Recruiters         — <count>
  Skipped            — <count> (already labeled or skip rule)

New sublabels created:
  <Display Name> (untracked — consider running apply-to-job)
  <Display Name> (tracked)

Ambiguous (left in inbox): <N>
  - From: <sender> | Subject: "<subject>" — <one-line reason>
  - <up to 5; if more, end with "...and N more">

Failed (label apply): <N>
  - <error summary>

Suggested next steps:
  - <if any new untracked sublabels: "Run apply-to-job for <Co1>, <Co2> to add them to your tracked companies">
  - <if many ambiguous: "Review <N> ambiguous messages still in the inbox">
  - <if no suggestions apply, omit this section entirely>
```

Brief context phrase rules (the parenthetical after each company):

- If the count is 1, omit the parenthetical entirely.
- If 50% or more of the messages for that company share a clear
  theme keyword in their subjects, surface it. Theme keywords to
  detect:
  - "interview", "interviewing", "schedule" → "interview scheduling"
  - "application", "applied", "received" → "application receipts"
  - "follow", "checking in" → "follow-up"
  - "recruiter", "reach out", "wanted to connect" → "recruiter outreach"
  - "offer", "offer letter" → "offer"
- Otherwise omit the parenthetical.

If a company.md collision was detected in Step 5 (multiple companies
sharing a domain), include a single-line note in the Triaged section:
> "(Note: domain {domain} is shared between {Co1} and {Co2}; classified
> by most-recent folder mtime — review if wrong)"

Don't editorialize. Don't add encouragement. The user reads counts,
not narrative.

---

## Things to remember

- **Read-and-label only.** You may create labels under `{label_root}`,
  apply them, and remove `INBOX`. You may not delete messages, send
  replies, mark anything as read or unread, or apply any label outside
  the `{label_root}/*` hierarchy.
- **`gws` quota.** Personal Gmail accounts get 250 quota units/second.
  `messages.list` is 5 units, `messages.get` is 5 units, `batchModify`
  is 50 units regardless of how many messages it modifies. Typical
  runs (under 100 messages) won't hit limits. Don't issue unnecessary
  retries.
- **Path translation.** Host paths look like `/Users/.../2026 Job Search`
  for Read/Write/Edit; bash-mounted paths look like
  `/sessions/*/mnt/...`. Hold both forms throughout.
- **`Email domain:` is a recognized field.** After this skill backfills
  it, other plugin skills can read it without re-deriving. Future
  iterations of `company-research` should populate it proactively.
- **Discovery surface.** New untracked sublabels surface in the
  closing summary as a suggestion to run `apply-to-job`. Don't
  auto-trigger that skill — leave the choice to the user.
- **No em-dashes** in any user-facing message.
- **Don't reuse the `Recruiters` catch-all** as a fallback for tracked
  companies. If the message clearly relates to a tracked company,
  classify to that company even if the sender is a third-party
  recruiter. The catch-all is for unaffiliated agencies.
