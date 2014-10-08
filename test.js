#!/bin/env node

sys = require('sys');
async = require('async');
exec = require('child_process').exec;
urllib = require('url')


fetchUrls = function(urls, callback) {

  fetchEach = function(url, callback) {
    fetchUrlData(url, function(err, result) {
      if (err) {
        callback(err)
      } else {
        console.log("fetched")
        callback(null)
      }
    })
  }

  doneFetching = function(err) {
    if (err) {
      console.log(err)
      callback()
    } else {
      console.log("done fetching")
      callback()
    }
  }

  async.each(urls, fetchEach, doneFetching)
}



fetchUrlData = function(url, callback) {
  urlBits = urllib.parse(url)
  protolib = urlBits.protocol == "https:" ? "https" : "http"

  require(protolib).get(url, function(response) {
    data = ''
    response.on('data', function(chunk) {data += chunk});
    response.on('end', function() {
      callback(null, data)
    })
  }).on('error', function(err) {
    callback(err)
  });
}

p = exec("./test.sh", function(error, stdout, stderr) {
  urls = stdout.split('\n')
  console.log(urls)
  return fetchUrls(urls, function() {
    return console.log("finished");
  });
});
