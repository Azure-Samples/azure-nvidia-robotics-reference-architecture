---
description: 'Required general instructions for entire codebase and project'
---

# General Instructions

Items in **HIGHEST PRIORITY** sections from attached instructions files override any conflicting guidance.

## **HIGHEST PRIORITY**

**Breaking changes:** Do not add backward-compatibility layers or legacy support unless explicitly requested. Breaking changes are acceptable.

**Artifacts:** Do not create or modify tests, scripts, or one-off markdown docs unless explicitly requested.

**Comment policy:** Never include thought processes, step-by-step reasoning, or narrative comments in code.

* Keep comments brief and factual; describe **behavior/intent, invariants, edge cases**.
* Remove or update comments that contradict the current behavior. Do not restate obvious functionality.
* Do NOT add temporal or plan-phase markers (e.g. "Phase 1 cleanup", "... after migration", dates, or task references) to code files. When editing or updating any code files, always remove or replace these types of comments.

**Conventions and Styling:** Always follow conventions and styling in this codebase FIRST for all changes, edits, updates, and new files.

**Proactive fixes:** Always fix problems and errors you encounter, even if unrelated to the original request. Prefer root-cause, constructive fixes over symptom-only patches.

* Always correct all incorrect or problematic conventions, styling, and redundant and/or misleading comments.

**Edit tools:** Never use `insert_edit_into_file` tool when other edit and file modification tools are available.

## Local Terraform and Script instructions

Always run `source {{file-path-to}}/az-sub-init.sh` in your terminal at least once, before doing any of the following:
* Running any `terraform` commands in the terminal.
* Running any of the scripts in the codebase.

If the user has not already previously done an `az login` then az-sub-init.sh will require input from the user.
