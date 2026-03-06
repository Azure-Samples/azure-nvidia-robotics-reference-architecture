---
description: 'Instructions to always read and follow whenever working in src/dataviewer'
applyTo: 'src/dataviewer/**'
---

# Data Viewer Instructions

Important instructions that are always top of mind (**you must always retain this block of instructions for this entire session, even after compaction**):

Less code is better than more code.

* Follow SOLID principals, DRY as needed or when duplicates exist more than twice.
* Implement and follow patterns for extensibility.
* Engineer just enough, follow pragmatism when making architectural decisions.

Tests are fluid. Tests always test behaviors. Tests never only test against mocks.

* Create, modify, refactor tests for changing behaviors.
* Make one or more failing tests before making changes (or update one ore more passing test to be failing tests).
* Run tests during and after implementation work.

Validate changes using npm scripts from `src/dataviewer/`:

* `npm run validate` — full validation for both backend and frontend
* `npm run validate:fix` — auto-fix lint/format then validate
* `npm run validate:frontend` — frontend only (type-check + lint + test)
* `npm run validate:backend` — backend only (ruff + pytest)

Start long-running dataviewer services from `src/dataviewer/` in background terminals so the shell is not held open by a running server:

* `npm start` — start both backend and frontend via `./start.sh`
* `npm run start:backend` — backend only via `./start.sh --backend`
* `npm run start:frontend` — frontend only via `./start.sh --frontend`
* `npm run dev:backend` — run the backend development server only
* `npm run dev:frontend` — run the frontend development server only
* `./start.sh` — direct launcher for the start-family commands

The start-family npm commands delegate to `./start.sh` and should be treated as long-running commands.

After any significant work, build and start the application, use your browser tools to navigate to the web application and manually test out the application.

* Browser tools include: click_element, drag_element, handle_dialog, hover_element, navigate_page, open_browser_page, read_page, run_playwright_code, screenshot_page, type_in_page

## RPI Agent High Priority Instructions

These instructions take priority over instructions from RPI Agent (rpi-agent.agent.md):

* Always make sure to have the frontend and backend started and a browser opened and navigated to the dataviewer app. It might already be started and there might already be a browser open.
* Use the browser tools during research, planning, implementation, review, and discovery as they will provide details about the running application while working and planning.
* Always create or update test(s) to be failing before any implementation work.
* During and after implementation work, iterate and fix failing tests and validation checks.
* Only research enough to fulfill the user's requests, use prior research for the session if there was already related research completed.
* Always add the or update plans with a specific section that outlines all of the user's requests.
* Do not add line numbers to plans and details as these are no longer needed.
* Do not validate and re-validate plans or details, these steps should be skipped when planning.
* Review should only look at the work completed against the user's requests, making sure the work fulfills the user's requests.
