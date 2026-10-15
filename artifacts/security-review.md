# EHS launch security review

Scope: `src/EHS.sol`, `src/EHSHook.sol`, `launch.json`, Foundry configuration and committed dependencies. This is the implementer's review using the pinned Uniswap v4 security and Ethereum testing references, not an independent audit. No deployment or transaction broadcast occurred.

## Fixed behavior and authority

`EHS` mints 1e27 minor units once to its deployer. Constructor emission and balances are tested. No mint, burn, tax, allocation, owner, proxy, upgrade or privileged function exists. The factory, outside this project, handles 90% pool liquidity and the 10% Merkle allocation. Transfers and allowances conserve supply, including self-transfers and failed allowance spending.

`EHSHook` fixes its manager and launch token at construction; IMD, the rates, threshold, fee tier and tick spacing are constants. The constructor rejects empty manager/token addresses and a token identical to IMD. There is no role, admin, mutable configuration or withdraw/sweep function.

The hook's permission mask is `0x20cc`: initialization guard, before/after swap, and both swap return-delta flags. Each declared callback and the reward unlock callback checks the immutable PoolManager caller. `beforeInitialize` accepts only the one launch-token/IMD key, tier 12500 and spacing 60; price remains the factory's decision. That fixes the unique pool ID without a privileged initializer. No liquidity callback can block the factory's zero-liquidity fee collection.

## Swap accounting

Let `F` be the absolute **actual IMD delta from the pool**, before hook deltas, and `f = floor(F / 50)`. The core manager's independently decoded Swap event is the test oracle for F and the static LP fee.

| IMD side | Before-swap behavior | After-swap behavior |
| --- | --- | --- |
| Unspecified | No reserve or LP override. | Return `+f` on unspecified currency, mint `f` claims to the hook. |
| Specified, exact input budget B | Reserve `R = ceil(B / 51)`, leaving B − R for the pool. | Mint `f` to the hook and R − f to the calling swapper; return zero unspecified delta. |
| Specified, exact output target O | Reserve `R = ceil(O / 49)`, asking the pool for O + R. | Mint `f` to the hook and R − f to the calling swapper; return zero unspecified delta. |

For exact input, `F ≤ B − R`, so `floor(F / 50) ≤ R`. For exact output, `F ≤ O + R`, and `49R ≥ O`, so again `floor(F / 50) ≤ R`. The reservation is capped at `floor(2^127 / 50) + 1`, which covers every possible int128 filled amount while allowing huge price-limited requests. The positive specified request is rejected with `UnrepresentableFee` only when adding the reserve would overflow int256. `type(int256).min` magnitude is computed without negating that value directly.

Each mint creates a manager debit against the hook: either `f` (unspecified side) or `f + (R − f) = R` (specified side). The return delta credits exactly that debit. Thus hook transient currency deltas settle to zero, and partial fills retain only `floor(F / 50)`. Refund claims belong to the actual caller whose swap delta paid the reserve. Their redemption is exercised in tests. Tiny input rounding can leave the entire amount as a refundable claim with zero fee; it cannot extract another account's assets or create an unbacked reward.

Callbacks mint claims instead of taking IMD. This avoids dependence on the manager's pre-settlement token balance. A test starts from a fresh real PoolManager with token-only liquidity and exactly zero IMD, then buys and later claims successfully. No reward payment or user token transfer occurs inside a swap callback. The hook never invokes a nested swap, dynamic-fee update, or LP override.

## Reward solvency and payment

A buy is identified by a negative IMD pool delta. If F is at least 10e18, the newly recorded reward is `min(floor(F / 100), accruedBalance − owedTotal)`. Fee accrual happens first. `owedTotal` is the sum of recorded liabilities and never exceeds the hook's ERC-6909 IMD balance. The new reward is at most half the same trade's fee; no claim consumes another beneficiary's reserved backing.

`claimRewards()` pays the caller's record. Permissionless `payRecorded(beneficiary)` always pays that same beneficiary. There is no destination override. Checks and state updates precede manager unlock/transfer; a `paying` guard rejects reentrant payment. Only the manager may enter `unlockCallback`, and only during a payment. It burns this hook's claims and takes the same amount of IMD to the recorded beneficiary. Transfer failure rolls back the debt changes. Double payment is a no-op. A blocked recipient does not affect swaps or other recipients' records.

IMD is the specified fixed ERC-20, not an arbitrary user-provided asset. Fork validation checked its address/code/symbol and exercised settlement and payouts. The design assumes normal transfer amounts for that fixed token; it does not generalize to rebasing or fee-on-transfer pairs. There is no ETH payout, price oracle, signature authorization, deadline, randomness or time-based reward mechanism.

## Recipient and router boundary

PoolManager exposes the swap caller, normally a router. It does not expose the later output `take` destination. Compatible routers must pass canonical `abi.encode(outputRecipient)` as hook data and send the output there. The direct swapper fallback uses the callback sender for missing, zero or malformed data so those inputs never freeze trading. `tx.origin` is not used.

An unrestricted caller may assign its own trade's new reward to another address. It cannot modify existing records, redirect `payRecorded`, impersonate manager callbacks, or access another owner's ERC-6909 claims. The external router remains responsible for truthful recipient context and for burning/redeeming refund claims on behalf of its payer. A router that ignores hook context or ERC-6909 refunds is unsuitable. The website is a launch landing page and does not implement or implicitly endorse such a router.

## Review coverage and evidence

| Review area | Evidence |
| --- | --- |
| Constructor/address permissions | Real CREATE2 mining; mask matches reported permissions; wrong-address construction is not bypassed. |
| Callback authentication | Direct non-manager calls to all enabled callbacks and unlock callback reject. |
| Pool binding/static fee | Wrong fee/pair settings fail initialization; real factory-style initialize succeeds; manager Swap events always report 12500. |
| Delta accounting | Exact input/output buys/sells, both currency orders, four partial-fill cases, refund redemption and sequence solvency. |
| Payment safety | Self claim, third-party trigger, fixed beneficiary, double claim, failed transfer rollback and reentrant token callback. |
| Boundary arithmetic | Exact 10 IMD threshold, subthreshold buys, extreme specified requests, zero/invalid context, fuzzed trade amount/direction/limits. |
| NoOp exposure | Reserves fund only bounded proportional fees and refundable claims. No arbitrary take, self-directed swap, or exogenous state-dependent return delta. |
| Factory lifecycle | Zero-liquidity fee collection remains callable; no add/remove callback restrictions. |
| Runtime finality | Bytecode walker rejects executable SELFDESTRUCT, DELEGATECALL and CALLCODE while skipping PUSH data, for token and hook. No proxy/delegate architecture. |
| Size and linking | Hook runtime 4,146 bytes; creation 4,857 bytes plus 64 constructor bytes. EHS runtime 1,153, creation 1,261. Empty link references. |
| Outside-protocol integration | Offline tests deploy committed real v4-core PoolManager. Separate fork tests use mainnet manager and IMD at block 26,197,826. |

The complete default suite passed 42 tests with the mandated seed; the separately configured fork suite passed two tests. The claim cap is checked as a live accounting invariant; because this immutable fee rate funds every qualifying buy by at least twice its reward, an ordinarily reachable buy does not exhaust that cap. No test manufactures an impossible depleted-but-owed state just to exercise a branch.

The build emitted lint warnings for narrowing casts, an unused manager-unlock return value, and the guard reset/event after that external call. These were reviewed rather than hidden: reserves and fees are bounded below int128 maximum; pair delta is promoted before absolute value; the unlock callback intentionally returns empty bytes; payment effects and `paying = true` precede unlock, and reentrant payment is tested. `paying = false` and the successful-payment event occur after the guarded transfer completes.

No unresolved concrete accounting or access-control defect was found in this review. Remaining deployment responsibilities are CREATE2 salt mining with final constructor arguments, factory allocation and initialization, and compatible route integration. Permissionless liquidity markets and normal AMM slippage/price manipulation remain economic properties; this hook provides no price guarantee. No independent audit, formal proof or Slither result is asserted.
