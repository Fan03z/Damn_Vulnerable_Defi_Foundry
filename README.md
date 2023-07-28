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
