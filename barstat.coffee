fs = require 'fs'
express = require 'express'
app = express()
db = require("redis").createClient()
__ = require 'underscore'
bcrypt = require 'bcrypt'
async = require 'async'
moment = require 'moment'


# signed cookies
app.use express.cookieParser('om nom nom')
# enable sessions
app.use express.session()
# support for static files
app.use '/bar_stat/static/', express.static(__dirname + '/static')
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


get_browser_name = (useragent)->
    if useragent.indexOf('Safari') >= 0 
        if useragent.indexOf('Chrome') >= 0 
            name = 'chrome' 
        else 
            name = 'safari'
    else if useragent.indexOf('Firefox') >= 0
        name = 'ff'
    else if useragent.indexOf('Opera') >= 0
        name = 'opera'
    else if useragent.indexOf('MSIE') >= 0
        name = 'msie'
    else 
        name = 'other'

get_ts_and_day_ts = (date) ->
    cts = date.getTime()
    day_ts = "#{date.getUTCFullYear()}-#{date.getUTCMonth()}-#{date.getUTCDate()}"

    return [cts, day_ts]

check_if_needs_auth = (req) ->
    not (req.session.loggedin and req.session.user is req.params.partner)

# new session
app.get '/bar_stat/session/:partner/:instid', (req, res, next) ->
    instid = req.params.instid
    partner = req.params.partner
    browser = get_browser_name req.headers?['user-agent']
    console.log "new session request: #{partner}:#{instid}"
    if not instid or not partner then return

    [cts, day_ts] = get_ts_and_day_ts(new Date())

    # add new partner if needed
    db.sismember "partners", partner, (err, reply) =>
        if not reply then db.sadd "partners", partner
    
    # add a session record
    db.incr "#{partner}.#{day_ts}.s_count", (err, reply) =>
        # temporary disabled saving session data
        # db.hmset "#{partner}.#{day_ts}.session.#{reply}", {
        #     instid: instid
        #     browser: browser
        #     ts: cts
        # }, (err, reply) =>
        #     if err then console.error err.stack

    # add to partner users and increment user count if needed
    db.sismember "#{partner}.users", instid, (err, reply) =>
        db.sadd "#{partner}.users", instid
        if not reply then db.incr "#{partner}.#{day_ts}.nu_count"
    
    db.sadd "#{partner}.#{day_ts}.users", instid, (err, reply) =>
        if reply then db.incr "#{partner}.#{day_ts}.u_count"

    res.send 'ok'


# partner's homepage
app.get '/bar_stat/panel/:partner/', (req, res, next) ->
    needs_auth = check_if_needs_auth(req)
    res.render 'index.html', {
        partner: req.params.partner
        needs_auth: needs_auth
    }

# login here :)
app.get '/bar_stat/api/login/:partner/', (req, res, next) ->
    partner = req.params.partner
    secret = req.query.secret
    if not secret then res.send 'nosecret', 400
    console.log "#{partner} login attempt"
    db.hget "partner.creds.#{partner}", 'hsecret', (err, reply) ->
        if not reply then res.send 'nouser', 400
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
    if check_if_needs_auth(req) then res.send 'denied', 401

    [ts, day_ts] = get_ts_and_day_ts(new Date())

    multi = db.multi()
    multi.scard "#{partner}.users"
    multi.get "#{partner}.#{day_ts}.u_count"
    multi.get "#{partner}.#{day_ts}.nu_count"
    multi.get "#{partner}.#{day_ts}.s_count"
    multi.exec (err, replies) =>
        if err then throw err
        reply =
            u_count_total: replies[0] || 0
            u_count: replies[1] || 0
            nu_count: replies[2] || 0
            s_count: replies[3] || 0
        
        res.send reply

app.get '/bar_stat/api/:partner/graphdata', (req, res, next) ->
    partner = req.params.partner
    if check_if_needs_auth(req) then res.send 'denied', 401

    d = new Date()
    dates = (moment().subtract('days', i).toDate() for i in [14..1])
    daily_stats = []

    get_daily_stats = (date, cb) ->
        [ts, day_ts] = get_ts_and_day_ts(date)
        multi = db.multi()
        multi.get "#{partner}.#{day_ts}.u_count"
        multi.get "#{partner}.#{day_ts}.nu_count"
        multi.exec (err, replies) =>
            if err then throw err
            total_u = parseInt(replies[0]) || 0
            n_u = parseInt(replies[1]) || 0
            returning_u = total_u - n_u
            reply =
                name: moment(date).format("MMM Do 'YY");
                data: [returning_u, n_u]
            console.log replies
            daily_stats.push reply
            cb()
    
    async.forEach dates, get_daily_stats, (err) ->
        if err then console.error err
        console.log daily_stats
        res.send daily_stats


# Start the express app on port 1337.
app.listen 1337
console.log 'barstat started', new Date()

process.on 'uncaughtException', (err) ->
    console.error err.stack

