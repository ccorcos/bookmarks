#!/usr/bin/env bash

defaults read ~/Library/Safari/Bookmarks.plist | sed -En 's/^ *URLString = "(.*)";/\1/p'
