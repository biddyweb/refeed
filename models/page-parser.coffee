log = require("#{process.cwd()}/logger")

EventEmitter = require('events').EventEmitter
async        = require 'async'
_            = require 'lodash'
url          = require 'url'
cheerio      = require 'cheerio'

BlockParser  = require './block-parser'
PageLoader   = require './page-loader'

module.exports = class PageParser extends EventEmitter
    constructor: (@html, @config) ->
        super()
        @$ = cheerio.load @html, _.pick config, 'xmlMode', 'decodeEntities'
        @selectors = config.selectors

    start: ->
        self = this
        $ = @$
        config = @config

        startDate = new Date
        items = []

        # log 'info', "Modes for feed", config.modes

        # Refer to https://github.com/dylang/node-rss#feedoptions for fields
        for metadata in [
            'title', 'author', 'description', 'url', 'language',
            'categories', 'copyright', 'image_url', 'managingEditor',
            'docs', 'webMaster'
        ]
            matches = $ ":not(#{@selectors.item.block}) #{@selectors[metadata]}"
            if matches.length > 0
                object = new Object
                # metadataMode = config.modes[metadata]
                # log 'info', "Metadata mode for #{metadata} is #{metadataMode}"
                # object[metadata] = matches[metadataMode]()
                object[metadata] = matches.text()
                # log 'info', 'Emitting metadata', object
                self.emit 'metadata', object


        log 'debug', 'Block selector is', @selectors.item.block
        log 'verbose', "Found #{$(@selectors.item.block).length} items in page"

        $(@selectors.item.block).each ->
            try
                $block = $ this
                item = new Object
                config.fallbackDate = startDate - items.length

                for property in [
                    'title', 'author', 'description', 'url', 'date'
                ]
                    item[property] = BlockParser.parse property, $block, config

                items.push item
                log 'debug', 'Emitting item', item.url
                self.emit 'item', item unless config.full_page

            catch err
                log 'error', 'PageParser error', err
                self.emit 'error', err

        if config.full_page
            log 'warn', 'Feed set up to load full articles,
            this may take a while!'

            getFullPage = (item, done) ->
                loader = new PageLoader item.url

                loader.on 'pageLoaded', (html) ->
                    logg 'info', 'Article page loaded', item.url
                    $article = cheerio.load html
                    log 'info', 'Article length:', html.length
                    item.description = $article(config.full_page).html()
                    done null, item

                loader.on 'error', (err) ->
                    done err

                log 'info', 'Loading article page', item.url
                loader.load config

            async.mapLimit items, 3, getFullPage, (err, items) =>
                return @emit 'error', err if err
                @emit 'item', item for item in items
                @emit 'end'

        else @emit 'end'

    Object.defineProperty this.prototype, 'nextPage', {
        get: ->
            href = this.$(@selectors.nextPage).attr('href') || ''
            if url then url.resolve @config.host, href else null
    }

    Object.defineProperty @prototype, 'hasNext', {
        get: ->
            this.$(@selectors.nextPage).length
    }
