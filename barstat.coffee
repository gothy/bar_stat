fs = require 'fs'
express = require 'express'
app = express()
__ = require 'underscore'
bcrypt = require 'bcrypt'
async = require 'async'
moment = require 'moment'
utils = require './utils'

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
            if reply then db.incr "#{partner}.#{day_ts}.u_count"

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

        get_partner_stats = (partner, cb) =>
            multi = db.multi()
            multi.scard "#{partner}.users"
            multi.get "#{partner}.#{day_ts}.u_count"
            multi.get "#{partner}.#{day_ts}.nu_count"
            multi.get "#{partner}.#{day_ts}.s_count"
            multi.exec (err, replies) =>
                if err then cb err
                sum_reply.u_count_total += parseInt(replies[0] || 0)
                sum_reply.u_count += parseInt(replies[1] || 0)
                sum_reply.nu_count += parseInt(replies[2] || 0)
                sum_reply.s_count += parseInt(replies[3] || 0)
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
            multi.exec (err, replies) =>
                if err then throw err
                total_u = parseInt(replies[0]) || 0
                n_u = parseInt(replies[1]) || 0
                returning_u = total_u - n_u
                reply =
                    name: moment(date).format("MMM Do 'YY");
                    data: [returning_u, n_u]
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
            
            multi.exec (err, replies) =>
                if err then throw err
                d_data = {name: moment(date).format("MMM Do 'YY"), data: []}
                for i in [0..partners.length-1]
                    d_data.data.push {partner: partners[i], val: parseInt(replies[i]) || 0}
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


launch = ->
    # Start the express app on port 1337.
    app.listen 1337
    console.log 'barstat started', new Date()
    exports.RUNNING = true

if not module.parent 
    launch()
else
    exports.launch = launch


process.on 'uncaughtException', (err) ->
    console.error err.stack

