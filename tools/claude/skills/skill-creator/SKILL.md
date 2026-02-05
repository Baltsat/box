---
name: skill-creator
description: Guide for creating effective skills. Use when users want to create a new skill that extends Claude's capabilities with specialized knowledge, workflows, or tool integrations.
---

# Skill Creator

Guide for creating effective Claude Code skills.

## What Skills Provide

1. **Specialized workflows** - Multi-step procedures for specific domains
2. **Tool integrations** - Instructions for working with specific file formats or APIs
3. **Domain expertise** - Company-specific knowledge, schemas, business logic
4. **Bundled resources** - Scripts, references, and assets for complex tasks

## Anatomy of a Skill

```
skill-name/
├── SKILL.md (required)
│   ├── YAML frontmatter (name, description)
│   └── Markdown instructions
└── Optional Resources
    ├── scripts/     - Executable code
    ├── references/  - Documentation
    └── assets/      - Templates, icons
```

## SKILL.md Structure

### Frontmatter (required)

```yaml
---
name: my-skill
description: What this skill does and when to use it. Include trigger phrases.
---
```

**Important:** The description is the primary triggering mechanism. Include both what it does AND when to use it.

### Body

Instructions and guidance for using the skill. Only loaded AFTER the skill triggers.

## Core Principles

### Concise is Key

Context window is shared. Only add what Claude doesn't already know. Challenge each piece: "Does Claude really need this?"

Prefer concise examples over verbose explanations.

### Degrees of Freedom

Match specificity to task fragility:

- **High freedom** (text instructions): Multiple approaches valid
- **Medium freedom** (pseudocode): Preferred pattern exists
- **Low freedom** (specific scripts): Fragile/error-prone operations

### Progressive Disclosure

Three-level loading system:
1. **Metadata** (name + description) - Always in context (~100 words)
2. **SKILL.md body** - When skill triggers (<5k words)
3. **Bundled resources** - As needed

## What NOT to Include

- README.md, INSTALLATION_GUIDE.md, CHANGELOG.md
- User-facing documentation
- Setup/testing procedures
- Content Claude can infer from codebase

## Creation Process

1. **Understand** - Get concrete examples of how skill will be used
2. **Plan** - Identify reusable resources (scripts, references, assets)
3. **Initialize** - Create skill directory with SKILL.md
4. **Edit** - Implement resources and write instructions
5. **Test** - Use the skill on real tasks
6. **Iterate** - Improve based on usage

## Validation

Skills must have SKILL.md with frontmatter containing `name` and `description`:

```bash
# Validate skill
./sync.sh validate
```

## Installing Skills

```bash
# Add to ~/.claude/skills/
ln -sfn /path/to/skill ~/.claude/skills/skill-name
```

Or use npx skills CLI:
```bash
npx skills add owner/repo@skill-name
```
