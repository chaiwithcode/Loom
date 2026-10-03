# Loom — Product Brief

## Problem

Developers increasingly run multiple AI coding agents across repositories. Their state is fragmented across terminals and apps. The developer repeatedly checks: what is running, where, whether anything needs attention, and what finished.

## Product thesis

Loom should be the smallest useful layer above local coding agents: a single macOS surface that shows what each agent is doing without replacing the agents themselves.

## Target user

A developer who actively uses two or more local AI coding tools such as Codex, Claude Code, and Antigravity.

## V0 user story

> When I click Loom in the menu bar, I can immediately see which AI agents have sessions, which project each belongs to, and whether the session is working, waiting, finished, failed, or unknown.

## V0 acceptance criteria

- Launches as a macOS menu bar app.
- Detects installed/available Codex, Claude Code, and Antigravity independently.
- Displays real session information for each integration where locally obtainable.
- Refreshes without relaunching.
- One broken provider cannot crash or block the others.
- No login/backend/telemetry.
- No secrets displayed or persisted.

## Differentiation

Loom is not primarily a token/quota meter. Quota may become metadata later. Its core object is the **agent session** and its relationship to a project.

## Future expansion

Once session monitoring is trustworthy:
- attention notifications
- git diff/test summaries
- safe session actions
- handoff between providers
- local CLI/API
- remote companion
