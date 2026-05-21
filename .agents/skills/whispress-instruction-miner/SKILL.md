---
name: whispress-instruction-miner
description: Extract recurring WordPress Workspace repo instructions, user preferences, product rules, and future-agent guidance from visible chat history, docs, and repository searches. Use when the user asks to mine repeated instructions, create agent guidance, or summarize durable preferences.
---

# WordPress Workspace Instruction Miner

Use this skill when turning repeated user guidance into durable repo instructions.

## Workflow

1. Start with visible context and repo docs.
   - Review the current user request, recent conversation, `README.md`, `docs/prd.md`, and existing `.agents/skills`.
   - Be explicit if hidden or older chat history is unavailable.
2. Use regex searches to ground claims.
   - Product terms: `rg -n "WordPress Workspace|WP Workspace|WordPress Agent|selected site|guideline|transcribe" .`
   - Non-goals: `rg -n "model picker|prompt editor|provider|API key|WordPress Studio|local" README.md docs Sources`
   - Release flow: `rg -n "manual-release|notarize|OAuth|client secret|CODESIGN|GitHub Release" .`
   - Skills and agent docs: `rg -n "AGENTS|agents.md|\\.agents|SKILL.md|skill" .`
3. Classify extracted guidance.
   - Durable product rule: stable direction that should go into PRD or agent instructions.
   - Repo fact: implementation or tooling truth that should cite a file path.
   - User preference: repeated instruction from the user that may belong in a skill or AGENTS-style doc.
   - One-off request: useful for the current task but not durable enough to preserve.
4. Propose the smallest durable artifact.
   - PRD section for product strategy.
   - Repo skill for repeatable agent workflow.
   - README note for contributor discovery.
   - Inline code comment only when it explains non-obvious implementation behavior.

## Output Shape

- Lead with durable findings.
- Include file references for repo facts.
- Flag uncertainty when full chat history is unavailable.
- Do not invent repeated preferences from a single ambiguous message.
- Keep recommendations compact and immediately actionable.
