# Damn Vulnerable Defi V3

[Damn Vulnerable Defi](https://www.damnvulnerabledefi.xyz/) 是款针对在 Defi 领域合约安全审计的 wargame

此 repo 是针对 Damn Vulnerable DeFi V3 在 foundry 上的解决方案

> [Unstoppable](#unstoppable)
>
> [Naive Receiver](#naive-receiver)
>
> [Truster](#truster)
>
> [Side Entrance](#side-entrance)
>
> [The Rewarder](#the-rewarder)
>
> [Selfie](#selfie)
>
> [Compromised](#compromised)
>
> [Puppet](#puppet)
>
> [Puppet V2](#puppet-v2)
>
> [Free Rider](#free-rider)
>
> [Backdoor](#backdoor)

---

## Unstoppable

目标是想让金库的闪电贷停摆,即对其合约发动 Dos 攻击

金库闪电贷的基础代币是"DVT",对应的金库铸造的代币凭证是"oDVT"

UnstoppableVault 合约中的 flashLoan() 存在问题:

```js
uint256 balanceBefore = totalAssets();
if (convertToShares(totalSupply) != balanceBefore) revert InvalidBalance(); // enforce ERC4626 requirement
```

每次在执行前都会检查金库里的资产数量,也就是硬性要求金库内的基础代币总量一定要等于正常流程计算下来的基础代币的总提供量(即初始提供的量加减上那些通过提供代币获得凭证和借贷出去的存入借出量)

然而金库内的基础代币还是通过`totalAssets()`里的`asset.balanceOf(address(this))`逻辑得到的,也就是 balanceBefore 的计算是通过独立的计算系统

这样的话,只要不走常规手段,让金库的基础代币资产多了或少了,直接转账或者找个合约自毁往里灌入基础代币也行,数量上只要对不上了,闪电贷就自然停摆了

[Solution](./test/unstoppable.t.sol)

`forge test --match-path ./test/unstoppable.t.sol -vvv`

## Naive Receiver

漏洞在于 pool 合约逻辑上允许任何人代替任何接受者调用 flashloan(),因此可以耗尽接收合约里的资金

具体只要另外实现一个攻击逻辑的合约,在合约的 fallback() 上代替接受者调 flashloan() 就可以了,调一次就抽接受者 flashFee() 的 ETH ,多调几次就抽干接受者的资金到池子里去了(当然这里例子是直接设置了 flashFee()是 1 ether,事实上不会到那么贵的)

[Solution](./test/naive_receiver.t.sol)

`forge test --match-path ./test/naive_receiver.t.sol -vvv`

## Truster

```js
token.transfer(borrower, amount);
target.functionCall(data);
```

漏洞在于调用 flashloan()时,不对 amount 进行限制,也就是甚至可以进行 0 金额的闪贷

而且 flashloan()的内部还支持 call 外部的函数

这样以来可以申请 0 金额的闪电贷,再传入批准(approve) hacker 操作指定金额的函数指令去 call,那 hacker 在闪电贷结束后就可以从中随意提取指定的金额了

[Solution](./test/truster.t.sol)

`forge test --match-path ./test/truster.t.sol -vvv`

## Side Entrance

```js
// 存储或者提取改的都是设置的balances数组的值
mapping(address => uint256) private balances;
// 但闪电贷里却是直接检测eth余额
uint256 balanceBefore = address(this).balance;
```

和 Unstoppable 问题差不多,都是在于闪电贷和合约存储是用的两套不同的计算系统

实际攻击只要先借闪电贷,再在其回调函数 execute() 里调 deposit() 存回闪电贷合约去,这样结束之后 balances[] 上记的值多了,接下来就直接调 withdraw() 正常提出去就好了

[Solution](./test/side_entrance.t.sol)

`forge test --match-path ./test/side_entrance.t.sol -vvv`

## The Rewarder

这次给出的是一个利用流动性质押获得奖励的代币池

在奖励池计算奖励上存在几个漏洞:

1. 奖励的计算实现是通过一个奖励代币快照实现的,具体是专门有个 AccountingToken 的代币,人们在存入质押代币的同时,质押池会为人们铸造等量的 AccountingToken 来记录,而这个质押奖励是在 5 天结算一次的,实现上就是每 5 天给 AccountingToken 照个快照,问题也是这个快照是在固定的时间点照的,而且看它的计算公式 `rewards = amountDeposited.mulDiv(REWARDS, totalDeposits);` ,在池资产较低时将大量代币投入池中就可以操纵奖励金额,所以这里问题多多

2. 奖励的领取时限上也很有问题,看下面的逻辑

```js
    if (amountDeposited > 0 && totalDeposits > 0) {
        rewards = amountDeposited.mulDiv(REWARDS, totalDeposits);
        if (rewards > 0 && !_hasRetrievedReward(msg.sender)) {
            rewardToken.mint(msg.sender, rewards);
            astRewardTimestamps[msg.sender] = uint64(block.timestamp);
        }
    }

    function _hasRetrievedReward(address account) private view returns (bool) {
        return (
            lastRewardTimestamps[account] >= lastRecordedSnapshotTimestamp
            && lastRewardTimestamps[account] <= lastRecordedSnapshotTimestamp + REWARDS_ROUND_MIN_DURATION
        );
    }
```

在满足计算出的 reward > 0 这个大前提的情况下,这时如果是第一次在这里领取奖励的话,完全就可以绕过 5 天即 REWARDS_ROUND_MIN_DURATION 的时间限制直接拿到奖励

3. AccountingToken 快照的实现也有问题,具体看快照的逻辑:

```js
    function deposit(uint256 amount) external {
        if (amount == 0) {
            revert InvalidDepositAmount();
        }

        accountingToken.mint(msg.sender, amount);
        // 这个快照实现逻辑的函数应该要在上面 accountingToken.mint() 的前面
        distributeRewards();

        SafeTransferLib.safeTransferFrom(
            liquidityToken,
            msg.sender,
            address(this),
            amount
        );
    }
```

只要到了新的一轮周期,就更新快照,但是这个快照的实现竟然是在 accountingToken.mint() 的后面,也就是先算了新存进去的钱,再找快照,那这轮奖励里自然多了本该下一轮才结算的奖励

也就是直接存,就直接 reward 算出来是有的了,配合上面那个直接提 reward,显然就可以攻击了

**攻击的大概流程:** 身无分文,先闪电贷,利用闪电贷回调,质押,解质押(在里面就包含有提 reward 环节的,省心),转 reward 走,还闪电贷,over (注意在模拟的时候,要先让它跑一个周期(5 天))

[Solution](./test/the_rewarder.t.sol)

`forge test --match-path ./test/the_rewarder.t.sol -vvv`

## Selfie

这是一个涉及 质押 Dao 和 闪电贷池 的攻击,简单说下组成:

这个自治组织是通过质押某种代币到一池子内,通过在池子内质押的代币快照确认份额,从而获得对应的提案权,而其中这个质押的池子还提供闪电贷的服务

成分复杂,内容拉满,但也有几个漏洞问题:

1. 首先最大的问题就是池子质押的代币和治理代币竟然是一种代币

2. 允许任何人都可以对池子的质押代币进行快照,也就意味着人们可以随时确认自己的份额

这两个漏洞已经够了,大概攻击过程: 先闪电贷,回调中直接快照确认份额并拿到提案权,提案申请毁池,还闪电贷回去,过两天后(硬性要求提案要拖两天),直接毁池并转出池子所有的资产,完成攻击

[Solution](./test/selfie.t.sol)

`forge test --match-path ./test/selfie.t.sol -vvv`

## Compromised

题目已经给出了从 web 服务器端捕获到的两段 http 报文,这就是对应其中两个预言机的私钥

只要对报文,从十六进制转换为 ASCII 码,再 经过 base64 decode 就能得到两个私钥了 (具体实现逻辑在 script/compromised.js 下)

`node script/compromised.js`

得到私钥 `0xc678ef1aa456da65c6fc5861d44892cdfac0c6c8c2560bf0c9fbcdae2f4735a9` 和 `0x208242c40acdfa9ed889e685c23547acbed9befc60371e9875fbcd736340bb48` ,总共三个预言机,操纵了两个,后面攻击就简单多了,只要操纵价格预言机,然后调整 NFT 价格,低买高卖就可以了

[Solution](./test/compromised.t.sol)

`forge test --match-path ./test/compromised.t.sol -vvv`

## Puppet

这个攻击实例就很真实的暴露出 Uniswap V1 的问题: 对于流动性小的池子,价格很容易被操控

这次攻击实现也是利用了这点,因为 DVT 借贷池参考的是 Uniswap 的 DVT/ETH 池子价格

**攻击大概步骤:** 先在 Uniswap V1 池子里将 DVT 换为 ETH,操纵价格,再到借贷池里用少量的 ETH 就可以借贷出所有的 DVT 了

[Solution](./test/puppet.t.sol)

`forge test --match-path ./test/puppet.t.sol -vvv`

## Puppet V2

这次借贷池调用的是 Uniswap V2 ,对比 V1 引入了 TWAP(时间加权平均价格) 的概念,就是采用多个时间的平均的价格加权得到预言机的价格,能有效防止 V1 时的那种预言机操纵,并且会在每个区块的开头就测量一下价格,这样加权算进去就很难操纵价格的短时大范围波动了

可惜的是,借贷池计算质押时,用的还是现货当前价格,而没使用 TWAP ,因此也是跟 [Puppet](#puppet) 差不多的攻击流程

[Solution](./test/puppetv2.t.sol)

`forge test --match-path ./test/puppetv2.t.sol -vvv`

## Free Rider

目的是要获得 marketPlace 里的 NFT 和一些 ETH,最后 NFT 回到接收地址 recoverer 去,而得到的 ETH 到 hacker 地址去

主要抓住漏洞: FreeRiderNFTMarketplace 合约里的 \_buyOne() 逻辑有问题,卖家出售的 NFT 的同时还倒打钱给买家

```js
_token.safeTransferFrom(_token.ownerOf(tokenId), msg.sender, tokenId);

payable(_token.ownerOf(tokenId)).sendValue(priceToPay);
```

而且调用 buyMany() 一次买多个的话,也是多次调用 \_buyOne() 的逻辑,但在 msg.value 上只检查包含购买一次的钱,也就是其实发购买一次的钱,就可以调用 buyMany(),再加上卖出去的钱也是打买家账户,攻击逻辑就完整了

**攻击大概流程**: 先闪电贷,然后发一次的 ETH 去 marketPlace 调 buyMany() 买 NFT,还闪电贷后再把 NFT 发回给 recoverer 就好了

[Solution](./test/free_rider.t.sol)

`forge test --match-path ./test/free_rider.t.sol -vvv`

## Backdoor

目标是帮 WalletRegistry 里那四个 beneficiary 注册 [Safe](https://github.com/safe-global/safe-contracts) 钱包,每人注册时都会得到 10 个 DVT 代币奖励,但这一共 40 个 DVT 得到 hacker 袋子里

**逻辑分析:** 首先看看是怎么注册钱包的,注册钱包是通过调用 walletFactory 钱包工厂合约里的 createProxyWithCallback() 实现的,而在调用注册钱包的这个函数后就回调 WalletRegistry 注册人名单合约里的 proxyCreated(),其中有

```js
// Ensure initial calldata was a call to `Safe::setup`
if (bytes4(initializer[:4]) != Safe.setup.selector) {
    revert WrongInitialization();
}
```

看到这里调用了 Safe.setup(),到 Safe 钱包合约的 setup()

```js
function setup(
    address[] calldata _owners,
    uint256 _threshold,
    address to,
    bytes calldata data,
    address fallbackHandler,
    address paymentToken,
    uint256 payment,
    address payable paymentReceiver
) external {
    setupOwners(_owners, _threshold);
    if (fallbackHandler != address(0)) internalSetFallbackHandler(fallbackHandler);

    setupModules(to, data);

    if (payment > 0) {
        handlePayment(payment, 0, 1, paymentToken, paymentReceiver);
    }
    emit SafeSetup(msg.sender, _owners, _threshold, to, fallbackHandler);
}
```

这里传入的字节码会在 `setupModules(to, data);` 这里调用传入的 data 字节码,但还有 `if (fallbackHandler != address(0)) internalSetFallbackHandler(fallbackHandler);` 就是在调用 setup() 时,如果第五个参数 fallbackHandler 和空地址对不上的话,就会调用 `internalSetFallbackHandler(fallbackHandler)`

`internalSetFallbackHandler(fallbackHandler)`定义在 FallbackManager 合约里,同时这个合约里还有 fallback() 这么个注册钱包的'后门'方法

```js
fallback() external {
    bytes32 slot = FALLBACK_HANDLER_STORAGE_SLOT;
    assembly {
        let handler := sload(slot)
        if iszero(handler) {
            return(0, 0)
        }
        calldatacopy(0, 0, calldatasize())
        mstore(calldatasize(), shl(96, caller()))
        let success := call(gas(), handler, 0, 0, add(calldatasize(), 20), 0, 0)
        returndatacopy(0, 0, returndatasize())
        if iszero(success) {
            revert(0, returndatasize())
        }
        return(0, returndatasize())
    }
}
```

这段 fallback()允许了对 handler 地址上的任何方法调用,注意那奖励的 DVT 本身是在 Safe 钱包上的,而不是 beneficiary 地址上的,如果 fallbackHandler 传入的是 DVT 地址的话,那就意味着将允许钱包本身调用 DVT 上的方法,而且还是以钱包的身份直接进行低级调用,要是调用 DVT 上的 transfer() 就可以直接把钱包里的 DVT 转出来了,那攻击就实现了

**攻击流程**: 调用 walletFactory.createProxyWithCallback() 注册钱包,传入特定设置了调用 setup() 并且 fallbackHandler 参数为 DVT 地址的 data,再对钱包进行 transfer(address,uint256 amount) 调用,直接传 DVT 到指定的 hacker 地址就好了

[完整分析参考](https://stermi.medium.com/damn-vulnerable-defi-challenge-11-solution-backdoor-bc9651a49e22)

这种攻击忽略了 hacker 只进行一次交易的要求,如果只要进行一次交易的话,可以设置两个合约,其中一个合约里部署到另一个合约,而攻击逻辑就在第二个合约的构造函数里,具体看[分析实现](https://dacian.me/damn-vulnerable-defi-backdoor-solution#heading-test-setup-analysis-backdoorchallengejshttpsgithubcomdevdaciandamn-vulnerable-defi-solutionsblobmastertestbackdoorbackdoorchallengejs)

[Solution](./test/backdoor.t.sol)

`forge test --match-path ./test/backdoor.t.sol -vvv`
