# Postmark

A World of Warcraft Forever addon that tracks your auction house sales while the money is on its way. Sale mail takes 1 hour to arrive.

## Features
- **Ghost mail icon**: a faded copy of the game's mail icon appears in the mail spot the moment you sell something. If real mail is already waiting, it sits just beside the real icon.
- **Countdown**: a small timer under the icon shows when the next sale mail arrives.
- **Gold incoming**: hover the icon to see the total you'll receive. That's the sale price minus the 5% AH cut, plus your deposit back. A `~` marks an estimate.
- **Sales history**: right-click the icon (or `/pm history`) to open a window with your last 100 sales: item, amount, date and time sold, Pending or Arrived, plus today's and all-time totals.

## Commands
| Command | What it does |
|---|---|
| `/pm` or `/postmark` | List pending sales in chat |
| `/pm history` | Open/close the sales history window |
| `/pm clear` | Clear the pending list |
| `/pm test` | Add a 2-minute test sale to preview the icon |
| `/pm debug` | Print info about the game's mail icon |

## Install
Copy the `Postmark` folder into `World of Warcraft\_forever_\Interface\AddOns\` and `/reload`.

Or install it with WoW Tinker Box (it's in Frank's Pack).
