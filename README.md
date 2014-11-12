# Commandline Bookmarks

This is an attempt to build a commandline tool for indexing and searching your bookmarks. I'm sick of having so many bookmarks and not being able to find any of them! This is supposed to be the solution, but its not quite working yet.

## Getting Started

Clone this repo:

    git clone https://github.com/ccorcos/bookmarks.git

You can play around with my bookmarks that are already loaded into `bookmarks.json` or you can load your own bookmarks. First, to clear out my bookmarks:

    ./bm reset

Then you can load your own manually with `./bm add <url> <url> <url> ...` or you can load all of your Safari bookmarks with `./bm safari` which gets all your Safari bookmarks using the `safari.sh` shell script.

Then you can try searching your bookmarks with `./bm search <query>`. Here's an example of the output:

![](/search.png)

## Implementation Details

The current implementation fetched the urls for each of your bookmarks. It parses out all the html so its left with just the plain text, the url, and the title of the webpage. These three things are stored in the `bookmarks.json` file using `nedb`.

Using the awesome natural language processing library, [`Natural`](https://github.com/NaturalNode/natural) I compile the results into a text-frequency inverse-text-frequency (tfidf) object to perform searches on the bookmarks.

If you look at some of the previous commits, I tried using their Naive Bayes classifier but I got worse results.

## Issues

Sometimes this script fails when importing a ton of bookmarks from Safari. This seems to be a problem with the async callbacks firing more than once when a url fails to be fetched and spontaneously tries again. I think I figured out the problem but I'm not 100% sure.

Another problem is simply that the search results aren't very good. If you look at the results for "github javascript", there really ought to be many many many more results that match that description. Tfidf is a very very simple algorithm and there is just no intelligent searching going on here. Something as simple as search "typography" won't show up for a website that has "typographic" in the title!

Long story short, this project is in dire need of a better searching algorithm. I'd really appreciate any help!
