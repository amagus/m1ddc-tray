# m1ddc-tray

A macOS menu bar (tray) app for controlling external display via DDC on Apple Silicon Macs.

Built on top of [m1ddc](https://github.com/waydabber/m1ddc).

## Features

- Menu bar icon with per-display controls for brightness, contrast, and volume
- Preset management — save and quickly apply display configurations
- Runs as a background agent (no Dock icon)

## Building

> **Note:** This project uses git submodules. Make sure to clone with `--recursive`.

```sh
cmake -B build
cmake --build build
```

### With codesigning...

```sh
cmake -B build -DAPPLE_CODESIGN_DEV="Apple Development: Your Name (TEAMID)"
cmake --build build
```

## License

This project is licensed under the [GNU General Public License v3.0](LICENSE).

The bundled [m1ddc](https://github.com/waydabber/m1ddc) library (`m1ddc/`) is MIT licensed.

## TO-DO

- Add support for volume/brightness key presses and map it to specific displays
- Allow to specify limits to certain settings