<div align="center">
  <img src="./logo.svg" width="150em">
</div>

## What is Bridge?

A horizontal-tiling window manager based on [river](https://codeberg.org/river/river/) wayland compositor. Under a bridge, there are bridge openings of different sizes arranged horizontally. This window manager also has windows of different widths tiled horizontally.

- Each window has a weight from 1 to 10.
- Focused or sticky windows are tiled horizontally on the screen according to their weight. Other windows is hidden.
- Each view contains a group of sticky status.
- Each screen has 10 views.

![bridge screenshot](./screenshot.png)

## Why Bridge?

- Bridge is Lightweight. Bridge has 2000+ lines of zig source code.
- Bridge is Minimalist. The people who advocate for minimalist workflows might like the horizontal-tiling layout.
- Bridge is Attention-friendly. You should focus on whether the window is sticky, not on where the window is placed.
- Bridge has Built-in status bar. The bar is used to show the informations about views, windows and weights.

## Why not Bridge?

- Bridge is customized through editing its source code.
- Bridge becomes very ugly when tiling 3+ windows.
- Bridge is not good at managing 10+ windows.
- Bridge built-in bar only displays icons, not other information such as the time and date.

## How to use Bridge?

### Dependencies

- wayland
- xkbcommon
- fcft
- pixman
- zig (build)

### Build

```sh
zig build -Doptimize=ReleaseSafe --prefix ~/.local install
```

### Run

```sh
river -c bridge
```

> Recommended tools
> - fuzzel
> - foot
> - mako
> - swaybg
> - swaylock
> - wl-clip-persist
> - wob

## How to config Bridge?

Edit the `src/config.zig` and re-build.
