# job-search

End-to-end job search system for Claude. A connected set of skills that share a common directory structure and memory model so the agent never starts from scratch — every session loads what it has already learned about you, what's in your pipeline, and what you've studied.

## Skills

The skills fall into four groups: **setup** skills you run once to stand things up, **main** skills that drive the day-to-day job search, **support** skills the main flows orchestrate (but that you can also run directly), and a **maintenance** skill for keeping your inbox in order.

### Setup

Run these to stand up the system and plan your prep.

| Skill | What it does |
|-------|--------------|
| `job-search-init` | One-time setup. Walks you through a short interview, then writes the directory scaffolding (config.yaml, CLAUDE.md, profile.md, insights.md, Story Bank.md, study-plans/) every other skill reads from. |
| `create-study-plan` | Generate a customized study plan via interview. Writes weekly plan files into `study-plans/{slug}/` and updates the active-study pointer. Supports modify-in-place mode for active plans. |

### Main

The skills you reach for as you apply and practice.

| Skill | What it does |
|-------|--------------|
| `apply-to-job` | Track a new position. Writes `posting.md` and `position-fit.md` (gap analysis with strengths, gaps, relevant stories, red flags, plus a status header). On Apply intent, also invokes resume-tailor and offers find-recruiter. |
| `study-session` | Run a daily prep session against the active study. Updates progress and appends durable insights to `insights.md`. |
| `interview-prep` | Prep for a specific upcoming scheduled interview. Pulls calendar context, researches interviewers and reported questions, suggests stories and topics to refresh. |

### Support

The main flows call these automatically, but each runs standalone too.

| Skill | What it does |
|-------|--------------|
| `company-research` | Research a company (and optionally a specific posting). Writes `companies/{co}/company.md`. |
| `resume-tailor` | Tailor your resume to a specific posting. Writes the tailored `.docx` and `.pdf` into the position folder. |
| `find-recruiter` | Find a recruiter at a company and draft outreach. Updates `companies/{co}/contacts.md` and writes the position's `outreach.md`. |

### Maintenance

| Skill | What it does |
|-------|--------------|
| `label-job-search-emails` | Sort recent job-search emails into per-company Gmail sublabels and archive them out of the inbox. |

## Directory shape

After running `job-search-init`, the directory looks like:

```
{root}/
  config.yaml
  CLAUDE.md
  profile.md
  insights.md
  Story Bank.md
  {your-resume}.docx
  companies/
  study-plans/
    index.md
```

Positions in flight live under `companies/{slug}/{pos}/` — there's no separate pipeline file. Status, recruiter, and posting all live inside the position folder.

As you use the plugin, content accumulates:

```
companies/
  acme/
    company.md
    contacts.md
    staff-backend/
      posting.md
      position-fit.md
      Acme-Staff-Backend-resume.docx
      Acme-Staff-Backend-resume.pdf
      outreach.md
      prep/
        recruiter-screen.md
        tech-screen.md
        system-design.md
        leadership.md
      interviews/
        2026-05-02-tech-screen.md
        2026-05-02-tech-screen-debrief.md

study-plans/
  staff-backend-4wk/
    plan.md
    week-1.md ... week-4.md
    progress.md
```

## Memory model

Four files are always loaded at the start of every session:

- `profile.md` — who you are, target role, comm style
- `insights.md` — running collection of patterns, gotchas, and weak spots learned across all studies and interviews
- `CLAUDE.md` — lean session log + pointers
- `study-plans/index.md` — roster of all study plans with one-line summaries

`config.yaml` is also loaded for configuration (calendar provider, mail settings, LinkedIn search method, active study). Positions in flight aren't loaded eagerly — they're scanned from `companies/` on demand.

This means: when you switch between study plans, start a new search, or come back after a break, the agent already knows you. It doesn't re-learn what's in those files; it picks up where you left off.

Routing: stable identity → `profile.md`. Recurring patterns and gotchas → `insights.md`. This-session activity → `study-plans/{slug}/progress.md`. New stories that surface during practice → `Story Bank.md` (with help refining them).

## Getting started

Install the plugin and run `job-search-init` to scaffold a new directory. After init, run `create-study-plan` if you want to start a structured prep plan, or `apply-to-job` if you have a posting you want to track.
