{CurlProofOfWork} = require "@iota-pico/pow-webgl/dist/curlProofOfWork"
{Trytes} = require "@iota-pico/data"

MAX_TIMESTAMP_VALUE = (Math.pow(3,27) - 1) / 2


ccurlHashing = (iota, trunkTransaction, branchTransaction, minWeightMagnitude, trytes) ->
  throw new Error('Invalid trunkTransaction') unless iota.valid.isHash(trunkTransaction)
  throw new Error('Invalid branchTransaction') unless iota.valid.isHash(trunkTransaction)
  throw new Error('Invalid minWeightMagnitude') unless iota.valid.isValue(minWeightMagnitude)

  finalBundleTrytes = []

  for thisTrytes in trytes
    txObject = iota.utils.transactionObject(thisTrytes)
    Object.assign txObject,
      tag: txObject.tag or txObject.obsoleteTag
      attachmentTimestamp: Date.now()
      attachmentTimestampLowerBound: 0
      attachmentTimestampUpperBound: MAX_TIMESTAMP_VALUE
    if previousTxHash
      txObject.trunkTransaction = previousTxHash
      txObject.branchTransaction = trunkTransaction
    else
      if txObject.lastIndex isnt txObject.currentIndex
        new Error('Wrong bundle order. The bundle should be ordered in descending order from currentIndex')
      txObject.trunkTransaction = trunkTransaction
      txObject.branchTransaction = branchTransaction

    packedTrytes = Trytes.create(iota.utils.transactionTrytes txObject)
    curl = new CurlProofOfWork()
    await curl.initialize()
    newTrytes = await curl.pow packedTrytes, minWeightMagnitude
    newTxObject = iota.utils.transactionObject newTrytes.toString()
    previousTxHash = newTxObject.hash
    finalBundleTrytes.unshift newTrytes.toString()

  finalBundleTrytes


export default (iota) ->
  localAttachToTangle = (trunkTransaction, branchTransaction, minWeightMagnitude, trytes, callback) ->
    console.log 'Light Wallet: localAttachToTangle'
    try
      res = await ccurlHashing(iota, trunkTransaction, branchTransaction, minWeightMagnitude, trytes)
      console.log(res)
      callback(null, res)
    catch error
      callback(error)

  iota.api.attachToTangle = localAttachToTangle
  iota.api.__proto__.attachToTangle = localAttachToTangle
