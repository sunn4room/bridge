<div align="center">
  <img src="logo.svg" width="150em">
</div>

## What is Bridge?

A horizontal-tiling window manager based on [river](https://codeberg.org/river/river/) wayland compositor.

- Each window has a weight from 1 to 10.
- All focused or sticky windows are tiled horizontally on the monitor according to their weight.

## Why Bridge?

I have been using dwm for many years. I found that:

- Most of the time I only have one window in my monitor.
- Occasionally I have more than one window when I need to compare window contents.
- Dwm primary/stack layout is ugly and useless.
- Dwm tag system is very powerful but also very attention-demanding.

Bridge is very simple. Bridge has no tag. Bridge manages windows directly. Bridge only stick what you want.

## Why not Bridge?

Bridge is not good at managing more than 10 windows.

## How to use Bridge?

### Dependencies

- wayland
- xkbcommon
- zig (build)

### Build

```sh
zig build -Doptimize=ReleaseSafe --prefix ~/.local install
```

### Run

```sh
river -c bridge
```

## How to config Bridge?

Edit the `src/config.zig` and re-build.
