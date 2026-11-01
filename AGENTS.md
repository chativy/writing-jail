# Repository Guidelines

This repository is currently an empty workspace: it has no source files, build configuration, tests, assets, or Git metadata. This guide establishes initial expectations and should be updated as implementation is added.

## Project Structure & Module Organization

Place application source in `src/`, tests in `tests/` or beside the code they cover, and static files in `assets/`. Group files by feature or module, and keep generated output such as `dist/`, `build/`, and coverage reports out of version control. If an existing project is imported, preserve its established layout and document any exceptions here.

## Build, Test, and Development Commands

No build, test, or local-development commands are defined because no manifest or task runner is present. Inspect the repository root for the supported package manager and follow its committed scripts rather than assuming a toolchain. When commands are added, document the exact commands here, for example `npm test`, `cargo test`, or `make dev`, only when the corresponding tooling exists.

## Coding Style & Naming Conventions

Use the language formatter and linter configuration committed at the repository root. Until a language is selected, use two-space indentation, UTF-8, LF line endings, and a trailing newline. Name directories and files in `kebab-case` where the language permits it; use `PascalCase` for types and classes and the language's conventional casing for functions and variables. Keep names descriptive and avoid unexplained abbreviations.

## Testing Guidelines

No testing framework or coverage threshold is established. Every behavior change should add or update tests. Use `*.test.*` or `*.spec.*` for test filenames unless the language framework requires another pattern. Run the relevant test suite before submitting changes and record the command and result in the pull request.

## Commit & Pull Request Guidelines

No Git history currently exists to establish a commit convention. Use concise, imperative subjects of 72 characters or fewer, such as `Add workspace setup documentation`, and keep each commit focused. Pull requests should explain the change and its motivation, list verification steps, and link related issues. Include screenshots for visible UI changes and update this guide whenever structure or tooling changes.

## Agent-Specific Instructions

Inspect the root for project manifests and repository instructions before editing. Preserve existing configuration and user changes, and do not invent unavailable commands or conventions.
