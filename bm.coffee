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

classifier = null

loadClassifier = (callbackLoaded) ->
  if fs.existsSync('./classifier.json')
    natural.BayesClassifier.load 'classifier.json', null, (err, c) ->
      if err
        debugPrint err
        classifier = new natural.BayesClassifier()
        debugPrint "fresh new classifier"
        callbackLoaded()
      else
        debugPrint "classifier loaded"
        classifier = c
        callbackLoaded()
  else
    classifier = new natural.BayesClassifier()
    callbackLoaded()

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
    # errorPrint(err, + ' ' + url.red)
    callbackErrHtml(err)

  require(protolib).get(url, response).on('error', httpError)




cleanHTML = (html) ->
  $ = cheerio.load(html)
  title = $("title").text()

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



# add urls to classifier and database
indexUrls = (urls, callbackDone) ->
  debugPrint "indexing urls..."

  errorUrls = []

  fetchEach = (url, callbackFetch) ->
    db.count {url:url}, (err, count) ->
      if count isnt 0
        console.log "repeat: ".grey + url.grey
      else
        fetchUrl url, (err, html) ->
          if err
            errorUrls.push(url)
            callbackFetch(err)
          else
            [title, text] = cleanHTML(html)
            db.insert {url:url, title:title, text:text, createdAt: Date.now()}, (err, doc) ->
              if err
                callbackFetch(err)
              else
                classifier.addDocument(doc.url + ' ' + doc.title.toLowerCase() + ' ' + doc.text, doc._id)
                callbackFetch()


  doneFetching = (err) ->
    debugPrint("training classifier")
    classifier.train()
    debugPrint("serializing classifier")
    classifier.save 'classifier.json', (err, classifier) -> callbackDone(err)

  async.each urls, fetchEach, doneFetching




reindex = (callbackDone) ->
  debugPrint "reindexing..."
  classifier = new natural.BayesClassifier()

  db.find {}, (err, docs) ->
    if docs.length is 0
      errorPrint "Add urls before reindexing."
    else
      urls = _.pluck docs, "url"
      db.remove {}, { multi: true }, (err, num) ->
        if err
          callbackDone(err)
        else
          indexUrls(urls, callbackDone)




# rebuild the classifier from the database
rebuildClassifier = (callbackDone) ->
  debugPrint "rebuilding classifier..."
  classifier = new natural.BayesClassifier()

  update = (doc, callbackUpdate) ->
    classifier.addDocument(doc.url + ' | ' + doc.title.toLowerCase() + ' | ' + doc.text, doc._id)
    callbackUpdate()

  done = (err) ->
    if err
      callbackDone(err)
    else
      debugPrint("training classifier")
      classifier.train()
      debugPrint("serializing classifier")
      classifier.save 'classifier.json', (err, classifier) -> callbackDone(err)

  db.find {}, (err, docs) ->
    if docs.length isnt 0
      async.each docs, update, done





search = (text, n, callbackResults) ->
  text = text.toLowerCase()

  debugPrint 'searching for "' + text + '"'
  labelValues = classifier.getClassifications(text)

  sorted = _.sortBy labelValues, (doc) -> -1*doc.value
  ids = _.pluck sorted[0..n], "label"

  db.find {_id: $in: ids}, (err, docs) ->
    if err
      callbackResults(err)
    else
      results = _.sortBy docs, (doc) -> ids.indexOf(doc._id)
      results = _.map results, (result, index) ->
        result.score = sorted[index].value
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
  loadClassifier ->
    indexUrls program.args, (err) ->
      if err then errorPrint err
      debugPrint "finished"

else if program.search
  loadClassifier ->
    search program.args.join(' '), 5, (err, results) ->
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
  fs.unlink './classifier.json', (err) -> if err then debugPrint err

  if typeof program.reset is "string"
    fs.createReadStream('./backups/' + program.reset).pipe(fs.createWriteStream('bookmarks.json'))
    rebuildClassifier (err) ->
      if err then errorPrint err
      debugPrint "finished"

else if program.safari
  loadClassifier ->
    p = exec "./safari.sh", (err, stdout, stderr) ->
      if err
        errorPrint err
      else
        bookmarks = stdout.split('\n')[..20]
        indexUrls bookmarks, (err) ->
          if err then errorPrint err
          debugPrint "finished import safari bookmarks"

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
