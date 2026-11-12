# GrupoFacil

**Find the right players for your group, and join groups faster, in World of Warcraft: Forever.**

The native Looking For Group window lists every player and group with no filters, so you have to scroll through all of them. GrupoFacil opens next to it and lets you filter the list by level, class and role. It also asks a group leader to let you in with one ready-made whisper.

## Features

- **Filters for the Looking For Group list**
  - **Players** (solo listings), **Groups** or **All**.
  - **Level range**, or **Near me** (your level, 3 below to 3 above).
  - **Class**: click the class icons; none selected means all classes.
  - **Role**: tank, healer or DPS. In Groups mode it becomes **Needs**: groups missing a tank, a healer, or with room for DPS.
  - Hide players and groups that left the list.
  - Sort by level, name or newest.
- **One-click actions on each row**
  - **Invite** a solo player (when you are solo or the group leader/assistant).
  - **Ask to join** a group: sends the leader a whisper such as *"Hi, I'm a level 29 Beast Mastery Hunter, can I join your group?"* (only when you are solo).
  - **Whisper**: opens the chat to write your own message.
- **Search again** repeats your last Looking For Group search.
- **Your own message**: use `{class}`, `{spec}`, `{level}` and `{name}`. Your spec is detected from your talents, or you can set it yourself.
- **English and Brazilian Portuguese** interface (switch in the options; the UI reloads).
- **Minimap button** and an entry in the AddOns menu: left-click opens the window, right-click opens the options.
- **Options** in their own window and in *Options > AddOns > GrupoFacil*.

## Safe by design

WoW: Forever uses the modern add-on security rules (taint and secret values). GrupoFacil follows them:

- It never changes or calls into the Blizzard Looking For Group window. It only reads the search results, so the native window keeps working.
- Searches only run from your click, as the game requires.
- Built-in limits on whispers: one request every 3 seconds, the same leader at most once every 5 minutes, and a request is only marked **Sent** after the game confirms it.
- When the game restricts chat (inside instances), the list freezes and no messages are sent.

## Usage

1. Open **Looking For Group** and search as usual. GrupoFacil opens next to it.
2. Pick Players or Groups, then filter by level, class and role.
3. Use **Invite**, **Ask to join** or **Whisper** on any row.

## Commands

| Command | What it does |
|---|---|
| `/gf` | Open or close the window |
| `/gf options` | Open the options |
| `/gf lang en` / `/gf lang pt` | Interface language (reloads the UI) |
| `/gf msg` | Show the join request text and how it goes out |
| `/gf msg <text>` | Set your own text (`{class}`, `{spec}`, `{level}`, `{name}`) |
| `/gf msg default` | Back to the default English text |
| `/gf spec <name>` / `/gf spec auto` | Set or detect your spec (per character) |
| `/gf mode direct` / `/gf mode prefill` | Send the whisper, or only open the chat with the text |
| `/gf minimap on` / `/gf minimap off` | Show or hide the minimap button |
| `/gf diag` | Show the diagnostic summary (for bug reports) |

## Bug reports

If something goes wrong, GrupoFacil logs it on its own. Type `/gf diag`, then `/reload`, and attach `WTF/Account/<your account>/SavedVariables/GrupoFacil.lua` to your report. The file has no other players' names.

## Compatibility

- WoW: Forever 1.60.1 (`Interface: 16001`).
- No library dependencies.

## Support

GrupoFacil is free and always will be. If you want to support its development: [GitHub Sponsors](https://github.com/sponsors/bsfraga).

## Author and license

Authored by Bael (Bagael Bagacera, Alliance). Released under the [MIT License](LICENSE).
