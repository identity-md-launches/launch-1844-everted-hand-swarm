// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {PoolManager} from "v4-core/src/PoolManager.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {Currency} from "v4-core/src/types/Currency.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "v4-core/src/types/PoolId.sol";
import {SwapParams, ModifyLiquidityParams} from "v4-core/src/types/PoolOperation.sol";
import {Vm} from "forge-std/Vm.sol";
import {BalanceDelta, toBalanceDelta} from "v4-core/src/types/BalanceDelta.sol";
import {BeforeSwapDelta, BeforeSwapDeltaLibrary} from "v4-core/src/types/BeforeSwapDelta.sol";
import {StateLibrary} from "v4-core/src/libraries/StateLibrary.sol";
import {TickMath} from "v4-core/src/libraries/TickMath.sol";
import {EHS} from "../src/EHS.sol";
import {EHSHook} from "../src/EHSHook.sol";
import {MockIMD} from "./mocks/MockIMD.sol";
import {HookHarness, SweepableRouter} from "./EHSHook.t.sol";
import {IUnlockCallback} from "v4-core/src/interfaces/callback/IUnlockCallback.sol";

/// @dev A second liquidity provider, independent of the test harness, to show the hook leaves LP
/// operations and pool donations alone.
contract OtherLP {
    IPoolManager internal immutable manager;

    constructor(IPoolManager manager_) {
        manager = manager_;
    }

    function modify(PoolKey memory key, int24 lower, int24 upper, int256 liquidity) external returns (BalanceDelta) {
        return
            abi.decode(manager.unlock(abi.encode(key, lower, upper, liquidity, uint256(0), uint256(0))), (BalanceDelta));
    }

    function donate(PoolKey memory key, uint256 a0, uint256 a1) external {
        manager.unlock(abi.encode(key, int24(0), int24(0), int256(0), a0, a1));
    }

    function unlockCallback(bytes calldata data) external returns (bytes memory) {
        require(msg.sender == address(manager), "manager only");
        (PoolKey memory key, int24 lower, int24 upper, int256 liquidity, uint256 a0, uint256 a1) =
            abi.decode(data, (PoolKey, int24, int24, int256, uint256, uint256));
        BalanceDelta delta;
        if (a0 != 0 || a1 != 0) {
            delta = manager.donate(key, a0, a1, "");
        } else {
            (delta,) = manager.modifyLiquidity(key, ModifyLiquidityParams(lower, upper, liquidity, bytes32(0)), "");
        }
        settle(key.currency0, delta.amount0());
        settle(key.currency1, delta.amount1());
        return abi.encode(delta);
    }

    function settle(Currency currency, int128 amount) internal {
        if (amount < 0) {
            manager.sync(currency);
            currency.transfer(address(manager), uint256(uint128(-amount)));
            manager.settle();
        } else if (amount > 0) {
            manager.take(currency, address(this), uint256(uint128(amount)));
        }
    }
}

/// @dev Mints ERC-6909 IMD claims to any address from its own IMD, as anyone may through the manager.
contract ClaimPusher is IUnlockCallback {
    IPoolManager internal immutable manager;

    constructor(IPoolManager manager_) {
        manager = manager_;
    }

    function push(address to, uint256 id, uint256 amount) external {
        manager.unlock(abi.encode(to, id, amount));
    }

    function unlockCallback(bytes calldata data) external returns (bytes memory) {
        require(msg.sender == address(manager), "manager only");
        (address to, uint256 id, uint256 amount) = abi.decode(data, (address, uint256, uint256));
        manager.mint(to, id, amount);
        Currency currency = Currency.wrap(address(uint160(id)));
        manager.sync(currency);
        currency.transfer(address(manager), amount);
        manager.settle();
        return "";
    }
}

contract EHSHookEdgeTest is HookHarness {
    using StateLibrary for IPoolManager;

    uint256 internal constant ID = uint256(uint160(IMD));

    function setUp() public {
        manager = IPoolManager(address(new PoolManager(address(this))));
        vm.etch(IMD, address(new MockIMD()).code);
        MockIMD(IMD).mint(address(this), 1e38);
        setupPool(false);
    }

    // ------------------------------------------------------------ deployment

    function test_constructorRejectsMissingManagerOrToken() public {
        vm.expectRevert(EHSHook.InvalidDeployment.selector);
        new EHSHook(IPoolManager(address(0)), address(token));
        vm.expectRevert(EHSHook.InvalidDeployment.selector);
        new EHSHook(manager, address(0));
    }

    function test_constructorRejectsIMDAsTheLaunchToken() public {
        vm.expectRevert(EHSHook.InvalidDeployment.selector);
        new EHSHook(manager, IMD);
    }

    function test_constructorRejectsAnAddressWithoutTheRightBits() public {
        // Plain CREATE lands on an address whose low 14 bits almost never spell 0x20cc.
        address predicted = vm.computeCreateAddress(address(this), vm.getNonce(address(this)));
        vm.assume(uint160(predicted) & 0x3fff != 0x20cc);
        vm.expectRevert(abi.encodeWithSelector(Hooks.HookAddressNotValid.selector, predicted));
        new EHSHook(manager, address(token));
    }

    function test_immutablesAndConstantsMatchTheBrief() public view {
        assertEq(address(hook.poolManager()), address(manager));
        assertEq(hook.token(), address(token));
        assertEq(hook.PAIRED_CURRENCY(), IMD);
        assertEq(hook.FEE_BPS(), 200);
        assertEq(hook.REWARD_BPS(), 100);
        assertEq(hook.MIN_BUY(), 10 ether);
        assertEq(hook.LP_FEE(), 12500);
        assertEq(hook.TICK_SPACING(), 60);
        assertEq(
            hook.FLAGS(),
            Hooks.BEFORE_INITIALIZE_FLAG | Hooks.BEFORE_SWAP_FLAG | Hooks.AFTER_SWAP_FLAG
                | Hooks.BEFORE_SWAP_RETURNS_DELTA_FLAG | Hooks.AFTER_SWAP_RETURNS_DELTA_FLAG
        );
        assertEq(uint160(address(hook)) & Hooks.ALL_HOOK_MASK, hook.FLAGS(), "address bits beyond the five flags");
        assertFalse(Hooks.hasPermission(IHooks(address(hook)), Hooks.BEFORE_REMOVE_LIQUIDITY_FLAG));
        assertFalse(Hooks.hasPermission(IHooks(address(hook)), Hooks.AFTER_REMOVE_LIQUIDITY_FLAG));
        assertFalse(Hooks.hasPermission(IHooks(address(hook)), Hooks.AFTER_INITIALIZE_FLAG));
    }

    function test_hookRunsOnlyOneLegitimatePoolPerManager() public {
        // The same hook refuses a second pool through the real manager for any other pair.
        EHS other = new EHS();
        (address a, address b) = address(other) < IMD ? (address(other), IMD) : (IMD, address(other));
        PoolKey memory second = PoolKey(Currency.wrap(a), Currency.wrap(b), 12500, 60, IHooks(address(hook)));
        vm.expectRevert();
        manager.initialize(second, Q96);
        // And the launch pool itself cannot be opened twice.
        vm.expectRevert();
        manager.initialize(key, Q96);
    }

    // ------------------------------------------------------- beforeSwap math

    function test_beforeSwapReservesOnlyWhenIMDIsSpecified() public {
        vm.startPrank(address(manager));
        // Exact-input buy: IMD in is the specified currency; reserve = ceil(budget / 51).
        (bytes4 sel, BeforeSwapDelta d, uint24 fee) =
            hook.beforeSwap(address(this), key, SwapParams(pair0, -5100, 0), "");
        assertEq(sel, IHooks.beforeSwap.selector);
        assertEq(BeforeSwapDeltaLibrary.getSpecifiedDelta(d), 100);
        assertEq(BeforeSwapDeltaLibrary.getUnspecifiedDelta(d), 0);
        assertEq(fee, 0, "must never override the LP fee");
        (, d,) = hook.beforeSwap(address(this), key, SwapParams(pair0, -5101, 0), "");
        assertEq(BeforeSwapDeltaLibrary.getSpecifiedDelta(d), 101);
        // Exact-output sell: IMD out is specified; reserve = ceil(target / 49).
        (, d,) = hook.beforeSwap(address(this), key, SwapParams(!pair0, 4900, 0), "");
        assertEq(BeforeSwapDeltaLibrary.getSpecifiedDelta(d), 100);
        (, d,) = hook.beforeSwap(address(this), key, SwapParams(!pair0, 4901, 0), "");
        assertEq(BeforeSwapDeltaLibrary.getSpecifiedDelta(d), 101);
        // EHS specified in either direction: nothing reserved, the fee comes from afterSwap.
        (, d,) = hook.beforeSwap(address(this), key, SwapParams(!pair0, -1e30, 0), "");
        assertEq(BeforeSwapDelta.unwrap(d), 0);
        (, d,) = hook.beforeSwap(address(this), key, SwapParams(pair0, 1e30, 0), "");
        assertEq(BeforeSwapDelta.unwrap(d), 0);
        // One wei still reserves one wei (refunded later), and int256.min does not overflow.
        (, d,) = hook.beforeSwap(address(this), key, SwapParams(pair0, -1, 0), "");
        assertEq(BeforeSwapDeltaLibrary.getSpecifiedDelta(d), 1);
        (, d,) = hook.beforeSwap(address(this), key, SwapParams(pair0, type(int256).min, 0), "");
        assertEq(BeforeSwapDeltaLibrary.getSpecifiedDelta(d), int128(int256((uint256(1) << 127) / 50 + 1)));
        vm.stopPrank();
    }

    /// forge-config: default.fuzz.runs = 2000
    function testFuzz_reserveIsCappedAndNeverBelowTheFeeOnAnyFill(int256 specified) public {
        vm.assume(specified != 0);
        bool exactInput = specified < 0;
        SwapParams memory s = SwapParams(exactInput ? pair0 : !pair0, specified, 0);
        uint256 cap = (uint256(1) << 127) / 50 + 1;
        vm.prank(address(manager));
        if (!exactInput && specified > type(int256).max - int256(cap)) {
            // Only here may a real swap be refused, and only because the request cannot carry its fee.
            uint256 m = uint256(specified);
            uint256 r = m / 49 + (m % 49 == 0 ? 0 : 1);
            if (r > cap) r = cap;
            if (specified > type(int256).max - int256(r)) {
                vm.expectRevert(EHSHook.UnrepresentableFee.selector);
                hook.beforeSwap(address(this), key, s, "");
                return;
            }
        }
        (, BeforeSwapDelta d,) = hook.beforeSwap(address(this), key, s, "");
        int128 reserve = BeforeSwapDeltaLibrary.getSpecifiedDelta(d);
        assertGt(reserve, 0);
        assertLe(uint256(uint128(reserve)), cap);
        // The pool can fill at most the whole int128 range; 2% of that never exceeds the reserve, so
        // afterSwap's refund (reserve - fee) cannot underflow and revert a filled swap.
        uint256 magnitude = exactInput ? uint256(-(specified + 1)) + 1 : uint256(specified);
        uint256 maxFill = exactInput ? magnitude - uint256(uint128(reserve)) : magnitude + uint256(uint128(reserve));
        uint256 int128Max = uint256(uint128(type(int128).max));
        if (maxFill > int128Max) maxFill = int128Max;
        assertLe(maxFill / 50, uint256(uint128(reserve)), "a full fill's fee would exceed the reserve");
    }

    // ------------------------------------------------------------- afterSwap

    function test_swapEventsReportFeeRefundAndReward() public {
        // Exact-input buy of 102 IMD: reserve 2, pool takes 100, fee 2, nothing to refund.
        vm.expectEmit(true, true, true, true, address(hook));
        emit EHSHook.FeeAccrued(100 ether, 2 ether);
        vm.expectEmit(true, true, true, true, address(hook));
        emit EHSHook.RewardRecorded(buyer, 1 ether);
        (uint256 filled, uint256 fee, uint256 refund) = trade(true, true, 102 ether, 0, abi.encode(buyer));
        assertEq(filled, 100 ether);
        assertEq(fee, 2 ether);
        assertEq(refund, 0);

        // A price-limited exact-input buy refunds the unused reserve to the calling swapper.
        uint160 limit = TickMath.getSqrtPriceAtTick(pair0 ? int24(-60) : int24(60));
        (filled, fee, refund) = trade(true, true, 100_000 ether, limit, abi.encode(buyer));
        assertGt(refund, 0);
        assertEq(manager.balanceOf(address(this), ID), refund, "the refund is a claim owned by this swapper");

        uint256 due = hook.pending(buyer);
        vm.expectEmit(true, true, true, true, address(hook));
        emit EHSHook.RewardPaid(buyer, due);
        hook.payRecorded(buyer);
    }

    function test_feeRefundedEventNamesTheSwapper() public {
        uint160 limit = TickMath.getSqrtPriceAtTick(pair0 ? int24(-60) : int24(60));
        SwapParams memory params = SwapParams(pair0, -int256(100_000 ether), limit);
        vm.recordLogs();
        manager.unlock(abi.encode(uint8(1), abi.encode(params, abi.encode(buyer))));
        Vm.Log[] memory logs = vm.getRecordedLogs();
        bytes32 topic = keccak256("FeeRefunded(address,uint256)");
        bool seen;
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].emitter == address(hook) && logs[i].topics[0] == topic) {
                assertEq(address(uint160(uint256(logs[i].topics[1]))), address(this), "refund credited to someone else");
                assertEq(abi.decode(logs[i].data, (uint256)), manager.balanceOf(address(this), ID));
                seen = true;
            }
        }
        assertTrue(seen, "no FeeRefunded event");
    }

    function test_hookDataOfTheWrongLengthRecordsNoRewardForAnyone() public {
        // Each shape is one qualifying buy (100 IMD filled) whose context is not exactly one
        // canonical nonzero address word. The fee is taken; nobody is credited, least of all the
        // calling swapper, which under a shared router would be sweepable by anyone.
        (, uint256 fee1,) = trade(true, true, 102 ether, 0, abi.encodePacked(buyer)); // 20 bytes
        (, uint256 fee2,) = trade(true, true, 102 ether, 0, abi.encode(buyer, uint256(1))); // 64 bytes
        (, uint256 fee3,) = trade(true, true, 102 ether, 0, abi.encode(uint256(0))); // zero word
        (, uint256 fee4,) = trade(true, true, 102 ether, 0, abi.encode(uint256(type(uint160).max) + 1)); // 21 bytes set
        assertGt(fee1, 0);
        assertEq(fee2, fee1);
        assertEq(fee3, fee1);
        assertEq(fee4, fee1);
        assertEq(hook.pending(buyer), 0, "malformed context must not pick a beneficiary");
        assertEq(hook.pending(address(this)), 0, "calling swapper must not be credited");
        assertEq(hook.pending(address(0)), 0);
        assertEq(hook.owedTotal(), 0, "unattributed buys leave the fee unowed");
        assertEq(hook.accruedBalance(), fee1 * 4);
        // The same buy with a canonical word is rewarded, so the shapes above were the only reason.
        (uint256 filled,,) = trade(true, true, 102 ether, 0, abi.encode(buyer));
        assertEq(hook.pending(buyer), filled / 100);
        assertEq(hook.owedTotal(), filled / 100);
    }

    // ------------------------------------------------ settled review findings

    /// @dev Finding 7c10a20d (info, answered "documented"): ERC-6909 IMD pushed at the hook from
    /// outside is never counted in accruedBalance and no call path can pay or withdraw it. The
    /// README's "Permanent remainder" paragraph now says so; this pins the documented behaviour.
    function test_outsideClaimsPushedAtTheHookAreNeitherCountedNorPayable() public {
        trade(true, true, 102 ether, 0, abi.encode(buyer));
        uint256 accruedBefore = hook.accruedBalance();
        uint256 owedBefore = hook.owedTotal();
        uint256 claimsBefore = manager.balanceOf(address(hook), ID);
        assertEq(claimsBefore, accruedBefore);

        ClaimPusher pusher = new ClaimPusher(manager);
        MockIMD(IMD).mint(address(pusher), 5 ether);
        pusher.push(address(hook), ID, 5 ether);

        assertEq(manager.balanceOf(address(hook), ID), claimsBefore + 5 ether, "the manager accepted the push");
        assertEq(hook.accruedBalance(), accruedBefore, "outside claims must not count as fees");
        assertEq(hook.owedTotal(), owedBefore, "outside claims must not become rewards");
        // A later buy (sent directly, since the harness helper asserts claims == accruedBalance)
        // still accrues and rewards from the hook's own count only.
        uint160 limit = pair0 ? TickMath.MIN_SQRT_PRICE + 1 : TickMath.MAX_SQRT_PRICE - 1;
        manager.unlock(
            abi.encode(uint8(1), abi.encode(SwapParams(pair0, -int256(102 ether), limit), abi.encode(buyer)))
        );
        assertEq(hook.accruedBalance(), accruedBefore + 2 ether);
        assertEq(hook.pending(buyer), 2 ether);
        assertEq(manager.balanceOf(address(hook), ID), hook.accruedBalance() + 5 ether);
        // Nothing can move the pushed claims: paying and claiming only ever touch recorded rewards.
        hook.payRecorded(buyer);
        hook.payRecorded(address(pusher));
        vm.prank(address(pusher));
        hook.claimRewards();
        assertEq(hook.owedTotal(), 0);
        assertEq(MockIMD(IMD).balanceOf(buyer), 2 ether);
        assertEq(hook.accruedBalance(), 2 ether, "unowed remainder of two 2% fees");
        assertEq(manager.balanceOf(address(hook), ID), hook.accruedBalance() + 5 ether, "pushed claims moved");
        assertEq(MockIMD(IMD).balanceOf(address(pusher)), 0);
    }

    /// @dev Finding 225b3991 (info, answered "documented"): the specified-side refund is minted to
    /// PoolManager's `sender`, the router, not to the router's payer. A router that never burns
    /// claims strands the refund; one that burns its swap's refund before settling passes it on.
    function test_refundClaimBelongsToTheRouterNotItsPayer() public {
        SweepableRouter router = new SweepableRouter(manager);
        address payer = makeAddr("payer");
        uint256 budget = 100_000 ether;
        MockIMD(IMD).mint(address(router), budget);
        uint160 limit = TickMath.getSqrtPriceAtTick(pair0 ? int24(-60) : int24(60));
        uint256 feesBefore = hook.accruedBalance();
        vm.recordLogs();
        router.swap(key, SwapParams(pair0, -int256(budget), limit), payer, abi.encode(payer));
        uint256 filled = fillFromLogs(vm.getRecordedLogs());
        uint256 fee = hook.accruedBalance() - feesBefore;
        assertEq(fee, filled / 50);
        uint256 reserve = budget / 51 + (budget % 51 == 0 ? 0 : 1);
        uint256 refund = reserve - fee;
        assertGt(refund, 0, "the price limit did not leave a refund");
        assertEq(manager.balanceOf(address(router), ID), refund, "refund claim is owned by the router");
        assertEq(manager.balanceOf(payer, ID), 0, "payer holds no claim");
        assertEq(MockIMD(IMD).balanceOf(payer), 0, "payer received no IMD");
        // The buy itself was correct: fee 2% of the fill, reward 1% of it, EHS went to the payer.
        assertGt(token.balanceOf(payer), 0);
        assertEq(hook.pending(payer), filled / 100);
        // The router paid the whole reserve in IMD; the refund is recoverable only by burning the claim.
        assertEq(MockIMD(IMD).balanceOf(address(router)), budget - filled - fee - refund);
        assertEq(MockIMD(IMD).balanceOf(address(router)), budget - filled - reserve);
    }

    function fillFromLogs(Vm.Log[] memory logs) internal view returns (uint256 filled) {
        bytes32 topic = keccak256("Swap(bytes32,address,int128,int128,uint160,uint128,int24,uint24)");
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].emitter == address(manager) && logs[i].topics[0] == topic) {
                (int128 a0, int128 a1,,,,) = abi.decode(logs[i].data, (int128, int128, uint160, uint128, int24, uint24));
                int256 d = pair0 ? int256(a0) : int256(a1);
                filled = uint256(d < 0 ? -d : d);
            }
        }
    }

    /// @dev One swap in one transaction through a router that burns its own refund before settling:
    /// its payer is charged exactly fill + 2% on a partial fill, so the stranding is the router's
    /// choice and not the hook's.
    function test_routerThatBurnsRefundChargesPayerOnlyFillPlusFee() public {
        uint160 limit = TickMath.getSqrtPriceAtTick(pair0 ? int24(-60) : int24(60));
        uint256 budget = 100_000 ether;
        uint256 imdBefore = MockIMD(IMD).balanceOf(address(this));
        uint256 feesBefore = hook.accruedBalance();
        SwapParams memory params = SwapParams(pair0, -int256(budget), limit);
        vm.recordLogs();
        manager.unlock(abi.encode(uint8(3), abi.encode(params, abi.encode(buyer)))); // mode 3 burns the refund
        uint256 filled = fillFromLogs(vm.getRecordedLogs());
        uint256 fee = hook.accruedBalance() - feesBefore;
        assertGt(fee, 0);
        assertEq(fee, filled / 50);
        assertLt(filled + fee, budget, "the price limit did not cut the fill");
        assertEq(manager.balanceOf(address(this), ID), 0, "no claim left behind");
        assertEq(imdBefore - MockIMD(IMD).balanceOf(address(this)), filled + fee, "payer charged more than fill + 2%");
    }

    function test_sellsNeverRecordRewardsForAnyBeneficiary() public {
        (uint256 filled,,) = trade(false, true, 1_000 ether, 0, abi.encode(buyer));
        assertGt(filled, 10 ether);
        (filled,,) = trade(false, false, 1_000 ether, 0, abi.encode(buyer));
        assertGt(filled, 10 ether);
        assertEq(hook.pending(buyer), 0);
        assertEq(hook.pending(address(this)), 0);
        assertEq(hook.owedTotal(), 0);
        assertGt(hook.accruedBalance(), 0, "sells still pay the 2% fee");
    }

    function test_rewardIsAtMostHalfOfTheSameBuysFee() public {
        for (uint256 i = 1; i <= 5; ++i) {
            (uint256 filled, uint256 fee,) = trade(true, i & 1 == 1, i * 37 ether, 0, abi.encode(buyer));
            if (filled >= 10 ether) assertLe(filled / 100 * 2, fee + 1);
        }
        assertLe(hook.owedTotal() * 2, hook.accruedBalance() + 5, "the reward cap bound was ever in play");
    }

    function test_hugeExactOutputBuyWithPriceLimitTakesFeeOnIMD() public {
        // EHS is the specified (output) currency; nothing is reserved and the fee rides the IMD side.
        uint160 limit = TickMath.getSqrtPriceAtTick(pair0 ? int24(-600) : int24(600));
        (uint256 filled, uint256 fee, uint256 refund) =
            trade(true, false, uint256(uint128(type(int128).max)), limit, abi.encode(buyer));
        assertGt(filled, 0);
        assertEq(fee, filled / 50);
        assertEq(refund, 0);
        assertEq(hook.pending(buyer), filled / 100);
    }

    function test_afterSwapWithNothingFilledIsANoOpForTheUnspecifiedSide() public {
        // Directly from the manager, a zero-delta EHS-specified swap must return a zero fee delta.
        vm.prank(address(manager));
        (bytes4 sel, int128 delta) =
            hook.afterSwap(address(this), key, SwapParams(!pair0, -1, 0), toBalanceDelta(0, 0), "");
        assertEq(sel, IHooks.afterSwap.selector);
        assertEq(delta, 0);
        assertEq(hook.accruedBalance(), 0);
    }

    // ---------------------------------------------------------------- payouts

    function test_claimWithNothingPendingIsANoOp() public {
        address stranger = makeAddr("stranger");
        vm.prank(stranger);
        hook.claimRewards();
        hook.payRecorded(stranger);
        hook.payRecorded(address(0));
        assertEq(MockIMD(IMD).balanceOf(stranger), 0);
        assertEq(hook.owedTotal(), 0);
    }

    function test_paymentNeverTouchesOtherSwappersRefundClaims() public {
        uint160 limit = TickMath.getSqrtPriceAtTick(pair0 ? int24(-60) : int24(60));
        (,, uint256 refund) = trade(true, true, 100_000 ether, limit, abi.encode(buyer));
        assertGt(refund, 0);
        uint256 due = hook.pending(buyer);
        assertGt(due, 0);
        hook.payRecorded(buyer);
        assertEq(manager.balanceOf(address(this), ID), refund, "a payout consumed the swapper's refund");
        assertEq(MockIMD(IMD).balanceOf(buyer), due);
    }

    function test_rewardsRemainPayableAfterLiquidityLeavesThePool() public {
        trade(true, true, 1_000 ether, 0, abi.encode(buyer));
        uint256 due = hook.pending(buyer);
        // The harness removes its whole position: the manager keeps every fee and claim backing.
        manager.unlock(abi.encode(uint8(0), abi.encode(int24(-60000), int24(60000), -int256(1_000_000 ether))));
        assertEq(manager.getLiquidity(key.toId()), 0);
        hook.payRecorded(buyer);
        assertEq(MockIMD(IMD).balanceOf(buyer), due);
        assertEq(hook.owedTotal(), 0);
        // Trading against an empty pool fills nothing and reverts nothing.
        (uint256 filled, uint256 fee,) = trade(true, true, 100 ether, 0, abi.encode(buyer));
        assertEq(filled, 0);
        assertEq(fee, 0);
    }

    // ------------------------------------------------------------- liquidity

    function test_otherLPsAndDonationsAreUntouchedByTheHook() public {
        OtherLP lp = new OtherLP(manager);
        deal(IMD, address(lp), 1e24);
        token.transfer(address(lp), 1e24);
        uint256 claimsBefore = manager.balanceOf(address(hook), ID);
        lp.modify(key, -600, 600, 1e21);
        lp.donate(key, 1e18, 1e18);
        trade(true, true, 100 ether, 0, abi.encode(buyer));
        BalanceDelta collected = lp.modify(key, -600, 600, 0);
        assertTrue(collected.amount0() >= 0 && collected.amount1() >= 0, "hook charged a fee collect");
        assertTrue(collected.amount0() > 0 || collected.amount1() > 0, "LP earned nothing");
        BalanceDelta removed = lp.modify(key, -600, 600, -1e21);
        assertGt(removed.amount0(), 0);
        assertGt(removed.amount1(), 0);
        assertEq(hook.accruedBalance(), manager.balanceOf(address(hook), ID));
        assertGt(manager.balanceOf(address(hook), ID), claimsBefore);
    }
}
