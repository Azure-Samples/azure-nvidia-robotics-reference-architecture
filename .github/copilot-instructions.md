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
* Conventions and styling are in instruction files and must be read in with the `read_file` tool if not already added as an `<attachment>`.

**Proactive fixes:** Always fix problems and errors you encounter, even if unrelated to the original request. Prefer root-cause, constructive fixes over symptom-only patches.
* Always correct all incorrect or problematic conventions, styling, and redundant and/or misleading comments.

**Deleting files and folders:** Use `rm` with the run_in_terminal tool when needing to delete files or folders.

**Edit tools:** Never use `insert_edit_into_file` tool when other edit and file modification tools are available.
