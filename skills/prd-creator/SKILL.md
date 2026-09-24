---
name: prd-creator
description: Use when the user wants to create a Product Requirements Document (PRD) for a new app, feature, or project. Runs a structured interview and produces a complete PRD (as a visual single-file HTML page, a markdown file, or both) along with ready-to-build milestone prompts for a coding agent.
user_invocable: true
---

# PRD Creator

Adapted from [buildermethods/bm-skills](https://github.com/buildermethods/bm-skills)'s `bm-prd-creator`, inlined into a single file (this repo's skill pipeline only deploys `SKILL.md` text, not sibling files, so the original's `steps/*.md` split doesn't survive deployment here — see `skills/tailscale/SKILL.md` for the same constraint solved a different way).

You are guiding a non-technical business builder through turning a raw idea into a structured PRD and a sequence of milestone prompts that they can use to drive a coding agent through implementation.

This skill follows a structured, multi-phase interview. Do not skip ahead — earlier phases produce the inputs that later phases depend on.

## Audience assumption

The user understands product, user experience, and what they want their app to do. They do NOT have a developer's understanding of code, databases, integrations, APIs, background jobs, authentication, or deployment. Whenever a technical concept appears, briefly explain it in plain language before asking the user to make a decision about it. Examples of how to explain things:

- "A _background job_ is just a way for the app to do slow work (like calling an AI) after the user has already moved on, so the user doesn't have to wait."
- "An _API token_ is like a password the app gives out so other tools can talk to it on the user's behalf."
- "A _data model_ is the list of things your app needs to remember — like 'bookmarks' and 'tags' — and how they relate to each other."

## Core interaction principles

1. **Always propose a default with reasoning, then ask to confirm or change.** Never ask open-ended "what do you want?" questions when you can propose a sensible default and explain why. The user is much better at editing a proposal than generating one.
2. **Use the AskUserQuestion tool for decisions with discrete options.** For free-form input (the initial brain dump, naming the app, describing a feature), use a normal chat message. For choosing between defined options, always use AskUserQuestion — the user is much more likely to be on mobile, and tappable options beat typing.
3. **One decision at a time, in sequence.** Don't ask three unrelated questions at once. Walk through phases in order. Lock each phase before moving to the next.
4. **Adapt depth to the idea.** The default interview is balanced (~10–15 decisions). For very simple ideas, compress; for complex ideas with many features and integrations, expand. The user's initial brain dump tells you how to scope.
5. **The PRD is a _what_ document, not a _how_ document.** The PRD describes user functionality, user flows, UI/UX behavior, scope boundaries, integrations, and the data the app needs to remember. It does NOT prescribe technical implementation: no code samples, no specific libraries (beyond the stack itself), no method names, no internal logic, no algorithmic decisions, and no technical patterns like timeouts, retry strategies, parsing approaches, or error-handling structure. Those decisions belong to the agent in plan mode for each milestone. The PRD's tech-stack section names the stack (e.g., Rails, React) and the integrations section names the providers (e.g., OpenAI, Resend) — that's the depth limit. Anything more specific is implementation.
6. **Keep your prose tight.** Short framings, no preamble. The user is making decisions, not reading essays.
7. **HTML is the default output.** Early in the interview the user picks a format (HTML / Markdown / Both). HTML is recommended because it's visual, scannable, and easier for non-technical users to review. The format choice changes _presentation only_ — the locked scope, voice, and "what vs. how" boundary are identical across formats.

## Phases

Execute the following phases in order. Confirm each phase is locked before moving to the next.

### 1. Brain dump intake

If the user's first message is already a substantive description of the idea, you have your brain dump — proceed to phase 3 (Core purpose). If their first message is just "help me plan an app" or similar, ask them to describe in their own words: what is the idea, what problem does it solve, who is it for. Free-form text response, no AskUserQuestion needed here.

### 2. Format choice

Before diving into the rest of the interview, lock the **output format** for the PRD. This decides what file(s) get written at the end. Milestone prompt files always stay as markdown regardless of this choice — they're consumed by the coding agent in plan mode, not by you.

Briefly explain the options in one short framing message, then use AskUserQuestion:

- **HTML (recommended)** — A single self-contained `prd.html` file you can open in a browser. Visual, scannable, mobile-responsive, with a light/dark toggle. Cards, tables, icons, formatted lists. Best for understanding the plan at a glance and sharing with non-technical collaborators.
- **Markdown** — A traditional `prd.md` text file. Best if you want to read in your editor, edit by hand, or paste sections elsewhere.
- **Both** — Generate both `prd.html` and `prd.md`.

Lock the choice and remember it. You'll reference it again in the "Write files" phase.

### 3. Core purpose

Synthesize the user's brain dump into a 1–3 sentence "what we're building" statement. Propose it back to them and ask if it's right. This becomes the opening of the PRD's "What we're building" section.

Use AskUserQuestion with options like:

- Yes, that captures it
- Mostly right, I'll edit in chat
- Off — let me re-explain

If they edit, refine and re-confirm before moving on.

### 4. Top-level features (in scope)

Propose a list of 4–8 core features that the app needs to deliver its core purpose. Present them as a numbered list in chat with a one-line explanation of each. Ask the user (via AskUserQuestion or free text) which to keep, which to cut, and what's missing.

The output of this phase is a locked list of in-scope features at the headline level.

### 5. Top-level out-of-scope

Based on the in-scope feature list, proactively propose a list of likely out-of-scope items — things that _could_ be in this kind of app but the user almost certainly doesn't want in v1. Examples for common app types:

- For most apps: mobile app, browser extension, social/sharing features, advanced search, OAuth/third-party login, payment/billing, multi-tenant or team features, importing from other tools
- For AI-powered apps: model selection, fine-tuning, per-user API keys, multiple AI providers
- For content apps: archiving, favorites, trash, public pages, comments

Present the list, explain why each is a reasonable cut for v1, and ask the user to confirm or pull anything back into scope. Also ask if there's anything else they want explicitly out.

### 6. Tech stack & starter template

**First, detect what's already there.** Without asking the user, check the codebase:

1. Read `CLAUDE.md` and/or `AGENTS.md` if either exists — these often spell out the stack and conventions.
2. Look at top-level config files: `Gemfile`, `package.json`, `composer.json`, `requirements.txt`, `pyproject.toml`, `go.mod`, `Cargo.toml`, etc.
3. Look at folder structure for framework signatures (`app/`, `config/`, `db/migrate/` for Rails; `pages/` or `app/` for Next.js; `src/` patterns; etc.)
4. Note any starter template signatures. If the codebase looks like the **Build New** starter (Rails 8 + Inertia + React 19 + Tailwind + shadcn + PostgreSQL + Solid Queue + the standard `AppShell` and authenticated routes), call that out specifically.

**Then summarize what you found** to the user in plain language: "Looks like you're working in a Rails app with React on the frontend, using the Build New starter template. That gives you user signup/login, the app shell, dark mode, and a job queue out of the box."

**If detection is empty or ambiguous** (no clear stack found, or this is a fresh empty project), recommend the Build New template as the default and explain in plain language what it gives them. Use AskUserQuestion to confirm or override:

- Use Build New (recommended)
- Use a different stack — I'll specify in chat
- I'm not sure — explain my options

**Then, the starter template question.** Ask what's already built into the starter that the PRD shouldn't re-spec. Default proposal based on Build New: signup/login/password reset, the User model, the authenticated app shell, settings/profile pages, dark mode, email previews in development, background job queue. Ask them to confirm or add to this list.

### 7. External integrations & credentials

For each in-scope feature, identify whether it needs an external service. Examples:

- AI summarization → OpenAI or Anthropic API
- Email sending → Resend, Postmark, SendGrid
- Payments → Stripe (but probably out of scope for v1)
- File uploads → S3 or similar
- SMS → Twilio
- Maps → Google Maps or Mapbox

For each integration:

1. Explain what the integration does in plain language.
2. Propose a default provider with a one-line reason (cheapest / simplest / most common).
3. Use AskUserQuestion to confirm the provider or switch.
4. List the credentials the user will need to obtain (API keys, account signups) so they know what to sign up for before the agent reaches the milestone that uses the integration. Don't prescribe how the credentials are stored in the codebase — the agent decides that during implementation.

Lock the integration list before moving on. If a feature requires an integration the user doesn't want to set up, flag it now — that feature may need to move out of scope.

### 8. Data model

Now that features and integrations are locked, propose the data model. For a non-technical user, frame this as: "Here are the things your app needs to remember, and how they relate to each other."

For each entity (data model):

1. Name it (e.g., Bookmark, Tag, Project, Task)
2. List its fields in plain language ("URL — the link being saved", "title — the headline of the page")
3. Note any relationships ("each Bookmark belongs to a User; each Bookmark can have multiple Tags")

Propose the full model at once, then ask the user to confirm or adjust. Common adjustments: missing fields, missing entities, fields that should be required vs. optional. Use AskUserQuestion for the confirmation step:

- Looks right, lock it in
- Mostly right, I'll edit in chat
- Missing something — let me describe

### 9. Per-feature scoping

Now revisit each in-scope feature one at a time and lock its detailed scope. For each feature, focus on **user-facing decisions only** — what the user sees, does, and experiences. Do NOT discuss technical implementation (libraries, methods, error handling, timeouts, parsing logic). Those are the agent's job to plan later.

For each feature:

1. Propose the specific user-facing sub-features and capabilities that ARE in scope: what does the user see on screen, what can they do, what UI elements exist, what happens after they take an action, what does the recipient/output look like.
2. Propose the specific user-facing sub-features and capabilities that are NOT in scope: things a more ambitious version of this feature would have but v1 won't (e.g., editing after sending, history, analytics, advanced filters, preview images, attachments, multi-recipient, etc.).
3. Ask the user to confirm or adjust.

Example of the right level of specificity (for a "share by email" feature):

- In scope: a "Share" button on each item; a small form with recipient email, pre-filled subject, pre-filled body the user can edit; one-shot send action; recipient sees a readable email with the item's details.
- Out of scope: tracking opens or clicks, share history, sharing to multiple recipients at once, attaching files, scheduled sends.

What does NOT belong here: which mailer library to use, what queue backend, retry behavior, timeout values, how the email template is rendered. The agent decides all of that in plan mode.

Move through features one at a time. Don't batch.

### 10. Milestone breakout

Propose a default milestone breakout based on a reasonable dependency sequence, plus 2 alternatives at different granularities. For example:

- **Default (recommended):** 3 milestones — Core CRUD → Integrations layer → Public-facing additions
- **Alternative A — fewer/bigger:** 2 milestones — Foundation+CRUD+Integrations together → Public-facing
- **Alternative B — more/smaller:** 5–6 milestones — One per major feature

Each milestone must:

- Deliver visible, usable functionality the user can see and test in the browser
- Be a self-contained working session for a coding agent
- Have clear dependencies (later milestones build on earlier ones)

Explain the tradeoff in plain language: fewer milestones = larger one-shot sessions, more risk per session, less control; more milestones = more checkpoints, slower overall, more context-switching.

Use AskUserQuestion to let the user pick. After they pick, propose the actual milestone names and one-line scopes, and confirm.

### 11. Write files

Once everything is locked, generate the files. **Just write them.** Don't show a draft for approval first — the user already approved each piece during the interview.

**What to write, based on the format choice** locked in phase 2:

- **HTML** → write `_build_plan/prd.html` only. Use the HTML scaffold in "prd.html structure" below.
- **Markdown** → write `_build_plan/prd.md` only. Use the markdown template below.
- **Both** → write **both** `_build_plan/prd.html` **and** `_build_plan/prd.md`. The two files must describe the same locked scope — HTML is a different presentation, not a different plan.

Milestone `prompt.md` files are **always written as markdown** regardless of the format choice. They're consumed by the coding agent in plan mode, not by the user.

Create this exact structure in the codebase root (file presence depends on the format choice above):

```
_build_plan/
  prd.html         # HTML or Both
  prd.md           # Markdown or Both
  milestones/
    1-{milestone-slug}/
      prompt.md
    2-{milestone-slug}/
      prompt.md
    ...
```

`{milestone-slug}` is a short kebab-case name derived from the milestone (e.g., `core-crud`, `integrations-layer`, `public-docs`).

After writing the `_build_plan/` files, also add a short note about the `_build_plan/` folder to the project's agent instructions file — see "Agent instructions note" below.

After writing, briefly tell the user the files are ready and how to use them. Tailor the message to what was written:

- If `prd.html` was written: tell them to open it in a browser (`open _build_plan/prd.html`) to review the plan visually, then open the milestone-1 `prompt.md` and ask the agent to start there.
- If only `prd.md` was written: tell them to open `_build_plan/prd.md` to review, then open the milestone-1 `prompt.md` and ask the agent to start there.
- Either way, mention that after each milestone the agent will write a `milestone-log.md` in that milestone's folder to record what was done.

#### prd.html structure

When the format choice was **HTML** or **Both**, write `_build_plan/prd.html` using the scaffold and section snippets below. The file must be fully self-contained — only CDN-loaded dependencies (Tailwind, Google Fonts, Lucide), no other files, no build step.

Start every `prd.html` from this scaffold. Fill in the `{{PLACEHOLDERS}}` and section blocks as described under "Section visual treatments" below. Do not rename CSS classes — they work as written with Tailwind Play CDN.

```html
<!doctype html>
<html lang="en">
  <head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <title>{{APP_NAME}} — PRD</title>
    <script src="https://cdn.tailwindcss.com"></script>
    <script>
      tailwind.config = { darkMode: "class" };
    </script>
    <link rel="preconnect" href="https://fonts.googleapis.com" />
    <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin />
    <link
      href="https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700&display=swap"
      rel="stylesheet"
    />
    <script src="https://unpkg.com/lucide@latest"></script>
    <style>
      html {
        font-family:
          "Inter",
          system-ui,
          -apple-system,
          sans-serif;
      }
      body {
        font-feature-settings: "cv11", "ss01";
      }
      @media print {
        html {
          background: white !important;
          color: black !important;
          color-scheme: light;
        }
        html.dark {
          color-scheme: light;
        }
        html.dark body,
        html.dark * {
          background: white !important;
          color: black !important;
          border-color: #d4d4d8 !important;
        }
        .no-print {
          display: none !important;
        }
        .print-card {
          break-inside: avoid;
          page-break-inside: avoid;
        }
        header.sticky {
          position: static !important;
          backdrop-filter: none !important;
        }
        main {
          padding-top: 0 !important;
        }
        a {
          color: black !important;
          text-decoration: none !important;
        }
      }
    </style>
  </head>
  <body
    class="bg-zinc-50 dark:bg-zinc-950 text-zinc-900 dark:text-zinc-100 antialiased"
  >
    <header
      class="sticky top-0 z-10 backdrop-blur bg-zinc-50/80 dark:bg-zinc-950/80 border-b border-zinc-200 dark:border-zinc-800"
    >
      <div
        class="max-w-4xl mx-auto px-4 sm:px-6 py-3 flex items-center justify-between"
      >
        <span class="text-sm font-medium text-zinc-500 dark:text-zinc-400"
          >PRD · {{APP_NAME}}</span
        >
        <button
          id="theme-toggle"
          class="no-print inline-flex items-center justify-center w-9 h-9 rounded-md border border-zinc-200 dark:border-zinc-800 hover:bg-zinc-100 dark:hover:bg-zinc-900 transition"
          aria-label="Toggle theme"
        >
          <i data-lucide="sun" class="hidden dark:inline-block w-4 h-4"></i>
          <i data-lucide="moon" class="inline-block dark:hidden w-4 h-4"></i>
        </button>
      </div>
    </header>

    <main class="max-w-4xl mx-auto px-4 sm:px-6 py-10 sm:py-14 space-y-14">
      <!-- DISCLAIMER (keep verbatim) -->
      <div
        class="rounded-lg border border-amber-200 dark:border-amber-900/60 bg-amber-50 dark:bg-amber-950/30 p-4 text-sm text-amber-900 dark:text-amber-200"
      >
        <p>
          <strong class="font-semibold">About this file:</strong> Everything in
          <code class="font-mono text-xs">_build_plan/</code> (this PRD and the
          per-milestone folders) is a temporary documentation artifact for the
          initial build-out of this codebase. These files are not functional —
          no code, configuration, runtime logic, tests, or deployment process
          should import, read, reference, or depend on anything in
          <code class="font-mono text-xs">_build_plan/</code>. Once the initial
          milestones are built and shipped, the entire
          <code class="font-mono text-xs">_build_plan/</code> folder is expected
          to be deleted from the codebase.
        </p>
      </div>

      <!-- HERO -->
      <section>
        <h1 class="text-4xl sm:text-5xl font-bold tracking-tight">
          {{APP_NAME}}
        </h1>
        <p
          class="mt-5 text-lg sm:text-xl text-zinc-600 dark:text-zinc-400 leading-relaxed"
        >
          {{WHAT_WE_ARE_BUILDING}}
        </p>
        <div class="mt-6 flex flex-wrap gap-2">{{TECH_STACK_BADGES}}</div>
      </section>

      <!-- WHAT THE APP DOES -->
      <section>
        <h2
          class="text-xs font-semibold uppercase tracking-[0.18em] text-zinc-500 dark:text-zinc-400 flex items-center gap-2"
        >
          <i data-lucide="sparkles" class="w-3.5 h-3.5"></i>What the app does
        </h2>
        <ul class="mt-5 grid grid-cols-1 sm:grid-cols-2 gap-3 list-none p-0">
          {{FEATURE_CARDS}}
        </ul>
      </section>

      <!-- ALREADY PROVIDED -->
      <section>
        <h2
          class="text-xs font-semibold uppercase tracking-[0.18em] text-zinc-500 dark:text-zinc-400 flex items-center gap-2"
        >
          <i data-lucide="package-check" class="w-3.5 h-3.5"></i>Already
          provided by {{STARTER_NAME}}
        </h2>
        <ul class="mt-5 flex flex-wrap gap-2 list-none p-0">
          {{STARTER_PROVIDED_PILLS}}
        </ul>
      </section>

      <!-- OUT OF SCOPE -->
      <section>
        <h2
          class="text-xs font-semibold uppercase tracking-[0.18em] text-zinc-500 dark:text-zinc-400 flex items-center gap-2"
        >
          <i data-lucide="minus-circle" class="w-3.5 h-3.5"></i>Out of scope
          (v1)
        </h2>
        <ul class="mt-5 space-y-2.5 list-none p-0">
          {{OUT_OF_SCOPE_ITEMS}}
        </ul>
      </section>

      <!-- INTEGRATIONS (omit section entirely if no integrations) -->
      <section>
        <h2
          class="text-xs font-semibold uppercase tracking-[0.18em] text-zinc-500 dark:text-zinc-400 flex items-center gap-2"
        >
          <i data-lucide="plug" class="w-3.5 h-3.5"></i>External integrations
        </h2>
        <div class="mt-5 grid grid-cols-1 sm:grid-cols-2 gap-3">
          {{INTEGRATION_CARDS}}
        </div>
      </section>

      <!-- DATA MODEL -->
      <section>
        <h2
          class="text-xs font-semibold uppercase tracking-[0.18em] text-zinc-500 dark:text-zinc-400 flex items-center gap-2"
        >
          <i data-lucide="database" class="w-3.5 h-3.5"></i>Data model
        </h2>
        <p class="mt-3 text-sm text-zinc-500 dark:text-zinc-400">
          What the app needs to remember.
        </p>
        <div class="mt-5 grid grid-cols-1 sm:grid-cols-2 gap-3">
          {{ENTITY_CARDS}}
        </div>
      </section>

      <!-- MILESTONES -->
      <section>
        <h2
          class="text-xs font-semibold uppercase tracking-[0.18em] text-zinc-500 dark:text-zinc-400 flex items-center gap-2"
        >
          <i data-lucide="route" class="w-3.5 h-3.5"></i>Milestones
        </h2>
        <div class="mt-5 space-y-5">{{MILESTONE_CARDS}}</div>
      </section>

      <footer
        class="pt-8 border-t border-zinc-200 dark:border-zinc-800 text-xs text-zinc-500 dark:text-zinc-400"
      >
        Generated by <span class="font-medium">prd-creator</span>. Open the
        milestone-1 <code class="font-mono">prompt.md</code> to start building.
      </footer>
    </main>

    <script>
      (function () {
        var html = document.documentElement;
        var stored = localStorage.getItem("prd-theme");
        var prefersDark =
          window.matchMedia &&
          window.matchMedia("(prefers-color-scheme: dark)").matches;
        var initial = stored ? stored : prefersDark ? "dark" : "light";
        if (initial === "dark") html.classList.add("dark");
        var btn = document.getElementById("theme-toggle");
        if (btn) {
          btn.addEventListener("click", function () {
            var isDark = html.classList.toggle("dark");
            localStorage.setItem("prd-theme", isDark ? "dark" : "light");
          });
        }
        if (window.lucide) window.lucide.createIcons();
      })();
    </script>
  </body>
</html>
```

**Section visual treatments** — drop these snippets into the matching placeholder, repeated per item:

- Tech-stack badge — `{{TECH_STACK_BADGES}}`: one badge per item (framework, database, hosting, key libraries from the locked stack).
  ```html
  <span
    class="inline-flex items-center gap-1.5 px-2.5 py-1 rounded-full bg-white dark:bg-zinc-900 border border-zinc-200 dark:border-zinc-800 text-xs font-medium text-zinc-700 dark:text-zinc-300"
    >{{TECH_NAME}}</span
  >
  ```
- Feature card — `{{FEATURE_CARDS}}`: one `<li>` per high-level capability from "What the app does". Pick a sensible Lucide icon per item (see icon hints below).
  ```html
  <li
    class="print-card rounded-lg border border-zinc-200 dark:border-zinc-800 bg-white dark:bg-zinc-900 p-4"
  >
    <div class="flex items-start gap-3">
      <div
        class="shrink-0 mt-0.5 w-8 h-8 rounded-md bg-zinc-100 dark:bg-zinc-800 flex items-center justify-center"
      >
        <i
          data-lucide="{{LUCIDE_ICON}}"
          class="w-4 h-4 text-zinc-700 dark:text-zinc-300"
        ></i>
      </div>
      <div>
        <p class="font-medium text-zinc-900 dark:text-zinc-100">
          {{FEATURE_LABEL}}
        </p>
        <p
          class="mt-1 text-sm text-zinc-600 dark:text-zinc-400 leading-relaxed"
        >
          {{FEATURE_DESCRIPTION}}
        </p>
      </div>
    </div>
  </li>
  ```
- Starter-provided pill — `{{STARTER_PROVIDED_PILLS}}`: one pill per pre-built capability.
  ```html
  <li
    class="inline-flex items-center gap-1.5 px-3 py-1.5 rounded-md bg-white dark:bg-zinc-900 border border-zinc-200 dark:border-zinc-800 text-sm text-zinc-700 dark:text-zinc-300"
  >
    <i
      data-lucide="check"
      class="w-3.5 h-3.5 text-emerald-600 dark:text-emerald-400"
    ></i
    >{{ITEM}}
  </li>
  ```
- Out-of-scope item — `{{OUT_OF_SCOPE_ITEMS}}`:
  ```html
  <li class="flex items-start gap-3">
    <i
      data-lucide="x"
      class="w-4 h-4 mt-1 shrink-0 text-zinc-400 dark:text-zinc-600"
    ></i>
    <span class="text-zinc-700 dark:text-zinc-300"
      ><span class="font-medium">{{ITEM}}</span
      ><span class="text-zinc-500 dark:text-zinc-400"> — {{REASON}}</span></span
    >
  </li>
  ```
- Integration card — `{{INTEGRATION_CARDS}}`: one per external service, listing the credentials the user must obtain.
  ```html
  <div
    class="print-card rounded-lg border border-zinc-200 dark:border-zinc-800 bg-white dark:bg-zinc-900 p-5"
  >
    <div class="flex items-center gap-2">
      <i
        data-lucide="plug"
        class="w-4 h-4 text-zinc-500 dark:text-zinc-400"
      ></i>
      <h3 class="font-semibold text-zinc-900 dark:text-zinc-100">
        {{PROVIDER_NAME}}
      </h3>
      <span class="ml-auto text-xs text-zinc-500 dark:text-zinc-400"
        >{{PURPOSE}}</span
      >
    </div>
    <p class="mt-3 text-sm text-zinc-600 dark:text-zinc-400 leading-relaxed">
      {{PLAIN_LANGUAGE_EXPLANATION}}
    </p>
    <p
      class="mt-4 text-[11px] font-semibold uppercase tracking-[0.16em] text-zinc-500 dark:text-zinc-400 flex items-center gap-1.5"
    >
      <i data-lucide="key" class="w-3 h-3"></i>Credentials needed
    </p>
    <ul class="mt-2 space-y-1.5 list-none p-0">
      <!-- repeat per credential -->
      <li
        class="flex items-center gap-2 text-sm text-zinc-700 dark:text-zinc-300"
      >
        <i
          data-lucide="key-round"
          class="w-3.5 h-3.5 text-zinc-400 dark:text-zinc-500"
        ></i
        >{{CREDENTIAL_NAME}}
      </li>
    </ul>
  </div>
  ```
- Entity card — `{{ENTITY_CARDS}}`: one card per entity in the data model. Table holds fields described in plain language (not column types). "Related to" footer lists other entity names.
  ```html
  <div
    class="print-card rounded-lg border border-zinc-200 dark:border-zinc-800 bg-white dark:bg-zinc-900 p-5"
  >
    <div class="flex items-center gap-2">
      <i data-lucide="box" class="w-4 h-4 text-zinc-500 dark:text-zinc-400"></i>
      <h3 class="font-semibold text-zinc-900 dark:text-zinc-100">
        {{ENTITY_NAME}}
      </h3>
    </div>
    <table class="mt-4 w-full text-sm">
      <tbody class="divide-y divide-zinc-100 dark:divide-zinc-800">
        <!-- repeat per field -->
        <tr>
          <td
            class="py-2 pr-4 font-mono text-xs font-medium text-zinc-700 dark:text-zinc-300 align-top whitespace-nowrap"
          >
            {{FIELD_NAME}}
          </td>
          <td class="py-2 text-zinc-600 dark:text-zinc-400 leading-relaxed">
            {{FIELD_DESCRIPTION}}
          </td>
        </tr>
      </tbody>
    </table>
    <p class="mt-4 text-xs text-zinc-500 dark:text-zinc-400">
      <span class="font-semibold uppercase tracking-[0.14em] text-[11px]"
        >Related to</span
      >
      · {{RELATIONSHIPS}}
    </p>
  </div>
  ```
- Milestone card — `{{MILESTONE_CARDS}}`: one per milestone, in order. The two-column "What gets built" / "Not in this milestone" stacks on mobile.
  ```html
  <article
    class="print-card rounded-lg border border-zinc-200 dark:border-zinc-800 bg-white dark:bg-zinc-900 overflow-hidden"
  >
    <header
      class="flex items-center gap-3 p-5 border-b border-zinc-100 dark:border-zinc-800"
    >
      <span
        class="shrink-0 w-8 h-8 rounded-full bg-zinc-900 dark:bg-zinc-100 text-zinc-50 dark:text-zinc-900 flex items-center justify-center text-sm font-semibold"
        >{{N}}</span
      >
      <h3 class="font-semibold text-lg text-zinc-900 dark:text-zinc-100">
        {{MILESTONE_NAME}}
      </h3>
    </header>
    <div class="p-5">
      <p class="text-zinc-600 dark:text-zinc-400 leading-relaxed">
        {{MILESTONE_FRAMING}}
      </p>
      <div class="mt-5 grid grid-cols-1 md:grid-cols-2 gap-5">
        <div>
          <h4
            class="text-[11px] font-semibold uppercase tracking-[0.16em] text-zinc-500 dark:text-zinc-400 flex items-center gap-1.5"
          >
            <i
              data-lucide="check-circle-2"
              class="w-3.5 h-3.5 text-emerald-600 dark:text-emerald-400"
            ></i
            >What gets built
          </h4>
          <ul
            class="mt-3 space-y-2 text-sm text-zinc-700 dark:text-zinc-300 list-none p-0"
          >
            <!-- repeat per item -->
            <li class="flex items-start gap-2">
              <i
                data-lucide="check"
                class="w-3.5 h-3.5 mt-0.5 shrink-0 text-emerald-600 dark:text-emerald-400"
              ></i
              ><span>{{IN_SCOPE_ITEM}}</span>
            </li>
          </ul>
        </div>
        <div>
          <h4
            class="text-[11px] font-semibold uppercase tracking-[0.16em] text-zinc-500 dark:text-zinc-400 flex items-center gap-1.5"
          >
            <i
              data-lucide="x-circle"
              class="w-3.5 h-3.5 text-zinc-400 dark:text-zinc-500"
            ></i
            >Not in this milestone
          </h4>
          <ul
            class="mt-3 space-y-2 text-sm text-zinc-500 dark:text-zinc-400 list-none p-0"
          >
            <!-- repeat per item -->
            <li class="flex items-start gap-2">
              <i data-lucide="minus" class="w-3.5 h-3.5 mt-0.5 shrink-0"></i
              ><span>{{OUT_OF_SCOPE_ITEM}}</span>
            </li>
          </ul>
        </div>
      </div>
      <div
        class="mt-5 rounded-md border-l-4 border-emerald-500 bg-emerald-50 dark:bg-emerald-950/30 p-4 text-sm text-emerald-900 dark:text-emerald-200"
      >
        <p class="flex items-start gap-2">
          <i data-lucide="flag" class="w-4 h-4 mt-0.5 shrink-0"></i
          ><span
            ><span class="font-semibold">Done when:</span> {{DONE_WHEN}}</span
          >
        </p>
      </div>
    </div>
  </article>
  ```

Lucide icon hints — pick icons that fit the meaning, never invent icon names:

- Feature cards: `zap`, `users`, `mail`, `bell`, `search`, `tag`, `bookmark`, `file-text`, `calendar`, `lock`, `link`, `image`, `message-square`, `share-2`, `download`, `upload`, `play`, `wand-2`, `pencil`, `eye`
- Auth/users: `user`, `user-plus`, `shield`, `lock`, `log-in`
- Data/storage: `database`, `box`, `archive`, `folder`
- AI/automation: `wand-2`, `sparkles`, `bot`, `cpu`
- Communication: `mail`, `send`, `message-square`, `phone`
- Money/billing: `credit-card`, `dollar-sign`, `receipt`
- If unsure, use `circle-dot`.

HTML style and voice notes:

- **Keep prose tight.** Cards lose their value if they're stuffed with sentences. One line label + one short description sentence per feature card.
- **Don't add scope.** HTML is purely presentation. Never invent features, data fields, milestones, or integrations to "fill out" a card grid. If the PRD section is short, render fewer cards — empty white space is fine.
- **No emoji.** Use Lucide icons only.
- **No section IDs needed.** This is single-page, scroll-only — no table of contents, no anchor links, no `id` attributes required.
- **Omit empty sections.** If a PRD has no external integrations, delete the entire integrations `<section>` block — don't render an empty one.
- **Section spacing.** The outer `<main>` already has `space-y-14`. Inside cards, use the spacing in the snippets as-is.
- **Same content as markdown PRD.** When the user picked **Both**, the HTML and markdown must describe the same scope. The HTML is a different presentation of the same locked decisions, never a different plan.

#### prd.md structure

Mirror the structure of a high-quality real PRD. Use these sections in order:

```markdown
# {App name}

> **About these build-plan files:** Everything in `_build_plan/` (this PRD and the per-milestone folders) is a **temporary documentation and guidance artifact** for the initial build-out of this codebase. These files are not functional — no code, configuration, runtime logic, tests, or deployment process should import, read, reference, or depend on anything in `_build_plan/`. Once the initial milestones are built and shipped, the entire `_build_plan/` folder is expected to be deleted from the codebase. Do not treat it as long-living documentation.

## What we're building

{1–3 sentence core purpose, expanded with a paragraph or two of context. End with a sentence on the tech stack and how the build is structured around milestones.}

---

### What the app does

{Bulleted list of the high-level user-facing capabilities, written from the user's perspective. 5–10 bullets.}

---

### Already provided by the {starter template name, or "existing codebase"}

{Bulleted list of what's already built and does not need to be re-specced.}

---

### Out of scope

{Top-level out-of-scope list with brief reasoning for each item. Each bullet is one line.}

---

### Data model

{For each entity, a heading and a bullet list of fields described in plain language — what the app needs to remember about this thing, not the database column types or constraints. Note relationships in prose between entities or at the end. Keep this conceptual, not technical: "url — the link being saved", not "url: string, not null, indexed."}

---

## Milestone 1 — {Name}

{1–2 sentence framing of what this milestone delivers.}

### What gets built

{Bulleted list of user-facing capabilities and screens delivered in this milestone. Describe what the user can do, see, or experience when this milestone is done — not the technical pieces (controllers, models, jobs) needed to deliver it. The agent will figure out the technical pieces in plan mode.}

### What milestone {N} explicitly does NOT include

{Bulleted list of things a coder might assume should be in this milestone but aren't.}

### Done when

{1–2 sentences describing the verification criteria — what the user should be able to do in the browser when this milestone is complete.}

---

{Repeat for each milestone}
```

#### milestones/N-{slug}/prompt.md structure

Keep this lean. The prompt.md is a thin trigger file — it does NOT re-summarize what's in the PRD.

Substitute `{PRD_PATH}`:

- If the user picked **HTML** only → `_build_plan/prd.html`
- If the user picked **Markdown** only or **Both** → `_build_plan/prd.md` (markdown is easier for the agent to parse; if both formats exist, prefer the markdown one for the agent's context)

```markdown
# Milestone {N} — {Name}

You are entering plan mode to plan and then build milestone {N} of this project.

## Context

- Read `@{PRD_PATH}` for the full project context, scope, data model, and tech stack.
- Read previous milestone folders (`@_build_plan/milestones/1-*/milestone-log.md`, etc.) to understand what has already been built. If you are working on milestone 1, there is no prior milestone to read.

## Your task

1. Plan the implementation for **only** milestone {N} as defined in the PRD. Do not plan or build anything from later milestones.
2. After the user confirms the plan, build only what is in milestone {N}'s scope.
3. Verify your work against the "Done when" criteria for milestone {N} in the PRD.
4. When complete, write a `milestone-log.md` in this folder (`_build_plan/milestones/{N}-{slug}/milestone-log.md`). Structure it as follows:
   - **Start with a `## What's new in the app` section at the very top.** This is a concise, human-readable, bulleted list of the main user-facing features or functionality that were added in this milestone — written so a non-technical reviewer can see at a glance what new things to expect in the app now that this milestone is done. Frame each bullet as a capability the user will now see or be able to do, not as a technical artifact. Keep it short and scannable.
   - Then include the implementation detail sections below for the next milestone's agent to reference:
     - What was built (files created, models added, routes added, etc.)
     - Any decisions made during implementation that weren't pre-specified in the PRD
     - Anything the next milestone will need to know
     - Any deviations from the PRD and why

Ask me any clarifying questions using AskUserQuestion tool to lock in the implementation plan for this milestone.
```

#### Agent instructions note

After writing the `_build_plan/` files, append a short note to the project's agent instructions file so future agent sessions understand the role of `_build_plan/`.

1. Check the codebase root for an existing `CLAUDE.md` or `AGENTS.md`. Use whichever exists.
2. If neither exists, create `AGENTS.md` at the codebase root.
3. Append the section below at the **bottom** of the file (after any existing content). If a `## _build_plan/` section already exists, update it in place rather than duplicating.

```markdown
## `_build_plan/`

The `_build_plan/` folder contains the initial PRD and per-milestone prompts used to scaffold this codebase during its initial build-out phase. These files are **temporary** — they exist for documentation and guidance only. They are **not** functional: no code, configuration, or runtime logic in this codebase should import, reference, or depend on anything inside `_build_plan/`.

Do not treat `_build_plan/` as long-living documentation for the codebase. The codebase will evolve past the assumptions and decisions captured here. Once the initial milestones are complete, this folder is expected to be deleted.
```

#### Style notes for the PRD output

- Mirror the voice of a sharp product spec: concrete, specific, opinionated. Not "the app should probably support X" but "the app supports X."
- Per-feature scoping is specific about user-facing behavior: what the user sees on screen, what they can do, what they cannot do, what the output looks like. It is NOT specific about technical implementation (timeouts, libraries, error-handling patterns, parsing logic) — that's the agent's job in plan mode.
- The "Out of scope" lists are valuable — never skip them, never make them generic.
- Data model fields are described in plain language (what the app needs to remember), not as database column definitions.
- When referring to the starter template features, use the actual names if known (e.g., "Build New starter" rather than "the starter template").
- These style notes apply to both formats. The HTML version uses the same locked content as the markdown — it's a different presentation, not a different scope.

## Final note on user energy

This interview can run long. Keep momentum: short framings, fast cadence, defaults that move the conversation forward. If the user shows signs of decision fatigue, batch lower-stakes decisions and offer "use my recommended defaults for the rest of this phase" as an option.
