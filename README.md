# Wiretap

See who is talking. Wiretap groups every socket on this machine by the process that owns it.

Network associates you to an AP. Wiretap shows the sockets.

## Install

```sh
omarchy plugin add https://github.com/thebenwalther/omarchy-wiretap.git --enable
omarchy bar move io.github.thebenwalther.wiretap --section right
```

Place it beside `omarchy.network`. The interface widget and the socket inspector are a pair.

## Try

The bar stays quiet until something internet-facing is established — then a count appears next to the mark. A new outbound session flashes the contact on the glyph.

- Left-click: open the inspector
- Right-click: cycle All → Established → Listening → Internet → Local
- Middle-click: refresh now

Inside the panel, sockets sit under their process. Type to filter. `j`/`k` move. Enter expands a process or copies a connection.

## Keyboard

| Key | Action |
| --- | --- |
| `/` | Focus filter |
| `j` `k` | Move |
| `h` `l` | Collapse / expand |
| `Enter` | Expand process or copy connection |
| `c` | Copy the cursor row |
| `e` | Copy the snapshot JSON |
| `E` | Write `~/Downloads/wiretap-<unix>.json` |
| `a` / `A` | Expand all / collapse all |
| `1`–`5` | All, Established, Listening, Internet, Local |
| `r` | Refresh |
| `s` | Toggle system processes |
| `Esc` | Close |

## Requirements

- Omarchy with shell plugin support
- `iproute2` (`ss`) — already on Omarchy
- `wl-copy` for clipboard actions
- No extra packages. No root.

## CLI

```sh
bin/wiretap snapshot --pretty
bin/wiretap snapshot --include-system --include-unconnected-udp
```

Unix sockets stay hidden unless you pass `--include-unix`. Reverse DNS is not on the poll path.

## Remove

```sh
omarchy plugin remove io.github.thebenwalther.wiretap
```

## Development

```sh
ln -sfn "$HOME/Work/wiretap" \
  "$HOME/.config/omarchy/plugins/io.github.thebenwalther.wiretap"
omarchy plugin enable io.github.thebenwalther.wiretap --section right
tests/all
```

## License

MIT
