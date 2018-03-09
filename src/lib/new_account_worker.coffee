import IotaLib from 'iota.lib.js'

IOTA = new IotaLib

self.onmessage = ({data}) =>
  {requestId, seed, keyIndex, security} = Object.assign(security: 2, data)
  address = IOTA.api._newAddress seed, keyIndex, security, true
  postMessage({requestId, address, keyIndex, security})
  null
