---
name: reclaude
description: Refactor CLAUDE.md files to follow progressive disclosure principles. Use when CLAUDE.md is too long or disorganized.
---

# reclaude

Refactor CLAUDE.md files to follow progressive disclosure principles.

## Steps

### 1. Check length

Report the current line count:
- **Ideal**: <50 lines
- **Acceptable**: 50-100 lines
- **Needs refactoring**: >100 lines (move content to `.claude/rules/` files)

### 2. Ensure verification section exists

Check for a `## Verification` section with commands Claude can run after making changes. If missing:
- Look in package.json for test/lint/typecheck/build scripts
- Look for Makefile, justfile, or other task runners
- Add a `## Verification` section with discovered commands

This is critical—Claude performs dramatically better when it can verify its work.

### 3. Find contradictions

Identify any instructions that conflict with each other. Ask which version to keep.

### 4. Check for global skill candidates

Look for content that could become a **reusable global skill** in `~/.claude/skills/`:
- Is about a tool/framework (not project-specific)
- Same instructions would apply in 2+ projects
- Is substantial (>20 lines)

If found, suggest creating a global skill.

### 5. Identify essentials for root CLAUDE.md

Extract only what belongs in root CLAUDE.md:
- One-line project description
- Package manager (if not npm)
- Non-obvious commands only
- Links to `.claude/rules/` files
- Verification section (always required)

### 6. Group remaining content

Organize into `.claude/rules/` files by category (TypeScript conventions, testing patterns, API design, Git workflow).

### 7. Flag for deletion

Remove entirely:
- API documentation (link instead)
- Code examples (Claude can infer from source)
- Interface/type definitions (exist in code)
- Generic advice ("write clean code")
- Obvious instructions
- Redundant info

## Target Template

```markdown
# Project Name

One-line description.

## Commands
- `command` - what it does (only non-obvious ones)

## Rules
- [Topic](/.claude/rules/topic.md) — brief description

## Verification
After making changes:
- `npm test` - Run tests
- `npm run lint` - Check linting
```

## What to Keep vs Remove

**Keep in CLAUDE.md:**
- Commands Claude can't guess
- Non-standard patterns specific to this project
- Project gotchas and footguns
- Links to detailed rules files

**Move to `.claude/rules/`:**
- Detailed conventions (>10 lines on a topic)
- Style guides
- Architecture decisions

**Remove entirely:**
- Anything Claude can infer from codebase
- Standard practices for the language/framework
- Documentation that exists elsewhere
