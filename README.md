# Twin USB controller fix for nxnative on macOS

Some two-port “Twin USB Gamepad” adapters (USB vendor `0810`, product `0001`) send each controller as a separate HID report, but appear as one controller to a particular nxnative Mac game build. This workaround reads report ID 2 and sends it to the host as Player 2, leaving the first controller on the normal input path.

Tested on an Apple silicon Mac running macOS 27.0 with a particular nxnative build of Crash Team Racing Nitro-Fueled. Two-player split-screen and both controllers worked in that setup. Other games, adapters, controller layouts, macOS releases, and nxnative builds have not been verified. USB IDs are shared by different devices, so an identically identified adapter may use a different report layout.

This is an experimental, game-specific workaround, not an official nxnative feature. It loads a locally compiled dynamic library into the game host and depends on internal `dm_pad_players` and `dm_pad_set_player` symbols; an update can break it. The code assumes this adapter has report IDs 1 and 2 and maps the second report's first 12 buttons in a typical PlayStation-style layout. Button and stick mappings may vary. It reserves Player 2 and repeatedly sets the connected-player mask to Players 1 and 2, so it is not suitable for setups with more than two controllers. No rumble support is added for the second controller.

## Build and install

Requires Xcode or Apple Command Line Tools, an existing nxnative Mac app, and Terminal. These steps affect only the specified game's nxnative settings. They do not provide a game, keys, or game data.

1. Quit the game. Download this repository and open Terminal in its folder.
2. Set the title ID below to your game's ID. The example is for the tested Crash Team Racing build. Check that this is the right game before proceeding.
3. Compile and install the library:

```sh
GAME_ID=0100F9F00C696000
GAME_DIR="$HOME/Library/Application Support/nxnative/$GAME_ID"
mkdir -p "$GAME_DIR"
clang -dynamiclib -fblocks -O2 twinfix.c -framework IOKit -framework CoreFoundation -o "$GAME_DIR/twinfix.dylib"
```

4. Open `env.txt` in that folder in a text editor, creating it if necessary. Add the following **one line**, replacing the path with the actual full path to `twinfix.dylib`:

```text
DYLD_INSERT_LIBRARIES=/Users/YOUR_USER/Library/Application Support/nxnative/0100F9F00C696000/twinfix.dylib
```

Preserve any existing lines. If `DYLD_INSERT_LIBRARIES` is already set, do not add a second line: this workaround may conflict with the existing library and needs manual integration. This setting applies when the nxnative launcher reads the game's `env.txt`; other launchers or hardened/signed builds may ignore or reject it.

5. Start the game, choose Local Arcade and two players, and test both controllers. The game log is normally at `~/Library/Logs/nxnative/<GAME_ID>.log`. Lines beginning `[twinfix]` show whether the input manager started and report 2 was received.

## Remove

Quit the game, remove only the `DYLD_INSERT_LIBRARIES` line that points to `twinfix.dylib` from that game's `env.txt`, and delete `twinfix.dylib` from the same folder. Leave other settings intact. Restart the game.

## How it works

The macOS HID manager opens the adapter without exclusive access. The library filters for vendor `0810`, product `0001` and report ID 2, translates its button, hat and axis values, marks the second player connected, and passes its input to the nxnative host. The original app continues to handle Player 1. This does not modify the game executable or game assets.
