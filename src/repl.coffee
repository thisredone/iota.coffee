{IOTA, IotaWallet, IotaTransaction} = require './index'

if process?.argv[2] is 'repl'
  pry = require 'pry'
  eval pry.it
