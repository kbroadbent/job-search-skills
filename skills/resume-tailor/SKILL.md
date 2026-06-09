---
name: resume-tailor
description: >
  Tailor the user's base resume to a specific job posting. Produces a .docx and .pdf
  saved at companies/{co}/{pos}/. Use when the user says "tailor my resume for
  [URL or company]", "customize my resume for this job", "update my resume for [role]",
  or shares a job posting URL and wants their resume adapted to it. Also called internally
  by apply-to-job with company slug, position slug, and posting context pre-loaded.
---

# resume-tailor

Tailor the user's base resume to a specific job posting. Output: a `.docx` and `.pdf`
named after the user and role, saved at `companies/{co}/{pos}/`. Produce a
clear summary of every substantive change and flag any gaps that couldn't be resolved.

**The most important constraint: never fabricate.** Every word in the tailored resume
must reflect something true in the user's background. You are an editor, not a ghostwriter.

---

## Step 0 — Verify directory, load context, and locate DOCX tooling

### Find the job search root

```bash
find /sessions/*/mnt -maxdepth 2 -name "config.yaml" 2>/dev/null | head -5
```

The job search root is the directory containing `config.yaml` at its top level. Hold both
path forms — you will need both throughout this skill:
- **Host path** (for Read/Write/Edit tools): e.g., `/Users/.../2026 Job Search`
- **Bash-mounted path** (for shell commands): e.g., `/sessions/*/mnt/2026 Job Search`

If no `config.yaml` is found, tell the user the plugin hasn't been initialized and offer
to run `job-search-init`. Stop until init completes.

### Verify required files exist

Check that all of these are present:
- `config.yaml`
- `profile.md`
- `insights.md`
- `CLAUDE.md`
- `study-plans/index.md`

If any are missing, tell the user the directory isn't fully initialized and offer
`job-search-init`. Stop until init completes.

Read all five files. Hold the contents for the rest of the session.

### Locate the DOCX skill and scripts

Run both of these now. Store both results — you will need them later.

```bash
# Find the DOCX SKILL.md
find /sessions/*/mnt -path "*/skills/docx/SKILL.md" 2>/dev/null | head -1

# Find the DOCX scripts directory
find /sessions/*/mnt -path "*/skills/docx/scripts" -type d 2>/dev/null | head -1
```

If either find returns empty, try broader searches:
```bash
find /sessions/*/mnt -name "unpack.py" 2>/dev/null | head -3
find /sessions/*/mnt -name "pack.py" 2>/dev/null | head -3
```

If the scripts directory cannot be located after these attempts, tell the user the DOCX
skill isn't installed and the resume cannot be edited programmatically. Offer to provide
a written summary of recommended edits the user can apply manually. Stop the skill.

If found: read the DOCX SKILL.md so you understand how to unpack, edit, and repack .docx
files correctly. Store the scripts path — call it DOCX_SCRIPTS throughout this document.
Because each bash call runs in isolation (no environment carries over), re-derive
DOCX_SCRIPTS inline at the start of each bash block in Steps 8 and 9 rather than assuming
it persists.

---

## Step 1 — Detect invocation mode

Examine the invocation message. To qualify as **Mode B** (called by apply-to-job), all
three of the following must be explicitly present:
1. A company slug named directly (e.g., "company slug: stripe" or "co: stripe")
2. A position slug named directly (e.g., "position slug: staff-engineer" or "pos: staff-engineer")
3. Posting content — either a path to an existing `posting.md` or the posting text/URL in the message

If all three are present, skip to Step 2B.

If any are missing or ambiguous, treat it as **Mode A** (standalone). Continue to Step 2A.

---

## Step 2A — Standalone: resolve company + position

### Get the posting

If a posting URL or text was provided in the invocation message, use it. Otherwise ask:
> "Please share the job posting — a URL or pasted text works."

If a URL is given:
```
WebFetch(url)
```

If the fetch fails or is blocked, ask the user to paste the job description as text.
If the user declines, stop — the skill cannot tailor the resume without knowing what the
role requires.

### Extract and derive slugs

From the posting, extract:
- **Company name** as displayed (e.g., "Stripe", "Capital One", "Block, Inc.")
- **Position title** as listed (e.g., "Staff Software Engineer, Billing Infrastructure")

Derive the **company slug**: lowercase, spaces → hyphens, strip all punctuation (commas,
periods, apostrophes, parentheses — drop them entirely, not replaced with hyphens),
preserve numbers.
Examples: "Stripe" → `stripe`, "Block, Inc." → `block-inc`, "O'Reilly Media" → `oreilly-media`

Derive the **position slug**: same rules.
Examples:
- "Staff Software Engineer, Billing Infrastructure" → `staff-software-engineer-billing-infrastructure`
- "Principal Engineer - Platform" → `principal-engineer-platform`
- "Engineering Manager, Data" → `engineering-manager-data`

### Confirm with the user

Present both slugs:
> "I've got **{Company Name}** (`{company-slug}`) and **{Position Title}** (`{position-slug}`).
> Does that look right, or should I adjust either?"

Wait for the user's response. If they request any correction, apply it and then repeat
the confirmation message with the updated values:
> "Updated: **{Company Name}** (`{corrected-company-slug}`) and **{Position Title}** (`{corrected-position-slug}`). Good to go?"

Do not proceed until the user explicitly confirms. Do not assume silence is confirmation.

### Create the position folder

```bash
mkdir -p "{bash-mounted root}/companies/{co}/{pos}"
```

### Check for an existing tailored resume

```bash
ls "{bash-mounted root}/companies/{co}/{pos}/"*Resume.docx 2>/dev/null
```

If a tailored resume already exists, tell the user and ask via AskUserQuestion:
- Question: "A tailored resume already exists for this position. Overwrite it?"
- Options: "Yes — re-tailor and overwrite" / "No — stop here"

Hold the extracted posting content. Proceed to Step 3.

---

## Step 2B — Called by apply-to-job: use provided context

The invocation message contains all three required pieces: company slug, position slug,
and posting content (path to `posting.md` or posting text/URL in context).

- Set company slug and position slug from the provided values.
- If a `posting.md` path is provided, read it using the Read tool (host path).
- If posting text or URL is in the message, use it directly.
- Skip slug confirmation — apply-to-job already confirmed these values.

Proceed to Step 3.

---

## Step 3 — Load the base resume

Read `resume.filename` from config.yaml.

**If `resume.filename` is null or empty:**
Ask the user conversationally:
> "Your config doesn't have a resume filename set. What's the filename of your base
> resume in the job search folder? (e.g., `Jordan_Lee_Resume.docx`)"

Once provided, update config.yaml under `resume.filename` using the Edit tool (host path).
Confirm the write by reading the field back.

**Verify the file exists:**
```bash
ls "{bash-mounted root}/{resume filename}" 2>/dev/null
```

If not found:
> "The file `{resume filename}` isn't in the job search folder. Please put it there
> before continuing — the skill always works from the base resume in the root directory,
> not from a previously tailored version."

Stop until the file is confirmed present. Do not fall back to uploads.

**If the file ends in `.pdf`:** Tell the user the base resume must be a `.docx` — the
DOCX tooling cannot edit a PDF. Ask them to provide a `.docx` version. Stop until done.

**Extract the resume text:**
```bash
pandoc "{bash-mounted root}/{resume filename}" -o /tmp/resume_raw.md
```

Check that the output file exists and is non-empty:
```bash
wc -l /tmp/resume_raw.md 2>/dev/null
```

If the file is missing or empty (pandoc failed), report the error verbatim to the user
and stop. Do not continue with an empty resume.

```bash
cat /tmp/resume_raw.md
```

Read the resume carefully. Understand:
- Work history and titles (every role, every bullet)
- Skills and technologies listed
- Accomplishments and metrics
- Education and certifications
- Summary or headline section

---

## Step 4 — Assemble posting content

Check whether `posting.md` already exists at the position path:
```bash
ls "{bash-mounted root}/companies/{co}/{pos}/posting.md" 2>/dev/null
```

**If it exists:** Read it using the Read tool (host path). Use it as the posting source.
No re-fetch needed.

**If it doesn't exist:**
- Use the posting content already in hand from Step 2A or 2B.
- Strip any HTML tags — the file should contain readable plain text only.
- Write it to the position path using the Write tool (host path):
  `{host root}/companies/{co}/{pos}/posting.md`
- Format: plain markdown. If the posting has clear sections (responsibilities,
  requirements, qualifications), preserve them as markdown headers. If it's a text blob,
  write it as-is with no reformatting.
- Confirm the write:
  ```bash
  head -5 "{bash-mounted root}/companies/{co}/{pos}/posting.md"
  ```
  If the head check returns empty, report the error and stop.

**Confirm you can extract from the posting:**
- Company name and position title
- Key responsibilities (top 3–5)
- Required qualifications (hard skills, technologies, experience level)
- Preferred qualifications
- Soft skills and values language
- Seniority signals (years of experience, scope, leadership expectations)

---

## Step 5 — Load supporting context

Read each of the following if it exists. If a file is absent, note it and continue. If a
read fails for any other reason, note the error and continue — none of these are blockers.

**`companies/{co}/company.md`** (host path):
- Skim Tech Stack and Culture sections.
- Extract: confirmed languages/frameworks, cloud provider, architectural patterns.
- Use to sharpen keyword matching — a technology confirmed in an engineering blog post
  is stronger signal than one that only appears in job postings.

**`companies/{co}/{pos}/position-fit.md`** (host path):
- If it exists, read the gap analysis and strengths sections.
- Use the listed gaps to seed Step 6. Still do your own analysis, but prioritize
  what apply-to-job already surfaced rather than re-deriving from scratch.

**`Story Bank.md`** (host path, root level):
- Scan the summary line of each story.
- Identify 1–3 stories whose core achievement directly anchors what the role is asking for.
- Hold these — they inform which bullets to strengthen and what framing to use. Do not
  recommend stories to the user at sign-off; that's interview-prep's job. Use them here
  only to guide editorial choices on the resume.

**`insights.md`** (already loaded in Step 0):
- Skim for observations about how the user presents their experience. Ignore algorithm
  or study-session observations. Focus on anything like "undersells X" or "buries depth
  on Y" that would affect resume framing.

---

## Step 6 — Gap analysis

Compare the job requirements against the resume. Build a working list under these
categories. This analysis is internal — do not present the raw list to the user. Use it
to drive Step 8.

**Keywords to surface:** Does the job use a specific term the resume doesn't? If the job
says "Kubernetes" and the resume says "container orchestration" and company.md confirms
they use Kubernetes, surface the specific term — only if the user genuinely has that
experience.

**Achievements to re-lead with:** If the job emphasizes scale/reliability and the resume
leads with feature work, identify bullets that have the right metrics or scope and flag
them to be brought forward.

**Skills to reorder:** If the job's top requirement matches something buried in the skills
list, flag it for promotion.

**Content to de-emphasize:** If the job is a backend infrastructure role and the resume
leads with unrelated work, identify what to push down.

**Gaps to flag:** If the job requires something not on the resume, do not paper over it.
Decide: is this something the user might have but didn't capture (→ ask in Step 7) or
a genuine gap the user needs to address in interviews (→ flag in Step 12)?

**Summary angle:** Decide whether the summary needs adjustment. If it doesn't match what
the role cares about most, note a targeted edit — not a full rewrite.

---

## Step 7 — Clarifying questions (if needed)

If the gap analysis reveals ambiguities only the user can resolve, ask them now in
conversational prose. Ask all questions in one message — not one at a time.

Good questions: ones where the user's answer would change which bullet to strengthen,
which technology to name, or which framing to use.

Examples:
- "The posting puts a lot of weight on Kafka operations at scale — your resume mentions
  messaging systems but doesn't name Kafka directly. Do you have hands-on Kafka experience
  we can name explicitly? And if so, what's the largest cluster or throughput you worked with?"
- "The role is explicitly Staff level and mentions cross-org technical leadership. Which
  of your experiences best shows leading a technical direction across teams?"

Rules:
- Cap at 3 questions. If there are more ambiguities, ask only the ones where the answer
  would most change the output. Make editorial calls on the rest.
- If the gap analysis is clear and you can make all calls confidently, skip this step
  entirely and go directly to Step 8.

Wait for the user's response before proceeding to Step 8. If the user says "I don't
know" or provides a partial answer, use what you have and note any remaining uncertainty
in Step 12.

---

## Step 8 — Make the edits

### Determine the output filename

From config.yaml → `user.name`:
- Split on the **first space** to get first name and last name.
- If there is no space in the name (single-word name), use the full value as first name
  and omit the last name segment entirely (no trailing underscore).
- Example: "Jordan Lee" → first = "Jordan", last = "Lee" → `Jordan_Lee_...`
- Example: "A. K. Singh" → first = "A.", last = "K. Singh" → `A._K._Singh_...`
- Example: "Madonna" → first = "Madonna", no last → `Madonna_...`

For the company and position display names in the filename:
- Use the actual company name and position title (not the slugs)
- Drop all special characters: commas, hyphens, slashes, parentheses, apostrophes —
  drop them entirely (do not replace with anything)
- After dropping, collapse any resulting consecutive spaces to a single space
- Replace all spaces with underscores
- Preserve the original casing

Format: `{FirstName}_{LastName}_{CompanyDisplay}_{PositionDisplay}_Resume`
(If no last name: `{FirstName}_{CompanyDisplay}_{PositionDisplay}_Resume`)

Examples:
- "Jordan Lee", "Stripe", "Staff Software Engineer, Billing Infrastructure"
  → drop comma → collapse → underscores
  → `Jordan_Lee_Stripe_Staff_Software_Engineer_Billing_Infrastructure_Resume`
- "A. K. Singh", "Block, Inc.", "Principal Engineer - Platform"
  → drop comma and hyphen → collapse → underscores
  → `A._K._Singh_Block_Inc_Principal_Engineer_Platform_Resume`
- "Jordan Lee", "Capital One", "Senior Staff Engineer / Payments"
  → drop slash → collapse → underscores
  → `Jordan_Lee_Capital_One_Senior_Staff_Engineer_Payments_Resume`

### Copy the base resume to a working location

```bash
cp "{bash-mounted root}/{resume filename}" /tmp/resume_working.docx
```

### Unpack

Re-derive the scripts path in this bash call (environment does not persist between calls):
```bash
DOCX_SCRIPTS=$(find /sessions/*/mnt -path "*/skills/docx/scripts" -type d 2>/dev/null | head -1)
if [ -z "$DOCX_SCRIPTS" ]; then echo "ERROR: DOCX scripts not found"; exit 1; fi
python "${DOCX_SCRIPTS}/office/unpack.py" \
  /tmp/resume_working.docx /tmp/resume_unpacked/
```

If this fails, report the error and stop. Do not attempt to continue without a valid
unpacked directory.

Inspect `word/document.xml` to understand the structure before editing.

### Edit

Use the Edit tool for precise string replacements in `/tmp/resume_unpacked/word/document.xml`.

Make only targeted, necessary edits. The goal is surgical improvement, not a full rewrite.
Work through the gap analysis from Step 6 in this order:

1. **Summary / headline:** Adjust the angle to surface the most relevant specialization.
   Do not rewrite the whole summary. Never use the job description's own phrasing — the
   hiring manager who wrote "create durable leverage" will recognize it instantly. Only
   name technologies in the summary that already appear in the user's skills or work history.

2. **Skills section:** Reorder to surface the most relevant skills first. Do not add
   skills the user doesn't have.

3. **Work history bullets:** Rephrase bullets that have the right content but wrong
   framing. Use the job's vocabulary where it honestly fits. Bring relevant metrics to
   the front of bullets. Do not change what the bullet describes.

4. **Section ordering:** Reorder sections only if the XML structure supports it cleanly
   and the gain is significant. Don't restructure for marginal improvement.

**Never fabricate:**
- Do not add a skill, technology, or tool the user didn't list.
- Do not invent a metric, outcome, or accomplishment.
- Do not claim experience the resume doesn't support.
- Do not rephrase a bullet so it describes different work than what actually happened.
- Do not use em-dashes (—) anywhere. Replace any with a comma or restructure the sentence.

If you are unsure whether a rephrase changes the meaning, keep the original and flag it
in Step 12 with an explicit question for the user.

### Repack and validate

```bash
DOCX_SCRIPTS=$(find /sessions/*/mnt -path "*/skills/docx/scripts" -type d 2>/dev/null | head -1)
python "${DOCX_SCRIPTS}/office/pack.py" \
  /tmp/resume_unpacked/ /tmp/resume_output.docx \
  --original /tmp/resume_working.docx

python "${DOCX_SCRIPTS}/office/validate.py" \
  /tmp/resume_output.docx
```

**If validation fails:**
1. Report the exact error to the user.
2. Attempt to fix only if the error is a specific, identifiable string issue in
   `word/document.xml` (e.g., an unclosed tag you introduced). Re-run validate after the fix.
3. If the fix is unclear or the error is structural, do not attempt further edits.
   Tell the user: "Validation failed and I can't safely fix it. I'm providing the
   unedited original (`/tmp/resume_working.docx`) — all edits are lost. You can apply
   the changes manually using the summary below."
   Copy `/tmp/resume_working.docx` as the fallback output, then **stop**. Do not attempt
   PDF generation. Proceed to Step 11 to log the session, then deliver the fallback in
   Step 12.

---

## Step 9 — Generate the PDF

```bash
DOCX_SCRIPTS=$(find /sessions/*/mnt -path "*/skills/docx/scripts" -type d 2>/dev/null | head -1)
python "${DOCX_SCRIPTS}/office/soffice.py" \
  --headless --convert-to pdf \
  --outdir /tmp/ \
  /tmp/resume_output.docx
```

This produces `/tmp/resume_output.pdf`. If PDF generation fails, report the error to the
user and note that only the `.docx` will be saved. Do not stop the skill over a PDF
failure — the `.docx` is the deliverable; the `.pdf` is a convenience.

---

## Step 10 — Save files

Use the bash-mounted path for copy commands:

```bash
OUTDIR="{bash-mounted root}/companies/{co}/{pos}"
FILENAME="{computed filename from Step 8}"

cp /tmp/resume_output.docx "${OUTDIR}/${FILENAME}.docx"
cp /tmp/resume_output.pdf  "${OUTDIR}/${FILENAME}.pdf" 2>/dev/null || true
```

Verify the `.docx` is present — it is required:
```bash
ls -lh "{bash-mounted root}/companies/{co}/{pos}/"*Resume* 2>/dev/null
```

If the `.docx` is missing from the listing, report the error and stop. Do not proceed to
Step 11. The `.pdf` may be absent if Step 9 failed; note its absence in Step 12 but do
not stop over it.

---

## Step 11 — Append CLAUDE.md session log

Read `CLAUDE.md` using the Read tool (host path). Append one row to the session log table:

```
| {YYYY-MM-DD} | resume-tailor: {Company} — {Position Title} | {one observation — e.g., "surfaced Kafka depth; two gaps flagged (eBPF, chaos engineering)"} |
```

If no session log table exists in CLAUDE.md, add one before appending:
```markdown
## Session Log

| Date | Covered | Observations |
|------|---------|--------------|
```

Write the updated CLAUDE.md back using the Write tool at the host path.

Confirm the write succeeded:
```bash
head -5 "{bash-mounted root}/CLAUDE.md"
```

If the head check returns empty, report the error but do not stop — proceed to Step 12.

---

## Step 12 — Sign off

Report what was produced and what changed. Be concise and direct.

```
Files written:
  companies/{co}/{pos}/{filename}.docx
  companies/{co}/{pos}/{filename}.pdf   [or: "PDF generation failed — .docx only"]

Changes made:
  Summary: {What changed and why. One or two sentences.
            e.g., "Surfaced distributed systems specialization; removed unrelated
            frontend framing."}
  Skills: {What was reordered.
           e.g., "Promoted Kafka, Flink, AWS to top of list."}
  {Resume role title @ Company (from your work history, not the target job)}:
    {One line per changed bullet describing what it now leads with and why.
     e.g., "Kafka migration bullet: now leads with 100K msgs/sec throughput rather
     than implementation detail, matching the posting's scale emphasis."}
  {Other resume role if changed}: {same format}

Gaps flagged:
  {Honest list of what the job asks for that isn't on the resume. Be specific:
   distinguish between "completely absent" (e.g., "no eBPF experience listed") and
   "present but lighter than required" (e.g., "Kubernetes mentioned once in skills,
   but posting wants deep cluster-ops experience"). These are for the user to decide
   how to address — in interviews or by adding to the resume if the experience exists.
   Write "None" if there are no material gaps.}

{If any rephrase was uncertain — you weren't sure it stayed true to the original —
list it explicitly: "I adjusted [the X bullet in Role Y] to lead with [Z]. Confirm
this still accurately describes what you did."}
```

Do not list every minor edit. Focus on changes that meaningfully affect how the resume
reads for this role. If you fell back to the unedited original due to a validation
failure, say so here and list the intended changes as a reference for manual application.

---

## Edge cases

**Posting fetch blocked or fails:** Ask the user to paste the job description as text.
If they decline, stop.

**No meaningful gap between posting and resume:** Tell the user the resume is already
well-aligned and list the 2–3 strongest match areas. Make minimal edits (keyword
normalization, skills reorder if helpful) and note that there isn't much to do. Don't
manufacture changes for the sake of producing output.

**Massive posting with vague requirements:** Focus on hard skills and stated
responsibilities. Ignore boilerplate phrases like "strong communicator" unless they appear
repeatedly or are echoed in the company values from company.md.

**User asks to tailor from a previously-tailored version:** Decline. Always work from
the base resume at the root (`config.yaml → resume.filename`). Tailored versions contain
role-specific framing that would carry forward incorrectly into an unrelated application.
Explain this and proceed from the base.

**Company or position folder has a naming collision:** If `companies/{co}/` already exists
but its company.md header shows a different company, surface the conflict:
> "A folder for a different company already uses the slug `{co}`. Suggested alternative:
> `{co}-2`."
Use AskUserQuestion to confirm a slug before proceeding.

---

## Principles to keep in mind

**Surgical, not sweeping.** Targeted edits to relevant content. Preserve the user's voice
and the document's visual style.

**Editor, not ghostwriter.** Every word must reflect something already true in the user's
background. Rephrasing is fine. Invention is not.

**No em-dashes.** Anywhere in the resume. Replace with a comma or restructure the sentence.

**No echoing the JD.** In the summary especially, lifting the posting's distinctive
phrasing signals the candidate copied rather than wrote. The hiring manager who wrote it
will recognize it. Use the candidate's own voice aimed at what the role values.

**Less is more.** Tightening a vague bullet is usually better than adding a new one.

**Honesty is non-negotiable.** A resume that misrepresents someone's background sets them
up to fail in the interview. Name gaps clearly — it's more useful than papering over them.

**Always produce both formats.** The `.docx` is the editable master. The `.pdf` is what
gets submitted. Both should be present in the position folder unless PDF generation failed.
