#!/usr/bin/env coffee

path = require 'path'
fs = require 'fs'
program = require 'commander'
urllib = require 'url'
async = require 'async'
nedb = require 'nedb'
sys = require 'sys'
exec = require('child_process').exec

db = new nedb()

fetchUrl = (url, callbackErrHtml) ->
  urlBits = urllib.parse(url)
  protolib = (if urlBits.protocol is "https:" then "https" else "http")
  response = (r) ->
    if r.statusCode isnt 200
      callbackErrHtml('status code isnt 200')
      # here
    else if not r.headers['content-type']?
      callbackErrHtml('no content type')
      # here
    else if r.headers['content-type'].indexOf('html') is -1
      callbackErrHtml('no html')
      # here
    else
      html = ''
      r.on 'data', (chunk) -> html += chunk
      r.on 'end', ->
        callbackErrHtml(null, html)

  httpError = (err) ->
    callbackErrHtml(err)

  require(protolib).get(url, response).on('error', httpError)


indexUrls = (urls, callbackDone) ->
  errorUrls = []

  fetchEach = (url, callbackFetch) ->
    console.log url
    db.count {url:url}, (err, count) ->
      if count isnt 0
        console.log "1 - done", url
        callbackFetch()
      else
        fetchUrl url, (err, html) ->
          if err
            console.log "2 - done", url, err
            errorUrls.push(url)
            callbackFetch()
          else
            db.insert {url:url, html:html, createdAt: Date.now()}, (err, doc) ->
              if err
                console.log "3 - done", url
                callbackFetch()
              else
                console.log "4 - done", url
                callbackFetch()


  doneFetching = (err) ->
    if err then console.log err
    callbackDone()

  async.each urls, fetchEach, doneFetching


p = exec "./test1.sh", (err, stdout, stderr) ->
  if err
    console.log err
  else
    bookmarks = stdout.split('\n')[..-2]
    console.log 'bookmarks:', bookmarks

    indexUrls bookmarks, (err) ->
      if err then console.log err
      console.log "finished import safari bookmarks"
