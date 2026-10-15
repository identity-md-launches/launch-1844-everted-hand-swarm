// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {PoolManager} from "v4-core/src/PoolManager.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {IUnlockCallback} from "v4-core/src/interfaces/callback/IUnlockCallback.sol";
import {Currency} from "v4-core/src/types/Currency.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {SwapParams, ModifyLiquidityParams} from "v4-core/src/types/PoolOperation.sol";
import {BalanceDelta} from "v4-core/src/types/BalanceDelta.sol";
import {StateLibrary} from "v4-core/src/libraries/StateLibrary.sol";
import {TransientStateLibrary} from "v4-core/src/libraries/TransientStateLibrary.sol";
import {TickMath} from "v4-core/src/libraries/TickMath.sol";
import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {EHS} from "../src/EHS.sol";
import {EHSHook} from "../src/EHSHook.sol";
import {MockIMD} from "./mocks/MockIMD.sol";

/// @dev Shared router in the Universal Router's shape: swaps for whoever calls it, settles from
/// its own balance, takes the output to the caller's chosen recipient, forwards whatever hookData
/// the caller gives (the Uniswap interface gives none) and lets anyone sweep tokens it holds.
contract SweepableRouter is IUnlockCallback {
    IPoolManager internal immutable manager;

    constructor(IPoolManager manager_) {
        manager = manager_;
    }

    function swap(PoolKey calldata key, SwapParams calldata params, address recipient, bytes calldata hookData)
        external
    {
        manager.unlock(abi.encode(key, params, recipient, hookData));
    }

    function unlockCallback(bytes calldata data) external returns (bytes memory) {
        require(msg.sender == address(manager), "manager only");
        (PoolKey memory key, SwapParams memory params, address recipient, bytes memory hookData) =
            abi.decode(data, (PoolKey, SwapParams, address, bytes));
        BalanceDelta delta = manager.swap(key, params, hookData);
        _settle(key.currency0, delta.amount0(), recipient);
        _settle(key.currency1, delta.amount1(), recipient);
        return "";
    }

    function _settle(Currency currency, int128 amount, address recipient) internal {
        if (amount < 0) {
            manager.sync(currency);
            currency.transfer(address(manager), uint256(uint128(-amount)));
            manager.settle();
        } else if (amount > 0) {
            manager.take(currency, recipient, uint256(uint128(amount)));
        }
    }

    /// @dev Universal Router's SWEEP command: anyone may take whatever the router holds.
    function sweep(address asset, address to) external {
        Currency.wrap(asset).transfer(to, Currency.wrap(asset).balanceOfSelf());
    }
}

abstract contract HookHarness is Test, IUnlockCallback {
    using StateLibrary for IPoolManager;
    using TransientStateLibrary for IPoolManager;
    address internal constant IMD = 0xD34a99Bc0f67aE1bbd63C660e6d0b0dd03E263B7;
    uint160 internal constant Q96 = 79228162514264337593543950336;
    IPoolManager internal manager;
    EHS internal token;
    EHSHook internal hook;
    PoolKey internal key;
    address internal buyer;
    bool internal pair0;

    function setupPool(bool oneSided) internal {
        if (address(token) == address(0)) token = new EHS();
        buyer = makeAddr("swap output recipient");
        bytes memory code = abi.encodePacked(type(EHSHook).creationCode, abi.encode(manager, address(token)));
        bytes32 hash = keccak256(code);
        address deployed;
        for (uint256 i; i < 300_000; ++i) {
            bytes32 salt = bytes32(i);
            address predicted =
                address(uint160(uint256(keccak256(abi.encodePacked(bytes1(0xff), address(this), salt, hash)))));
            if (uint160(predicted) & 0x3fff != 0x20cc) continue;
            assembly ("memory-safe") { deployed := create2(0, add(code, 32), mload(code), salt) }
            break;
        }
        require(deployed != address(0), "CREATE2 mining failed");
        hook = EHSHook(deployed);
        pair0 = IMD < address(token);
        key = PoolKey(
            Currency.wrap(pair0 ? IMD : address(token)),
            Currency.wrap(pair0 ? address(token) : IMD),
            12500,
            60,
            IHooks(deployed)
        );
        manager.initialize(key, Q96);
        int24 lower = oneSided ? (pair0 ? int24(-600) : int24(60)) : int24(-60000);
        int24 upper = oneSided ? (pair0 ? int24(-60) : int24(600)) : int24(60000);
        manager.unlock(abi.encode(uint8(0), abi.encode(lower, upper, int256(1_000_000 ether))));
    }

    function unlockCallback(bytes calldata data) external returns (bytes memory) {
        require(msg.sender == address(manager), "manager only");
        (uint8 mode, bytes memory args) = abi.decode(data, (uint8, bytes));
        BalanceDelta delta;
        if (mode == 0) {
            (int24 lower, int24 upper, int256 liquidity) = abi.decode(args, (int24, int24, int256));
            (delta,) = manager.modifyLiquidity(key, ModifyLiquidityParams(lower, upper, liquidity, bytes32(0)), "");
        } else if (mode == 1 || mode == 3) {
            (SwapParams memory params, bytes memory context) = abi.decode(args, (SwapParams, bytes));
            uint256 claimsBefore = manager.balanceOf(address(this), uint256(uint160(IMD)));
            delta = manager.swap(key, params, context);
            if (mode == 3) {
                // A router can burn only this swap's refund before settling. This avoids
                // prefunding the reservation and leaves any older claims untouched.
                uint256 refund = manager.balanceOf(address(this), uint256(uint160(IMD))) - claimsBefore;
                if (refund != 0) manager.burn(address(this), uint256(uint160(IMD)), refund);
            }
        } else {
            uint256 claims = manager.balanceOf(address(this), uint256(uint160(IMD)));
            manager.burn(address(this), uint256(uint160(IMD)), claims);
            manager.take(Currency.wrap(IMD), address(this), claims);
            return "";
        }
        settle(key.currency0, manager.currencyDelta(address(this), key.currency0), mode != 0);
        settle(key.currency1, manager.currencyDelta(address(this), key.currency1), mode != 0);
        return abi.encode(delta);
    }

    function settle(Currency currency, int256 amount, bool isTrade) internal {
        if (amount < 0) {
            manager.sync(currency);
            currency.transfer(address(manager), uint256(-amount));
            manager.settle();
        } else if (amount > 0) {
            // Exactly the address encoded as recipient in hookData receives the output.
            manager.take(currency, isTrade ? buyer : address(this), uint256(amount));
        }
    }

    function trade(bool buy, bool exactInput, uint256 amount, uint160 limit, bytes memory context)
        public
        returns (uint256 filled, uint256 fee, uint256 refunded)
    {
        bool z = buy == pair0;
        if (limit == 0) limit = z ? TickMath.MIN_SQRT_PRICE + 1 : TickMath.MAX_SQRT_PRICE - 1;
        SwapParams memory params = SwapParams(z, exactInput ? -int256(amount) : int256(amount), limit);
        uint256 beforeFees = hook.accruedBalance();
        uint256 beforeRefund = manager.balanceOf(address(this), uint256(uint160(IMD)));
        int256 pairBefore = int256(MockIMD(IMD).balanceOf(address(this)) + MockIMD(IMD).balanceOf(buyer));
        int256 tokenBefore = int256(token.balanceOf(address(this)) + token.balanceOf(buyer));
        int256 rawTokenDelta;
        vm.recordLogs();
        manager.unlock(abi.encode(uint8(1), abi.encode(params, context)));
        Vm.Log[] memory logs = vm.getRecordedLogs();
        for (uint256 i; i < logs.length; ++i) {
            if (
                logs[i].emitter == address(manager)
                    && logs[i].topics[0]
                        == keccak256("Swap(bytes32,address,int128,int128,uint160,uint128,int24,uint24)")
            ) {
                (int128 a0, int128 a1,,,, uint24 lpFee) =
                    abi.decode(logs[i].data, (int128, int128, uint160, uint128, int24, uint24));
                int256 d = pair0 ? int256(a0) : int256(a1);
                rawTokenDelta = pair0 ? int256(a1) : int256(a0);
                filled = uint256(d < 0 ? -d : d);
                assertEq(lpFee, 12500, "static LP fee changed");
            }
        }
        fee = hook.accruedBalance() - beforeFees;
        refunded = manager.balanceOf(address(this), uint256(uint160(IMD))) - beforeRefund;
        int256 pairAfter = int256(MockIMD(IMD).balanceOf(address(this)) + MockIMD(IMD).balanceOf(buyer));
        int256 tokenAfter = int256(token.balanceOf(address(this)) + token.balanceOf(buyer));
        // Independently verify what the trader actually paid/received, including refund claims.
        int256 expectedPairChange = buy ? -int256(filled + fee) : int256(filled - fee);
        assertEq(pairAfter - pairBefore + int256(refunded), expectedPairChange, "net IMD settlement");
        assertEq(tokenAfter - tokenBefore, rawTokenDelta, "hook must not tax EHS");
        assertEq(fee, filled * 200 / 10000, "fee must track the actual manager fill");
        assertLe(hook.owedTotal(), hook.accruedBalance(), "insolvent rewards");
        assertEq(manager.balanceOf(address(hook), uint256(uint160(IMD))), hook.accruedBalance());
    }
}

contract EHSHookTest is HookHarness {
    function setUp() public virtual {
        manager = IPoolManager(address(new PoolManager(address(this))));
        vm.etch(IMD, address(new MockIMD()).code);
        MockIMD(IMD).mint(address(this), 1e38);
        setupPool(false);
    }

    function test_buyExactInput() public {
        checkTrade(true, true);
    }

    function test_buyExactOutput() public {
        checkTrade(true, false);
    }

    function test_sellExactInput() public {
        checkTrade(false, true);
    }

    function test_sellExactOutput() public {
        checkTrade(false, false);
    }

    function checkTrade(bool buy, bool input) internal {
        uint256 recipientBefore = MockIMD(IMD).balanceOf(buyer);
        (uint256 filled,,) = trade(buy, input, 100 ether, 0, abi.encode(buyer));
        assertGt(filled, 0);
        assertEq(hook.pending(buyer), buy ? filled / 100 : 0);
        if (buy) assertEq(MockIMD(IMD).balanceOf(buyer), recipientBefore, "no rewards paid during swap");
        else assertGt(MockIMD(IMD).balanceOf(buyer), recipientBefore);
    }

    function test_exactInputPartialFillRefund() public {
        partialFill(true, true);
    }

    function test_exactOutputPartialFillRefund() public {
        partialFill(false, false);
    }

    function test_exactOutputBuyPartialFill() public {
        partialFill(true, false);
    }

    function test_exactInputSellPartialFill() public {
        partialFill(false, true);
    }

    function test_zeroFillRefundsEntireReserve() public {
        manager.unlock(abi.encode(uint8(0), abi.encode(int24(-60000), int24(60000), -int256(1_000_000 ether))));
        uint256 snapshot = vm.snapshotState();
        for (uint256 i; i < 4; ++i) {
            bool buy = i & 1 == 0;
            bool input = i & 2 == 0;
            uint160 limit = TickMath.getSqrtPriceAtTick(buy == pair0 ? int24(-60) : int24(60));
            (uint256 filled, uint256 fee, uint256 refund) = trade(buy, input, 100 ether, limit, abi.encode(buyer));
            assertEq(filled, 0);
            assertEq(fee, 0);
            assertEq(hook.owedTotal(), 0);
            if (buy == input) assertGt(refund, 0, "zero fill must return its entire reservation");
            else assertEq(refund, 0);
            assertTrue(vm.revertToState(snapshot));
        }
    }

    function test_partialFillBelowThresholdDoesNotEarnReward() public {
        // Keep a large input request, but stop after less than 10 IMD actually fills.
        uint160 limit = pair0 ? Q96 - Q96 / 1_000_000 : Q96 + Q96 / 1_000_000;
        (uint256 filled, uint256 fee, uint256 refund) = trade(true, true, 100 ether, limit, abi.encode(buyer));
        assertGt(filled, 0);
        assertLt(filled, 10 ether);
        assertGt(fee, 0);
        assertGt(refund, 0);
        assertEq(hook.pending(buyer), 0, "eligibility must use the fill, not the request");
    }

    function test_refundBurnAvoidsPrefundingHugeInputReservation() public {
        checkRefundBurn(true);
    }

    function test_refundBurnAvoidsPrefundingHugeOutputReservation() public {
        checkRefundBurn(false);
    }

    function checkRefundBurn(bool buy) internal {
        // First create a separate refund which the next trade must leave untouched.
        uint160 firstLimit = TickMath.getSqrtPriceAtTick(pair0 ? int24(-1) : int24(1));
        (,, uint256 oldClaims) = trade(true, true, 100_000 ether, firstLimit, abi.encode(buyer));
        assertGt(oldClaims, 0);
        uint256 payerFunds = buy ? 10_000 ether : 0;
        deal(IMD, address(this), payerFunds);
        uint256 recipientBefore = MockIMD(IMD).balanceOf(buyer);
        uint256 feesBefore = hook.accruedBalance();
        uint160 limit = TickMath.getSqrtPriceAtTick(buy == pair0 ? int24(-60) : int24(60));
        // This request's reserve is much larger than the entire production IMD supply.
        SwapParams memory params = SwapParams(buy == pair0, buy ? -int256(1e50) : int256(1e50), limit);
        vm.recordLogs();
        manager.unlock(abi.encode(uint8(3), abi.encode(params, abi.encode(buyer))));
        Vm.Log[] memory logs = vm.getRecordedLogs();
        uint256 filled;
        for (uint256 i; i < logs.length; ++i) {
            if (
                logs[i].emitter == address(manager)
                    && logs[i].topics[0]
                        == keccak256("Swap(bytes32,address,int128,int128,uint160,uint128,int24,uint24)")
            ) {
                (int128 a0, int128 a1,,,,) = abi.decode(logs[i].data, (int128, int128, uint160, uint128, int24, uint24));
                int256 raw = pair0 ? int256(a0) : int256(a1);
                filled = uint256(raw < 0 ? -raw : raw);
            }
        }
        assertGt(filled, 0);
        uint256 fee = hook.accruedBalance() - feesBefore;
        assertEq(fee, filled / 50);
        assertEq(manager.balanceOf(address(this), uint256(uint160(IMD))), oldClaims, "older claims consumed");
        if (buy) {
            assertEq(payerFunds - MockIMD(IMD).balanceOf(address(this)), filled + fee);
        } else {
            assertEq(MockIMD(IMD).balanceOf(address(this)), 0);
            assertEq(MockIMD(IMD).balanceOf(buyer) - recipientBefore, filled - fee);
        }
        assertEq(manager.balanceOf(address(hook), uint256(uint160(IMD))), hook.accruedBalance());
    }

    function partialFill(bool buy, bool input) internal {
        uint160 limit = TickMath.getSqrtPriceAtTick(buy == pair0 ? int24(-60) : int24(60));
        (uint256 filled, uint256 fee, uint256 refund) = trade(buy, input, 100_000 ether, limit, abi.encode(buyer));
        assertLt(filled, 100_000 ether / 10, "not a partial fill");
        assertGt(fee, 0);
        if (buy == input) {
            assertGt(refund, 100 ether, "unused reserve was not refunded");
            uint256 beforeBalance = MockIMD(IMD).balanceOf(address(this));
            manager.unlock(abi.encode(uint8(2), bytes("")));
            assertEq(MockIMD(IMD).balanceOf(address(this)), beforeBalance + refund);
        } else {
            assertEq(refund, 0);
        }
    }

    function test_claimAndPermissionlessPaymentCannotRedirect() public {
        trade(true, false, 100 ether, 0, abi.encode(buyer));
        uint256 reward = hook.pending(buyer);
        address caller = makeAddr("payment caller");
        vm.prank(caller);
        hook.payRecorded(buyer);
        assertEq(MockIMD(IMD).balanceOf(caller), 0);
        assertEq(MockIMD(IMD).balanceOf(buyer), reward);
        assertEq(hook.pending(buyer), 0);
        assertEq(hook.owedTotal(), 0);
        hook.payRecorded(buyer);
        assertEq(MockIMD(IMD).balanceOf(buyer), reward, "double claim");
        trade(true, true, 100 ether, 0, abi.encode(buyer));
        vm.prank(buyer);
        hook.claimRewards();
        assertEq(hook.pending(buyer), 0);
    }

    function test_paymentFailurePreservesDebtAndDoesNotBlockSwaps() public {
        trade(true, true, 100 ether, 0, abi.encode(buyer));
        uint256 reward = hook.pending(buyer);
        MockIMD(IMD).setFailure(true);
        vm.expectRevert();
        hook.payRecorded(buyer);
        assertEq(hook.pending(buyer), reward);
        MockIMD(IMD).setFailure(false);
        trade(true, false, 100 ether, 0, abi.encode(buyer));
        MockIMD(IMD).setReentry(address(hook));
        hook.payRecorded(buyer);
        assertEq(hook.owedTotal(), 0);
    }

    function test_multipleBeneficiariesRetainIndependentBacking() public {
        address firstBuyer = buyer;
        trade(true, true, 100 ether, 0, abi.encode(firstBuyer));
        uint256 firstReward = hook.pending(firstBuyer);
        buyer = makeAddr("second output recipient");
        trade(true, false, 200 ether, 0, abi.encode(buyer));
        uint256 secondReward = hook.pending(buyer);
        assertGt(firstReward, 0);
        assertGt(secondReward, 0);
        assertEq(hook.owedTotal(), firstReward + secondReward);

        uint256 backingBefore = hook.accruedBalance();
        MockIMD(IMD).setFailure(true);
        vm.expectRevert();
        hook.payRecorded(firstBuyer);
        assertEq(hook.pending(firstBuyer), firstReward);
        assertEq(hook.pending(buyer), secondReward);
        assertEq(hook.owedTotal(), firstReward + secondReward);
        assertEq(hook.accruedBalance(), backingBefore);
        assertEq(manager.balanceOf(address(hook), uint256(uint160(IMD))), backingBefore);

        MockIMD(IMD).setFailure(false);
        vm.prank(makeAddr("permissionless payer"));
        hook.payRecorded(firstBuyer);
        assertEq(MockIMD(IMD).balanceOf(firstBuyer), firstReward);
        assertEq(hook.pending(buyer), secondReward);
        assertEq(hook.owedTotal(), secondReward);
        vm.prank(buyer);
        hook.claimRewards();
        assertEq(MockIMD(IMD).balanceOf(buyer), secondReward);
        assertEq(hook.owedTotal(), 0);
        assertEq(hook.accruedBalance(), backingBefore - firstReward - secondReward);
    }

    function test_blockedBeneficiaryDoesNotBlockOtherBuyers() public {
        address blockedBuyer = buyer;
        trade(true, true, 100 ether, 0, abi.encode(blockedBuyer));
        uint256 blockedReward = hook.pending(blockedBuyer);
        MockIMD(IMD).setBlockedRecipient(blockedBuyer);
        vm.expectRevert();
        hook.payRecorded(blockedBuyer);
        // A buy still succeeds even when its reward beneficiary cannot receive IMD.
        trade(true, false, 100 ether, 0, abi.encode(blockedBuyer));
        assertGt(hook.pending(blockedBuyer), blockedReward);
        blockedReward = hook.pending(blockedBuyer);

        buyer = makeAddr("unblocked buyer");
        trade(true, true, 100 ether, 0, abi.encode(buyer));
        uint256 reward = hook.pending(buyer);
        hook.payRecorded(buyer);
        assertEq(MockIMD(IMD).balanceOf(buyer), reward);
        assertEq(hook.owedTotal(), blockedReward);
        assertEq(hook.pending(blockedBuyer), blockedReward);
        MockIMD(IMD).setBlockedRecipient(address(0));
        hook.payRecorded(blockedBuyer);
        assertEq(MockIMD(IMD).balanceOf(blockedBuyer), blockedReward);
        assertEq(hook.owedTotal(), 0);
    }

    function test_belowThresholdAndMalformedContextDoNotRevert() public {
        trade(true, true, 9 ether, 0, abi.encode(buyer));
        assertEq(hook.pending(buyer), 0);
        (, uint256 fee1,) = trade(true, true, 100 ether, 0, "");
        (, uint256 fee2,) = trade(true, true, 100 ether, 0, hex"1234");
        (, uint256 fee3,) = trade(true, true, 100 ether, 0, abi.encode(type(uint256).max));
        (, uint256 fee4,) = trade(true, true, 100 ether, 0, abi.encode(address(0)));
        assertGt(fee1 * fee2 * fee3 * fee4, 0, "fee is still taken without recipient context");
        assertEq(hook.pending(buyer), 0);
        // No named recipient means no reward for anyone: `sender` is the router, never a buyer.
        assertEq(hook.pending(address(this)), 0, "calling swapper must not be credited");
        assertEq(hook.pending(address(0)), 0);
        assertEq(hook.owedTotal(), 0, "unattributed buys leave the fee unowed");
    }

    /// A UI buy through a shared router (Universal Router shape: swaps for its caller, takes the
    /// output to the chosen recipient, passes empty hookData, permissionless sweep) must not leave
    /// a reward that anyone can pay to the router and sweep.
    function test_sharedRouterWithEmptyHookDataEarnsNothingToSweep() public {
        SweepableRouter router = new SweepableRouter(manager);
        address attacker = makeAddr("attacker");
        MockIMD(IMD).mint(address(router), 1_000 ether);
        bool z = pair0;
        uint160 limit = z ? TickMath.MIN_SQRT_PRICE + 1 : TickMath.MAX_SQRT_PRICE - 1;
        uint256 before = hook.accruedBalance();
        router.swap(key, SwapParams(z, int256(500 ether), limit), buyer, "");
        assertEq(token.balanceOf(buyer), 500 ether, "buyer received EHS");
        assertGt(hook.accruedBalance() - before, 10 ether, "hook took its 2% fee");
        assertEq(hook.pending(address(router)), 0, "reward recorded to the shared router");
        assertEq(hook.pending(buyer), 0, "nobody named the buyer");
        assertEq(hook.owedTotal(), 0);
        // The router holds only what the payer did not spend; paying its record must add nothing.
        uint256 leftover = MockIMD(IMD).balanceOf(address(router));
        vm.startPrank(attacker);
        hook.payRecorded(address(router));
        assertEq(MockIMD(IMD).balanceOf(address(router)), leftover, "reward pushed to the router");
        router.sweep(IMD, attacker);
        vm.stopPrank();
        assertEq(MockIMD(IMD).balanceOf(attacker), leftover, "attacker swept more than the leftover");
        // The same router naming its recipient earns the reward for that recipient, not itself.
        MockIMD(IMD).mint(address(router), 1_000 ether);
        router.swap(key, SwapParams(z, int256(500 ether), limit), buyer, abi.encode(buyer));
        assertGt(hook.pending(buyer), 0);
        assertEq(hook.pending(address(router)), 0);
    }

    function test_exactTenIMDThreshold() public {
        (uint256 filled,,) = trade(true, true, 10.2 ether, 0, abi.encode(buyer));
        assertEq(filled, 10 ether);
        assertEq(hook.pending(buyer), 0.1 ether);
    }

    function test_oneWeiBelowThresholdDoesNotEarnReward() public {
        (uint256 filled,,) = trade(true, true, 10.2 ether - 1, 0, abi.encode(buyer));
        assertEq(filled, 10 ether - 1);
        assertEq(hook.pending(buyer), 0);
    }

    /// forge-config: default.fuzz.runs = 1000
    function testFuzz_smallSwapRounding(uint8 raw, bool buy, bool input) public {
        (uint256 filled,,) = trade(buy, input, uint256(raw) + 1, 0, abi.encode(buyer));
        assertLt(filled, 10 ether);
        assertEq(hook.owedTotal(), 0);
    }

    function test_noRuntimeEscapeHatches() public view {
        scan(address(token).code);
        scan(address(hook).code);
    }

    function scan(bytes memory code) internal pure {
        for (uint256 i; i < code.length; i++) {
            uint8 op = uint8(code[i]);
            if (op >= 0x60 && op <= 0x7f) {
                i += op - 0x5f;
                continue;
            }
            require(op != 0xf4 && op != 0xf2 && op != 0xff, "runtime escape opcode");
        }
    }

    function test_permissionsAccessAndSizes() public {
        assertEq(uint160(address(hook)) & 0x3fff, hook.FLAGS());
        Hooks.Permissions memory p = hook.getHookPermissions();
        assertTrue(
            p.beforeInitialize && p.beforeSwap && p.afterSwap && p.beforeSwapReturnDelta && p.afterSwapReturnDelta
        );
        assertFalse(p.beforeRemoveLiquidity || p.afterRemoveLiquidity || p.beforeDonate);
        assertLt(type(EHSHook).creationCode.length + 64, 49152);
        assertLt(address(hook).code.length, 24576);
        vm.expectRevert(EHSHook.OnlyPoolManager.selector);
        hook.beforeInitialize(address(this), key, Q96);
        SwapParams memory s = SwapParams(pair0, -100 ether, Q96 / 2);
        vm.expectRevert(EHSHook.OnlyPoolManager.selector);
        hook.beforeSwap(address(this), key, s, "");
        vm.expectRevert(EHSHook.OnlyPoolManager.selector);
        hook.afterSwap(address(this), key, s, BalanceDelta.wrap(0), "");
        vm.expectRevert(EHSHook.OnlyPoolManager.selector);
        hook.unlockCallback(abi.encode(buyer, 1 ether));
        vm.prank(address(manager));
        vm.expectRevert(EHSHook.ReentrantPayment.selector);
        hook.unlockCallback(abi.encode(buyer, 1 ether));
    }

    function test_factoryCanCollectWithZeroLiquidityChange() public {
        trade(true, true, 100 ether, 0, abi.encode(buyer));
        manager.unlock(abi.encode(uint8(0), abi.encode(int24(-60000), int24(60000), int256(0))));
    }

    function test_wrongPoolCannotInitialize() public {
        PoolKey memory wrong = key;
        wrong.fee = 3000;
        vm.expectRevert();
        manager.initialize(wrong, Q96);
    }

    function test_poolBindingRejectsEveryMismatchedField() public {
        for (uint256 i; i < 5; ++i) {
            PoolKey memory wrong = key;
            if (i == 0) wrong.currency0 = Currency.wrap(makeAddr("foreign currency0"));
            if (i == 1) wrong.currency1 = Currency.wrap(makeAddr("foreign currency1"));
            if (i == 2) wrong.fee = 0x800000; // Dynamic-fee flag is forbidden.
            if (i == 3) wrong.tickSpacing = 10;
            if (i == 4) wrong.hooks = IHooks(makeAddr("foreign hook"));
            vm.prank(address(manager));
            vm.expectRevert(EHSHook.InvalidPool.selector);
            hook.beforeInitialize(address(this), wrong, Q96);
        }
    }

    function test_extremeSpecifiedAmountRejectsOnlyUnrepresentableFee() public {
        SwapParams memory s = SwapParams(!pair0, type(int256).max, Q96 / 2);
        vm.prank(address(manager));
        vm.expectRevert(EHSHook.UnrepresentableFee.selector);
        hook.beforeSwap(address(this), key, s, "");
        uint160 limit = TickMath.getSqrtPriceAtTick(pair0 ? int24(-60) : int24(60));
        trade(true, true, uint256(type(int256).max), limit, abi.encode(buyer));
    }

    /// forge-config: default.fuzz.runs = 1000
    function testFuzz_allDirectionsAndPriceLimitedFills(uint96 raw, bool buy, bool input, uint16 ticks) public {
        uint256 amount = bound(raw, 2, 1_000_000 ether);
        int24 distance = int24(uint24(bound(ticks, 1, 300)));
        uint160 limit = TickMath.getSqrtPriceAtTick(buy == pair0 ? -distance : distance);
        uint256 beforeReward = hook.pending(buyer);
        (uint256 filled,,) = trade(buy, input, amount, limit, abi.encode(buyer));
        assertEq(hook.pending(buyer) - beforeReward, buy && filled >= 10 ether ? filled / 100 : 0);
    }

    /// forge-config: default.fuzz.runs = 1000
    function testFuzz_sequenceSolvency(uint256 seed) public {
        for (uint256 i; i < 12; ++i) {
            seed = uint256(keccak256(abi.encode(seed, i)));
            this.trade(seed & 1 == 1, seed & 2 == 2, 1 ether + seed % (1000 ether), 0, abi.encode(buyer));
            if (seed % 3 == 0) hook.payRecorded(buyer);
            assertEq(hook.owedTotal(), hook.pending(buyer));
            assertLe(hook.owedTotal(), manager.balanceOf(address(hook), uint256(uint160(IMD))));
        }
    }
}

/// @dev Exercise the same complete suite with IMD sorted before the launch token.
contract EHSHookReverseOrderTest is EHSHookTest {
    function setUp() public override {
        manager = IPoolManager(address(new PoolManager(address(this))));
        vm.etch(IMD, address(new MockIMD()).code);
        MockIMD(IMD).mint(address(this), 1e38);
        address high;
        for (uint256 i;; ++i) {
            high = address(uint160(uint256(keccak256(abi.encode("test token ordering", i)))));
            if (high > IMD) break;
        }
        vm.etch(high, address(new EHS()).code);
        token = EHS(high);
        deal(high, address(this), 1e27);
        setupPool(false);
        assertTrue(pair0);
    }
}

contract FreshManagerTest is HookHarness {
    function test_firstBuyTokenOnlyLiquidityNoIMDBalance() public {
        manager = IPoolManager(address(new PoolManager(address(this))));
        vm.etch(IMD, address(new MockIMD()).code);
        MockIMD(IMD).mint(address(this), 1e30);
        setupPool(true);
        assertEq(MockIMD(IMD).balanceOf(address(manager)), 0);
        (uint256 filled, uint256 fee,) = trade(true, true, 100 ether, 0, abi.encode(buyer));
        assertGt(filled, 0);
        assertGt(fee, 0);
        assertEq(MockIMD(IMD).balanceOf(buyer), 0);
        hook.payRecorded(buyer);
        assertGt(MockIMD(IMD).balanceOf(buyer), 0);
    }
}

contract EHSMainnetForkTest is HookHarness {
    function setUp() public {
        // Opt in with forge test --fork-url ... --fork-block-number ... .
        // Tests never read environment variables or contact an RPC in the default run.
        try vm.activeFork() returns (uint256) {}
        catch {
            vm.skip(true);
            return;
        }
        assertEq(block.chainid, 1);
        manager = IPoolManager(0x000000000004444c5dc75cB358380D2e3dE08A90);
        assertGt(address(manager).code.length, 0);
        assertGt(IMD.code.length, 0);
        assertEq(MockIMD(IMD).symbol(), "IMD");
        assertEq(MockIMD(IMD).decimals(), 18);
        deal(IMD, address(this), 1e30);
        setupPool(false);
    }

    function test_forkAllSwapModesAndClaims() public {
        uint256 rewards;
        for (uint256 i; i < 4; ++i) {
            bool buy = i & 1 == 0;
            (uint256 filled,,) = trade(buy, i & 2 == 0, 100 ether, 0, abi.encode(buyer));
            assertGt(filled, 0);
            if (buy) rewards += filled / 100;
            assertEq(hook.pending(buyer), rewards);
        }
        uint256 recipientBefore = MockIMD(IMD).balanceOf(buyer);
        hook.payRecorded(buyer);
        assertEq(MockIMD(IMD).balanceOf(buyer) - recipientBefore, rewards);
        assertEq(hook.pending(buyer), 0);
        assertEq(hook.owedTotal(), 0);
    }

    function test_forkPartialFills() public {
        uint256 snapshot = vm.snapshotState();
        for (uint256 i; i < 4; ++i) {
            bool buy = i & 1 == 0;
            bool input = i & 2 == 0;
            uint160 limit = TickMath.getSqrtPriceAtTick(buy == pair0 ? int24(-60) : int24(60));
            (uint256 filled, uint256 fee, uint256 refund) = trade(buy, input, 100_000 ether, limit, abi.encode(buyer));
            assertGt(fee, 0);
            assertLt(filled, 10_000 ether, "not a partial fill");
            assertEq(hook.pending(buyer), buy ? filled / 100 : 0);
            if (buy == input) {
                assertGt(refund, 0);
                uint256 beforeBalance = MockIMD(IMD).balanceOf(address(this));
                manager.unlock(abi.encode(uint8(2), bytes("")));
                assertEq(MockIMD(IMD).balanceOf(address(this)), beforeBalance + refund);
            } else {
                assertEq(refund, 0);
            }
            assertTrue(vm.revertToState(snapshot));
        }
    }
}
