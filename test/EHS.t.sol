// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;
import {Test} from "forge-std/Test.sol";
import {EHS} from "../src/EHS.sol";

contract EHSTest is Test {
    EHS token;

    function setUp() public {
        token = new EHS();
    }

    function test_fullSupplyAndNoMintPath() public {
        assertEq(token.totalSupply(), 1e27);
        assertEq(token.balanceOf(address(this)), 1e27);
        (bool ok,) = address(token).call(abi.encodeWithSignature("mint(address,uint256)", address(this), 1));
        assertFalse(ok);
        assertEq(token.totalSupply(), 1e27);
    }

    /// forge-config: default.fuzz.runs = 1000
    function testFuzz_transferConservesSupply(uint256 amount) public {
        amount = bound(amount, 0, 1e27);
        address recipient = makeAddr("holder");
        token.transfer(recipient, amount);
        vm.prank(recipient);
        token.transfer(recipient, amount);
        assertEq(token.balanceOf(recipient), amount);
        assertEq(token.balanceOf(address(this)) + token.balanceOf(recipient), 1e27);
    }

    function test_allowanceLimitsAndZeroRecipient() public {
        address spender = makeAddr("spender");
        address recipient = makeAddr("recipient");
        token.approve(spender, 100);
        vm.prank(spender);
        token.transferFrom(address(this), recipient, 100);
        assertEq(token.allowance(address(this), spender), 0);
        vm.prank(spender);
        vm.expectRevert(EHS.InsufficientAllowance.selector);
        token.transferFrom(address(this), recipient, 1);
        vm.expectRevert(EHS.InvalidRecipient.selector);
        token.transfer(address(0), 1);
    }
}
