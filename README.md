# Twin USB controller fix for macOS

This project maps both halves of a Twin USB Gamepad adapter (`0810:0001`) as two players on a Mac. It was tested with two Macher MR-58 controllers on an Apple silicon Mac running macOS 27.0. USB IDs are shared by different hardware; another adapter may use a different report layout.

**Twin Controller Studio** is one visual mapping panel for both players. Select Player 1 or Player 2, click a control in the diagram, press the physical button you want, and choose **Save both players**. A conflicting assignment swaps the two buttons. The app saves one shared layout to two small configuration files: one for the tested Crash Team Racing Nitro-Fueled nxnative build, and one for its virtual-controller output to other compatible Mac games. Sticks and D-pad directions pass through unchanged. Physical buttons assigned to triggers are digital (fully pressed or released).

The repository contains source code and build scripts. It does **not** contain the game, game assets, keys, firmware, a prebuilt app, or the OpenJoystickDriver helper.

## Build the controller editor

Install Apple Command Line Tools, then run from this repository:

```sh
sh studio/build.sh
```

This creates `outputs/Twin Controller Studio.app`. Move that app to your Applications folder and open it. Connect the Twin USB adapter, then use the two Player tabs to remap buttons. The **Live Input** indicator shows reports from the selected controller. Save writes both players' settings; restart Crash after changing its mappings.

The editor uses AppKit, WebKit, and IOKit. Its GUI check is:

```sh
"outputs/Twin Controller Studio.app/Contents/MacOS/TwinControllerStudio" --self-test-ui
"outputs/Twin Controller Studio.app/Contents/MacOS/TwinControllerStudio" --self-test-sync
```

The second check writes only temporary test files and verifies that one Save creates identical Crash and universal layouts. With the adapter connected, `--self-test-input` verifies input continues after switching between shared and exclusive USB capture.

Run `sh verify.sh` to build and check the bridge's button mapping and the Studio UI together. The bridge tests cover all 4,096 possible 12-button states for several Player 1 and Player 2 layouts.

## Crash Team Racing (nxnative)

The game-specific bridge is needed in addition to Studio. Quit the game, build the bridge, and copy it into the tested title's settings directory:

```sh
sh build-bridge.sh
GAME_DIR="$HOME/Library/Application Support/nxnative/0100F9F00C696000"
mkdir -p "$GAME_DIR"
cp twinfix.dylib "$GAME_DIR/twinfix.dylib"
```

In that game's `env.txt`, add this line with your **actual absolute home path**:

```text
DYLD_INSERT_LIBRARIES=/Users/YOUR_USER/Library/Application Support/nxnative/0100F9F00C696000/twinfix.dylib
```

Preserve other `env.txt` entries. If `DYLD_INSERT_LIBRARIES` is already set, integrate manually rather than adding a second line. nxnative updates, signing, or a different launcher can prevent injection or change the internal symbols on which this bridge depends.

The bridge reads `controller-mappings.txt` when the game starts. Player 1 uses the game's native GameController path with button reads remapped only for `Twin USB Gamepad`; Player 2 uses the adapter's second HID report. The game still owns its stick handling and most controller lifecycle behavior. The bridge also maps low- and high-frequency game vibration to the adapter's two output channels for each controller and holds very short pulses for 150 ms. This is an approximation of the game's rumble, not Switch HD rumble. The game's vibration setting must be on; `DM_RUMBLE=0` disables bridge vibration.

To remove the Crash fix, quit the game, remove only the `DYLD_INSERT_LIBRARIES` entry pointing to this bridge, and delete its `twinfix.dylib`. Leave other game settings intact.

## Other compatible Mac games

For virtual gamepads, install the signed, notarized [OpenJoystickDriver](https://github.com/xsyetopz/OpenJoystickDriver) app separately. Studio expects its `virtual feed` command, tested with version `0.6.0-alpha.1`, at `~/Applications/OpenJoystickDriver.app` or `/Applications/OpenJoystickDriver.app`. It may need the macOS permissions shown on its Access page. No kernel extension or reduced system security is required for this setup.

Choose an output profile in Studio, press **Start virtual controllers**, and select the two virtual controllers inside your game. Keep Studio open while playing. Stop output or quit Studio to remove the virtual devices. If Crash opens, Studio stops virtual output to avoid duplicate routing. Compatibility depends on the game; generic HID mode does not provide rumble.

## Scope and files

The adapter's two report IDs, button layout, and output report format were measured on one physical setup. Other games, controller models, adapters, macOS versions, and nxnative builds have not all been verified. This is an experimental user workaround, not an official nxnative feature.

Mappings are plain text, two rows of twelve integers, at:

- `~/Library/Application Support/nxnative/0100F9F00C696000/controller-mappings.txt`
- `~/Library/Application Support/Twin Universal Mapper/controller-mappings.txt`

Studio writes the same layout to both; each player has an independent row. It does not copy or modify game resources. The controller outline in Studio is adapted from [KW-M/virtual-gamepad-lib](https://github.com/KW-M/virtual-gamepad-lib) under the MIT license reproduced in [`studio/REFERENCE-LICENSE`](studio/REFERENCE-LICENSE). No game artwork is bundled.
