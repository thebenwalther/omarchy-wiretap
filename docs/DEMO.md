# Wiretap demo

The strongest demo is one beat: an app is talking, a port is open to the world,
and you can tell which is which without reading `ss`. The complete story fits
in about a minute. A 14-second soundtracked loop lives in
`docs/demo/wiretap-demo-loop.mp4`. The README plays it inline from a GitHub
user-attachment URL. Rebuild the local file with `docs/demo/record`; re-upload
it if the README copy should change.

## Logo

The mark is the bar glyph: two parallel wires and a vertical tap. Source:

- `docs/logo.svg` / `docs/logo.png` — square lockup
- `WiretapIcon.qml` — the live, theme-colored version on the bar

Do not invent a second logo. Recolor the same geometry with the current theme.

## Rebuild stills and the promo loop

```sh
docs/demo/render-assets
docs/demo/record
```

`render-assets` draws `preview.png`, `docs/demo/thumbnail.png`, and the panel
still from SVG. `record` renders an original 14-second electronic score with
`docs/demo/score.py` (signal motif, packet clicks, warm pads, and low pulse —
no third-party samples) and encodes `docs/demo/wiretap-demo-loop.mp4`.

## One-minute live take (optional)

Use throwaway windows. Never record mail, chat, a lock screen, or a password
prompt.

1. Run `tests/all`.
2. Put Wiretap on the bar beside Network.
3. `omarchy screenrecord --fullscreen`
4. Follow the table.

| Time | Action | Narration |
| --- | --- | --- |
| 0–5s | Title card, then the quiet bar mark. | “Something on this computer is talking. You just cannot see who.” |
| 5–14s | Left-click Wiretap. Hero reads apps talking / waiting. | “Wiretap groups every connection by the app that owns it.” |
| 14–28s | Open ChatGPT. Point at `https → …` in accent. | “Talking is the live color. That is an outbound conversation.” |
| 28–40s | Scroll to dropbox. Point at open-to-the-world in urgent. | “Waiting on the world is the warning color. That port is listening.” |
| 40–50s | Type `443` in search. Cycle Talking → Internet. | “Find an app, a port, or only internet conversations.” |
| 50–60s | End card and repository URL. | “Wiretap. See who is talking.” |

Stop with `omarchy screenrecord --stop-recording`. Keep the raw take private if
it shows real destinations; the repo loop is the synthetic panel, not a live
capture.

## Capture checklist

- The mark and the word **Wiretap** are readable.
- At least one **Talking** row and one **Open to the world** row appear.
- Search or a scope chip is used once.
- Colors are the current theme’s accent and urgent, not a custom palette.
- No lock screen, passwords, notifications, or personal hostnames in a public file.
