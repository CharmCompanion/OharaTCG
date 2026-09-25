# OharaTCG live gaps

## High
- h1 done — "You may" costs ask Pay or Decline when a person is playing. `Match.gd` `_pay_activation`
- h2 done — Top or bottom of Life asks. `Match.gd` life_edge
- h3 done — "Up to N" and hand-to-Life ask on the board. Sims still take the strongest.
- h4 done — Login checks a local password. LAN host/join on the pre-duel screen. Shop spends bounty. Chat saves and relays on LAN.
- h5 done — Field trash checks "cannot leave". `Match.gd` `_move_to_trash`
- h6 done — Replay pause, step, and speed. `TestBoard.gd` `_tick_replay`

## Medium
- m1 done — Settings, Shop, and Replays are on the main menu.
- m2 done — Board HUDs show the profile avatar and the opponent avatar.
- m3 done — The updater reads OHARA_API_KEY or user://api_key.txt. The key is not in the script.
- m4 done — Hand test in the deck editor draws 5 and allows one mulligan. `scripts/decks/Decks.gd`
- m5 done — LAN rooms are listed on the pre-duel screen. Join or Watch. A lobby on port 7780 relays public rooms. `scripts/net/Lan.gd`
- m6 done — Friends and crews are separate. Crew members have a role and a rank, and both lists show time since last login. Tournaments are invite-only: the holder sets time and rules, then shares the code. `scripts/managers/Social.gd`
- m7 done — Invites for friends, crews, duels, and tournaments share one inbox. Officers can kick members; only the captain sets a role. The tournament clock runs on the board. Brackets cover Swiss, round robin, single elimination, double elimination, and Swiss then top 4, best of 1, 3, or 5.
- m8 done — The public IP in `data/server.cfg` is the account server and lobby. No domain. This PC uses loopback while the lobby runs. Admins review bans, a Discord webhook gets the notice, tag is 2v2, and a series follows best of 1, 3, or 5.

## Low
- l1 done — Best of 3 on the board. Same deck, a new throw between games. No side deck (the official game does not use one).
- l2 done — Finished games save under user://replays and open from Replays.
- l3 done — Auto win-this-turn packs were not generated. The miner cannot prove a forced line.
- l4 done — Launch refreshes cards, blocks, and the banlist (at most once a week). Article notes are mulligan and seat hints, not turn logs.
- l5 done — Android skips the server and chat. Card art loads from Downloads/OharaTCG/cards. The phone uses the mobile renderer. `scripts/managers/CardDatabase.gd`
