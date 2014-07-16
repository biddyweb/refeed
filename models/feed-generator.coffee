EventEmitter = require('events').EventEmitter

defaults   = require '../defaults.json'

_          = require 'lodash'
async      = require 'async'
fs         = require 'fs'
url        = require 'url'

cheerio    = require 'cheerio'

Feed       = require 'rss'
request    = require 'request'

PageLoader = require './page-loader'
PageParser = require './page-parser'

module.exports = class FeedGenerator extends EventEmitter
    constructor: (@feed_id, @config) ->
        @feed = new Feed
            title: config.title
            description: config.description
            site_url: config.url

        console.log 'Feed created'
        
        # Read file if exists, get the last entry guid we fetched
        @cachedFeed =
            path: "./feeds/#{feed_id}.xml"
            $: null
            lastArticleUrl: null

        if fs.existsSync @cachedFeed.path
            console.log "Reusing cached feed file #{@cachedFeed.path}"
            
            xml = fs.readFileSync(@cachedFeed.path).toString()
            console.log "Cached feed XML length is #{xml.length}"
            
            @cachedFeed.$ = cheerio.load xml, xmlMode: yes
            @cachedFeed.lastArticleUrl = @cachedFeed.$('item').first().find('link').text()

            console.log "Last cached article is #{@cachedFeed.lastArticleUrl}"
        else console.log "Cached file does not exist, was expected at #{@cachedFeed.path}"


    maxPages: Infinity

    generate: ->
        pageUrl        = @config.url
        loaded         = 0
        articles       = []
        parser         = null
        
        noMoreArticles = =>
            (loaded >= @maxPages) or
            (typeof pageUrl isnt 'string') or
            (_.contains articles, @cachedFeed.lastArticleUrl) or
            (!!parser and not parser.hasNext)

        end = =>
            xml = @.feed.xml()
            process.stdout.write 'Feed should be ready!\n'
            @.emit 'end', xml

        loadPage = (done) =>
            process.stdout.write "Loading page #{pageUrl}\n, total pages loaded: #{loaded}\n"
            
            loader = new PageLoader pageUrl
            loader.on 'pageLoaded', (html) =>  
                parser = new PageParser @config.host, html, @config

                parser.on 'item', (item) =>
                    @feed.item item
                    articles.push item.url

                parser.on 'end', =>
                    loaded += 1
                    if parser.hasNext
                        pageUrl = parser.nextPage
                    done()

                parser.start()

            loader.on 'error', (err) ->
                process.stderr.write err
                done err

            loader.load _.defaults(@config, defaults)

        async.until noMoreArticles, loadPage, end