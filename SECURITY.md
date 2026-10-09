# Security and privacy

Treat local project paths, summaries and agent metadata as sensitive. Do not put credentials, tokens, transcripts, provider databases, or private project details in public issues or screenshots.

## Reporting a vulnerability

For ordinary bugs, use the repository issue tracker once published, with synthetic examples. For a security issue, first check whether the repository offers GitHub's private vulnerability reporting option. If available, use it. Private reporting has not yet been confirmed; do not assume it is enabled.

If no private route is available, ask the maintainer for a private reporting channel without posting exploit details or sensitive data. The maintainer's public profile is [Deepak Sharma / chaiwithcode](https://github.com/chaiwithcode). No response time or security support schedule is promised.

## Current boundaries

- Loom has no hosted backend, account system or telemetry pipeline. It reads local metadata and status interfaces.
- Loom does not inject prompts, approve commands or modify sessions. Local subprocesses are used for discovery/status.
- Codex usage travels through a local app-server subprocess over standard input/output.
- Antigravity quota queries target a discovered loopback HTTPS host and port. A scoped TLS trust exception accepts that endpoint; redirects are rejected to avoid forwarding its ephemeral token. Tokens are used in memory and not persisted by Loom.
- Local provider data is untrusted input. Adapters should validate formats, bound reads and fail independently, keeping unknown states explicit.

Loopback alone does not prove provider identity; a malicious local process remains a risk. Monitored tools manage their own credentials and external connections. Read-only monitoring does not make session content safe to share.

The packaging script creates a development bundle, not a signing, notarization or audited security guarantee.
