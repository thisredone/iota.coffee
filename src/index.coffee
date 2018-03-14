IotaLib = require 'iota.lib.js'
Promise = require 'bluebird'
useLocalAttachToTangle = require './lib/local_attach'
log = console.log.bind(console)

DEPTH = 3
MIN_WEIGHT = 14


retry = (times, promise) ->
  n = times
  delay = 1500
  loop
    try
      return await promise
    catch e
      throw new Error("Retried #{n} times and failed, last error: #{e.message}") if --times < 0
      log e
      await Promise.delay(Math.min(delay *= 1.3, 30 * 1000))


sum = (arr, key) ->
  if key?
    arr.reduce ((x, y) -> x + +y[key]), 0
  else
    arr.reduce ((x, y) -> x + +y), 0


class WorkerPool
  constructor: ->
    @workerRequestId = 0
    @workerRequests = {}
    @totalCount = 0
    @current = 0
    @workers = []

  add: (worker) ->
    worker.onmessage = ({data}) =>
      rid = data?.requestId
      if rid?
        delete data.requestId
        @workerRequests[rid](data)
        delete @workerRequests[rid]
    @workers.push(worker)
    @totalCount++

  task: (job, message) ->
    throw new Error('No wokers added through IOTA.addWorker') if @totalCount is 0
    @current = 0 if ++@current is @totalCount
    worker = @workers[@current]
    rid = @workerRequestId++
    new Promise (resolve) =>
      @workerRequests[rid] = resolve
      worker.postMessage Object.assign({job, requestId: rid}, message)


class IotaWrapper
  constructor: ->
    @workers = new WorkerPool
    @changeNode('https://nodes.iota.cafe:443')

  addWorker: (worker) ->
    @workers.add(worker)

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
    sum (await @getBalances addresses)

  getInputs: (addresses) ->
    lastThree = addresses.slice(-3)
    nonEmpty = addresses[0...-3].filter (a) -> a.balance isnt 0
    toCheck = nonEmpty.concat(lastThree)
    for balance, i in (await @getBalances toCheck) when +balance > 0
      toCheck[i]

  getAddress: (seed, keyIndex, security = 2) ->
    if @workers.totalCount isnt 0
      @workers.task('newAddress', {seed, keyIndex, security})
    else
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
      adrs = await Promise.all indexes.map (i) => @getAddress(seed, i + startingIndex)

      if wereAllEmpty
        balances = await @getBalances adrs
        actives = balances.map (b) -> +b > 0
      else
        actives = await @iota.api.wereAddressesSpentFromAsync(adrs.map (a) -> a.address)
      log "actives: #{actives.join(', ')}"

      allAreEmpty = actives.indexOf(true) is -1
      if wereAllEmpty and allAreEmpty and jump is 1
        log 'empty twice, ending'
        break
      wereAllEmpty = allAreEmpty and jump is 1

      if (index - startingIndex) > 999
        throw new Error("No transactions found upto address with index #{index + startingIndex - 1}")

      if allAreEmpty and jump <= 1
        log 'allAreEmpty and last jump'
        index = indexes[2] + 1
        jump = 1
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
          addresses.length = indexes[0] + 1
          break
        if jump < 0
          if allAreEmpty
            break
          else
            jump = 1

    indexesToFill = []
    for adr, i in addresses
      indexesToFill.push(i + startingIndex) if not adr?
    adrs = await Promise.all indexesToFill.map (i) => @getAddress(seed, i)
    addresses[i] = adrs[i] for _, i in indexesToFill
    takeLast = Math.min(addresses.length, 10)
    toCheck = addresses.slice(-takeLast)
    [wereSpentFrom, balances] = await Promise.all [
      @iota.api.wereAddressesSpentFromAsync(toCheck.map (a) -> a.address)
      @getBalances(toCheck)
    ]
    used = wereSpentFrom.map (wasSpentFrom, i) -> wasSpentFrom or balances[i] > 0
    lastUsedIndex = Math.max(0, used.lastIndexOf true)
    lastUsedIndex++ if wereSpentFrom[lastUsedIndex]
    addresses.length -= takeLast - 1 - lastUsedIndex
    addresses

  findTail: (bundle) ->
    txs = await @iota.api.findTransactionObjectsAsync(bundles: [bundle])
    txs.find (tx) -> tx.currentIndex is 0

  replay: (tail) ->
    @ota.api.replayBundleAsync(tail, DEPTH, MIN_WEIGHT)

  promote: (tail) ->
    transfers = [value: 0, address: '9'.repeat(81)]
    txs = await @iota.api.promoteTransactionAsync(tail, DEPTH, MIN_WEIGHT, transfers, delay: 0)
    log "Promoted, hash: #{txs[0].hash}"

  getTransactionObject: (hash) ->
    txs = await @iota.api.getTransactionsObjectsAsync([hash])
    txs[0]

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
  constructor: ({@hash, @value, @bundle, @tail, timestamp}) ->
    @createdAt = if timestamp then new Date(timestamp * 1000) else new Date

  isConfirmed: ->
    return true if @wasConfirmed
    [res] = await IOTA.iota.api.getLatestInclusionAsync([@hash])
    @wasConfirmed = res

  update: ->
    {@bundle, @tail, @value} = await IOTA.getTransactionObject(@hash)

  getTail: ->
    await @update() if not @bundle?
    @tail ?= await IOTA.findTail(@bundle)

  reattach: ({force} = {}) ->
    if not force and (Date.now() - d) < 600000
      throw 'This tx less than 10 minutes old'
    tail = await @getTail()
    txs = await IOTA.replay(tail.hash)
    txs.map (t) -> t.hash

  promote: ({times = 5} = {}) ->
    return if @wasConfirmed
    tail = await @getTail()
    until --times < 0 or await @isConfirmed()
      await IOTA.promote(tail.hash)


class IotaWallet
  constructor: (@seed) ->

  @create: (seed) ->
    (new IotaWallet seed).init()

  init: ->
    cached = localStorage?.getItem('iota' + @seed[0..9])
    @addresses = JSON.parse(cached) if cached
    if not @addresses?
      @addresses = await IOTA.findAddresses(@seed)
      localStorage?.setItem('iota' + @seed[0..9], JSON.stringify(@addresses))
    @lastAddress = @addresses[@addresses.length - 1]
    this

  nextAddress: ->
    index = @lastAddress.keyIndex + 1
    @lastAddress = await IOTA.getAddress(@seed, index)
    @addresses.push @lastAddress
    localStorage?.setItem('iota' + @seed[0..9], JSON.stringify(@addresses))
    @lastAddress

  getBalance: ->
    IOTA.getBalance(@addresses)

  findRemainder: ->
    while await IOTA.wasAddressSpentFrom(@lastAddress)
      await @nextAddress()
    @lastAddress

  getInputs: ->
    IOTA.getInputs(@addresses)

  send: (value, destination, {inputs, remainder} = {}) ->
    if value > 0
      inputs ?= await @getInputs()
      throw 'Not enough balance' if sum(inputs, 'balance') < value
      if not remainder?
        remainder = await @findRemainder()
        if remainder in inputs and sum(inputs[0...-1], 'balance') < value
          remainder = await @nextAddress()
    input.address = IOTA.iota.utils.noChecksum(input.address) for input in (inputs || [])
    remainder = IOTA.iota.utils.noChecksum(remainder.address) if remainder?
    log {remainder, inputs}
    res = await IOTA.sendTransfer(@seed, value, destination.address ? destination, {inputs, remainder})
    new IotaTransaction(res)

  consolidate: ->
    remainder = await @findRemainder()
    inputs = await @getInputs()
    inputs.pop() if remainder in inputs
    return if inputs.length is 0
    amount = await IOTA.getBalance(inputs...)
    @send(amount, remainder, {remainder, inputs})


module.exports = {IOTA, IotaWallet, IotaTransaction}
