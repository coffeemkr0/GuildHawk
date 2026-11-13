# Guild Hawk

A World of Warcraft addon for WoW Forever (client 1.60.1) that times guild recruitment posts across chat channels and picks a random message from a large pool each time.

## How it works
- Paste 100+ recruitment lines (one per line, max 255 characters each) into the config window and the addon picks one at random for each post, avoiding the last 20 used. An "In order" option is available.
- Each target (a numbered channel by name, Say or Yell) has its own interval, with a 60-second minimum.
- **Sending needs a click.** The modern engine only allows chat to Say, Yell and numbered channels from a hardware event, so a timer cannot send by itself. When a channel is due, a preview window opens showing the message and the channel, with five buttons:
  - **Next**: pick another random message (it is also marked as used).
  - **Okay**: post the message.
  - **Skip**: don't post, and restart that channel's timer.
  - **Cancel**: stop the timer for that channel.
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
