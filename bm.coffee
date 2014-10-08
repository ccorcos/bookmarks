#!/usr/bin/env coffee

# get safari urls, chrome, firefox
# package json
# suggested search terms?


# imports
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
sys = require 'sys'
exec = require('child_process').exec




# initialize database
db = new nedb({ filename: './bookmarks.json', autoload: true })

tfidf = null

loadTfidf = ->
  if fs.existsSync './tfidf.json'
    string = fs.readFileSync './tfidf.json', 'utf8'
    json = JSON.parse string
    tfidf = new natural.TfIdf json
  else
    tfidf = new natural.TfIdf()

# printing functions
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






fetchUrl = (url, callbackErrHtml) ->
  urlBits = urllib.parse(url)
  protolib = (if urlBits.protocol is "https:" then "https" else "http")

  response = (r) ->
    if r.statusCode isnt 200
      fetchPrint false, r.statusCode, r.headers['content-type'], url
      callbackErrHtml('status code isnt 200')
    else if not r.headers['content-type']?
      fetchPrint false, r.statusCode, 'no contentType', url
      callbackErrHtml('no content type')
    else if r.headers['content-type'].indexOf('html') is -1
      fetchPrint false, r.statusCode, r.headers['content-type'], url
      callbackErrHtml('no html')
    else
      html = ''
      r.on 'data', (chunk) -> html += chunk
      r.on 'end', ->
        fetchPrint true, r.statusCode, r.headers['content-type'], url
        callbackErrHtml(null, html)

  httpError = (err) ->
    console.log('ERR'.red + ' ' + err.toString() + ': ' + url.toString().red)
    callbackErrHtml(err)

  require(protolib).get(url, response).on('error', httpError)




cleanHTML = (html) ->
  $ = cheerio.load(html)
  title = $("title").text()
  title = title.replace(/\s+/g, ' ')
  title = title.replace(/^\s+|\s+$/g, '')


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



# add urls to tfidf and database
indexUrls = (urls, callbackDone) ->
  debugPrint "indexing urls..."

  errorUrls = []

  fetchEach = (url, callbackFetch) ->
    db.count {url:url}, (err, count) ->
      if count isnt 0
        console.log "repeat: ".grey + url.grey
        callbackFetch()
      else
        fetchUrl url, (err, html) ->
          if err
            errorUrls.push(url)
            # don't ruin it for everyone else!
            callbackFetch()
            # callbackFetch(err)
          else
            [title, text] = cleanHTML(html)
            db.insert {url:url, title:title, text:text, createdAt: Date.now()}, (err, doc) ->
              if err
                # don't ruin it for everyone else!
                errorPrint err
                callbackFetch()
                # callbackFetch(err)
              else
                tfidf.addDocument(doc.url + ' ' + doc.title.toLowerCase() + ' ' + doc.text, doc._id)
                callbackFetch()


  doneFetching = (err) ->
    if err then errorPrint err
    if errorUrls.length isnt 0
      errorPrint "The following urls could not be added:"
      for url in errorUrls
        console.log url.grey
    debugPrint("serializing tfidf")
    json = JSON.stringify(tfidf)
    fs.writeFile './tfidf.json', json, {encoding:'utf8'}, (err) -> callbackDone(err)

  async.each urls, fetchEach, doneFetching




reindex = (callbackDone) ->
  debugPrint "reindexing..."
  tfidf = new natural.TfIdf()

  db.find {}, (err, docs) ->
    if docs.length is 0
      errorPrint "Add urls before reindexing."
      callbackDone()
    else
      urls = _.pluck docs, "url"
      db.remove {}, { multi: true }, (err, num) ->
        if err
          callbackDone(err)
        else
          indexUrls(urls, callbackDone)




# rebuild the tfidf from the database
rebuildTfidf = (callbackDone) ->
  debugPrint "rebuilding tfidf..."
  tfidf = new natural.TfIdf()

  update = (doc, callbackUpdate) ->
    tfidf.addDocument(doc.url + ' | ' + doc.title.toLowerCase() + ' | ' + doc.text, doc._id)
    callbackUpdate()

  done = (err) ->
    if err
      callbackDone(err)
    else
      debugPrint("serializing tfidf")
      json = JSON.stringify(tfidf)
      fs.writeFile './tfidf.json', json, {encoding:'utf8'}, (err) -> callbackDone(err)

  db.find {}, (err, docs) ->
    if docs.length isnt 0
      async.each docs, update, done

searchTfidf = (text) ->
  results = []
  tfidf.tfidfs text, (index, score, id) ->
    results.push {score:score, id:id}
  return results

search = (text, n, callbackResults) ->
  text = text.toLowerCase()

  debugPrint 'searching for "' + text + '"'
  idScores = searchTfidf(text)

  sorted = _.sortBy idScores, (doc) -> -1*doc.score
  ids = _.pluck sorted[0..n], "id"

  db.find {_id: $in: ids}, (err, docs) ->
    if err
      callbackResults(err)
    else
      results = _.sortBy docs, (doc) -> ids.indexOf(doc._id)
      results = _.map results, (result, i) ->
        result.score = sorted[i].score
        return result
      sort = _.sortBy results, (doc) -> -1*doc.score
      callbackResults(null, sort)


printSearchResults = (results) ->
  for result in results
    console.log result.score.toFixed(2).toString().blue + ' - ' + result.title.white + ' ' + result.url.gray




program
  .version('0.0.1')
  .usage('[option] [urls|query]')
  .option('reindex', 'index all urls')
  .option('add', 'add urls')
  .option('safari', 'add Safari bookmarks')
  .option('search', 'search')
  .option('backup', 'make a database backup')
  .option('backups', 'list backups')
  .option('reset [backup]', 'reset the database')
  .parse(process.argv)







if program.reindex
  reindex (err) ->
    if err then errorPrint err
    debugPrint "finished"

else if program.add
  loadTfidf()
  indexUrls program.args, (err) ->
    if err then errorPrint err
    debugPrint "finished"

else if program.search
  loadTfidf()
  search program.args.join(' '), 20, (err, results) ->
    if err then errorPrint err else printSearchResults(results)

else if program.backup
  if not fs.existsSync('./backups/') then fs.mkdirSync('./backups/')
  fs.createReadStream('bookmarks.json').pipe(fs.createWriteStream('./backups/backup-' + Date.now().toString() + '.json'))

else if program.backups
  if not fs.existsSync('./backups/') then fs.mkdirSync('./backups/')
  fs.readdir './backups/', (err, files) ->
    if err
      errorPrint err
    else
      for file in files
        console.log file

else if program.reset
  fs.unlink './bookmarks.json', (err) -> if err then debugPrint err
  fs.unlink './tfidf.json', (err) -> if err then debugPrint err

  if typeof program.reset is "string"
    fs.createReadStream('./backups/' + program.reset).pipe(fs.createWriteStream('bookmarks.json'))
    rebuildTfidf (err) ->
      if err then errorPrint err
      debugPrint "finished"

else if program.safari
  loadTfidf()
  p = exec "./test1.sh", (err, stdout, stderr) ->
    if err
      errorPrint err
    else
      bookmarks = stdout.split('\n')[..-2]
      bookmarks = _.uniq bookmarks
      indexUrls bookmarks, (err) ->
        if err then errorPrint err
        debugPrint "finished import safari bookmarks"
        # process.exit()

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
