---
name: simplify
description: Simplify and refine recently modified code for clarity and consistency. Use after writing code to improve readability without changing functionality.
---

# Code Simplification

Analyze recently modified code and apply refinements that:

## 1. Preserve Functionality
Never change what the code does - only how it does it. All original features, outputs, and behaviors must remain intact.

## 2. Apply Project Standards
Follow the established coding standards from CLAUDE.md including:
- Use ES modules with proper import sorting
- Prefer `function` keyword over arrow functions for top-level
- Use explicit return type annotations for exported functions
- Follow proper React component patterns with explicit Props types
- Use proper error handling patterns (avoid try/catch when possible)
- Maintain consistent naming conventions

## 3. Enhance Clarity
Simplify code structure by:
- Reducing unnecessary complexity and nesting
- Eliminating redundant code and abstractions
- Improving readability through clear variable and function names
- Consolidating related logic
- Removing unnecessary comments that describe obvious code
- Avoiding nested ternary operators - prefer switch or if/else
- Choose clarity over brevity - explicit code > overly compact code

## 4. Maintain Balance
Avoid over-simplification that could:
- Reduce code clarity or maintainability
- Create overly clever solutions that are hard to understand
- Combine too many concerns into single functions
- Remove helpful abstractions that improve organization
- Prioritize "fewer lines" over readability

## 5. Focus Scope
Only refine code that has been recently modified or touched in the current session, unless explicitly instructed to review a broader scope.

Report with a brief summary of changes made.
