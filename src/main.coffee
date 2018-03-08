import 'babel-polyfill'
import './globals'
import {IOTA, IotaWallet, IotaTransaction} from './iota_wrapper'

window.IOTA = IOTA
window.IotaWallet = IotaWallet
window.IotaTransaction = IotaTransaction
