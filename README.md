# BACE Contract (Clarity)

This contract implements settlement, escrow funding, and an internal oracle feed for a Bitcoin-fee prediction position. It defines storage maps for positions, escrows, settlements, and oracle fee reports, along with public entrypoints to fund, settle, or refund positions based on oracle data.

## Storage

- `positions`: `uint -> { expiration-block, strike-price, payout, long-holder, short-holder }`
- `escrows`: `uint -> { long-escrow, short-escrow }`
- `settlements`: `uint -> { status, settled-at, oracle-value?, winner? }`
- `oracle-fees`: `uint -> { avg-fee, reported-at, reporter }`
- Data vars:
  - `oracle-admin`: current oracle admin principal (initialized to `tx-sender`)
  - `oracle-max-delay`: max allowed delay between a target block and the report block

## Constants

- Error codes: `ERR-NOT-FOUND`, `ERR-NOT-EXPIRED`, `ERR-ALREADY-SETTLED`, `ERR-UNAUTHORIZED`, `ERR-ORACLE-MISSING`, `ERR-ORACLE-STALE`, `ERR-FUTURE-BLOCK`, `ERR-ESCROW-INCOMPLETE`, `ERR-BAD-AMOUNT`, `ERR-ESCROW-EXCESS`, `ERR-ORACLE-PRESENT`
- Status codes: `STATUS-SETTLED`, `STATUS-REFUNDED`
- `EMPTY-ESCROW`: `{ long-escrow: u0, short-escrow: u0 }`

## Read-only Functions

- `get-oracle-fee(block uint) -> (response uint uint)`
  - Returns the reported `avg-fee` for a block if present and within `oracle-max-delay`.
  - Errors if missing or stale.

## Public Functions

- `set-oracle-admin(new-admin principal)`
  - Only current `oracle-admin` may update admin.
- `set-oracle-max-delay(new-delay uint)`
  - Only `oracle-admin` may update the allowed delay; must be > 0.
- `report-fee(block uint, avg-fee uint)`
  - Only `oracle-admin` may report; block must be <= `burn-block-height`.
  - Stores the report with `reported-at` set to the current `burn-block-height`.
- `fund-escrow(position-id uint, amount uint)`
  - Only long/short holder may fund.
  - Transfers STX into the contract and updates escrow.
  - Total escrow cannot exceed the position `payout`.
- `refund-position(position-id uint)`
  - Requires expired position and no settlement.
  - If no valid oracle data exists, refunds any escrowed amounts to each side.
  - Marks status as `STATUS-REFUNDED`.
- `settle-position(position-id uint)`
  - Requires expired position, full escrow equal to `payout`, and valid oracle data.
  - Transfers `payout` to the winner (long if `avg-fee > strike-price`, else short).
  - Marks status as `STATUS-SETTLED`.

## Notes

- This file documents only what is present in `contracts/bace.clar`.
- There is no position creation logic in this contract yet; `positions` is assumed to be populated externally.
