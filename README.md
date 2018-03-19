### Disclaimer

Don't use with your actual seed. This is experimental work and **should not** be trusted to work in a production environment. This is intended only for programmers that can understand the code and it's implications.



## iota.coffee

Wrapper for the browser and node.js around [iotaledger/iota.lib.js](https://github.com/iotaledger/iota.lib.js) with local PoW using:
* for borwser: [@iota-pico/pow-webgl](https://github.com/iotaeco/iota-pico-pow-webgl)
* for node.js [@iota-pico/pow-nodejs](https://github.com/iotaeco/iota-pico-pow-nodejs)

It exposes `IOTA`, `IotaWallet` and `IotaTransaction`.
`IOTA` is a wrapped and `promisyAll`'ed [iotaledger/iota.lib.js](https://github.com/iotaledger/iota.lib.js/). It has a bunch of functions declared but most of them don't need to be used directly.


### Installing

```bash
yarn add iota.coffee
```


### nodejs
In order for PoW work in node.js you need to install [@iota-pico/pow-nodejs](https://github.com/iotaeco/iota-pico-pow-nodejs)
```bash
yarn add @iota-pico/pow-nodejs
```


### Importing

```coffeescript
import 'babel-polyfill'
import {IOTA, IotaWallet, IotaTransaction} from 'iota.coffee'
```


### Selecting the node

By default it uses `https://field.carriota.com:443` so you don't _need_ to do anything.

```coffeescript
IOTA.changeNode('https://nodes.iota.cafe:443')
```


### WebWorkers

In `node_modules/iota.coffee/dist/lib` directory there's a WebWorker: `new_account_worker.js`. By adding at least one of them through `IOTA.addWorker` **iota.coffee** creates a pool of workers that significantly speed up wallet scanning process since `_newAddress` function of the **iota.lib.js** can work in parallel off of the main thread.

```coffeescript
for i in [0...3]
  IOTA.addWorker(new Worker 'iota.coffee/dist/lib/new_account_worker.js')
```


### IotaWallet

`IotaWallet` keeps addresses for a seed cached for speedier balance discovery, selecting inputs and finding a remainder. It exposes mostly `getBalance` and `send` functions.

```coffeescript
# `IotaWallet.create` scans address space for the supplied seed and returns `IotaWallet` instance.
# It also saves the addresses in localStorage under the key: 'iota' + first ten characters of the seed
seed = '99999999999999999999'
wallet = await IotaWallet.create(seed)

await wallet.getBalance()
#=> 7

wallet2 = await IotaWallet.create('AAAAAAAAAAAAAAA')
tx = await wallet.send(3, wallet2.lastAddress)
await tx.promote()
```


### IotaTransaction

Most of the time this will be a product of `IotaWallet` `send` function but it can also be created directly. In that case at least `hash` must be provided.

```coffeescript
tx = new IotaTransaction(hash: 'STINBALCZIHQGKTXTH9QAAQTCO9LVBOSCWXCJRZDRS9FGDDAXIQJQKFE9SETXLRISZFVGIHEPVV9A9999')

# when created with only hash `update` fills it with `value`, `bundle` and `tail`
await tx.update()
tx.value
#=> 500

await tx.isConfirmed()
#=> true
```

#### Reattach and Promote

```coffeescript
tx = await wallet.send(3, wallet2.lastAddress)

await tx.promote()

txs = await tx.reattach()
```


### License
MIT
