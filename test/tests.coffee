buster = require "buster"
request = require 'request'
redis = require 'redis'
utils = require '../utils'
barstat = require '../barstat'

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
                done()

    'test new session': (done) ->
        request 'http://localhost:1337/bar_stat/session/test/testid/', (err, res, body) ->
            assert.calledOnce utils.get_db_client
            assert.calledOnce utils.get_ts_and_day_ts
            assert.calledOnce utils.get_browser_name
            assert.same res.statusCode, 200
            assert.same body, 'ok'
            done()

    'test panel': (done) ->
        request 'http://localhost:1337/bar_stat/panel/test/', (err, res, body) ->
            refute.called utils.get_db_client
            refute.called utils.get_ts_and_day_ts
            assert.match body, 'needs_auth = true'
            done()

    'test login without pwd': (done) ->
        request 'http://localhost:1337/bar_stat/api/login/test/', (err, res, body) ->
            refute.called utils.get_db_client
            refute.called utils.get_ts_and_day_ts
            assert.same res.statusCode, 400
            assert.same body, 'nosecret'
            done()

    'test login with wrong user': (done) ->
        request 'http://localhost:1337/bar_stat/api/login/test/?secret=f1234', (err, res, body) ->
            assert.calledOnce utils.get_db_client
            refute.called utils.get_ts_and_day_ts
            assert.same res.statusCode, 400
            assert.same body, 'nouser'
            done()

    'test login with wrong pwd': (done) ->
        @db.hset 'partner.creds.test', 'hsecret', "$2a$10$bNgCrGwIGGCaffxAQ1Hku.frwE819shB4ATbpKr1Vp5C1Gdo3EM8y"
        request 'http://localhost:1337/bar_stat/api/login/test/?secret=f1234', (err, res, body) ->
            assert.calledOnce utils.get_db_client
            refute.called utils.get_ts_and_day_ts
            assert.same res.statusCode, 401
            assert.same body, 'badsecret'
            done()

    # 'test login': (done) ->
    #     request 'http://localhost:1337/bar_stat/api/login/test/?secret=ololo', (err, res, body) ->
    #         assert.calledOnce utils.get_db_client
    #         refute.called utils.get_ts_and_day_ts
    #         assert.same res.statusCode, 200
    #         assert.same body, 'ok'
    #         done()

