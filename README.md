# Sports Prediction Clash

Before every football drive, swipe through about 20 quick predictions, stack them into one slip, and win trophies if they all land. Trophies only, no real money.

| Folder | What it is |
| --- | --- |
| `SportsPredictionClash/` | The iOS app (SwiftUI, iOS 26) |
| `Server/` | The game server: accounts, feeds, slips, settlement and the trophy ledger |
| `sports-prediction-clash.html` | The web prototype (still plays on its own, without the server) |

## Run it

The iOS app needs the game server running on the same Mac.

1. Start the server from this folder. It listens on `http://127.0.0.1:8787` and keeps its data in `server-data/`.

   ```bash
   swift run -c release ClashServer
   ```

2. Open `SportsPredictionClash/SportsPredictionClash.xcodeproj` and press Run. The simulator reaches the server at 127.0.0.1.

If the server isn't running, the app shows an offline card with a Try again button.

## How the server keeps the game fair

- **Secret seed:** every drive's feed and plays come from a seed mixed with a secret in `server-data/secret`, made on first run. Without it, nobody can work out a drive before it's played. Keep it out of git; it already is.
- **Checked on the server:** the app sends only its picks and stake at the snap. The server rebuilds the slip from its own markets and prices, checks it, takes the stake, plays the drive, settles and pays, all in one transaction.
- **One slip per drive:** a drive can be snapped once per player.
- **Ledger:** trophies move only as ledger rows, and a balance is the sum of a player's rows.
- **Shared engine:** the app and the server compile the same engine files (`SportsPredictionClash/SportsPredictionClash/Engine/DriveEngine.swift`, `Markets.swift`, `Pricing.swift`, `Game.swift`, `API.swift`), so the multiplier the app shows is the one the server pays.

## API

Every route except account creation needs `Authorization: Bearer <token>`.

| Route | What it does |
| --- | --- |
| `POST /v1/accounts` | New anonymous account with 🏆 1,000. Returns its token. |
| `GET /v1/me` | Name and balance |
| `GET /v1/feed` | Where the game stands, the balance, and this drive's markets |
| `POST /v1/snap` | Lock in a slip (or watch with no picks); returns the drive and how the slip settled |
| `POST /v1/missions/claim` | Pay a daily mission's reward, once per mission per day |
| `GET /v1/ledger` | The player's last 50 ledger rows |

## Tests

```bash
swift test
```

## Not done yet

- Sign in with Apple. Accounts are anonymous for now, one per install, with the token kept in the Keychain.
- The 60-second betting window is timed in the app; the server doesn't enforce it yet.
- Simulated players, leaderboards, friends and mission progress still live on the phone. Mission rewards are paid by the server, but it trusts the app's claim that a mission is done.
- Postgres, Redis and hosting. SQLite on one Mac is enough for development.
- The web prototype doesn't use the server yet.
