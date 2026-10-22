# Domain Docs

How the engineering skills should consume this repo's domain documentation when exploring the codebase.

## Layout: multi-context

This repo is **multi-context**: each subproject keeps its own `GLOSSARY.md` and `docs/adr/`, and a `GLOSSARY-MAP.md` at the repo root points at them. System-wide decisions live in the root `docs/adr/`.

`GLOSSARY-MAP.md` and the per-subproject `GLOSSARY.md` files do not exist yet: they are created lazily, the first time a real glossary entry is written, and the root `GLOSSARY-MAP.md` then points at each context's glossary.

## Before exploring, read these

- **`GLOSSARY-MAP.md`** at the repo root: it points at one `GLOSSARY.md` per context (subproject). Read each one relevant to the topic. In a multi-context repo there is no single root `GLOSSARY.md`.
- **`docs/adr/`**: read ADRs that touch the area you're about to work in. Also check the context's own `docs/adr/` (for example `Sources/docs/adr/`, `Backend/docs/adr/`) for context-scoped decisions.

If any of these files don't exist, **proceed silently**. Don't flag their absence; don't suggest creating them upfront. The `/domain-modeling` skill (reached via `/grill-with-docs` and `/improve-codebase-architecture`) creates them lazily when terms or decisions actually get resolved.

## File structure

Multi-context repo (this repo):

```
/
├── GLOSSARY-MAP.md          ← created with the first glossary entry; points at each context
├── docs/adr/                ← system-wide decisions
├── Sources/                 ← macOS app context
│   ├── GLOSSARY.md
│   └── docs/adr/            ← app-specific decisions
└── Backend/                 ← backend service context
    ├── GLOSSARY.md
    └── docs/adr/            ← backend-specific decisions
```

The current subprojects are `Sources/` (the macOS app) and `Backend/` (the backend service).

## Use the glossary's vocabulary

When your output names a domain concept (in an issue title, a refactor proposal, a hypothesis, a test name), use the term as defined in `GLOSSARY.md`. Don't drift to synonyms the glossary explicitly avoids.

If the concept you need isn't in the glossary yet, that's a signal: either you're inventing language the project doesn't use (reconsider) or there's a real gap (note it for `/domain-modeling`).

## Flag ADR conflicts

If your output contradicts an existing ADR, surface it explicitly rather than silently overriding:

> _Contradicts ADR-0007 (event-sourced orders), but worth reopening because…_
