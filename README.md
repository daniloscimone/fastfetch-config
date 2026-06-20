<div align="center">

# fastfetch-config

A clean and minimal [fastfetch](https://github.com/fastfetch-cli/fastfetch) configuration for macOS, built for Apple Silicon machines.

![preview](screenshot.png)

</div>

---

## Preview

The configuration displays system information in a logical, grouped layout:

- **Identity** — user, OS, kernel, host
- **Hardware** — CPU, GPU, memory (with percentage), disk (with percentage)
- **Session** — shell, terminal
- **Status** — uptime, battery (with charge status and time remaining)
- **Network** — local IP, public IP
- **Palette** — terminal color circles

---

## Requirements

- macOS (Apple Silicon recommended)
- [fastfetch](https://github.com/fastfetch-cli/fastfetch) ≥ 2.0
- A [Nerd Font](https://www.nerdfonts.com/) installed and set as your terminal font (for icons to render correctly)

Install fastfetch via Homebrew:

```bash
brew install fastfetch
```

---

## Installation

1. Clone this repository:

```bash
git clone https://github.com/daniloscimone/fastfetch-config.git
```

2. Copy the config file to your fastfetch config directory:

```bash
cp fastfetch-config/config.jsonc ~/.config/fastfetch/config.jsonc
```

3. Run fastfetch:

```bash
fastfetch
```

---

## Configuration

The config file is located at `~/.config/fastfetch/config.jsonc`.

Key choices:

| Option | Value | Notes |
|--------|-------|-------|
| `binaryPrefix` | `jedec` | Uses GB/MB instead of GiB/MiB |
| `key.width` | `14` | Aligns all key labels |
| `keys color` | `cyan` | Clean cyan for all labels |
| Memory format | `{used} / {total} ({percentage})` | Shows percentage inline |
| Disk format | `{size-used} / {size-total} ({size-percentage})` | Shows percentage inline |
| Battery format | `{capacity} ({status}) {time-remaining}` | Capacity + status + time |
| Colors symbol | `circle` | Minimal circle dots palette |

---

## License

MIT
