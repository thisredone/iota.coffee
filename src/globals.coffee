window.Promise = require 'bluebird'

window.log = console.log.bind(console)
window.after = (ms, fn) -> setTimeout(fn, ms)
window.every = (ms, fn) -> setInterval(fn, ms)
window._with = (val, fn) -> fn.bind(val)(val) if val?
window.merge = (objects...) -> objects.reduce ((res, obj) -> Object.assign(res, obj)), {}
window.minutes = (n) -> 60 * n * 1000

window.retry = (times, promise) ->
  n = times
  delay = 1500
  loop
    try
      return await promise
    catch e
      if --times < 0
        throw new Error("Retried #{n} times and failed, last error: #{e.message}")
      log e
      await Promise.delay(Math.min(delay *= 1.3, 30 * 1000))

window.waitFor = (timeout, fn) ->
  startedAt = Date.now()
  loop
    break if fn()
    if Date.now() > startedAt + timeout
      throw new Error("Timeout of #{timeout} exceeded")
    await Promise.delay(15)
  true

Array::last = (n) ->
  if n then @slice(-n) else @[@length - 1]

Array::sum = (key) ->
  if key?
    @reduce ((x, y) -> x + +y[key]), 0
  else
    @reduce ((x, y) -> x + +y), 0
