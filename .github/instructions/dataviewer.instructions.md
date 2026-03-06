---
description: 'Instructions to always read and follow whenever working in src/dataviewer'
applyTo: 'src/dataviewer/**'
---

# Data Viewer Instructions

Important instructions that are always top of mind (**you must always retain this block of instructions for this entire session, even after compaction**):

* We are working in the src/dataviewer folder and are working on a dataviewer and episode manager for IL training datasets.
* Less code is better than more code.
  * Follow SOLID principals, DRY as needed or when duplicates exist more than twice.
  * Implement and follow patterns for extensibility.
  * Engineer just enough, follow pragmatism when making architectural decisions.
* Tests are fluid. Tests always test behaviors. Tests never only test against mocks.
  * Create, modify, refactor tests for changing behaviors.
  * Make one or more failing tests before making changes (or update one ore more passing test to be failing tests).
  * Run tests during and after implementation work.
* Validate changes using npm scripts from `src/dataviewer/frontend/`:
  * `npm run validate` — full validation (type-check + lint + test)
  * `npm run lint:fix` — ESLint with auto-fix
  * `npm run format:fix` — Prettier auto-fix
  * Backend: `cd src/dataviewer/backend && pytest` and `ruff check src/ --fix`
* After any significant work, build and start the application, use your browser tools to navigate to the web application and manually test out the application.
  * Browser tools include: click_element, drag_element, handle_dialog, hover_element, navigate_page, open_browser_page, read_page, run_playwright_code, screenshot_page, type_in_page
