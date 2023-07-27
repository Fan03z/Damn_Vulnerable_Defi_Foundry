# Damn Vulnerable Defi

Damn Vulnerable Defi 是款针对合约安全审计的 wargame

此 repo 是针对 Damn Vulnerable DeFi 在 foundry 上的解决方案

1. [Unstoppable](#unstoppable)

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

[官方地址](https://www.damnvulnerabledefi.xyz/)
