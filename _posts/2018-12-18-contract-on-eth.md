---
layout: post
title: "基于以太坊发行智能合约"
description: "基于以太坊发行智能合约"
category: all-about-tech
tags: -[ETH] -[BlockChain]
date: 2018-12-18 00:05:57+00:00
---

近两年区块链项目~~比较火~~，特别是各种智能合约。

业余时间学习了相关知识，在这里顺便给大家普及一下以太坊智能合约。

## 同步

众所周知，以太坊所有的数据都是存储在链上的。

所有同步数据的终端都成为一个节点，原则上来讲我们是没有API来直接使用其他节点上面存储的数据。

因此，如果需要通过链上来查询数据、产生交易、发布交易、部署合约这些行为，都需要自己先把整个链上的数据全部同步到本地。

以太坊社区发布了一个使用golang编写的客户端叫做geth，开源地址：<https://github.com/ethereum/go-ethereum/>。使用它可以用来数据同步数据。

#### 安装

这里以OSX为例，下面是使用brew安装geth的命令：

```shell
brew tap ethereum/ethereum
brew install ethereum
```

除了OSX以外，同时geth还支持Windows、Ubuntu、RPI、ARM、Docker等平台。具体见：<https://github.com/ethereum/go-ethereum/wiki/Building-Ethereum>

根据自己的平台尽情使用。

#### 同步数据

通常情况下我们开发软件或者说编写代码的时候，是需要测试的。并且测试通过了，才能够发布。而区块链这个东西有个最大的优点(同时也可以认为是缺点)：一旦产生就无法更改。因此更加需要谨慎了，好在以太网目前支持多种网络。

大致可以分为: [主链](https://etherscan.io/)、私链、[Rinkeby](https://rinkeby.etherscan.io/)、[Ropsten](https://ropsten.etherscan.io/)、[Kovan](https://kovan.etherscan.io/)、Morden(已退役)

同步方法:

```shell
geth --rinkeby --syncmode "fast" \
--cache=1024 --rpc --rpcapi "eth,net,web3,debug" 
```

> 此种方式为同步rinkeby网络数据

![geth --rinkeby](https://i.postimg.cc/PrP4J4TQ/QQ20181205-104645.png)

如截图所示，开始同步之后会显示出各种信息。包括IPC和HTTP通讯地址等，注意这两个信息后面会用到。

#### 创建账户

在以太坊中，一个账户对应着一个地址，所有的操作都是基于地址进行的。因此，在我们进行任何操作之前我们需要创建一个钱包，并且geth能使用。

- 首先进入控制台：

```
# 此方式进入控制台无法创建账户。
geth attach http://127.0.0.1:8545
# 下面这种方式进入是可以创建账户的。
geth attach ipc:~/.ethereum/rinkeby/geth.ipc confolse
```

![](https://i.postimg.cc/jdK41zGQ/QQ20181206-111602.png)

红色标记部分表示当前控制台支持的api模块。

- 使用控制台创建账户

进入控制台之后通过`personal.newAccount("{password}");`命令即可创建账户。

创建之后会立即输出当前账户的地址。并且创建的账户会以文件形式加密存储在当前电脑当中。具体地址是IPC地址所在的文件夹下面的`keystore`文件中。所以我创建的账户的最终地址就是`~/.ethereum/rinkeby/UTC--2018-12-06T03-18-53.085642855Z--da00ff72703fcc97d167696359fc02328508302f`。

同时在控制台可以通过`eth.accounts`列出当前所有的账户。

下图包含了一切：

![](https://i.postimg.cc/sfPp5MvB/QQ20181206-112822.png)

> 如果已经使用其他钱包创建了账户，可以导出keystore直接复制到上面的路径中也可。对账号进行操作的时候需要执行unlock。

```
//personal.unlockAccount(address, password, duration)
personal.unlockAccount('0xda00ff72703fcc97d167696359fc02328508302f', 'af3f15982a1452fdd6b37186c52481ccc95731cd211c751840b8e8389fa05c8a', 360000);
```

## 编写合约

以太坊的链上使用Ethereum Virtual Machine(简称`EVM`)来支持执行智能合约的字节码。目前多种语言支持编译成EVM字节码，可以到<https://github.com/ethereum/wiki/wiki/Ethereum-Virtual-Machine-(EVM)-Awesome-List>查看。

其中，使用最广泛的就是`Solididy`。

关于Solidity语言特性简单介绍一下：

#### 语法

- **继承**

Solidity像其他面向对象的程序语言一样，有类(Solididy里面叫做contract)的概念，并且也是可以继承的。与其他语言不同的是，Solididy里面的contract是可以多重继承的。contract的继承通过关键词`is`完成。

- **函数**

**`声明`**

以`function`进行修饰，支持参数(类似flutter: 在调用时可以{}把参数括起来改变参数顺序)。

Solidity函数支持返回值，一般在函数声明的最后使用`returns`修饰，在函数代码块中使用`return`即可。同时Solididy也像golang等语言一样支持多返回值，如不需要使用某返回值直接置空即可。

例如：

```
function foo(uint count, address user) public returns (address, uint) {
    return (user, count);
}

function bar() public {
    (, count) = foo({user:address(0), count:1});
}
```

**`构造函数`**：

支持参数，类似Kotlin构造函数使用`constructor`关键词修饰就行了。构造函数必须是public的，可以不写public关键词(但是你会得到Warning)。

不同的是，构造函数必须只能声明一个。否则编译时会提示`Error: More than one constructor defined.`

```
constructor(uint count, address user) public{}
```

- **关键词**

**`可见性`**:

1. public

相当于其他函数中的`public`，函数默认声明，不论是合约内部还是合约外部都可以使用。

2. external

与public类似，不同的是它只能外合约外部调用, 合约内部可以使用`this`关键词配合赏味。

3. private

相当于其他函数中的`private`，只有当前合约类内部才可以调用

4. internal

相当于java中的`protected`，合约内部调用。与private不同在于子类可以调用父类中的internal函数。

**`this`**: 

同其他语言不同的话，Solidity中`this`是让函数以外部的方式被调用。也就是说在合约内部以`this.xxx`调用某一个内部函数(private/internal)是不被允许的，等同于当前合约调用另外一个合约中的函数。

例如：

```
function withdraw() onlyOwner payable external {
    this.div();
}
function div() onlyOwner internal {
}
// 错误如下：
contract/BatchTransfer.sol:69:9: Error: Member "div" not found or not visible after argument-dependent lookup in contract BatchTransfer
        this.div();
        ^------^
```

> 尽量不使用this就对了。

**`views`**

可以不经过矿工确认(不用花费任何的gas)，即不能对合约进行写入，但是能直接读取合约的存储。通常，合约某地址的token余额函数(`balanceOf`)就是此关键词修饰的。

**`pure`**

即不能写入也不能读取合约存储内容。适合用来修饰一些纯计算的函数。

```
function add(uint256 x, uint256 y) pure internal returns (uint256 z) {
    assert((z = x + y) >= x);
}
```

- **其他**

Public和External深层次的不同以及更详细的语法/API可以查看文档，地址: <https://solidity.readthedocs.io/en/latest/installing-solidity.html>

#### 合约

理论上在以太坊上面部署任何的可以运行的EVM字节码都可以称作合约。

比如，你写一个合约的作用只有一个：只要有人调用你就返回一个1，也可以称为合约。

如下：

```
pragma solidity ^0.4.23;1
contract Smile {
    function smile() pure public returns (uint) {
        return 1;
    }
}
```

但意义是什么？所以我们来点实际的，看看**之前**~~火热~~的以太坊TOKEN是如何发行的。

绝大多数以太坊的TOKEN是基于ERC20这个协议来实现的，那么只要是基于这个协议实现的，所有的钱包都可以进行查询、转账、委托等行为。

```
contract ERC20 {
    uint256 public totalSupply;

    function balanceOf(address who) view public returns (uint256 value);

    function transfer(address to, uint256 value) public returns (bool ok);

    function approve(address spender, uint256 value) public returns (bool ok);

    function allowance(address owner, address spender) view public returns (uint256 value);

    function transferFrom(address from, address to, uint256 value) public returns (bool ok);

    event Transfer(address indexed from, address indexed to, uint256 value);

    event Approval(address indexed owner, address indexed spender, uint256 value);
}
```

上面的ERC20类就是协议本身，它只是抽象出来的接口。

- totalSupply: 发行的TOKEN总量。
- balanceOf: 用于查询余额。
- transfer: 转账，两个参数分别是收款人地址和收款数。
- approve: 委托某人打理一定数量的TOKEN。
- allowance: 查询委托数量，参数分别是委托人和被委托人。不消耗GAS。
- transferFrom: 从某委托人账户转账。

下面是我实现的一个简单的TOKEN，并且已经部署到rinkeby了。可去浏览：<https://rinkeby.etherscan.io/token/0x08d8468a6b332ff48f7bccd8888e4a660ee42dbb>。

```
pragma solidity ^0.4.23;

library Math {

    function add(uint256 x, uint256 y) pure internal returns (uint256 z) {
        assert((z = x + y) >= x);
    }

    function sub(uint256 x, uint256 y) pure internal returns (uint256 z) {
        assert((z = x - y) <= x);
    }

    function mul(uint256 x, uint256 y) pure internal returns (uint256 z) {
        assert((z = x * y) >= x);
    }

    function div(uint256 x, uint256 y) pure internal returns (uint256 z) {
        assert((z = x / y) <= x);
    }
}

contract SimpleToken is ERC20 {
    using Math for uint256;

    //

    event Transfer(address indexed _from, address indexed _to, uint256 _value);
    event Approval(address indexed _owner, address indexed _spender, uint256 _value);
    event Burn(address indexed burner, uint256 value);

    //

    mapping(address => uint256) public balances;
    mapping(address => mapping(address => uint256)) public allowed;

    function balanceOf(address _address) view public returns (uint256) {
        return balances[_address];
    }

    function transfer(address _to, uint256 _amount) public returns (bool success) {
        require(msg.sender != 0);
        require(_amount <= balances[msg.sender]);

        balances[msg.sender] = balances[msg.sender].sub(_amount);
        balances[_to] = balances[_to].add(_amount);
        emit Transfer(msg.sender, _to, _amount);
        return true;
    }

    function transferFrom(address _from, address _to, uint256 _amount) public returns (bool success) {
        require(_from != 0);
        require(_amount <= balances[_from]);
        require(_amount <= allowed[_from][msg.sender]);

        balances[_from] = balances[_from].sub(_amount);
        allowed[_from][msg.sender] = allowed[_from][msg.sender].sub(_amount);
        balances[_to] = balances[_to].add(_amount);
        emit Transfer(_from, _to, _amount);
        return true;
    }

    function approve(address _spender, uint256 _value) public returns (bool success) {
        require(msg.sender != 0);
        if (_value == allowed[msg.sender][_spender]) {return false;}
        allowed[msg.sender][_spender] = _value;
        emit Approval(msg.sender, _spender, _value);
        return true;
    }

    function allowance(address _owner, address _spender) view public returns (uint256) {
        return allowed[_owner][_spender];
    }
}

contract Owner {
    address public owner;

    constructor() public {owner = msg.sender;}

    modifier onlyOwner {
        require(
            msg.sender == owner,
            "Only owner can call this function."
        );
        _;
    }

    function transferOwnership(address _newOwner) onlyOwner public {
        if (_newOwner != address(0)) {owner = _newOwner;}
    }
}

contract QHT is SimpleToken, Owner {

    string public constant name = "qihutoken";
    string public constant symbol = "QHT";
    uint public constant decimals = 18;

    uint256 public totalSupply = 31415926e18;

    constructor() public { balances[owner] = 100e18; }
}
```

> 以上代码测试使用仅作参考。涉及到安全问题以及复杂的封装请参考**openzeppelin-solidity**

- name: TOKEN的名字。
- symbol: TOKEN的符号。
- decimals: 是最小可分位数，意思是1Token最小可以分成10的{{decimals}}次方分之1。注意totalSupply后面应该加上{{decimals}}个0。

## 部署

以太坊目前提供了多种方式来进行合约部署，这里用相对原始的方式来进行部署。

部署是需要消耗GAS的，也就是对应的ETH的，在测试网络可以 <https://faucet.rinkeby.io/> 按照规则领取测试用的ETH。费用计算方式为: `gas * gasPrice`。

#### 基于solc

solc是使用C++实现的Solidity编译器，编译速度相对而言比较高效。

- 安装：

以osx为例：

```
brew upgrade
brew tap ethereum/ethereum
brew install solidity
brew linkapps solidity
```

- 编译：solc {{file}} --overwrite --optimize --bin --abi -o build

> - --bin --abi 分别表示输出deploybytecode和abi。
> - --optimize (默认关闭) 开启编译器优化，可以有效降低字节码大小。直接降低部署成本。如果使用truffle的话, 记得在配置中添加这个参数.

![](https://i.postimg.cc/90n1RBPq/sc-20181206-185320.png)

这里其实会把所有的contract都给编译出来，我们只要找到自己需要的合约即可。比如我要部署的合约是QHT。那么只要`QHT.abi`和`QHT.bin`这个文件就行。

- 部署：

`web3.eth.contract(${abi}).new({from: ${address}, gas:${limit}, gasPrice:${price}, data:${deploy_bytecode}})`

下面是具体的部署代码：

注意：下面操作都是在console里面完成，在操作之前按照上面方法把相应账号解锁。

```js
var dabi = [{"constant":true,"inputs":[],"name":"name","outputs":[{"name":"","type":"string"}],"payable":false,"stateMutability":"view","type":"function"},{"constant":false,"inputs":[{"name":"_spender","type":"address"},{"name":"_value","type":"uint256"}],"name":"approve","outputs":[{"name":"success","type":"bool"}],"payable":false,"stateMutability":"nonpayable","type":"function"},{"constant":true,"inputs":[],"name":"totalSupply","outputs":[{"name":"","type":"uint256"}],"payable":false,"stateMutability":"view","type":"function"},{"constant":false,"inputs":[{"name":"_from","type":"address"},{"name":"_to","type":"address"},{"name":"_amount","type":"uint256"}],"name":"transferFrom","outputs":[{"name":"success","type":"bool"}],"payable":false,"stateMutability":"nonpayable","type":"function"},{"constant":true,"inputs":[{"name":"","type":"address"}],"name":"balances","outputs":[{"name":"","type":"uint256"}],"payable":false,"stateMutability":"view","type":"function"},{"constant":true,"inputs":[],"name":"decimals","outputs":[{"name":"","type":"uint256"}],"payable":false,"stateMutability":"view","type":"function"},{"constant":true,"inputs":[{"name":"","type":"address"},{"name":"","type":"address"}],"name":"allowed","outputs":[{"name":"","type":"uint256"}],"payable":false,"stateMutability":"view","type":"function"},{"constant":true,"inputs":[{"name":"_address","type":"address"}],"name":"balanceOf","outputs":[{"name":"","type":"uint256"}],"payable":false,"stateMutability":"view","type":"function"},{"constant":true,"inputs":[],"name":"owner","outputs":[{"name":"","type":"address"}],"payable":false,"stateMutability":"view","type":"function"},{"constant":true,"inputs":[],"name":"symbol","outputs":[{"name":"","type":"string"}],"payable":false,"stateMutability":"view","type":"function"},{"constant":false,"inputs":[{"name":"_to","type":"address"},{"name":"_amount","type":"uint256"}],"name":"transfer","outputs":[{"name":"success","type":"bool"}],"payable":false,"stateMutability":"nonpayable","type":"function"},{"constant":true,"inputs":[{"name":"_owner","type":"address"},{"name":"_spender","type":"address"}],"name":"allowance","outputs":[{"name":"","type":"uint256"}],"payable":false,"stateMutability":"view","type":"function"},{"constant":false,"inputs":[{"name":"_newOwner","type":"address"}],"name":"transferOwnership","outputs":[],"payable":false,"stateMutability":"nonpayable","type":"function"},{"inputs":[],"payable":false,"stateMutability":"nonpayable","type":"constructor"},{"anonymous":false,"inputs":[{"indexed":true,"name":"_from","type":"address"},{"indexed":true,"name":"_to","type":"address"},{"indexed":false,"name":"_value","type":"uint256"}],"name":"Transfer","type":"event"},{"anonymous":false,"inputs":[{"indexed":true,"name":"_owner","type":"address"},{"indexed":true,"name":"_spender","type":"address"},{"indexed":false,"name":"_value","type":"uint256"}],"name":"Approval","type":"event"},{"anonymous":false,"inputs":[{"indexed":true,"name":"burner","type":"address"},{"indexed":false,"name":"value","type":"uint256"}],"name":"Burn","type":"event"}];
var dbin = '0x60806040526a19fc94c2d06261e018000060045534801561001f57600080fd5b5033600360006101000a81548173ffffffffffffffffffffffffffffffffffffffff021916908373ffffffffffffffffffffffffffffffffffffffff16021790555068056bc75e2d6310000060016000600360009054906101000a900473ffffffffffffffffffffffffffffffffffffffff1673ffffffffffffffffffffffffffffffffffffffff1673ffffffffffffffffffffffffffffffffffffffff16815260200190815260200160002081905550611095806100df6000396000f3006080604052600436106100c5576000357c0100000000000000000000000000000000000000000000000000000000900463ffffffff16806306fdde03146100ca578063095ea7b31461015a57806318160ddd146101bf57806323b872dd146101ea57806327e235e31461026f578063313ce567146102c65780635c658165146102f157806370a08231146103685780638da5cb5b146103bf57806395d89b4114610416578063a9059cbb146104a6578063dd62ed3e1461050b578063f2fde38b14610582575b600080fd5b3480156100d657600080fd5b506100df6105c5565b6040518080602001828103825283818151815260200191508051906020019080838360005b8381101561011f578082015181840152602081019050610104565b50505050905090810190601f16801561014c5780820380516001836020036101000a031916815260200191505b509250505060405180910390f35b34801561016657600080fd5b506101a5600480360381019080803573ffffffffffffffffffffffffffffffffffffffff169060200190929190803590602001909291905050506105fe565b604051808215151515815260200191505060405180910390f35b3480156101cb57600080fd5b506101d46107a3565b6040518082815260200191505060405180910390f35b3480156101f657600080fd5b50610255600480360381019080803573ffffffffffffffffffffffffffffffffffffffff169060200190929190803573ffffffffffffffffffffffffffffffffffffffff169060200190929190803590602001909291905050506107a9565b604051808215151515815260200191505060405180910390f35b34801561027b57600080fd5b506102b0600480360381019080803573ffffffffffffffffffffffffffffffffffffffff169060200190929190505050610b52565b6040518082815260200191505060405180910390f35b3480156102d257600080fd5b506102db610b6a565b6040518082815260200191505060405180910390f35b3480156102fd57600080fd5b50610352600480360381019080803573ffffffffffffffffffffffffffffffffffffffff169060200190929190803573ffffffffffffffffffffffffffffffffffffffff169060200190929190505050610b6f565b6040518082815260200191505060405180910390f35b34801561037457600080fd5b506103a9600480360381019080803573ffffffffffffffffffffffffffffffffffffffff169060200190929190505050610b94565b6040518082815260200191505060405180910390f35b3480156103cb57600080fd5b506103d4610bdd565b604051808273ffffffffffffffffffffffffffffffffffffffff1673ffffffffffffffffffffffffffffffffffffffff16815260200191505060405180910390f35b34801561042257600080fd5b5061042b610c03565b6040518080602001828103825283818151815260200191508051906020019080838360005b8381101561046b578082015181840152602081019050610450565b50505050905090810190601f1680156104985780820380516001836020036101000a031916815260200191505b509250505060405180910390f35b3480156104b257600080fd5b506104f1600480360381019080803573ffffffffffffffffffffffffffffffffffffffff16906020019092919080359060200190929190505050610c3c565b604051808215151515815260200191505060405180910390f35b34801561051757600080fd5b5061056c600480360381019080803573ffffffffffffffffffffffffffffffffffffffff169060200190929190803573ffffffffffffffffffffffffffffffffffffffff169060200190929190505050610e4a565b6040518082815260200191505060405180910390f35b34801561058e57600080fd5b506105c3600480360381019080803573ffffffffffffffffffffffffffffffffffffffff169060200190929190505050610ed1565b005b6040805190810160405280600981526020017f71696875746f6b656e000000000000000000000000000000000000000000000081525081565b6000803373ffffffffffffffffffffffffffffffffffffffff161415151561062557600080fd5b600260003373ffffffffffffffffffffffffffffffffffffffff1673ffffffffffffffffffffffffffffffffffffffff16815260200190815260200160002060008473ffffffffffffffffffffffffffffffffffffffff1673ffffffffffffffffffffffffffffffffffffffff168152602001908152602001600020548214156106b2576000905061079d565b81600260003373ffffffffffffffffffffffffffffffffffffffff1673ffffffffffffffffffffffffffffffffffffffff16815260200190815260200160002060008573ffffffffffffffffffffffffffffffffffffffff1673ffffffffffffffffffffffffffffffffffffffff168152602001908152602001600020819055508273ffffffffffffffffffffffffffffffffffffffff163373ffffffffffffffffffffffffffffffffffffffff167f8c5be1e5ebec7d5bd14f71427d1e84f3dd0314c0f7b2291e5b200ac8c7c3b925846040518082815260200191505060405180910390a3600190505b92915050565b60045481565b6000808473ffffffffffffffffffffffffffffffffffffffff16141515156107d057600080fd5b600160008573ffffffffffffffffffffffffffffffffffffffff1673ffffffffffffffffffffffffffffffffffffffff16815260200190815260200160002054821115151561081e57600080fd5b600260008573ffffffffffffffffffffffffffffffffffffffff1673ffffffffffffffffffffffffffffffffffffffff16815260200190815260200160002060003373ffffffffffffffffffffffffffffffffffffffff1673ffffffffffffffffffffffffffffffffffffffff1681526020019081526020016000205482111515156108a957600080fd5b6108fb82600160008773ffffffffffffffffffffffffffffffffffffffff1673ffffffffffffffffffffffffffffffffffffffff1681526020019081526020016000205461103790919063ffffffff16565b600160008673ffffffffffffffffffffffffffffffffffffffff1673ffffffffffffffffffffffffffffffffffffffff168152602001908152602001600020819055506109cd82600260008773ffffffffffffffffffffffffffffffffffffffff1673ffffffffffffffffffffffffffffffffffffffff16815260200190815260200160002060003373ffffffffffffffffffffffffffffffffffffffff1673ffffffffffffffffffffffffffffffffffffffff1681526020019081526020016000205461103790919063ffffffff16565b600260008673ffffffffffffffffffffffffffffffffffffffff1673ffffffffffffffffffffffffffffffffffffffff16815260200190815260200160002060003373ffffffffffffffffffffffffffffffffffffffff1673ffffffffffffffffffffffffffffffffffffffff16815260200190815260200160002081905550610a9f82600160008673ffffffffffffffffffffffffffffffffffffffff1673ffffffffffffffffffffffffffffffffffffffff1681526020019081526020016000205461105090919063ffffffff16565b600160008573ffffffffffffffffffffffffffffffffffffffff1673ffffffffffffffffffffffffffffffffffffffff168152602001908152602001600020819055508273ffffffffffffffffffffffffffffffffffffffff168473ffffffffffffffffffffffffffffffffffffffff167fddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef846040518082815260200191505060405180910390a3600190509392505050565b60016020528060005260406000206000915090505481565b601281565b6002602052816000526040600020602052806000526040600020600091509150505481565b6000600160008373ffffffffffffffffffffffffffffffffffffffff1673ffffffffffffffffffffffffffffffffffffffff168152602001908152602001600020549050919050565b600360009054906101000a900473ffffffffffffffffffffffffffffffffffffffff1681565b6040805190810160405280600381526020017f514854000000000000000000000000000000000000000000000000000000000081525081565b6000803373ffffffffffffffffffffffffffffffffffffffff1614151515610c6357600080fd5b600160003373ffffffffffffffffffffffffffffffffffffffff1673ffffffffffffffffffffffffffffffffffffffff168152602001908152602001600020548211151515610cb157600080fd5b610d0382600160003373ffffffffffffffffffffffffffffffffffffffff1673ffffffffffffffffffffffffffffffffffffffff1681526020019081526020016000205461103790919063ffffffff16565b600160003373ffffffffffffffffffffffffffffffffffffffff1673ffffffffffffffffffffffffffffffffffffffff16815260200190815260200160002081905550610d9882600160008673ffffffffffffffffffffffffffffffffffffffff1673ffffffffffffffffffffffffffffffffffffffff1681526020019081526020016000205461105090919063ffffffff16565b600160008573ffffffffffffffffffffffffffffffffffffffff1673ffffffffffffffffffffffffffffffffffffffff168152602001908152602001600020819055508273ffffffffffffffffffffffffffffffffffffffff163373ffffffffffffffffffffffffffffffffffffffff167fddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef846040518082815260200191505060405180910390a36001905092915050565b6000600260008473ffffffffffffffffffffffffffffffffffffffff1673ffffffffffffffffffffffffffffffffffffffff16815260200190815260200160002060008373ffffffffffffffffffffffffffffffffffffffff1673ffffffffffffffffffffffffffffffffffffffff16815260200190815260200160002054905092915050565b600360009054906101000a900473ffffffffffffffffffffffffffffffffffffffff1673ffffffffffffffffffffffffffffffffffffffff163373ffffffffffffffffffffffffffffffffffffffff16141515610fbc576040517f08c379a00000000000000000000000000000000000000000000000000000000081526004018080602001828103825260228152602001807f4f6e6c79206f776e65722063616e2063616c6c20746869732066756e6374696f81526020017f6e2e00000000000000000000000000000000000000000000000000000000000081525060400191505060405180910390fd5b600073ffffffffffffffffffffffffffffffffffffffff168173ffffffffffffffffffffffffffffffffffffffff161415156110345780600360006101000a81548173ffffffffffffffffffffffffffffffffffffffff021916908373ffffffffffffffffffffffffffffffffffffffff1602179055505b50565b6000828284039150811115151561104a57fe5b92915050565b6000828284019150811015151561106357fe5b929150505600a165627a7a72305820ec3dd240e50fbcf8c00637b8de743574fdf57299547a5ac3b3e74803db5156ff0029';
// 创建合约
web3.eth.contract(dabi).new({from: '0xda00ff72703fcc97d167696359fc02328508302f', gas:40e5, gasPrice:10e9, data:dbin});
```

其中:

- `dabi`变量的值就是`QHT.abi`中的内容.

- `dbin`就是`QHT.bin`中的内容, 注意:如果不是以`0x`开头, 则需要像上面一样手动添加`0x`. 否则无法部署.

执行之后会在geth的log里面显示出当前交易的hash以及合约地址：

![](https://i.postimg.cc/brWHNw8x/sc-20181206-190502.png)

如果，想可视化查看自己的交易的话，复制交易的hash(txid)可以去<http://etherscan.io>查看。比如: <https://rinkeby.etherscan.io/tx/0x1202c13e701d4d0a64e7b810161e4cd84de6860d34abd72efaf4d4e542cac0f0>

还有多种部署方式，比如remix和truffle：

##### remix

参见：[remix](https://remix.ethereum.org/)

##### truffle

- 安装：npm install -g truffle

- 编译：truffle compile 

- 部署：truffle migrate

> truffle需要配合 geth rpc，具体使用参见: <https://github.com/trufflesuite/truffle>

不喜欢折腾的直接使用remix吧.

## 操作

对于已经部署了的合约, 是可以直接对这个合约进行操作的.比如调用其中声明的函数/变量等等.

下面对刚才部署的合约进行操作。

#### 标准erc20的abi

如果你发行的是一个ERC20协议的合约，那么使用标准的ERC20的abi是可以执行标准接口的。

下面提供了一份标准ERC20的abi， 以及其他会只使用到的相关变量，其中使用到的token和以太坊地址均是我自己测试使用的, 请改成自己的。

```js
var token = '0x08d8468a6b332ff48f7bccd8888e4a660ee42dbb'; // 合约地址
var addr1 = '0xda00ff72703fcc97d167696359fc02328508302f'; // 地址1
var addr2 = '0x767976f6b20655243bba20497fcd8d9f4eb4ee39'; // 地址2
var addr3 = '0xd1ab0a8ffb68b076de20f06def43964748a7854a'; // 地址3
eth.gasPrice = 11e9; // 设定操作的gasPrice, 11e9表示11gwei, 最小1gwei, 越大越快
web3.eth.defaultAccount = addr1; // 需要设定默认账户，操作时不填写账户，则使用次默认账户。
var std_abi = [{"constant":true,"inputs":[],"name":"name","outputs":[{"name":"","type":"string"}],"payable":false,"type":"function"},{"constant":false,"inputs":[{"name":"_spender","type":"address"},{"name":"_value","type":"uint256"}],"name":"approve","outputs":[{"name":"success","type":"bool"}],"payable":false,"type":"function"},{"constant":true,"inputs":[],"name":"totalSupply","outputs":[{"name":"","type":"uint256"}],"payable":false,"type":"function"},{"constant":false,"inputs":[{"name":"_from","type":"address"},{"name":"_to","type":"address"},{"name":"_value","type":"uint256"}],"name":"transferFrom","outputs":[{"name":"success","type":"bool"}],"payable":false,"type":"function"},{"constant":true,"inputs":[],"name":"decimals","outputs":[{"name":"","type":"uint8"}],"payable":false,"type":"function"},{"constant":true,"inputs":[],"name":"version","outputs":[{"name":"","type":"string"}],"payable":false,"type":"function"},{"constant":true,"inputs":[{"name":"_owner","type":"address"}],"name":"balanceOf","outputs":[{"name":"balance","type":"uint256"}],"payable":false,"type":"function"},{"constant":true,"inputs":[],"name":"symbol","outputs":[{"name":"","type":"string"}],"payable":false,"type":"function"},{"constant":false,"inputs":[{"name":"_to","type":"address"},{"name":"_value","type":"uint256"}],"name":"transfer","outputs":[{"name":"success","type":"bool"}],"payable":false,"type":"function"},{"constant":false,"inputs":[{"name":"_spender","type":"address"},{"name":"_value","type":"uint256"},{"name":"_extraData","type":"bytes"}],"name":"approveAndCall","outputs":[{"name":"success","type":"bool"}],"payable":false,"type":"function"},{"constant":true,"inputs":[{"name":"_owner","type":"address"},{"name":"_spender","type":"address"}],"name":"allowance","outputs":[{"name":"remaining","type":"uint256"}],"payable":false,"type":"function"},{"inputs":[{"name":"_initialAmount","type":"uint256"},{"name":"_tokenName","type":"string"},{"name":"_decimalUnits","type":"uint8"},{"name":"_tokenSymbol","type":"string"}],"type":"constructor"},{"payable":false,"type":"fallback"},{"anonymous":false,"inputs":[{"indexed":true,"name":"_from","type":"address"},{"indexed":true,"name":"_to","type":"address"},{"indexed":false,"name":"_value","type":"uint256"}],"name":"Transfer","type":"event"},{"anonymous":false,"inputs":[{"indexed":true,"name":"_owner","type":"address"},{"indexed":true,"name":"_spender","type":"address"},{"indexed":false,"name":"_value","type":"uint256"}],"name":"Approval","type":"event"}];

// 获取合约对象
var stdStoken = web3.eth.contract(std_abi).at(token);
```

#### 余额

```js
stdStoken.balanceOf(addr1);
```

或者(自己封装，通过geth exec不用进入attach)：

```shell
geth_stdtoken 0x08d8468a6b332ff48f7bccd8888e4a660ee42dbb \
'contract.balanceOf(0x90e8fead8b2325562e6678328908b5702c222c61)'
```

下面以两种方式显示查询出来的余额：

```
> stdStoken.balanceOf(addr1);
100000000000000000000
> web3.fromWei(stdStoken.balanceOf(addr1))
100
```

- 第一个：结果是100000000000000000000(100后面18个0)，表示100个Token。可以跟上面的decimals=18联系起来。
- 第二个：就是100，因为以太坊本身默认的decimals是18位，刚好跟我们的一致。因此可以直接使用以太坊的最小单位(Wei)来进行转化。

#### 转账

从默认账户转1个TOKEN到addr2:

```js
stdStoken.transfer(addr2, 1e18);
```

#### 委托转账

- 设定委托数量 

默认账户(addr1)委托addr2管理14个TOKEN:

```js
stdStoken.approve(addr2, 14e18);
```

- 查询委托数量

```js
stdStoken.allowance(addr1, addr2);
```

- 执行委托转账

使用账户addr2从addr1的账户中转1个TOKEN给addr3

```js
web3.eth.defaultAccount = addr2; // 修改默认账户为address2
web3.eth.contract(std_abi).at(token).transferFrom(addr1, addr3, 1e18);
web3.eth.defaultAccount = addr1;
```

#### 修改账户

下面提供两种方式从某账户转账给addr2：

```js
web3.eth.contract(std_abi).at(token).transfer(addr2, 1e18);
web3.eth.contract(std_abi).at(token).transfer.sendTransaction(addr2, 1e18, {from:addr1, gasPrice:10e9});
```

第一种就是使用默认账户。

第二种是转账时自己填写了`from:addr1`。注意查看跟上面的不同。

## 其他

Android可以安装Toshi用测试网络的token进行转账等测试。

Toshi-4.2.apk下载地址：<https://pan.baidu.com/s/1v22-A8Mfc04uIINe0hllpQ>

部分参考链接:

<https://github.com/ethereum/go-ethereum/>

<https://github.com/OpenZeppelin/openzeppelin-solidity>

<http://me.tryblockchain.org/solidity-function-advanced1.html>

<https://gist.github.com/hyongbai/71daff50abd0a5708371c54d15894c27>

<https://rinkeby.etherscan.io/address/0x767976f6b20655243bba20497fcd8d9f4eb4ee39>

<https://rinkeby.etherscan.io/token/0x08d8468a6b332ff48f7bccd8888e4a660ee42dbb#balances>

> ~~没想到财富自由如此简单~~ (请合规合法合理合情使用区块链)