redis = require("redis")
__ = require 'underscore'

exports.clean_partner_cookie = (cookies)->
    cookies.build = cookies.build.split('/')[0]

exports.get_db_client = get_db_client = __.memoize ->
    console.log 'creating redis client'
    redis.createClient()

exports.get_browser_name = get_browser_name = (useragent='') ->
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

exports.get_ts_and_day_ts = get_ts_and_day_ts = (date) ->
    cts = date.getTime()
    day_ts = "#{date.getUTCFullYear()}-#{date.getUTCMonth()}-#{date.getUTCDate()}"

    return [cts, day_ts]

exports.check_if_needs_auth = check_if_needs_auth = (req) ->
    not (req.session.loggedin and req.session.user is req.params.partner)
