#!/usr/bin/env coffee

# get safari urls, chrome, firefox
# package json

# suggested search terms?

mkdirp = require 'mkdirp'
path = require 'path'
fs = require 'fs'
program = require 'commander'
colors = require 'colors'
cheerio = require 'cheerio'
urllib = require 'url'
entities = require 'entities'
natural = require 'natural'
_ = require 'lodash'
async = require 'async'

nedb = require 'nedb'
db = new nedb({ filename: './bookmarks.json', autoload: true })

tfidf = null

debug = true
debugPrint = (msg) ->
  if debug then console.log('DEBUG: '.yellow + msg)

errorPrint = (msg) ->
  console.log('ERROR: '.red + msg)

fetchPrint = (success, statusCode, contentType, url) ->
  if success
    console.log(statusCode.toString().magenta + ' ' + contentType + ': ' + url.toString().green)
  else
    console.log(statusCode.toString().magenta + ' ' + contentType + ': ' + url.toString().red)

fetchUrlData = (url, callback) ->
  urlBits = urllib.parse(url)
  protolib = (if urlBits.protocol is "https:" then "https" else "http")

  require(protolib).get(url, (response) ->
    if response.statusCode isnt 200
      fetchPrint false, response.statusCode, response.headers['content-type'], url
      # errorPrint('status code ' + response.statusCode.toString())
      callback(true)
    else if not response.headers['content-type']?
      fetchPrint false, response.statusCode, 'no contentType', url
      # errorPrint('no content-type')
      callback(true)
    else if response.headers['content-type'].indexOf('html') is -1
      fetchPrint false, response.statusCode, response.headers['content-type'], url
      # errorPrint('no html')
      callback(true)
    else
      data = ''
      response.on 'data', (chunk) -> data += chunk
      response.on 'end', ->
        fetchPrint true, response.statusCode, response.headers['content-type'], url
        callback(false, {url:url, html:data})
  ).on 'error', (err) ->
    errorPrint(err, + ' ' + url.red)
    # callback(true)



cleanHTML = (html) ->
  $ = cheerio.load(html)
  title = $("title").text()

  # get the raw text
  # remove <head>
  text = html.replace(/<head>[\s\S]*<\/head>/g, ' ')
  # remove scripts
  text = text.replace(/<script\b[^<]*(?:(?!<\/script>)<[^<]*)*<\/script/g, ' ')
  # remove html tags
  text = text.replace(/<[^>]*>/g, ' ')
  # ­remove soft-hyphens
  re = new RegExp(String.fromCharCode(173),"g")
  text = text.replace(re, '')
  # clean up white space
  text = text.replace(/\s+/g, ' ')
  # unescape to unicode
  text = entities.decodeHTML(text)
  # lowercase
  text = text.toLowerCase()

  # TODO: use an inflector to convert nouns, verbs, etc.

  return [title, text]


indexAll = (callback) ->
  debugPrint "indexing..."
  tfidf = new natural.TfIdf()

  fetchEach = (url, callback) ->
    fetchUrlData url, (err, result) ->
      if err
        callback(err)
      else
        [title, text] = cleanHTML(result.html)
        db.update {url:result.url}, {$set:{title:title, text:text, createdAt: Date.now()}}, (err, num, doc) ->
          if num
            db.find {url:result.url}, (err, docs) ->
              doc = docs[0]
              tfidf.addDocument(doc.url + ' | ' + doc.title.toLowerCase() + ' | ' + doc.text, doc._id)
              callback()
          else
            errorPrint("document not found! " + url.gray)
            callback true

  doneFetching = (err) ->
    if not err
      debugPrint("serializing tfidf")
      json = JSON.stringify(tfidf)
      fs.writeFile './tfidf.json', json, {encoding:'utf8'}, (err) -> if err then errorPrint err
    callback()

  db.find {}, (err, docs) ->
    if docs.length is 0
      errorPrint "Add urls before re-indexing."
    else
      urls = _.pluck docs, "url"
      async.each urls, fetchEach, doneFetching

updateIndex = (callback) ->
  debugPrint "updating index..."
  tfidf = new natural.TfIdf()

  update = (doc, callback) ->
    tfidf.addDocument(doc.url + ' | ' + doc.title.toLowerCase() + ' | ' + doc.text, doc._id)
    callback()

  done = (err) ->
    if not err
      debugPrint("serializing tfidf")
      json = JSON.stringify(tfidf)
      fs.writeFile './tfidf.json', json, {encoding:'utf8'}, (err) -> if err then errorPrint err
    callback()

  db.find {}, (err, docs) ->
    if docs.length isnt 0
      async.each docs, update, done



addUrls = (urls, callback) ->
  debugPrint "adding urls..."

  fetchEach = (url, callback) ->
    db.count {url:url}, (err, count) ->
      if count isnt 0
        console.log "repeat: ".grey + url.grey
      else
        fetchUrlData url, (err, result) ->
          if err
            callback()
          else
            [title, text] = cleanHTML(result.html)
            db.insert {url:result.url, title:title, text:text, createdAt: Date.now()}, (err, doc) ->
              if not err
                tfidf.addDocument(doc.url + ' | ' + doc.title.toLowerCase() + ' | ' + doc.text, doc._id)
              callback()

  doneFetching = (err) ->
    debugPrint("serializing tfidf")
    json = JSON.stringify(tfidf)
    fs.writeFile './tfidf.json', json, {encoding:'utf8'}, (err) -> if err then errorPrint err
    callback()

  async.each urls, fetchEach, doneFetching


search = (text, n, callback) ->
  # give suggestions:
  # natural.JaroWinklerDistance("dixon","dicksonx")
  # metaphone.compare(wordA, wordB)
  # wordnet = new natural.WordNet("./dict")
  # wordnet.lookup 'node', (results) ->
  #   results.forEach (result) ->
  #     console.log('------------------------------------')
  #     console.log(result.synsetOffset)
  #     console.log(result.pos)
  #     console.log(result.lemma)
  #     console.log(result.synonyms)
  #     console.log(result.pos)
  #     console.log(result.gloss)

  text = text.toLowerCase()

  debugPrint 'searching for "' + text + '"'
  results = []
  tfidf.tfidfs text, (index, score, id) ->
    results.push {index:index, score:score, id:id}

  sorted = _.sortBy results, (doc) -> -1*doc.score
  ids = _.pluck sorted[0..n], "id"

  db.find {_id: $in: ids}, (err, docs) ->
    results = _.sortBy docs, (doc) -> ids.indexOf(doc._id)
    results = _.map results, (result, index) ->
      result.score = sorted[index].score
      return result
    sort = _.sortBy results, (doc) -> -1*doc.score
    callback(sort)

printSearchResults = (results) ->
  for result in results
    console.log result.score.toFixed(2).toString().blue + ' - ' + result.title.white + ' ' + result.url.gray


program
  .version('0.0.1')
  .usage('[option] [urls|query]')
  .option('index', 'index all urls')
  .option('add', 'add url')
  .option('safari', 'add Safari bookmarks')
  .option('search', 'search')
  .option('backup', 'make a database backup')
  .option('backups', 'list backups')
  .option('reset [backup]', 'reset the database')
  .parse(process.argv)


loadTfidf = ->
  if fs.existsSync './tfidf.json'
    string = fs.readFileSync './tfidf.json', 'utf8'
    json = JSON.parse string
    tfidf = new natural.TfIdf json
  else
    tfidf = new natural.TfIdf()

if program.index
  indexAll ->
    debugPrint "finished"
else if program.add
  loadTfidf()
  addUrls program.args, ->
    debugPrint "finished"
else if program.search
  loadTfidf()
  search program.args.join(' '), 5, printSearchResults
else if program.backup
  if not fs.existsSync('./backups/') then fs.mkdirSync('./backups/')
  fs.createReadStream('bookmarks.json').pipe(fs.createWriteStream('./backups/backup-' + Date.now().toString() + '.json'))
else if program.backups
  if not fs.existsSync('./backups/') then fs.mkdirSync('./backups/')
  fs.readdir './backups/', (err, files) ->
    # console.log "Backups:".blue
    for file in files
      console.log file
else if program.reset
  fs.unlink './bookmarks.json', (err) -> if err then debugPrint err
  fs.unlink './tfidf.json', (err) -> if err then debugPrint err
  if typeof program.reset is "string"
    fs.createReadStream('./backups/' + program.reset).pipe(fs.createWriteStream('bookmarks.json'))
    updateIndex -> debugPrint "finished"
else if program.safari
  loadTfidf()
  # sys = require('sys')
  # exec = require('child_process').exec
  #
  #
  # p = exec "./safari.sh", (error, stdout, stderr) ->
  #   bookmarks = stdout.split('\n')[..20]
  #   addUrls bookmarks, ->
  #     debugPrint "finished with safari"

  sys = require('sys')
  spawn = require('child_process').spawn


  s = ""
  p = spawn "./safari.sh"
  p.stdout.on 'data', (data) -> s+= data
  p.stdout.on 'end', () ->
    console.log "end"
    bookmarks = s.split('\n')[..20]
    addUrls bookmarks, ->
      debugPrint "finished with safari"
      p.kill()

else
  errorPrint "no args!"



# defaults read ~/Library/Safari/Bookmarks.plist | sed -En 's/^ *URLString = "(.*)";/\1/p'
# ~/Library/Application Support/Google/Chrome/Default $ cat Bookmarks
# ~/Library/Application Support/Firefox/Profiles/z841ospp.default-1398923770842 $ cat bookmarkbackups/bookmarks-2014-03-27.json

# TEST
# urls = ["http://tympanus.net/codrops/", "http://letteringjs.com", "http://practicaltypography.com/typography-in-ten-minutes.html"]
# tfidf = new natural.TfIdf()
# db.find {}, (err, docs) -> console.log docs
# indexUrls urls, ->
#   search 'typography', 5, (results) ->



# tfidf.listTerms(2).forEach (item) -> console.log(item.term + ': ' + item.tfidf)

# tfidf.tfidfs 'typography',  (index, score, key)->
  # console.log arguments



# text = 'typography'
# results = []
# tfidf.tfidfs text, (index, score) -> results.push {index:index, score:score}
# console.log results
# sorted = _.sortBy results, (doc) -> -1*doc.score
# for result in sorted[0..5]
#   doc = db.find {index:result.index}
#   console.log doc
#   console.log result.score.toString().red + ' - ' + doc.title.white + ': ' + doc.url.gray

# tfidf.listTerms(0).forEach((item) -> console.log(item.term + ': ' + item.tfidf)
