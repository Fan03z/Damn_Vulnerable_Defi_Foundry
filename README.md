# Damn Vulnerable Defi

[Damn Vulnerable Defi](https://www.damnvulnerabledefi.xyz/) 是款针对在 Defi 领域合约安全审计的 wargame

此 repo 是针对 Damn Vulnerable DeFi 在 foundry 上的解决方案

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
