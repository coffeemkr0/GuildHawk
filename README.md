# Guild Hawk

A World of Warcraft addon for WoW Forever (client 1.60.1) that times guild recruitment posts across chat channels and picks a random message from a large pool each time.

## How it works
- **Messages tab:** `Bulk import...` opens a paste box where every line break starts a new message (blank lines ignored, lines over 255 characters cut). Your messages show as an ordered, scrollable list. Each row has an on/off tick (off = never used), a favorite star, its position, move up/down (`^` / `v`, hold Shift to move 10) and delete. Click a message to edit it, or type a new one and use `Add as new`. A search box and a favorites filter help with long lists.
- **Picking:** list position is priority. In random mode the top row is picked about 3x as often as the bottom row, favorites get another 3x, disabled messages are never picked, and the last 20 used are skipped. A tick box on the Channels tab switches to posting in list order, top to bottom.
- **Channels tab:** each target (a numbered channel by name, Say or Yell) has its own interval, with a 60-second minimum.
- **Sync groups:** give two or more channels the same group letter (A-D) and they share one timer and one message. You get one preview, and Okay posts the same message to all of them. Channels left on `-` keep their own timers.
- **Sending needs a click.** The modern engine only allows chat to Say, Yell and numbered channels from a hardware event, so a timer cannot send by itself. When a channel is due, a preview window opens showing the message and the channel, with five buttons:
  - **Favorite this message** (checkbox): star or un-star the message you are looking at before you post it.
  - **Next**: pick another random message (it is also marked as used).
  - **Okay**: post the message (to every channel in the sync group, if it is one).
  - **Skip**: don't post, and restart that channel's timer.
  - **Cancel**: stop the timer for that channel (or the whole sync group).
  - **Cancel All**: stop the timers for all channels and stop the loop.

## Install
1. Copy the `GuildHawk` folder into your Forever client's `Interface/AddOns/` folder (for example `_classic_era_` or `_classic_beta_`).
2. In game run `/dump (select(4, GetBuildInfo()))` and put that number on the `## Interface:` line of `GuildHawk.toc` if it differs from `16001`.
3. Join the channels you want to post in (Trade, for example), then run `/gh start`.

## Commands
| Command | Action |
| --- | --- |
| `/gh` | Open the config window |
| `/gh start` / `/gh stop` | Start or stop the timers |
| `/gh send` | Open the preview for the next due post, or confirm it if already open |
| `/gh status` | Show pool size and countdowns |

A minimap button opens the config window when clicked. Drag it to move it around the minimap rim.

A key binding is available under Key Bindings > AddOns > Guild Hawk. Drag the countdown/Ready button anywhere on screen to move it. Its position is saved.

Use sensible intervals. Spamming channels can get you muted or reported.
