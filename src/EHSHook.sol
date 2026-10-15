// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {IUnlockCallback} from "v4-core/src/interfaces/callback/IUnlockCallback.sol";
import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {Currency} from "v4-core/src/types/Currency.sol";
import {SwapParams} from "v4-core/src/types/PoolOperation.sol";
import {BalanceDelta} from "v4-core/src/types/BalanceDelta.sol";
import {BeforeSwapDelta, toBeforeSwapDelta} from "v4-core/src/types/BeforeSwapDelta.sol";

/// @notice Immutable 2% IMD swap fee and separately claimable 1% buyer rewards.
/// @dev Routers pass abi.encode(outputRecipient) as hookData. PoolManager exposes the
/// router, not its eventual output recipient; this explicit routing context is essential.
/// Empty/malformed context never blocks trading and uses the calling swapper as recipient. Fee refunds belong
/// to `sender`, the caller whose PoolManager delta pays the reserve (ERC-6909 claims).
contract EHSHook is IUnlockCallback {
    address public constant PAIRED_CURRENCY = 0xD34a99Bc0f67aE1bbd63C660e6d0b0dd03E263B7;
    uint256 public constant FEE_BPS = 200;
    uint256 public constant REWARD_BPS = 100;
    uint256 public constant MIN_BUY = 10 ether;
    uint24 public constant LP_FEE = 12500;
    int24 public constant TICK_SPACING = 60;
    uint160 public constant FLAGS = (1 << 13) | (1 << 7) | (1 << 6) | (1 << 3) | (1 << 2);
    IPoolManager public immutable poolManager;
    address public immutable token;
    mapping(address => uint256) public pending;
    uint256 public owedTotal;
    /// @notice IMD held as PoolManager ERC-6909 claims, including recorded obligations.
    uint256 public accruedBalance;
    bool private paying;

    error OnlyPoolManager();
    error InvalidPool();
    error InvalidDeployment();
    error UnrepresentableFee();
    error ReentrantPayment();
    event FeeAccrued(uint256 filledIMD, uint256 fee);
    event FeeRefunded(address indexed swapper, uint256 amount);
    event RewardRecorded(address indexed beneficiary, uint256 amount);
    event RewardPaid(address indexed beneficiary, uint256 amount);

    constructor(IPoolManager manager_, address token_) {
        if (address(manager_) == address(0) || token_ == address(0) || token_ == PAIRED_CURRENCY) {
            revert InvalidDeployment();
        }
        poolManager = manager_;
        token = token_;
        Hooks.validateHookPermissions(IHooks(address(this)), getHookPermissions());
    }

    modifier onlyPoolManager() {
        if (msg.sender != address(poolManager)) revert OnlyPoolManager();
        _;
    }

    function getHookPermissions() public pure returns (Hooks.Permissions memory p) {
        p.beforeInitialize = true;
        p.beforeSwap = true;
        p.afterSwap = true;
        p.beforeSwapReturnDelta = true;
        p.afterSwapReturnDelta = true;
    }

    function beforeInitialize(address, PoolKey calldata key, uint160) external view onlyPoolManager returns (bytes4) {
        (address a, address b) = token < PAIRED_CURRENCY ? (token, PAIRED_CURRENCY) : (PAIRED_CURRENCY, token);
        if (
            Currency.unwrap(key.currency0) != a || Currency.unwrap(key.currency1) != b || key.fee != LP_FEE
                || key.tickSpacing != TICK_SPACING || address(key.hooks) != address(this)
        ) revert InvalidPool();
        return IHooks.beforeInitialize.selector;
    }

    function beforeSwap(address, PoolKey calldata key, SwapParams calldata params, bytes calldata)
        external
        view
        onlyPoolManager
        returns (bytes4, BeforeSwapDelta, uint24)
    {
        uint256 reserve = _pairIsSpecified(key, params) ? _reserve(params.amountSpecified) : 0;
        if (params.amountSpecified > type(int256).max - int256(reserve)) revert UnrepresentableFee();
        return (IHooks.beforeSwap.selector, toBeforeSwapDelta(int128(int256(reserve)), 0), 0);
    }

    function afterSwap(
        address sender,
        PoolKey calldata key,
        SwapParams calldata params,
        BalanceDelta delta,
        bytes calldata data
    ) external onlyPoolManager returns (bytes4, int128) {
        bool pair0 = Currency.unwrap(key.currency0) == PAIRED_CURRENCY;
        int256 pairDelta = pair0 ? int256(delta.amount0()) : int256(delta.amount1());
        uint256 filled = uint256(pairDelta < 0 ? -pairDelta : pairDelta);
        uint256 fee = filled / 50;
        uint256 id = uint256(uint160(PAIRED_CURRENCY));
        bool specified = _pairIsSpecified(key, params);
        if (specified) {
            uint256 refund = _reserve(params.amountSpecified) - fee;
            if (refund != 0) {
                poolManager.mint(sender, id, refund);
                emit FeeRefunded(sender, refund);
            }
        }
        if (fee != 0) {
            poolManager.mint(address(this), id, fee);
            accruedBalance += fee;
            emit FeeAccrued(filled, fee);
        }
        if (pairDelta < 0 && filled >= MIN_BUY) {
            address beneficiary = sender;
            uint256 word;
            if (data.length == 32) {
                assembly ("memory-safe") { word := calldataload(data.offset) }
                if (word != 0 && word <= type(uint160).max) beneficiary = address(uint160(word));
            }
            uint256 reward = filled / 100;
            uint256 available = accruedBalance - owedTotal;
            if (reward > available) reward = available;
            if (reward != 0) {
                pending[beneficiary] += reward;
                owedTotal += reward;
                emit RewardRecorded(beneficiary, reward);
            }
        }
        return (IHooks.afterSwap.selector, specified ? int128(0) : int128(int256(fee)));
    }

    function claimRewards() external {
        payRecorded(msg.sender);
    }

    /// @notice Anyone may trigger a payment, but only to the recorded beneficiary.
    function payRecorded(address beneficiary) public {
        if (paying) revert ReentrantPayment();
        uint256 amount = pending[beneficiary];
        if (amount == 0) return;
        paying = true;
        pending[beneficiary] = 0;
        owedTotal -= amount;
        accruedBalance -= amount;
        poolManager.unlock(abi.encode(beneficiary, amount));
        paying = false;
        emit RewardPaid(beneficiary, amount);
    }

    function unlockCallback(bytes calldata data) external onlyPoolManager returns (bytes memory) {
        if (!paying) revert ReentrantPayment();
        (address beneficiary, uint256 amount) = abi.decode(data, (address, uint256));
        Currency currency = Currency.wrap(PAIRED_CURRENCY);
        poolManager.burn(address(this), currency.toId(), amount);
        poolManager.take(currency, beneficiary, amount);
        return "";
    }

    function _pairIsSpecified(PoolKey calldata key, SwapParams calldata params) private pure returns (bool) {
        bool specified0 = (params.amountSpecified < 0) == params.zeroForOne;
        return specified0 == (Currency.unwrap(key.currency0) == PAIRED_CURRENCY);
    }

    function _reserve(int256 specified) private pure returns (uint256) {
        uint256 magnitude = specified < 0 ? uint256(-(specified + 1)) + 1 : uint256(specified);
        // Input includes fee: ceil(budget/51). Output is net: ceil(output/49).
        uint256 divisor = specified < 0 ? 51 : 49;
        uint256 reserve = magnitude / divisor + (magnitude % divisor == 0 ? 0 : 1);
        // Actual fills are int128. Cap to permit huge, price-limited requests.
        uint256 cap = (uint256(1) << 127) / 50 + 1;
        return reserve > cap ? cap : reserve;
    }
}
