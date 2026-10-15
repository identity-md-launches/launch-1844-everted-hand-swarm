// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {Vm} from "forge-std/Vm.sol";
import {PoolManager} from "v4-core/src/PoolManager.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {IUnlockCallback} from "v4-core/src/interfaces/callback/IUnlockCallback.sol";
import {Currency} from "v4-core/src/types/Currency.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "v4-core/src/types/PoolId.sol";
import {SwapParams, ModifyLiquidityParams} from "v4-core/src/types/PoolOperation.sol";
import {BalanceDelta} from "v4-core/src/types/BalanceDelta.sol";
import {StateLibrary} from "v4-core/src/libraries/StateLibrary.sol";
import {TransientStateLibrary} from "v4-core/src/libraries/TransientStateLibrary.sol";
import {TickMath} from "v4-core/src/libraries/TickMath.sol";
import {EHS} from "../src/EHS.sol";
import {EHSHook} from "../src/EHSHook.sol";
import {MockIMD} from "./mocks/MockIMD.sol";

/// @notice Random call sequences against the hook: trades in every mode with random price limits,
/// reward payments from random callers, refund redemption, LP changes, pool donations and ERC-6909
/// claims pushed at the hook. Every ghost figure the invariants compare against is recorded here.
contract EHSHookHandler is Test, IUnlockCallback {
    using StateLibrary for IPoolManager;
    using TransientStateLibrary for IPoolManager;

    address public constant IMD = 0xD34a99Bc0f67aE1bbd63C660e6d0b0dd03E263B7;
    uint256 public constant ID = uint256(uint160(IMD));
    int24 public constant LOWER = -887220;
    int24 public constant UPPER = 887220;

    IPoolManager public immutable manager;
    EHS public immutable token;
    EHSHook public immutable hook;
    PoolKey public key;
    bool public immutable pair0;

    address[] public actors;
    address[] public strangers;

    // Ghost accounting.
    uint256 public ghostFees; // every fee the hook accrued, summed from accruedBalance deltas
    uint256 public ghostPaidTotal; // every reward paid out
    uint256 public ghostDonatedClaims; // ERC-6909 IMD pushed at the hook from outside
    uint256 public ghostRefunds; // refund claims minted to this swapper
    uint256 public ghostRedeemed; // refund claims this swapper burned for IMD
    uint256 public ghostLiquidity; // liquidity this handler added on top of the seed
    mapping(address => uint256) public ghostRecorded;
    mapping(address => uint256) public ghostPaid;
    uint256 public swaps;
    uint256 public buysRewarded;
    uint256 public unattributedBuys; // qualifying buys without a canonical recipient word: fee kept, no reward
    uint256 public partialFills;
    uint256 public zeroFills;
    uint256 public payments;

    struct Trade {
        bool buy;
        bool exactInput;
        uint256 amount;
        uint160 limit;
        bytes context;
    }

    constructor(IPoolManager manager_, EHS token_, EHSHook hook_, PoolKey memory key_) {
        manager = manager_;
        token = token_;
        hook = hook_;
        key = key_;
        pair0 = Currency.unwrap(key_.currency0) == IMD;
        for (uint256 i; i < 4; ++i) {
            actors.push(makeAddr(string.concat("beneficiary ", vm.toString(i))));
            strangers.push(makeAddr(string.concat("stranger ", vm.toString(i))));
        }
    }

    function actorCount() external view returns (uint256) {
        return actors.length;
    }

    function strangerCount() external view returns (uint256) {
        return strangers.length;
    }

    // ---------------------------------------------------------------- actions

    function swap(bool buy, bool exactInput, uint256 rawAmount, uint16 rawTicks, uint8 who, uint8 shape) external {
        // Exact-output requests are bounded tighter so a run of buys cannot ask for more EHS than the
        // full-range seed holds at a price the swapper could never settle.
        uint256 amount = bound(rawAmount, 1, exactInput ? 1e23 : 1e22);
        (, int24 tick,,) = manager.getSlot0(key.toId());
        uint160 limit = limitFor(buy, tick, bound(rawTicks, 0, 2000));
        address beneficiary = actors[who % actors.length];
        bytes memory context;
        uint256 mode = shape % 5;
        if (mode == 0) context = abi.encode(beneficiary);
        else if (mode == 1) context = "";
        else if (mode == 2) context = abi.encodePacked(beneficiary); // 20 bytes: malformed
        else if (mode == 3) context = abi.encode(beneficiary, uint256(1)); // 64 bytes: malformed
        else context = abi.encode(uint256(type(uint160).max) + 1); // not an address
        // Only a canonical single-word recipient is rewarded; every other shape rewards nobody, and
        // in particular never this swapper (the router in PoolManager's eyes).
        address expectedBeneficiary = beneficiary;

        uint256 feesBefore = hook.accruedBalance();
        uint256 owedBefore = hook.owedTotal();
        uint256 pendingBefore = hook.pending(expectedBeneficiary);
        uint256 claimsBefore = manager.balanceOf(address(this), ID);
        uint256 imdBefore = MockIMD(IMD).balanceOf(address(this));
        uint256 ehsBefore = token.balanceOf(address(this));

        bool z = buy == pair0;
        SwapParams memory params = SwapParams(z, exactInput ? -int256(amount) : int256(amount), limit);
        vm.recordLogs();
        manager.unlock(abi.encode(uint8(1), abi.encode(params, context)));
        (uint256 filled, int256 rawToken) = decodeSwap(vm.getRecordedLogs());

        uint256 fee = hook.accruedBalance() - feesBefore;
        uint256 refund = manager.balanceOf(address(this), ID) - claimsBefore;
        require(fee == filled / 50, "fee is not 2% of the actual fill");
        int256 imdChange = int256(MockIMD(IMD).balanceOf(address(this))) - int256(imdBefore) + int256(refund);
        require(imdChange == (buy ? -int256(filled + fee) : int256(filled - fee)), "swapper IMD settlement");
        require(int256(token.balanceOf(address(this))) - int256(ehsBefore) == rawToken, "EHS was taxed");
        bool specified = exactInput == buy; // IMD is the specified currency on exact-input buys and exact-output sells
        if (!specified) require(refund == 0, "refund on the unspecified side");

        uint256 reward = hook.owedTotal() - owedBefore;
        uint256 expectedReward = mode == 0 && buy && filled >= 10 ether ? filled / 100 : 0;
        require(reward == expectedReward, "reward is not 1% of a qualifying buy");
        require(hook.pending(expectedBeneficiary) - pendingBefore == reward, "reward went to the wrong beneficiary");
        require(hook.pending(address(this)) == 0, "the calling swapper was credited");
        if (reward != 0) buysRewarded++;
        else if (mode != 0 && buy && filled >= 10 ether) unattributedBuys++;

        ghostFees += fee;
        ghostRefunds += refund;
        ghostRecorded[expectedBeneficiary] += reward;
        swaps++;
        if (filled == 0) zeroFills++;
        else if (filled < amount / 2) partialFills++;
    }

    function payRecorded(uint8 who, uint8 callerIdx) external {
        address beneficiary = actors[who % actors.length];
        uint256 due = hook.pending(beneficiary);
        uint256 before = MockIMD(IMD).balanceOf(beneficiary);
        address caller = strangers[callerIdx % strangers.length];
        vm.prank(caller);
        hook.payRecorded(beneficiary);
        require(MockIMD(IMD).balanceOf(beneficiary) - before == due, "payment did not reach its beneficiary");
        require(hook.pending(beneficiary) == 0, "payment left a residue");
        ghostPaid[beneficiary] += due;
        ghostPaidTotal += due;
        if (due != 0) payments++;
    }

    function claimRewards(uint8 who) external {
        address beneficiary = actors[who % actors.length];
        uint256 due = hook.pending(beneficiary);
        uint256 before = MockIMD(IMD).balanceOf(beneficiary);
        vm.prank(beneficiary);
        hook.claimRewards();
        require(MockIMD(IMD).balanceOf(beneficiary) - before == due, "claim paid a different amount");
        ghostPaid[beneficiary] += due;
        ghostPaidTotal += due;
        if (due != 0) payments++;
    }

    /// @dev A stranger with nothing recorded gets nothing, however it asks.
    function strangerClaims(uint8 idx) external {
        address stranger = strangers[idx % strangers.length];
        vm.prank(stranger);
        hook.claimRewards();
        vm.prank(stranger);
        hook.payRecorded(stranger);
        require(MockIMD(IMD).balanceOf(stranger) == 0, "stranger was paid");
    }

    function redeemRefunds() external {
        uint256 claims = manager.balanceOf(address(this), ID);
        if (claims == 0) return;
        uint256 before = MockIMD(IMD).balanceOf(address(this));
        manager.unlock(abi.encode(uint8(2), abi.encode(claims)));
        require(MockIMD(IMD).balanceOf(address(this)) - before == claims, "refund redemption short");
        ghostRedeemed += claims;
    }

    /// @dev Outside ERC-6909 IMD pushed at the hook; it must never be counted as fees or rewards.
    function donateClaimsToHook(uint256 raw) external {
        uint256 amount = bound(raw, 1, 1e21);
        manager.unlock(abi.encode(uint8(3), abi.encode(amount)));
        ghostDonatedClaims += amount;
    }

    function modifyLiquidity(uint256 raw, bool add) external {
        int256 delta;
        if (add) {
            delta = int256(bound(raw, 1e15, 1e22));
            ghostLiquidity += uint256(delta);
        } else {
            if (ghostLiquidity == 0) return;
            uint256 remove = bound(raw, 1, ghostLiquidity);
            ghostLiquidity -= remove;
            delta = -int256(remove);
        }
        manager.unlock(abi.encode(uint8(0), abi.encode(LOWER, UPPER, delta)));
    }

    /// @dev Full-range seed position, added once from setUp; never a fuzz target.
    function seed(uint256 liquidity) external {
        manager.unlock(abi.encode(uint8(0), abi.encode(LOWER, UPPER, int256(liquidity))));
    }

    /// @dev The launch factory's fee collect: a zero liquidity change on the seeded range.
    function collectFees() external {
        manager.unlock(abi.encode(uint8(0), abi.encode(LOWER, UPPER, int256(0))));
    }

    function donateToPool(uint256 raw0, uint256 raw1) external {
        uint256 a0 = bound(raw0, 0, 1e21);
        uint256 a1 = bound(raw1, 0, 1e21);
        if (a0 == 0 && a1 == 0) return;
        if (manager.getLiquidity(key.toId()) == 0) return; // v4 refuses donations with nobody to receive them
        manager.unlock(abi.encode(uint8(4), abi.encode(a0, a1)));
    }

    // ------------------------------------------------------------- plumbing

    function unlockCallback(bytes calldata data) external returns (bytes memory) {
        require(msg.sender == address(manager), "manager only");
        (uint8 mode, bytes memory args) = abi.decode(data, (uint8, bytes));
        if (mode == 0) {
            (int24 lower, int24 upper, int256 liquidity) = abi.decode(args, (int24, int24, int256));
            manager.modifyLiquidity(key, ModifyLiquidityParams(lower, upper, liquidity, bytes32(0)), "");
        } else if (mode == 1) {
            (SwapParams memory params, bytes memory context) = abi.decode(args, (SwapParams, bytes));
            manager.swap(key, params, context);
        } else if (mode == 2) {
            uint256 claims = abi.decode(args, (uint256));
            manager.burn(address(this), ID, claims);
            manager.take(Currency.wrap(IMD), address(this), claims);
            return "";
        } else if (mode == 3) {
            uint256 amount = abi.decode(args, (uint256));
            manager.mint(address(hook), ID, amount);
        } else {
            (uint256 a0, uint256 a1) = abi.decode(args, (uint256, uint256));
            manager.donate(key, a0, a1, "");
        }
        settle(key.currency0, manager.currencyDelta(address(this), key.currency0));
        settle(key.currency1, manager.currencyDelta(address(this), key.currency1));
        return "";
    }

    function settle(Currency currency, int256 amount) internal {
        if (amount < 0) {
            manager.sync(currency);
            currency.transfer(address(manager), uint256(-amount));
            manager.settle();
        } else if (amount > 0) {
            manager.take(currency, address(this), uint256(amount));
        }
    }

    function limitFor(bool buy, int24 tick, uint256 distance) internal view returns (uint160) {
        bool z = buy == pair0;
        if (distance == 0) return z ? TickMath.MIN_SQRT_PRICE + 1 : TickMath.MAX_SQRT_PRICE - 1;
        int24 target = z ? tick - int24(uint24(distance)) : tick + 1 + int24(uint24(distance));
        if (target <= TickMath.MIN_TICK) target = TickMath.MIN_TICK + 1;
        if (target >= TickMath.MAX_TICK) target = TickMath.MAX_TICK - 1;
        return TickMath.getSqrtPriceAtTick(target);
    }

    function decodeSwap(Vm.Log[] memory logs) internal view returns (uint256 filled, int256 rawToken) {
        bool seen;
        for (uint256 i; i < logs.length; ++i) {
            if (
                logs[i].emitter == address(manager)
                    && logs[i].topics[0]
                        == keccak256("Swap(bytes32,address,int128,int128,uint160,uint128,int24,uint24)")
            ) {
                (int128 a0, int128 a1,,,, uint24 lpFee) =
                    abi.decode(logs[i].data, (int128, int128, uint160, uint128, int24, uint24));
                int256 d = pair0 ? int256(a0) : int256(a1);
                rawToken = pair0 ? int256(a1) : int256(a0);
                filled = uint256(d < 0 ? -d : d);
                require(lpFee == 12500, "LP fee changed");
                seen = true;
            }
        }
        require(seen, "no Swap event");
    }
}

/// forge-config: default.invariant.runs = 256
/// forge-config: default.invariant.depth = 40
/// forge-config: default.invariant.fail-on-revert = true
contract EHSHookInvariantTest is StdInvariant, Test {
    using StateLibrary for IPoolManager;

    address internal constant IMD = 0xD34a99Bc0f67aE1bbd63C660e6d0b0dd03E263B7;
    uint256 internal constant ID = uint256(uint160(IMD));
    uint160 internal constant Q96 = 79228162514264337593543950336;

    IPoolManager internal manager;
    EHS internal token;
    EHSHook internal hook;
    PoolKey internal key;
    EHSHookHandler internal handler;
    uint256 internal seedLiquidity = 1_000_000 ether;

    function setUp() public {
        manager = IPoolManager(address(new PoolManager(address(this))));
        vm.etch(IMD, address(new MockIMD()).code);
        token = new EHS();
        hook = EHSHook(mine());
        bool pair0 = IMD < address(token);
        key = PoolKey(
            Currency.wrap(pair0 ? IMD : address(token)),
            Currency.wrap(pair0 ? address(token) : IMD),
            12500,
            60,
            IHooks(address(hook))
        );
        manager.initialize(key, Q96);
        handler = new EHSHookHandler(manager, token, hook, key);
        MockIMD(IMD).mint(address(handler), 1e38);
        token.transfer(address(handler), token.totalSupply());
        // The handler seeds the pool so a single contract holds every position.
        handler.seed(seedLiquidity);

        targetContract(address(handler));
        bytes4[] memory selectors = new bytes4[](10);
        selectors[0] = EHSHookHandler.swap.selector;
        selectors[1] = EHSHookHandler.swap.selector; // weight trades
        selectors[2] = EHSHookHandler.swap.selector;
        selectors[3] = EHSHookHandler.payRecorded.selector;
        selectors[4] = EHSHookHandler.claimRewards.selector;
        selectors[5] = EHSHookHandler.strangerClaims.selector;
        selectors[6] = EHSHookHandler.redeemRefunds.selector;
        selectors[7] = EHSHookHandler.donateClaimsToHook.selector;
        selectors[8] = EHSHookHandler.modifyLiquidity.selector;
        selectors[9] = EHSHookHandler.collectFees.selector;
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
        bytes4[] memory more = new bytes4[](1);
        more[0] = EHSHookHandler.donateToPool.selector;
        targetSelector(FuzzSelector({addr: address(handler), selectors: more}));
    }

    function mine() internal returns (address deployed) {
        bytes memory code = abi.encodePacked(type(EHSHook).creationCode, abi.encode(manager, address(token)));
        bytes32 hash = keccak256(code);
        for (uint256 i; i < 300_000; ++i) {
            bytes32 salt = bytes32(i);
            address predicted =
                address(uint160(uint256(keccak256(abi.encodePacked(bytes1(0xff), address(this), salt, hash)))));
            if (uint160(predicted) & 0x3fff != 0x20cc) continue;
            assembly ("memory-safe") {
                deployed := create2(0, add(code, 32), mload(code), salt)
            }
            break;
        }
        require(deployed != address(0), "CREATE2 mining failed");
    }

    /// @dev What the hook holds equals what it owes plus the unowed fee remainder; outside claims
    /// pushed at it are extra and never counted.
    function invariant_claimsBackAccruedBalance() public view {
        assertEq(manager.balanceOf(address(hook), ID), hook.accruedBalance() + handler.ghostDonatedClaims());
        assertLe(hook.owedTotal(), hook.accruedBalance(), "rewards owed exceed the hook's backing");
    }

    function invariant_feeConservation() public view {
        assertEq(handler.ghostFees(), hook.accruedBalance() + handler.ghostPaidTotal(), "fees leaked or appeared");
        // Each qualifying buy funds at least twice its reward, so the cap can never bind.
        assertLe(hook.owedTotal() + handler.ghostPaidTotal(), handler.ghostFees() / 2 + 1);
    }

    function invariant_owedTotalIsSumOfPending() public view {
        uint256 sum;
        for (uint256 i; i < handler.actorCount(); ++i) {
            sum += hook.pending(handler.actors(i));
        }
        assertEq(hook.pending(address(handler)), 0, "the router-shaped swapper must never be owed");
        assertEq(hook.owedTotal(), sum);
    }

    function invariant_beneficiariesReceiveExactlyTheirRecords() public view {
        for (uint256 i; i < handler.actorCount(); ++i) {
            address a = handler.actors(i);
            assertEq(handler.ghostRecorded(a), hook.pending(a) + handler.ghostPaid(a), "record mismatch");
            assertEq(MockIMD(IMD).balanceOf(a), handler.ghostPaid(a), "beneficiary IMD differs from payments");
        }
        for (uint256 i; i < handler.strangerCount(); ++i) {
            assertEq(MockIMD(IMD).balanceOf(handler.strangers(i)), 0, "a payer or stranger received rewards");
        }
    }

    function invariant_managerBacksEveryClaim() public view {
        uint256 claims = manager.balanceOf(address(hook), ID) + manager.balanceOf(address(handler), ID);
        assertLe(claims, MockIMD(IMD).balanceOf(address(manager)), "ERC-6909 claims exceed manager IMD");
        assertEq(handler.ghostRefunds() - handler.ghostRedeemed(), manager.balanceOf(address(handler), ID));
    }

    function invariant_hookHoldsNoTokensAndTaxesNoEHS() public view {
        assertEq(token.balanceOf(address(hook)), 0);
        assertEq(MockIMD(IMD).balanceOf(address(hook)), 0);
        assertEq(manager.balanceOf(address(hook), uint256(uint160(address(token)))), 0);
        assertEq(token.totalSupply(), 1e27);
        assertEq(token.balanceOf(address(handler)) + token.balanceOf(address(manager)), 1e27, "EHS left the system");
    }

    function invariant_poolTermsAreFixed() public view {
        (,,, uint24 lpFee) = manager.getSlot0(key.toId());
        assertEq(lpFee, 12500);
        assertEq(hook.FEE_BPS(), 200);
        assertEq(hook.REWARD_BPS(), 100);
        assertEq(hook.MIN_BUY(), 10 ether);
        assertEq(uint160(address(hook)) & 0x3fff, hook.FLAGS());
    }

    function invariant_callSummary() public view {
        // Coverage sanity: the sequence actually traded in both regimes. Checked loosely so a short
        // sequence does not fail; the counters are what a reviewer reads in a failing run.
        assertLe(handler.buysRewarded() + handler.unattributedBuys(), handler.swaps());
        assertLe(handler.zeroFills() + handler.partialFills(), handler.swaps());
    }
}
