app = require('express').createServer()
db = require("redis").createClient()

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

app.get '/bar_stat/session/:partner/:instid', (req, res, next) ->
    instid = req.params.instid
    partner = req.params.partner
    browser = get_browser_name req.headers?['user-agent']
    if not instid or not partner then return

    cdate = new Date()
    cts = cdate.getTime()
    day_ts = "#{cdate.getUTCFullYear()}-#{cdate.getUTCMonth()}-#{cdate.getUTCDate()}"

    # add new partner if needed
    db.sismember "partners", partner, (err, reply) =>
        if not reply then db.sadd "partners", partner
    
    # add a session record
    db.incr "#{partner}.#{day_ts}.s_count", (err, reply) =>
        db.hmset "#{partner}.#{day_ts}.session.#{reply}", {
            instid: instid
            browser: browser
            ts: cts
        }, (err, reply) =>
            if err then console.log err

    # add to partner users and increment user count if needed
    db.sismember "#{partner}.users", instid, (err, reply) =>
        db.sadd "#{partner}.users", instid
        if not reply then db.incr "#{partner}.#{day_ts}.nu_count"
    
    db.sadd "#{partner}.#{day_ts}.users", instid
    db.incr "#{partner}.#{day_ts}.u_count"

    res.send 'ok'

 
# Start the express app on port 1337.
app.listen 1337