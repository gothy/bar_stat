buster = require "buster"
request = require 'request'
redis = require 'redis'
utils = require '../utils'
barstat = require '../barstat'

ROOT_PATH = 'http://localhost:1337/bar_stat/'

buster.testCase 'test api',
    setUp: (done) ->
        @db = db = utils.get_db_client()
        db.select 10, () => # make db #10 is a test DB
            db.flushdb (err, reply) =>
                console.log 'cleaning up test DB '
                @spy utils, 'get_db_client'
                @spy utils, 'get_ts_and_day_ts'
                @spy utils, 'get_browser_name'
                if not barstat.RUNNING then barstat.launch()
                multi = db.multi()
                multi.hset 'partner.creds.test', 
                    'hsecret', 
                    "$2a$10$bNgCrGwIGGCaffxAQ1Hku.frwE819shB4ATbpKr1Vp5C1Gdo3EM8y"
                multi.hset 'partner.creds.overall', 
                    'hsecret', 
                    "$2a$10$bNgCrGwIGGCaffxAQ1Hku.frwE819shB4ATbpKr1Vp5C1Gdo3EM8y",
                multi.exec (err, replies) ->
                    done()

    'test new session': (done) ->
        request "#{ROOT_PATH}session/test/testid/", (err, res, body) ->
            assert.calledOnce utils.get_db_client
            assert.calledOnce utils.get_ts_and_day_ts
            assert.calledOnce utils.get_browser_name
            assert.same res.statusCode, 200
            assert.same body, 'ok'
            done()

    'test panel': (done) ->

        request {url: "#{ROOT_PATH}panel/test/", jar: false}, (err, res, body) ->
            refute.called utils.get_db_client
            refute.called utils.get_ts_and_day_ts
            assert.match body, 'needs_auth = true'
            done()

    'test login without pwd': (done) ->
        request "#{ROOT_PATH}api/login/test/", (err, res, body) ->
            refute.called utils.get_db_client
            refute.called utils.get_ts_and_day_ts
            assert.same res.statusCode, 400
            assert.same body, 'nosecret'
            done()

    'test login with wrong user': (done) ->
        request "#{ROOT_PATH}api/login/testeee/?secret=f1234", (err, res, body) ->
            assert.calledOnce utils.get_db_client
            refute.called utils.get_ts_and_day_ts
            assert.same res.statusCode, 400
            assert.same body, 'nouser'
            done()

    'test login with wrong pwd': (done) ->
        request "#{ROOT_PATH}api/login/test/?secret=f1234", (err, res, body) ->
            assert.calledOnce utils.get_db_client
            refute.called utils.get_ts_and_day_ts
            assert.same res.statusCode, 401
            assert.same body, 'badsecret'
            done()

    'test login': (done) ->
        request "#{ROOT_PATH}api/login/test/?secret=ololo", (err, res, body) ->
            assert.calledOnce utils.get_db_client
            refute.called utils.get_ts_and_day_ts
            assert.same res.statusCode, 200
            assert.same body, 'ok'
            done()

    'test usage': {
        setUp: (done) =>
            request "#{ROOT_PATH}session/test/1q2w3e4r5t6y7u/", (err, res, body) ->
                assert.equals body, 'ok'
                request "#{ROOT_PATH}session/test2/0o9i8u7y6t/", (err, res, body) ->
                    assert.equals body, 'ok'
                    done()

        'test panel api for <test> partner': {
            setUp: (done) ->
                request "#{ROOT_PATH}api/login/test/?secret=ololo", (err, res, body) ->
                    done()
            
            'test usage for <test>': (done) ->
                request "#{ROOT_PATH}api/test/usage", (err, res, body) ->
                    resobj = JSON.parse(body)
                    assert.equals resobj, {
                        "u_count_total": 1,
                        "u_count": 1,
                        "nu_count": 1,
                        "s_count": 1,
                        "chrome_count": 0,
                        "ff_count": 0,
                        "opera_count": 0
                    }
                    done()

            'test graphdata for <test>': (done) ->
                request "#{ROOT_PATH}api/test/graphdata", (err, res, body) ->
                    resobj = JSON.parse(body)
                    assert.equals resobj.length, 14 # 2 weeks
                    for day_data in resobj 
                        assert.equals day_data.data, [0, 0]
                        assert.defined day_data.name

                    done()
        }

        'test panel api for overall usage': {
            setUp: (done) ->
                request "#{ROOT_PATH}api/login/overall/?secret=ololo", (err, res, body) ->
                    done()

            'test usage for overall': (done) ->
                request "#{ROOT_PATH}api/overall/usage", (err, res, body) ->
                    resobj = JSON.parse(body)
                    assert.equals resobj, {
                        "u_count_total": 2,
                        "u_count": 2,
                        "nu_count": 2,
                        "s_count": 2,
                        "chrome_count": 0,
                        "ff_count": 0,
                        "opera_count": 0
                    }
                    done()
        }
    }

        