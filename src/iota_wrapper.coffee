import IOTA from 'iota.lib.js'
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
    @iota = new IOTA({provider})
    @utils = @iota.utils
    @valid = @iota.valid
    useLocalAttachToTangle(@iota)
    Promise.promisifyAll(@iota.api)

  getBalance: (addresses...) ->
    {balances} = await retry(5, @iota.api.getBalancesAsync addresses, 100)
    balances.sum()

  getAddress: (seed, keyIndex, security = 2) ->
    address = @iota.api._newAddress seed, keyIndex, security, true
    {address, keyIndex, security}

  findTransactions: (opt) ->
    await retry(5, @iota.api.findTransactionsAsync(opt))

  sendTransfer: (seed, value, address, inputs) ->
    @iota.api.sendTransferAsync seed, DEPTH, MIN_WEIGHT, [{value, address}], {inputs}

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

  formatAmount: (amount) ->
    return '' if not amount?
    minus = if amount < 0 then '-' else ''
    amount = Math.abs amount
    for symbol, i in ['Ti', 'Gi', 'Mi', 'Ki', 'i']
      unit = Math.pow 1000, 4 - i
      break if amount / unit > 0.1
    "#{minus}#{amount / unit} #{symbol}"


export default new IotaWrapper
