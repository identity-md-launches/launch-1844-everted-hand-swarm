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
import {TickMath} from "v4-core/src/libraries/TickMath.sol";
import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {EHS} from "../src/EHS.sol";
import {EHSHook} from "../src/EHSHook.sol";
import {MockIMD} from "./mocks/MockIMD.sol";

abstract contract HookHarness is Test, IUnlockCallback {
    using StateLibrary for IPoolManager;
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
        } else if (mode == 1) {
            (SwapParams memory params, bytes memory context) = abi.decode(args, (SwapParams, bytes));
            delta = manager.swap(key, params, context);
        } else {
            uint256 claims = manager.balanceOf(address(this), uint256(uint160(IMD)));
            manager.burn(address(this), uint256(uint160(IMD)), claims);
            manager.take(Currency.wrap(IMD), address(this), claims);
            return "";
        }
        settle(key.currency0, delta.amount0(), mode == 1);
        settle(key.currency1, delta.amount1(), mode == 1);
        return abi.encode(delta);
    }

    function settle(Currency currency, int128 amount, bool isTrade) internal {
        if (amount < 0) {
            manager.sync(currency);
            currency.transfer(address(manager), uint256(-int256(amount)));
            manager.settle();
        } else if (amount > 0) {
            // Exactly the address encoded as recipient in hookData receives the output.
            manager.take(currency, isTrade ? buyer : address(this), uint256(uint128(amount)));
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
                filled = uint256(d < 0 ? -d : d);
                assertEq(lpFee, 12500, "static LP fee changed");
            }
        }
        fee = hook.accruedBalance() - beforeFees;
        refunded = manager.balanceOf(address(this), uint256(uint160(IMD))) - beforeRefund;
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

    function test_belowThresholdAndMalformedContextDoNotRevert() public {
        trade(true, true, 9 ether, 0, abi.encode(buyer));
        assertEq(hook.pending(buyer), 0);
        trade(true, true, 100 ether, 0, "");
        trade(true, true, 100 ether, 0, hex"1234");
        trade(true, true, 100 ether, 0, abi.encode(type(uint256).max));
        assertEq(hook.pending(buyer), 0);
        assertGt(hook.pending(address(this)), 0, "fallback recipient is the calling swapper");
    }

    function test_exactTenIMDThreshold() public {
        (uint256 filled,,) = trade(true, true, 10.2 ether, 0, abi.encode(buyer));
        assertEq(filled, 10 ether);
        assertEq(hook.pending(buyer), 0.1 ether);
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
        string memory rpc = vm.envOr("EHS_MAINNET_RPC_URL", string(""));
        if (bytes(rpc).length == 0) {
            vm.skip(true);
            return;
        }
        uint256 blockNumber = vm.envOr("EHS_FORK_BLOCK", uint256(0));
        if (blockNumber == 0) vm.createSelectFork(rpc);
        else vm.createSelectFork(rpc, blockNumber);
        assertEq(block.chainid, 1);
        manager = IPoolManager(0x000000000004444c5dc75cB358380D2e3dE08A90);
        assertGt(address(manager).code.length, 0);
        assertGt(IMD.code.length, 0);
        assertEq(MockIMD(IMD).symbol(), "IMD");
        deal(IMD, address(this), 1e30);
        setupPool(false);
    }

    function test_forkAllSwapModesAndClaims() public {
        trade(true, true, 100 ether, 0, abi.encode(buyer));
        trade(true, false, 100 ether, 0, abi.encode(buyer));
        trade(false, true, 100 ether, 0, abi.encode(buyer));
        trade(false, false, 100 ether, 0, abi.encode(buyer));
        hook.payRecorded(buyer);
        assertEq(hook.pending(buyer), 0);
    }

    function test_forkPartialFills() public {
        trade(true, true, 100_000 ether, TickMath.getSqrtPriceAtTick(pair0 ? int24(-60) : int24(60)), abi.encode(buyer));
        trade(false, false, 100_000 ether, Q96, abi.encode(buyer));
    }
}
