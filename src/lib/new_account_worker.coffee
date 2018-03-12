import IotaLib from 'iota.lib.js'

IOTA = new IotaLib

self.onmessage = ({data}) =>
  {requestId, job} = data
  switch job
    when 'newAddress'
      {seed, keyIndex, security} = data
      address = IOTA.api._newAddress seed, keyIndex, security, true
      postMessage({requestId, address, keyIndex, security})
    else
      postMessage({requestId, error: "#{job} not implemented in worker"})
  null
