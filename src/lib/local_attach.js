const proofOfWork = require("@iota-pico/pow-webgl/dist/curlProofOfWork");
const data = require("@iota-pico/data");

const MAX_TIMESTAMP_VALUE = (Math.pow(3,27) - 1) / 2

var ccurlHashing = function(iota, trunkTransaction, branchTransaction, minWeightMagnitude, trytes, callback) {
  var iotaObj = iota;
  if (!iotaObj.valid.isHash(trunkTransaction)) {
    return callback(new Error("Invalid trunkTransaction"));
  }
  if (!iotaObj.valid.isHash(branchTransaction)) {
    return callback(new Error("Invalid branchTransaction"));
  }
  if (!iotaObj.valid.isValue(minWeightMagnitude)) {
    return callback(new Error("Invalid minWeightMagnitude"));
  }
  var isInitialized = true;

  var finalBundleTrytes = [];
  var previousTxHash;
  var i = 0;

  function loopTrytes() {
    getBundleTrytes(trytes[i], function(error) {
      if (error) {
        return callback(error);
      } else {
        i++;
        if (i < trytes.length) {
          loopTrytes();
        } else {
          return callback(null, finalBundleTrytes.reverse());
        }
      }
    });
  }

  async function getBundleTrytes(thisTrytes, callback) {
    var txObject = iotaObj.utils.transactionObject(thisTrytes);
    txObject.tag = txObject.tag || txObject.obsoleteTag;
    txObject.attachmentTimestamp = Date.now();
    txObject.attachmentTimestampLowerBound = 0;
    txObject.attachmentTimestampUpperBound = MAX_TIMESTAMP_VALUE;
    if (!previousTxHash) {
      if (txObject.lastIndex !== txObject.currentIndex) {
        return callback(new Error("Wrong bundle order. The bundle should be ordered in descending order from currentIndex"));
      }
      txObject.trunkTransaction = trunkTransaction;
      txObject.branchTransaction = branchTransaction;
    } else {
      txObject.trunkTransaction = previousTxHash;
      txObject.branchTransaction = trunkTransaction;
    }

    var trytes = iotaObj.utils.transactionTrytes(txObject);

    try {
        const obj = new proofOfWork.CurlProofOfWork();
        await obj.initialize();
        var newTrytes = await obj.pow(data.Trytes.create(trytes), minWeightMagnitude)
        var newTxObject = iotaObj.utils.transactionObject(newTrytes.toString());
        previousTxHash = newTxObject.hash;
        finalBundleTrytes.push(newTrytes.toString());
        callback(null);
    } catch(e) {
        callback(e)
    }
  }
  loopTrytes();
}


export default function(iota) {
    var localAttachToTangle = function(trunkTransaction, branchTransaction, minWeightMagnitude, trytes, callback) {
        console.log("Light Wallet: localAttachToTangle");

        ccurlHashing(iota, trunkTransaction, branchTransaction, minWeightMagnitude, trytes, function(error, success) {
            console.log(error || success);
            if (callback) {
                return callback(error, success);
            } else {
                return success;
            }
        })
    }

    iota.api.attachToTangle = localAttachToTangle;
    iota.api.__proto__.attachToTangle = localAttachToTangle;
}

