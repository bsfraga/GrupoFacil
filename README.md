# GrupoFacil

**Find the right players for your group, and join groups faster, in World of Warcraft: Forever.**

The native Looking For Group window lists every player and group with no filters, so you have to scroll through all of them. GrupoFacil opens next to it and lets you filter the list by level, class and role. It also asks a group leader to let you in with one ready-made whisper.

## Features

- **Filters for the Looking For Group list**
  - **Players** (solo listings), **Groups** or **All**.
  - **Level range**, or **Near me** (your level, 3 below to 3 above).
  - **Class**: click the class icons; none selected means all classes.
  - **Role**: tank, healer or DPS, with how many results fit each one. In Groups mode it becomes **Needs**: groups with an open spot for that role, as the game reports it.
  - **Dungeon**: pick one or more dungeons from the current results, each with its suggested level.
  - Hide players and groups that left the list.
  - Sort by level, name or newest.
  - **Compact mode**: hide the filter rows so more of the list fits; the filters keep working.
- **Needs you**: groups with an open spot for a role you marked in Looking For Group are highlighted.
- **Group tooltip**: role, class and level of every member, the open spots, the leader's zone and the dungeon's level range.
- **Friends and guild first**: friends (including Battle.net friends playing Forever) and guild members are marked and listed first.
- **Hide or block**: right-click a row to hide it for this session or block the player for good. Players on your game ignore list are hidden too.
- **Who is this?**: right-click a row to run `/who` on the player (you press Enter); their guild and exact zone then show in the tooltip.
- **One-click actions on each row**
  - **Invite** a solo player (when you are solo or the group leader/assistant).
  - **Ask to join** a group: sends the leader a whisper such as *"Hi, I'm a level 29 Beast Mastery Hunter, can I join your group?"* (only when you are solo).
  - **Whisper**: opens the chat to write your own message.
- **Search again** repeats your last Looking For Group search.
- **Groups for your quests**: a magnifier next to every quest in the objective list and in the quest details. One click searches Looking For Group in the quest's zone and opens the quest groups window, with the groups doing that quest first. No group? **Create group** lists you in the quest's zone (a dungeon quest lists a dungeon group), and **Description** gives you a ready text with the quest, objective and zone to paste in the listing's description (the game doesn't let addons fill it in). Players who also use GrupoFacil see each other's quests silently, the leader invites from the window (or automatically, if they turn it on), and the invite from the leader you asked is accepted by itself. When the quest is done, the addon offers to leave the group and remove the listing.
- **Your own message**: use `{class}`, `{spec}`, `{level}`, `{name}`, `{role}` (your Looking For Group roles) and `{activity}` (the group's dungeon). Your spec is detected from your talents, or you can set it yourself.
- **Six languages**: English, Brazilian Portuguese, Spanish (Spain), Spanish (Latin America), German and French. It follows your game client until you pick one in the options (the UI reloads).
- **Resizable window**: drag the bottom-right corner; a taller window shows more rows.
- **Role icons** for tank, healer and DPS in the list and the filters.
- **Minimap button** and an entry in the AddOns menu: left-click opens the window, right-click opens the options.
- **Options** in their own window and in *Options > AddOns > GrupoFacil*.

## Safe by design

WoW: Forever uses the modern add-on security rules (taint and secret values). GrupoFacil follows them:

- It never changes or calls into the Blizzard Looking For Group window. It only reads the search results, so the native window keeps working.
- Searches only run from your click, as the game requires.
- Built-in limits on whispers: one request every 3 seconds, the same leader at most once every 5 minutes, and a request is only marked **Sent** after the game confirms it.
- When the game restricts chat (inside instances), the list freezes and no messages are sent.
- Quest groups never use a chat channel: GrupoFacil users talk through addon whispers only, with a send limit. The magnifier buttons sit on top of the quest tracker and quest log without changing them. Auto-invite is off by default and capped at 6 invites every 10 minutes; auto-accept only takes the invite from the leader you asked, for 2 minutes.

## Usage

1. Open **Looking For Group** and search as usual. GrupoFacil opens next to it.
2. Pick Players or Groups, then filter by level, class and role.
3. Use **Invite**, **Ask to join** or **Whisper** on any row.

The first time the window opens, a banner offers a 30-second tour of the window. You can replay it any time with `/gf tour`.

## Commands

| Command | What it does |
|---|---|
| `/gf` | Open or close the window |
| `/gf options` | Open the options |
| `/gf tour` | Show the quick tour of the window again |
| `/gf lang en` / `pt` / `es` / `mx` / `de` / `fr` | Interface language (reloads the UI) |
| `/gf msg` | Show the join request text and how it goes out |
| `/gf msg <text>` | Set your own text (`{class}`, `{spec}`, `{level}`, `{name}`, `{role}`, `{activity}`) |
| `/gf msg default` | Back to the default English text |
| `/gf spec <name>` / `/gf spec auto` | Set or detect your spec (per character) |
| `/gf mode direct` / `/gf mode prefill` | Send the whisper, or only open the chat with the text |
| `/gf minimap on` / `/gf minimap off` | Show or hide the minimap button |
| `/gf blocked` | List the players you blocked |
| `/gf unblock <name>` / `/gf unblock all` | Unblock one player or everyone |
| `/gf diag` | Show the diagnostic summary (for bug reports) |
| `/gf bug` | Open the **Report a problem** window |
| `/gf bug <text>` / `/gf bug list` | Report right away from the chat / list your reports and their state |
| `/gf quests` | Open or close the quest groups window (or click the magnifier next to a quest) |
| `/gf news` | Open **What's New**: one page per version, with the report box on the first page (it also opens by itself on every load until you tick "I've read it" for the current version) |

## Bug reports

Found something wrong or missing? Click the note icon in the window's title bar, the **Report a problem** button in the options, or type `/gf bug`. Write what happened, pick the kind (something broken, wrong text or translation, idea) and press **Send report**.

- The report is saved on your computer and goes to the author automatically, in the background, the next time you are both online on the same realm and faction. You don't need to keep the window open.
- It is only deleted on your side after the author's game has written it to disk, so a crash or a disconnect never loses it. **Your reports** shows the state of each one, and you get a chat message when the author receives it and when it is marked (fixed, won't fix, ...).
- The game only writes saved data to disk when the interface reloads or you log out; the window offers **Save now (/reload)** after you send one.
- By default the report includes the addon version, your settings and the addon's recent events. It never includes other players' names. Untick the box to send only your text.

GrupoFacil also logs its own errors. `/gf diag` shows the summary.

### Another ruleset or faction?

Reports travel as addon whispers, which the game delivers only inside the same ruleset (the author plays on Normal/PvE, Alliance) and possibly not across factions. From PvP, RP or the other faction, use the comments page instead: https://www.curseforge.com/wow/addons/grupofacil/comments (also linked in the report window, in What's New and with `/gf bug link`).

## Compatibility

- WoW: Forever 1.60.1 (`Interface: 16001`).
- No library dependencies.

## Support

GrupoFacil is free and always will be. If you want to support its development: [GitHub Sponsors](https://github.com/sponsors/bsfraga).

## Author and license

Authored by Bael (Bagael Bagacera, Alliance). Released under the [MIT License](LICENSE).
