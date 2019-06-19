---
layout: post
title: "libra简单上手"
description: "facebook libra intro"
category: all-about-tech
tags: -[blockchain]
date: 2019-06-19 14:05:57+00:00
---

## 安装libra环境

#### 下载源码

git clone https://github.com/libra/libra.git && cd libra

#### 安装依赖

./scripts/dev_setup.sh

![libra-tutorial-dev-setup.png](http://t.cn/AiNm8tzC)

#### 运行测试网络

./scripts/cli/start_cli_testnet.sh

这个脚本其实只是简单封装，最终还是调用cargo这个命令进入console:

```bash
source "$HOME/.cargo/env"

SCRIPT_PATH="$(dirname $0)"

RUN_PARAMS="--host ac.testnet.libra.org --port 80 -s $SCRIPT_PATH/trusted_peers.config.toml"

case $1 in
    -h | --help)
        print_help;exit 0;;
    -r | --release)
        echo "Building and running client in release mode."
        cargo run -p client --release -- $RUN_PARAMS
        ;;
    '')
        echo "Building and running client in debug mode."
        cargo run -p client -- $RUN_PARAMS
        ;;
    *) echo "Invalid option"; print_help; exit 0;
esac
```

看到如下界面就说明，你的libra环境到此就安装成功了。

![libra-tutorial-dev-start-testnet.png](http://t.cn/AiNmRymx)

## 交易

cargo相对于geth而言方便太多了。

#### 创建账户

比如创建账户，你只需要执行如下代码即可：

```
account create
```

会有如下输出：

```
libra% account create
>> Creating/retrieving next account from wallet
Created/retrieved account #0 address 9f34057fe65d688308b6e0000e52c82185b2e0abccf22b27edd2ce89********
```

更方便的是你可以使用`a create`来代替`account create`，其实这还不是最方便的。更丧心病狂的是你可以使用`a c`来代替`a create`

也就是说，在libra的console中，命令都可以像简写。你甚至可以只写命令的首字母即可。

> 注：并非所有指令都可以只输入一个字母。比如：`account list`用来列出当前所有账户，你不可以使用`a l`来代替，但是可以使用`a la`。

下面创建两个账户，并列出当前设备所有账户：

```
libra% a c
>> Creating/retrieving next account from wallet
Created/retrieved account #3 address 056d48eed959d7c62c13e7b200cad5b49ee9f49e2d0009550352a25f********
libra% a c
>> Creating/retrieving next account from wallet
Created/retrieved account #4 address e947b86a943064799758c8c13986e7a39c02d30df8e74493b398cdbd********
libra% a la
User account index: 0, address: 9f34057fe65d688308b6e0000e52c82185b2e0abccf22b27edd2ce89********, sequence number: 0, status: Local
User account index: 1, address: cf1bd27eb1398c9abead6129f7a85ff1b80882fe9412e5a3d5635f76********, sequence number: 0, status: Local
User account index: 2, address: def84944e21b82cc36425eca7ffcda8f332787ed77b122475c0d1bbd********, sequence number: 0, status: Local
User account index: 3, address: 056d48eed959d7c62c13e7b200cad5b49ee9f49e2d0009550352a25f********, sequence number: 0, status: Local
User account index: 4, address: e947b86a943064799758c8c13986e7a39c02d30df8e74493b398cdbd********, sequence number: 0, status: Local
libra%
```

简单说下，index后面的数字表示账户的index(废话)，address后面那一串字符是账户的地址。index有个用处，就是可以在`当前console`中替代交易地址。

#### 添加余额

上面我们创建了5个账户。但是，这些账户中默认都是没有余额的。不信你看:

```
libra% q b e947b86a943064799758c8c13986e7a39c02d30df8e74493b398cdbdb6bc7b8f
Balance is: 0
libra% q b 4
Balance is: 0
```

index为4的账户(e947b86a943064799758c8c13986e7a39c02d30df8e74493b398cdbdb6bc7b8f)余额为空。

> 注：`q b`是`query balance`的缩写，意为获取余额。

account中提供了mint指令，mint本身除了薄荷还有铸币厂的意思。

```
libra% a m 4 100
>> Minting coins
Mint request submitted
libra% q b 4
Balance is: 100
libra% q b e947b86a943064799758c8c13986e7a39c02d30df8e74493b398cdbdb6bc7b8f
Balance is: 100
```

`Mint request submitted`表示成功加入`mempool`。

> 注：`a m`是`account mint`的缩写。

#### 创建交易

我们打算从账户4往账户3里面转88个币。可以使用transfer这个参数(可以简称为t)。

```
libra% t 4 3 88
>> Transferring
Transaction submitted to validator
To query for transaction status, run: query txn_acc_seq 4 0 <fetch_events=true|false>
libra% q b 4
Balance is: 12
libra% q b 3
Balance is: 88
```

在测试网络中转账速度很快就完成了。正常情况下，我们可以需要区块链上面的节点验证通过才算转账成功，这取决于你本机的硬件情况网络情况等等。因此就需要查看转账状态。如下：

```
libra% q ts 4 0 true
>> Getting committed transaction by account and sequence number
Committed transaction: SignedTransaction {
 raw_txn: RawTransaction {
    sender: e947b86a943064799758c8c13986e7a39c02d30df8e74493b398cdbdb6bc7b8f,
    sequence_number: 0,
    payload: {,
        transaction: peer_to_peer_transaction,
        args: [
            {ADDRESS: 056d48eed959d7c62c13e7b200cad5b49ee9f49e2d0009550352a25f8d9b3c73},
            {U64: 88000000},
        ]
    },
    max_gas_amount: 10000,
    gas_unit_price: 0,
    expiration_time: 1560931898s,
},
 public_key: b4ab2f7a1abbad75774d1cd221c285fc1433b4c552b5f75dbe71afd68ea3e6bf,
 signature: Signature( R: CompressedEdwardsY: [162, 34, 108, 206, 37, 157, 103, 221, 123, 147, 71, 34, 169, 241, 140, 173, 48, 105, 18, 72, 45, 195, 107, 85, 25, 140, 79, 187, 171, 189, 192, 32], s: Scalar{
    bytes: [164, 38, 217, 175, 33, 70, 103, 215, 187, 162, 191, 164, 237, 19, 102, 180, 229, 222, 42, 245, 30, 95, 61, 131, 26, 227, 91, 109, 220, 131, 75, 3],
} ),
 }
Events:
ContractEvent { access_path: AccessPath { address: e947b86a943064799758c8c13986e7a39c02d30df8e74493b398cdbdb6bc7b8f, type: Resource, hash: "217da6c6b3e19f1825cfb2676daecce3bf3de03cf26647c78df00b371b25cc97", suffix: "/sent_events_count/" } , index: 0, event_data: AccountEvent { account: 056d48eed959d7c62c13e7b200cad5b49ee9f49e2d0009550352a25f8d9b3c73, amount: 88000000 } }
ContractEvent { access_path: AccessPath { address: 056d48eed959d7c62c13e7b200cad5b49ee9f49e2d0009550352a25f8d9b3c73, type: Resource, hash: "217da6c6b3e19f1825cfb2676daecce3bf3de03cf26647c78df00b371b25cc97", suffix: "/received_events_count/" } , index: 0, event_data: AccountEvent { account: e947b86a943064799758c8c13986e7a39c02d30df8e74493b398cdbdb6bc7b8f, amount: 88000000 } }
```

其中`q ts`后面第一个参数为地址，后一个参数为交易的sequence_number，最后一个表示是否查看event。

可以看到：

- libra中交易是需要gas的，max_gas_amount和gas_unit_price分别表示gas数量和gas单价。是不是很眼熟！
- 有过期时间，猜测是类似于网络请求中的timeout，即超时时间。
- 88个libra表示为`U64: 88000000`。也就是说libra本身不是最小单位。可以切分为1/100000，即十万分之一。猜测：libra的价格不可能会超过1000刀，理论上在网站购物是可能会存在0.01刀的价格的。目前还不太清楚libra的单位，纯假设。

下面为event为false的结果：

```
libra% q ts 4 0 false
>> Getting committed transaction by account and sequence number
Committed transaction: SignedTransaction {
 raw_txn: RawTransaction {
    sender: e947b86a943064799758c8c13986e7a39c02d30df8e74493b398cdbdb6bc7b8f,
    sequence_number: 0,
    payload: {,
        transaction: peer_to_peer_transaction,
        args: [
            {ADDRESS: 056d48eed959d7c62c13e7b200cad5b49ee9f49e2d0009550352a25f8d9b3c73},
            {U64: 88000000},
        ]
    },
    max_gas_amount: 10000,
    gas_unit_price: 0,
    expiration_time: 1560931898s,
},
 public_key: b4ab2f7a1abbad75774d1cd221c285fc1433b4c552b5f75dbe71afd68ea3e6bf,
 signature: Signature( R: CompressedEdwardsY: [162, 34, 108, 206, 37, 157, 103, 221, 123, 147, 71, 34, 169, 241, 140, 173, 48, 105, 18, 72, 45, 195, 107, 85, 25, 140, 79, 187, 171, 189, 192, 32], s: Scalar{
    bytes: [164, 38, 217, 175, 33, 70, 103, 215, 187, 162, 191, 164, 237, 19, 102, 180, 229, 222, 42, 245, 30, 95, 61, 131, 26, 227, 91, 109, 220, 131, 75, 3],
} ),
 }
```

> 注:`q ts`为`query txn_acc_seq`的缩写。

最后看一下各个账户的余额：

```
libra% q b 4
Balance is: 12
libra% q b 3
Balance is: 88
```

交易过程大概是这样的：买

![Lifecycle of the Transaction](https://developers.libra.org/docs/assets/illustrations/validator-sequence.svg)

#### 查看账户

转账完成之后，我们再来查看账户的完整信息。如下：

```
libra% q as 4
>> Getting latest account state
Latest account state is:
 Account: e947b86a943064799758c8c13986e7a39c02d30df8e74493b398cdbdb6bc7b8f
 State: Some(
    AccountStateBlob {
     Raw: 0x010000002100000001217da6c6b3e19f1825cfb2676daecce3bf3de03cf26647c78df00b371b25cc974400000020000000e947b86a943064799758c8c13986e7a39c02d30df8e74493b398cdbdb6bc7b8f001bb70000000000000000000000000001000000000000000100000000000000
     Decoded: Ok(
        AccountResource {
            balance: 12000000,
            sequence_number: 1,
            authentication_key: 0xe947b86a943064799758c8c13986e7a39c02d30df8e74493b398cdbd********,
            sent_events_count: 1,
            received_events_count: 0,
        },
    )
     },
)
 Blockchain Version: 17062
```

在这里可以看到`balance`和`sequence_number`等等。

## 其他

index只能是本地存在的账户才有笑，并且index是从0开始的。如果想查询其他账户的余额，那么就需要提供完整的地址了。

比如我想要在本机查询facebook官方demo中提供的地址的余额的话，就需要如下方法了：

```
libra% q b 3ed8e5fafae4147b2a105a0be2f81972883441cfaaadf93fc0868e7a0253c4a8
Balance is: 53
libra% q as 3ed8e5fafae4147b2a105a0be2f81972883441cfaaadf93fc0868e7a0253c4a8
>> Getting latest account state
Latest account state is:
 Account: 3ed8e5fafae4147b2a105a0be2f81972883441cfaaadf93fc0868e7a0253c4a8
 State: Some(
    AccountStateBlob {
     Raw: 0x010000002100000001217da6c6b3e19f1825cfb2676daecce3bf3de03cf26647c78df00b371b25cc9744000000200000003ed8e5fafae4147b2a105a0be2f81972883441cfaaadf93fc0868e7a0253c4a840b7280300000000010000000000000000000000000000000000000000000000
     Decoded: Ok(
        AccountResource {
            balance: 53000000,
            sequence_number: 0,
            authentication_key: 0x3ed8e5fafae4147b2a105a0be2f81972883441cfaaadf93fc0868e7a0253c4a8,
            sent_events_count: 0,
            received_events_count: 1,
        },
    )
     },
)
 Blockchain Version: 17213
```

## 参考

- <https://developers.libra.org/>
- <https://developers.libra.org/docs/my-first-transaction>