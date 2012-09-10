fs = require 'fs'
express = require 'express'
app = express()
__ = require 'underscore'
bcrypt = require 'bcrypt'
async = require 'async'
moment = require 'moment'
utils = require './utils'
uuid = require 'node-uuid'

FeedParser = require('feedparser')

# signed cookies
app.use express.cookieParser('om nom nom')
# enable sessions
app.use express.session()
# support for static files
app.use '/bar_stat/static/', express.static(__dirname + '/static')
# to parse uploaded files
app.use(express.bodyParser({ keepExtensions: false, uploadDir: __dirname + '/uploads/' }));
# define where the views are
app.set('views', __dirname + '/templates');
# define renderer for html files(underscore templates for now)
app.engine 'html', (path, options, fn) ->
    fs.readFile path, 'utf8', (err, str) ->
        if (err) then return fn(err)
        try
            html = __.template(str, options)
            fn(null, html)
        catch err
            fn(err)


# new session
app.get '/bar_stat/session/:partner/:instid', (req, res, next) ->
    instid = req.params.instid
    partner = req.params.partner
    browser = utils.get_browser_name req.headers?['user-agent']
    console.log "new session request: #{partner}:#{instid}"
    if not instid or not partner 
        res.send('n_e_data', 400)
    else
        [cts, day_ts] = utils.get_ts_and_day_ts(new Date())
        db = utils.get_db_client()

        # add new partner if needed
        db.sismember "partners", partner, (err, reply) =>
            if not reply then db.sadd "partners", partner
        
        # add a session record
        db.incr "#{partner}.#{day_ts}.s_count", (err, reply) =>

        # add to partner users and increment user count if needed
        db.sismember "#{partner}.users", instid, (err, reply) =>
            db.sadd "#{partner}.users", instid
            if not reply then db.incr "#{partner}.#{day_ts}.nu_count"
        
        db.sadd "#{partner}.#{day_ts}.users", instid, (err, reply) =>
            if reply 
                db.incr "#{partner}.#{day_ts}.u_count"
                db.incr "#{partner}.#{day_ts}.#{browser}.u_count"

        res.send 'ok'

# new action
app.post '/bar_stat/action/:action/:partner/', (req, res, next) ->
    partner = req.params.partner
    action = req.params.action
    console.log "new action request: #{partner}:#{action}"
    if not action or not partner 
        res.send('n_e_data', 400)
    else
        [cts, day_ts] = utils.get_ts_and_day_ts(new Date())
        db = utils.get_db_client()
        
        # add an action record
        db.incr "#{partner}.#{day_ts}.#{action}.count", (err, reply) =>
            res.send 'ok'

# partner's homepage
app.get '/bar_stat/panel/:partner/', (req, res, next) ->
    needs_auth = utils.check_if_needs_auth(req)
    res.render 'index.html', {
        partner: req.params.partner
        needs_auth: needs_auth
    }

# login here :)
app.get '/bar_stat/api/login/:partner/', (req, res, next) ->
    partner = req.params.partner
    secret = req.query.secret
    if not secret 
        res.send 'nosecret', 400
    else 
        console.log "#{partner} login attempt"
        db = utils.get_db_client()
        db.hget "partner.creds.#{partner}", 'hsecret', (err, reply) ->
            if not reply 
                res.send 'nouser', 400
            else 
                success = bcrypt.compareSync secret, reply
                if success
                    req.session.user = partner
                    req.session.loggedin = true
                    res.send 'ok'
                else 
                    req.session.loggedin = false
                    res.send 'badsecret', 401

# fetches data to show
app.get '/bar_stat/api/:partner/usage', (req, res, next) ->
    partner = req.params.partner
    if utils.check_if_needs_auth(req) 
        res.send 'denied', 401
    else
        [ts, day_ts] = utils.get_ts_and_day_ts(new Date())
        db = utils.get_db_client()
        sum_reply =
            u_count_total: 0
            u_count: 0
            nu_count: 0
            s_count: 0
            click_count: 0
            chrome_count: 0
            ff_count: 0
            opera_count: 0

        get_partner_stats = (partner, cb) =>
            multi = db.multi()
            multi.scard "#{partner}.users"
            multi.get "#{partner}.#{day_ts}.u_count" # user count
            multi.get "#{partner}.#{day_ts}.nu_count" # new users
            multi.get "#{partner}.#{day_ts}.s_count" # sessions
            multi.get "#{partner}.#{day_ts}.click.count" # <click> actions
            multi.get "#{partner}.#{day_ts}.chrome.u_count"
            multi.get "#{partner}.#{day_ts}.ff.u_count"
            multi.get "#{partner}.#{day_ts}.opera.u_count"
            multi.exec (err, replies) =>
                if err then cb err
                sum_reply.u_count_total += parseInt(replies[0] || 0)
                sum_reply.u_count += parseInt(replies[1] || 0)
                sum_reply.nu_count += parseInt(replies[2] || 0)
                sum_reply.s_count += parseInt(replies[3] || 0)
                sum_reply.click_count += parseInt(replies[4] || 0)
                sum_reply.chrome_count += parseInt(replies[5] || 0)
                sum_reply.ff_count += parseInt(replies[6] || 0)
                sum_reply.opera_count += parseInt(replies[7] || 0)
                cb()

        db.smembers "partners", (err, partners) =>
            if err 
                console.error(err); res.send('error')
            else
                # catch a single partner case
                if partner isnt 'overall' then partners = [partner,]
                # ---------------------------
                async.forEach partners, get_partner_stats, (err) =>
                    if err 
                        console.error err
                        res.send 'error', 500
                    else
                        res.send sum_reply

app.get '/bar_stat/api/:partner/graphdata', (req, res, next) ->
    partner = req.params.partner
    if utils.check_if_needs_auth(req) 
        res.send 'denied', 401
    else
        d = new Date()
        dates = (moment().subtract('days', i).toDate() for i in [14..1])
        daily_stats = []
        db = utils.get_db_client()

        get_daily_stats = (date, cb) ->
            [ts, day_ts] = utils.get_ts_and_day_ts(date)
            multi = db.multi()
            multi.get "#{partner}.#{day_ts}.u_count"
            multi.get "#{partner}.#{day_ts}.nu_count"
            multi.get "#{partner}.#{day_ts}.click.count"
            multi.exec (err, replies) =>
                if err then throw err
                total_u = parseInt(replies[0]) || 0
                n_u = parseInt(replies[1]) || 0
                clicks = parseInt(replies[2]) || 0
                returning_u = total_u - n_u
                reply =
                    name: moment(date).format("MMM Do 'YY");
                    data: [returning_u, n_u, clicks]
                daily_stats.push reply
                cb()
        
        async.forEach dates, get_daily_stats, (err) ->
            if err 
                console.error err
                res.send 'error', 500
            else
                res.send daily_stats

app.get '/bar_stat/api/:partner/sumgraphdata', (req, res, next) ->
    partner = 'overall' # force partner name
    if utils.check_if_needs_auth(req) 
        res.send 'denied', 401
    else
        d = new Date()
        dates = (moment().subtract('days', i).toDate() for i in [14..1])
        partners = []
        daily_stats = []
        db = utils.get_db_client()

        get_daily_common_stats = (date, cb) ->
            [ts, day_ts] = utils.get_ts_and_day_ts(date)
            multi = db.multi()
            for p in partners
                multi.get "#{p}.#{day_ts}.u_count"
                multi.get "#{p}.#{day_ts}.click.count"
            
            multi.exec (err, replies) =>
                if err then throw err
                d_data = {name: moment(date).format("MMM Do 'YY"), data: []}
                for i in [0..2*partners.length-1] by 2
                    d_data.data.push {
                        partner: partners[i/2], 
                        users: parseInt(replies[i]) || 0
                        clicks: parseInt(replies[i+1]) || 0
                    }
                daily_stats.push d_data
                cb()

        db.smembers "partners", (err, partners_list) =>
            if err 
                console.error(err); res.send('error')
            else
                partners = partners_list
                async.forEach dates, get_daily_common_stats, (err) ->
                    if err 
                        console.error err
                        res.send 'error', 500
                    else
                        res.send daily_stats

# get upload token
app.get '/bar_uploads/requestid/:partner/:instid', (req, res, next) ->
    db = utils.get_db_client()
    partner = req.params.partner
    instid = req.params.instid

    # generate unique token for file upload
    # todo: expiring tokens
    token = uuid.v1()
    multi = db.multi()
    multi.hmset "up.#{token}", {partner: partner, instid: instid}
    multi.expire "up.#{token}", 24*3600
    multi.exec (err, replies) ->
        res.send token

# uploading file
app.post '/bar_uploads/file/:token', (req, res, next) ->
    db = utils.get_db_client()
    token = req.params.token
    instid = req.body.instid
    partner = req.body.partner
    file = req.files.fm_file_upload
    console.log "new upload by #{instid} of #{partner}"

    # todo: cleanup token data and files
    if file
        db.hgetall "up.#{token}", (err, reply) =>
            if reply and (reply.instid is instid) and (reply.partner is partner)
                db.hmset "up.#{token}", 
                        {name: file.name, path: file.path, type: file.type}, 
                        (err, reply) ->
                    res.send 'ok'
            else 
                res.send 'fail'
    else
        res.send 'fail'

# getting file
app.get '/bar_uploads/file/:token', (req, res, next) ->
    db = utils.get_db_client()
    token = req.params.token

    db.hgetall "up.#{token}", (err, reply) ->
        if reply
            res.set 'Content-Disposition', "attachment; filename=\"#{reply.name}\""
            res.set 'Content-Type', "#{reply.type}"
            res.sendfile reply.path
        else
            res.send 404, 'Not found, sorry!'

#MirTesen helper
app.get '/mtrss/', (req, res, next) ->
    db = utils.get_db_client()
    db.get 'mtrss', (err, reply) ->
        res.set 'Content-Type', 'application/rss+xml'
        #res.set 'Content-Type', 'text/xml'
        res.send reply

combine_mt_feed = ->
    feeds = ['http://smi.mirtesen.ru/blog/rss', 'http://klikabol.mirtesen.ru/blog/rss',
     'http://showbiz.mirtesen.ru/blog/rss', 'http://zanimatsyaseksom.mirtesen.ru/blog/rss',
     'http://sam.mirtesen.ru/blog/rss', 'http://sdelaisam.mirtesen.ru/blog/rss',
     'http://mobilochko.ru/blog/rss', 'http://strasti.mirtesen.ru/blog/rss',
     'http://turprikol.mirtesen.ru/blog/rss', 'http://mylenta.mirtesen.ru/blog/rss']
    result = ''
    rss_template = __.template '''
    <?xml version="1.0"?> 
    <rss version="2.0">
    <channel>
        <%= articles %>
    </channel>
    </rss>
    '''
    item_template = __.template '''
    <item>
        <title><%=title%></title>
        <date><%=date%></date>
        <link><%=link%></link>
    </item>
    '''

    feed_extractor = (url, cb) ->
        parser = new FeedParser()
        parser.parseUrl url, (error, meta, articles) ->
            a = articles[0]
            result += item_template({'date': a.date, 'link': a.link, 'title': a.title})
            cb()

    async.forEach feeds, feed_extractor, (err) ->
        result = rss_template({articles: result})
        db = utils.get_db_client()
        db.set 'mtrss', result


launch = ->
    # Start the express app on port 1337.
    app.listen 1337
    console.log 'barstat started', new Date()
    exports.RUNNING = true
    combine_mt_feed()
    setTimeout combine_mt_feed, 600000

if not module.parent 
    launch()
else
    exports.launch = launch


process.on 'uncaughtException', (err) ->
    console.error err.stack

