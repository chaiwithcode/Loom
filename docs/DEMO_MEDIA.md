# Loom 2.0 demo media

The [Loom 2.0 trailer](loom-2.0-trailer.mp4) and [poster](loom-2.0-poster.png) are the Loom 2.0 promotional media. The poster links to the video from the README; downloads open the latest published release.

## What the demo shows

The trailer combines genuine user-provided macOS notification captures with genuine native Loom demo app screenshots and sample session/quota data. The opening coding windows are staged illustrations. Quota and session examples are illustrative; they do not represent an account or live provider measurements. The app screenshots are privacy-safe demo captures. The MacBook Pro is a presentation mockup frame, not an app feature.

The alert examples demonstrate supported Codex and Antigravity quota notifications. Claude Code quota is not available through its upstream local interface and is not represented as supported.

## Previewing notification examples

After building the app, run one scenario at a time:

```bash
open -n .build/Loom.app --args --demo-mock --demo-alert codex-warning
open -n .build/Loom.app --args --demo-mock --demo-alert codex-critical
open -n .build/Loom.app --args --demo-mock --demo-alert codex-reset
open -n .build/Loom.app --args --demo-mock --demo-alert antigravity-warning
open -n .build/Loom.app --args --demo-mock --demo-alert antigravity-critical
open -n .build/Loom.app --args --demo-mock --demo-alert antigravity-reset
```

Each demo alert is delayed by three seconds and requires macOS notification authorization. The scenarios only resolve with `--demo-mock`; normal production launches do not generate demo alerts.

## Attribution

“Cipher” by Kevin MacLeod ([incompetech.com](https://incompetech.com)), licensed under [Creative Commons Attribution 3.0 Unported](https://creativecommons.org/licenses/by/3.0/). Source recording: [Wikimedia Commons](https://commons.wikimedia.org/wiki/File:Cipher_(ISRC_USUAN1100844).oga). ISRC: USUAN1100844. The film credits the track on its closing card.

MacBook Pro photo mockup: [Plinth, Front / Silver](https://plinthmockups.com/?scene=macbook-11-silver). Commercial exports are permitted without credit; see [Plinth mockup terms](https://plinthmockups.com/macbook-mockup). The blank scene is not redistributed. The computer frame is for presentation only.

Notification banners are genuine user-provided macOS captures from 24 October 2026, cropped without changing their content. The trailer's session and quota data are illustrative demo content.

## Website and README captures

The current Sessions, Usage, Storage and widget images are the same audited native 2.0 captures used in the trailer. The [notification examples](loom-2.0-notifications.png) are genuine macOS banners captured from the explicit demo scenarios; their values are illustrative. The website includes an optional [English caption track](loom-2.0-captions.vtt). The film already contains visible subtitles, so this extra track is off by default to avoid duplicate text.
