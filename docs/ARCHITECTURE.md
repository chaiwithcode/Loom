# Architecture

## Layers

### Core
Provider-neutral models, protocols, state normalization, refresh coordination.

### Providers
One adapter per tool. Each adapter owns installation detection, session discovery and provider-specific parsing.

### UI
SwiftUI menu-bar presentation consuming only normalized core state.

## Data flow

Provider -> raw local state -> provider parser -> AgentSession -> SessionStore -> SwiftUI

## Important design rule

Do not leak raw provider JSON/log/config structures into UI code. Provider formats will change; the rest of Loom should not care.

## Refresh

Start with manual refresh + conservative polling (for example every 15-30 seconds). Later, adapters may use file-system/process observation where reliable.

## Discovery strategy

Each provider should attempt discovery in this order where applicable:
1. documented local status/interface
2. stable CLI output
3. stable local session metadata
4. narrow, tested log parsing as a last resort

Every fallback must fail gracefully.
