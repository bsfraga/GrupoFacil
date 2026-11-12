# Changelog

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
