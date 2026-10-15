// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

contract MockIMD {
    string public constant symbol = "IMD";
    uint8 public constant decimals = 18;
    mapping(address => uint256) public balanceOf;
    bool public failTransfers;
    address public reentryHook;

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
    }

    function setFailure(bool value) external {
        failTransfers = value;
    }

    function setReentry(address hook) external {
        reentryHook = hook;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        require(!failTransfers, "IMD transfer rejected");
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        if (reentryHook != address(0)) {
            (bool ok,) = reentryHook.call(abi.encodeWithSignature("payRecorded(address)", to));
            require(!ok, "reentry succeeded");
        }
        return true;
    }
}
