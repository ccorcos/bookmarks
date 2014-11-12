colors = require 'colors'

debug = true

# printing functions
debugPrint = (msg) ->
  if debug then console.log('DEBUG: '.yellow + msg)

errorPrint = (msg) ->
  console.log('ERROR: '.red + msg)

fetchPrint = (success, statusCode, contentType, url) ->
  if success
    console.log(statusCode.toString().magenta + ' ' + contentType + ': ' + url.toString().green)
  else
    console.log(statusCode.toString().magenta + ' ' + contentType + ': ' + url.toString().red)


module.exports =
  debugPrint: debugPrint
  errorPrint: errorPrint
  fetchPrint: fetchPrint
