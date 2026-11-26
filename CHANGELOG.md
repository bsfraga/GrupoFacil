# Changelog

## 0.14.0
- **Groups for your quests**: a magnifier next to every quest in the objective list (under the minimap) and in the quest details of the quest log. Click it and GrupoFacil searches Looking For Group (Quests & Zones, the quest's zone; a dungeon quest searches the dungeon) and opens the new **quest groups** window.
- The quest window lists the zone's groups and players: groups doing that quest first, then groups where someone has it, then the rest of the zone. **Join** asks the leader; **Invite** asks a solo player in.
- Players who also use GrupoFacil tell each other, silently (addon whisper, never a chat channel), which quests they are on. The leader gets your request in the quest window and invites with one click.
- **Create group** lists you in Looking For Group with the quest (playstyle: fun and relaxed, which the game requires), so whoever clicks the magnifier on the same quest finds you first. A dungeon quest lists a normal dungeon group for that dungeon. If the game refuses the quest in the listing, or doesn't answer, the addon says so and the next click lists without it. **Remove listing** takes it out.
- **Description**: a ready text (English by default, or your language) with the quest, its objective, the zone and a word about GrupoFacil, to copy and paste in your listing's description. It opens by itself when the listing goes up. The game doesn't let addons fill in the description.
- Options in the quest window: auto-invite players who ask for the same quest (off by default, at most 6 invites every 10 minutes), auto-accept the invite from the leader you asked (on, for 2 minutes after asking), and show or hide the magnifier.
- When the quest is done, the addon offers to leave the group and to remove the listing. It never does either on its own.
- A warning when you get close to the game's limit of about 16 groups joined per hour.
- The **Quests** button in the main window title and `/gf quests` open the quest window; its **Dungeons** button goes back to the main window.
- The **Find group** button in the quest details and the magnifier in the objective list move out of the way of other addons' buttons (for example Spoken's Play); with no free spot they hide instead of covering anything.
- GrupoFacil windows that overlap no longer show each other's buttons through: the one you open or click comes to the front.
- **What's New** has one page per version, and the first page always has its own box to report bugs, feedback and ideas to the author.
- Nothing is sent while the game restricts chat (instances, encounters). Search, create and remove only run from your click, one per click.

## 0.13.0
- **Report a problem**: a window to send bugs, wrong texts and ideas straight to the author (note icon in the title bar, the options, or `/gf bug`). Reports wait on your computer and go out by themselves when the author is online; you see the state of each one and get a message when it is received and when it is marked.
- `/gf bug <text>` reports from the chat; `/gf bug list` lists your reports.
- Players on another ruleset (PvP, RP...), and possibly on the other faction, can't reach the author through the game. The report window always shows a link to the comments on CurseForge, and when your reports never reach the author for days it says so in the window and once per session in the chat. `/gf bug link` prints the link.
- Reports work with Forever names (name and surname).
- The report window fits its texts in every language: long labels wrap and push the rest down, report types move to a second line when they don't fit, and your reports keep a piece of what you wrote after they are delivered.
- The note icon in the title bar glows until you open the report window for the first time.
- **What's New**: a window with the changes of the version opens every time the addon loads until you tick "I've read it" at the end of the list. It comes back with the next version. `/gf news` or the options open it any time.
- The list now uses the whole window height the first time it opens.
- `/gf spec` with no talent points says so instead of showing the class name.
- A group member the game fails to describe, or a native search that never answers, no longer logs an error in `/gf diag`.

## 0.12.0
- **Who is this? (/who)** in the right-click menu: opens the chat with `/who "Name Surname"` typed in; press Enter (the game only allows /who from your own chat). The answer shows in the row's tooltip: the player's guild (the Looking For Group data has none) and their exact zone, kept for 30 minutes.
- The dungeon list counts only what the list would show with your current filters.

## 0.11.0
- **Friends and guild first**: your friends (including Battle.net friends playing Forever) and guild members get an icon next to their name and go to the top of the list.
- Players on your game ignore list no longer show up.
- **Right-click a row** to hide it for this session or to block the player. Blocked players stay hidden after a reload.
- **Hidden (N)** button next to Search again: lists everyone you hid or blocked, with **Show** / **Unblock** for each one and **Show all**.
- Unblocking also works in the options (**Unblock all**) or with `/gf unblock <name>` / `/gf unblock all`; `/gf blocked` lists them.

## 0.10.0
- **Needs you**: groups with an open spot for a role you marked in Looking For Group get a green bar and a "needs you" tag.
- The Needs filter uses the open spots the game reports for each group (tank, healer, DPS) instead of guessing from the members.
- Each role filter shows how many results fit it.
- **Dungeon filter**: pick one or more dungeons from the ones in the current results, each with its suggested level.
- **Group tooltip**: every member's role, class and level, the open spots, the leader's zone and the dungeon's level range. A solo player's tooltip shows their zone.
- **Compact mode**: Hide filters folds the filter rows so more of the list fits. The filters keep working and the status line tells you they are on.
- New message variables: `{role}` (your roles in Looking For Group) and `{activity}` (the group's dungeon).

## 0.9.1
- Now also published on Wago Addons (addons.wago.io/addons/grupofacil), so WowUp and the Wago app can install and update it.

## 0.9.0
- New languages: Spanish (Spain), Spanish (Latin America), German and French. The language now follows your game client until you pick one; the options have a language list.
- The window can be resized: drag the corner. More rows fit in a taller window and long names or activities are no longer cut short as soon.
- Role icons instead of T/H/D letters in the list, the tooltips and the role filters.
- Changing the language now asks you to reload with a **Reload now** button, because the game can block add-ons from reloading the interface on their own.

## 0.8.1
- Options: the version line no longer overlaps the language selector.

## 0.8.0
- Quick tour for new users: the first time the window opens, a banner offers a 30-second tour that points at each part of the window (modes, filters, row buttons, Search again, message and options). It never starts on its own.
- One-time chat tip after installing: open Looking For Group or type `/gf`.
- `/gf tour` (or the **Show the tour** button in the options) shows the tour again.

## 0.7.0
- Options button opens the options in the add-on's own window (same content as *Options > AddOns > GrupoFacil*, kept in sync).
- Author credit in the main window and in both options screens.

## 0.6.0
- Minimap button: left-click opens the window, right-click opens the options, drag to move. Can be hidden.

## 0.5.0
- English interface by default, with Brazilian Portuguese available. Switching the language reloads the UI.

## 0.4.1
- Search again waits after any search and explains when the game throttles back-to-back searches.
- The class name sent by the server is no longer shown as a spec.

## 0.4.0
- Options page in *Options > AddOns* and an entry in the AddOns menu.

## 0.3.0
- Join request message in English by default, and customizable.

## 0.2.0
- Built-in diagnostics (`/gf diag`).

## 0.1.0
- First version: level, class and role filters for the Looking For Group list; Invite, Ask to join and Whisper.
