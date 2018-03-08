import IotaLib from 'iota.lib.js'
import Promise from 'bluebird'
import useLocalAttachToTangle from './lib/local_attach.js'

DEPTH = 3
MIN_WEIGHT = 14


class IotaWrapper
  constructor: ->
    @changeNode('https://nodes.iota.cafe:443')
    # @changeNode('http://iota.bitfinex.com:80')
    # @changeNode('http://mainnet.necropaz.com:14500')

  changeNode: (provider) ->
    @iota = new IotaLib({provider})
    @utils = @iota.utils
    @valid = @iota.valid
    useLocalAttachToTangle(@iota)
    Promise.promisifyAll(@iota.api)

  getBalances: (addresses) ->
    onlyAddresses = addresses
    onlyAddresses = addresses.map((a) -> a.address) if addresses[0]?.address?
    {balances} = await retry(3, @iota.api.getBalancesAsync onlyAddresses, 100)
    if addresses[0]?.address?
      for balance, i in balances
        addresses[i].balance = +balance
    balances

  getBalance: (addresses...) ->
    addresses = addresses[0] if @iota.valid.isArray(addresses[0])
    (await @getBalances(addresses)).sum()

  getInputs: (addresses) ->
    lastThree = addresses.last(3)
    nonEmpty = addresses[0...-3].filter (a) -> a.balance isnt 0
    toCheck = nonEmpty.concat(lastThree)
    for balance, i in (await @getBalances toCheck) when +balance > 0
      toCheck[i]

  getAddress: (seed, keyIndex, security = 2) ->
    address = @iota.api._newAddress seed, keyIndex, security, true
    {address, keyIndex, security}

  findTransactions: (opt) ->
    await retry(3, @iota.api.findTransactionsAsync(opt))

  wasAddressSpentFrom: (address) ->
    [wasSpentFrom] = await @iota.api.wereAddressesSpentFromAsync([address.address ? address])
    wasSpentFrom

  sendTransfer: (seed, value, address, {inputs, remainder} = {}) ->
    transfer = [{value, address}]
    options = {inputs, address: remainder}
    [tx] = await @iota.api.sendTransferAsync seed, DEPTH, MIN_WEIGHT, transfer, options
    tx

  findAddresses: (seed, startingIndex = 0) ->
    addresses = []
    index = 0
    jump = 4
    wereAllEmpty = false

    loop
      indexes = [index, index + jump, index + 2 * jump]
      log "findAddresses: indexes: #{indexes.join(', ')}, jump: #{jump}"
      addresses[i] = @getAddress(seed, i + startingIndex) for i in indexes

      actives = await @iota.api.wereAddressesSpentFromAsync(addresses[i].address for i in indexes)
      log "actives: #{actives.join(', ')}"

      allAreEmpty = actives.indexOf(true) is -1
      if wereAllEmpty and allAreEmpty and jump is 1
        log "empty twice, ending"
        break
      wereAllEmpty = allAreEmpty and jump is 1

      if (index - startingIndex) > 999
        throw new Error("No transactions found upto address with index #{index + startingIndex - 1}")

      if allAreEmpty and jump is 1
        log 'allAreEmpty and last jump'
        index = indexes[2] + 1
      else if actives[2] and jump > 1
        jump += 3
        index = indexes[2] + 1
      else
        jump -= 3
        if actives[1]
          index = indexes[1] + 1
          addresses.length = indexes[2] + 1
        else if actives[0]
          index = indexes[0] + 1
          addresses.length = indexes[1] + 1
        else
          addresses.length = indexes[0]
          break
        if jump < 0
          break

    for _, i in addresses
      addresses[i] ?= @getAddress(seed, i + startingIndex)
    takeLast = 10
    toCheck = addresses.last(takeLast).map (a) -> a.address

    [wereSpentFrom, haveTx] = await Promise.all [
      @iota.api.wereAddressesSpentFromAsync(toCheck)
      @findTransactions(addresses: toCheck)
    ]
    haveTx = toCheck.map (adr) -> adr in haveTx
    used = wereSpentFrom.map (wasSpentFrom, i) -> wasSpentFrom or haveTx[i]
    addresses.length -= takeLast - 1 - used.lastIndexOf(true)
    addresses

  findTail: (bundle) ->
    txs = await @iota.api.findTransactionObjectsAsync(bundles: [bundle])
    txs.find (tx) -> tx.currentIndex is 0

  replay: (tail) ->
    @ota.api.replayBundleAsync(tail, DEPTH, MIN_WEIGHT)

  promote: (tail) ->
    transfers = [value: 0, address: '9'.repeat(81)]
    @iota.api.promoteTransactionAsync(tail, DEPTH, MIN_WEIGHT, transfers, delay: 0)

  formatAmount: (amount) ->
    return '' if not amount?
    minus = if amount < 0 then '-' else ''
    amount = Math.abs amount
    for symbol, i in ['Ti', 'Gi', 'Mi', 'Ki', 'i']
      unit = Math.pow 1000, 4 - i
      break if amount / unit > 0.1
    "#{minus}#{amount / unit} #{symbol}"


IOTA = new IotaWrapper


class IotaTransaction
  constructor: ({@hash, @bundle, @tail, timestamp}) ->
    @createdAt = if timestamp then new Date(timestamp * 1000) else new Date

  isConfirmed: ->
    return true if @wasConfirmed
    [res] = await IOTA.iota.api.getLatestInclusionAsync([@hash])
    @wasConfirmed = res

  getTail: ->
    return @tail if @tail?
    @tail = await IOTA.findTail(@bundle)

  reattach: ({force} = {}) ->
    if not force and (Date.now() - d) < 600000
      throw 'This tx less than 10 minutes old'
    tail = await @getTail()
    txs = await IOTA.replay(tail.hash)
    txs.map (t) -> t.hash

  promote: ->
    return if @wasConfirmed
    count = 0
    tail = await @getTail()
    until await @isConfirmed()
      return if ++count > 10
      await IOTA.promote(tail.hash)


class IotaWallet
  constructor: (@seed) ->

  @create: (seed) ->
    (new IotaWallet seed).init()

  init: ->
    cached = localStorage.getItem('iota' + @seed[0..9])
    @addresses = JSON.parse(cached) if cached
    if not @addresses?
      @addresses = await IOTA.findAddresses(@seed)
      localStorage.setItem('iota' + @seed[0..9], JSON.stringify(@addresses))
    this

  nextAddress: ->
    index = @addresses.last().keyIndex + 1
    address = IOTA.getAddress(@seed, index)
    @addresses.push address
    localStorage.setItem('iota' + @seed[0..9], JSON.stringify(@addresses))
    address

  getBalance: ->
    IOTA.getBalance(@addresses)

  findRemainder: ->
    address = @addresses.last()
    while await IOTA.wasAddressSpentFrom(address)
      address = @nextAddress()
    address

  send: (value, destination) ->
    if value > 0
      inputs =
        for {address, security, keyIndex, balance} in await IOTA.getInputs(@addresses)
          {security, keyIndex, balance, address: IOTA.iota.utils.noChecksum(address)}
      remainder = IOTA.iota.utils.noChecksum((await @findRemainder()).address)
      log {remainder, inputs}
    res = await IOTA.sendTransfer(@seed, value, destination.address ? destination, {inputs, remainder})
    new IotaTransaction(res)


module.exports = {IOTA, IotaWallet, IotaTransaction}
