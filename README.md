# Prize Pool Update

## Changes
- Added `prizePool` variable in `FortunaVRFLottery`
- User entry amounts are now added to `prizePool`
- Reward distribution now uses `prizePool` instead of `address(this).balance`
- 20% reserve is stored separately in `jackpotReserve`

## Purpose
This separates the active player prize pool from reserved jackpot funds, preventing incorrect reward calculations caused by using the full contract balance.
