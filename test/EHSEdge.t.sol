// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {EHS} from "../src/EHS.sol";

/// @dev The launch token's failure paths and the shapes the launch floor checks for.
contract EHSEdgeTest is Test {
    EHS token;
    address holder = makeAddr("holder");
    address spender = makeAddr("spender");

    function setUp() public {
        token = new EHS();
    }

    function test_metadataAndConstructorEmission() public {
        vm.expectEmit(true, true, true, true);
        emit EHS.Transfer(address(0), address(this), 1e27);
        EHS fresh = new EHS();
        assertEq(fresh.name(), "Everted Hand Swarm");
        assertEq(fresh.symbol(), "EHS");
        assertEq(fresh.decimals(), 18);
        assertEq(fresh.totalSupply(), 1_000_000_000 * 1e18);
        assertEq(fresh.balanceOf(address(this)), fresh.totalSupply(), "deployer must hold the whole supply");
    }

    function test_transferMoreThanBalanceReverts() public {
        vm.expectRevert(EHS.InsufficientBalance.selector);
        token.transfer(holder, 1e27 + 1);
        vm.prank(holder);
        vm.expectRevert(EHS.InsufficientBalance.selector);
        token.transfer(address(this), 1);
        assertEq(token.balanceOf(address(this)), 1e27);
    }

    function test_zeroValueTransfersSucceedAndEmit() public {
        vm.expectEmit(true, true, true, true);
        emit EHS.Transfer(address(this), holder, 0);
        assertTrue(token.transfer(holder, 0));
        vm.prank(holder);
        assertTrue(token.transfer(address(this), 0));
    }

    function test_selfTransferOfEntireBalanceKeepsIt() public {
        assertTrue(token.transfer(address(this), 1e27));
        assertEq(token.balanceOf(address(this)), 1e27);
    }

    function test_infiniteAllowanceIsNotDecremented() public {
        token.approve(spender, type(uint256).max);
        vm.prank(spender);
        token.transferFrom(address(this), holder, 5e26);
        assertEq(token.allowance(address(this), spender), type(uint256).max);
        assertEq(token.balanceOf(holder), 5e26);
    }

    function test_finiteAllowanceOneWeiShortReverts() public {
        token.approve(spender, 99);
        vm.prank(spender);
        vm.expectRevert(EHS.InsufficientAllowance.selector);
        token.transferFrom(address(this), holder, 100);
        assertEq(token.allowance(address(this), spender), 99);
    }

    function test_allowanceDoesNotCoverAnEmptyBalance() public {
        vm.prank(holder);
        token.approve(spender, 1);
        vm.prank(spender);
        vm.expectRevert(EHS.InsufficientBalance.selector);
        token.transferFrom(holder, address(this), 1);
    }

    function test_transferFromToZeroAddressReverts() public {
        token.approve(spender, 1);
        vm.prank(spender);
        vm.expectRevert(EHS.InvalidRecipient.selector);
        token.transferFrom(address(this), address(0), 1);
    }

    function test_approveOverwritesAndEmits() public {
        vm.expectEmit(true, true, true, true);
        emit EHS.Approval(address(this), spender, 7);
        assertTrue(token.approve(spender, 7));
        token.approve(spender, 3);
        assertEq(token.allowance(address(this), spender), 3);
        token.approve(spender, 0);
        assertEq(token.allowance(address(this), spender), 0);
    }

    function test_noOwnerMintBurnOrPauseSurface() public {
        string[8] memory sigs = [
            "owner()",
            "mint(address,uint256)",
            "burn(uint256)",
            "burnFrom(address,uint256)",
            "pause()",
            "setFee(uint256)",
            "upgradeToAndCall(address,bytes)",
            "renounceOwnership()"
        ];
        for (uint256 i; i < sigs.length; ++i) {
            (bool ok,) = address(token).call(abi.encodeWithSignature(sigs[i], address(this), uint256(1)));
            assertFalse(ok, sigs[i]);
        }
        assertEq(token.totalSupply(), 1e27);
    }

    /// forge-config: default.fuzz.runs = 1000
    function testFuzz_transferFromConservesSupplyAndAllowance(uint256 approved, uint256 amount, address to) public {
        vm.assume(to != address(0) && to != address(this));
        approved = bound(approved, 0, type(uint256).max - 1); // finite
        amount = bound(amount, 0, 1e27);
        token.approve(spender, approved);
        vm.prank(spender);
        if (amount > approved) {
            vm.expectRevert(EHS.InsufficientAllowance.selector);
            token.transferFrom(address(this), to, amount);
            return;
        }
        token.transferFrom(address(this), to, amount);
        assertEq(token.allowance(address(this), spender), approved - amount);
        assertEq(token.balanceOf(to), amount);
        assertEq(token.balanceOf(address(this)) + token.balanceOf(to), 1e27);
    }

    /// forge-config: default.fuzz.runs = 1000
    function testFuzz_randomTransfersNeverCreateOrDestroySupply(uint256 seed) public {
        address[3] memory who = [address(this), holder, spender];
        for (uint256 i; i < 10; ++i) {
            seed = uint256(keccak256(abi.encode(seed, i)));
            address from = who[seed % 3];
            address to = who[(seed >> 8) % 3];
            uint256 balance = token.balanceOf(from);
            uint256 amount = bound(seed >> 16, 0, balance + (seed % 7 == 0 ? 1 : 0));
            if (amount > balance) vm.expectRevert(EHS.InsufficientBalance.selector);
            vm.prank(from);
            token.transfer(to, amount);
            assertEq(token.balanceOf(who[0]) + token.balanceOf(who[1]) + token.balanceOf(who[2]), 1e27);
        }
    }
}
