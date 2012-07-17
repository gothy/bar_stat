// Generated by CoffeeScript 1.3.1
(function() {
  var app, async, bcrypt, check_if_needs_auth, db, express, fs, get_browser_name, get_ts_and_day_ts, moment, __;

  fs = require('fs');

  express = require('express');

  app = express();

  db = require("redis").createClient();

  __ = require('underscore');

  bcrypt = require('bcrypt');

  async = require('async');

  moment = require('moment');

  app.use(express.cookieParser('om nom nom'));

  app.use(express.session());

  app.use('/bar_stat/static/', express["static"](__dirname + '/static'));

  app.set('views', __dirname + '/templates');

  app.engine('html', function(path, options, fn) {
    return fs.readFile(path, 'utf8', function(err, str) {
      var html;
      if (err) {
        return fn(err);
      }
      try {
        html = __.template(str, options);
        return fn(null, html);
      } catch (err) {
        return fn(err);
      }
    });
  });

  get_browser_name = function(useragent) {
    var name;
    if (useragent.indexOf('Safari') >= 0) {
      if (useragent.indexOf('Chrome') >= 0) {
        return name = 'chrome';
      } else {
        return name = 'safari';
      }
    } else if (useragent.indexOf('Firefox') >= 0) {
      return name = 'ff';
    } else if (useragent.indexOf('Opera') >= 0) {
      return name = 'opera';
    } else if (useragent.indexOf('MSIE') >= 0) {
      return name = 'msie';
    } else {
      return name = 'other';
    }
  };

  get_ts_and_day_ts = function(date) {
    var cts, day_ts;
    cts = date.getTime();
    day_ts = "" + (date.getUTCFullYear()) + "-" + (date.getUTCMonth()) + "-" + (date.getUTCDate());
    return [cts, day_ts];
  };

  check_if_needs_auth = function(req) {
    return !(req.session.loggedin && req.session.user === req.params.partner);
  };

  app.get('/bar_stat/session/:partner/:instid', function(req, res, next) {
    var browser, cts, day_ts, instid, partner, _ref, _ref1,
      _this = this;
    instid = req.params.instid;
    partner = req.params.partner;
    browser = get_browser_name((_ref = req.headers) != null ? _ref['user-agent'] : void 0);
    console.log("new session request: " + partner + ":" + instid);
    if (!instid || !partner) {
      return;
    }
    _ref1 = get_ts_and_day_ts(new Date()), cts = _ref1[0], day_ts = _ref1[1];
    db.sismember("partners", partner, function(err, reply) {
      if (!reply) {
        return db.sadd("partners", partner);
      }
    });
    db.incr("" + partner + "." + day_ts + ".s_count", function(err, reply) {});
    db.sismember("" + partner + ".users", instid, function(err, reply) {
      db.sadd("" + partner + ".users", instid);
      if (!reply) {
        return db.incr("" + partner + "." + day_ts + ".nu_count");
      }
    });
    db.sadd("" + partner + "." + day_ts + ".users", instid, function(err, reply) {
      if (reply) {
        return db.incr("" + partner + "." + day_ts + ".u_count");
      }
    });
    return res.send('ok');
  });

  app.get('/bar_stat/panel/:partner/', function(req, res, next) {
    var needs_auth;
    needs_auth = check_if_needs_auth(req);
    return res.render('index.html', {
      partner: req.params.partner,
      needs_auth: needs_auth
    });
  });

  app.get('/bar_stat/api/login/:partner/', function(req, res, next) {
    var partner, secret;
    partner = req.params.partner;
    secret = req.query.secret;
    if (!secret) {
      res.send('nosecret', 400);
    }
    console.log("" + partner + " login attempt");
    return db.hget("partner.creds." + partner, 'hsecret', function(err, reply) {
      var success;
      if (!reply) {
        res.send('nouser', 400);
      }
      success = bcrypt.compareSync(secret, reply);
      if (success) {
        req.session.user = partner;
        req.session.loggedin = true;
        return res.send('ok');
      } else {
        req.session.loggedin = false;
        return res.send('badsecret', 401);
      }
    });
  });

  app.get('/bar_stat/api/:partner/usage', function(req, res, next) {
    var day_ts, multi, partner, ts, _ref,
      _this = this;
    partner = req.params.partner;
    if (check_if_needs_auth(req)) {
      res.send('denied', 401);
    }
    _ref = get_ts_and_day_ts(new Date()), ts = _ref[0], day_ts = _ref[1];
    multi = db.multi();
    multi.scard("" + partner + ".users");
    multi.get("" + partner + "." + day_ts + ".u_count");
    multi.get("" + partner + "." + day_ts + ".nu_count");
    multi.get("" + partner + "." + day_ts + ".s_count");
    return multi.exec(function(err, replies) {
      var reply;
      if (err) {
        throw err;
      }
      reply = {
        u_count_total: replies[0] || 0,
        u_count: replies[1] || 0,
        nu_count: replies[2] || 0,
        s_count: replies[3] || 0
      };
      return res.send(reply);
    });
  });

  app.get('/bar_stat/api/:partner/graphdata', function(req, res, next) {
    var d, daily_stats, dates, get_daily_stats, i, partner;
    partner = req.params.partner;
    if (check_if_needs_auth(req)) {
      res.send('denied', 401);
    }
    d = new Date();
    dates = (function() {
      var _i, _results;
      _results = [];
      for (i = _i = 14; _i >= 1; i = --_i) {
        _results.push(moment().subtract('days', i).toDate());
      }
      return _results;
    })();
    daily_stats = [];
    get_daily_stats = function(date, cb) {
      var day_ts, multi, ts, _ref,
        _this = this;
      _ref = get_ts_and_day_ts(date), ts = _ref[0], day_ts = _ref[1];
      multi = db.multi();
      multi.get("" + partner + "." + day_ts + ".u_count");
      multi.get("" + partner + "." + day_ts + ".nu_count");
      return multi.exec(function(err, replies) {
        var n_u, reply, returning_u, total_u;
        if (err) {
          throw err;
        }
        total_u = parseInt(replies[0]) || 0;
        n_u = parseInt(replies[1]) || 0;
        returning_u = total_u - n_u;
        reply = {
          name: moment(date).format("MMM Do 'YY"),
          data: [returning_u, n_u]
        };
        daily_stats.push(reply);
        return cb();
      });
    };
    return async.forEach(dates, get_daily_stats, function(err) {
      if (err) {
        console.error(err);
      }
      return res.send(daily_stats);
    });
  });

  app.listen(1337);

  console.log('barstat started', new Date());

  process.on('uncaughtException', function(err) {
    return console.error(err.stack);
  });

}).call(this);
