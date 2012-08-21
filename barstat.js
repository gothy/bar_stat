// Generated by CoffeeScript 1.3.1
(function() {
  var FeedParser, app, async, bcrypt, combine_mt_feed, express, fs, launch, moment, utils, __;

  fs = require('fs');

  express = require('express');

  app = express();

  __ = require('underscore');

  bcrypt = require('bcrypt');

  async = require('async');

  moment = require('moment');

  utils = require('./utils');

  FeedParser = require('feedparser');

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

  app.get('/bar_stat/session/:partner/:instid', function(req, res, next) {
    var browser, cts, day_ts, db, instid, partner, _ref, _ref1,
      _this = this;
    instid = req.params.instid;
    partner = req.params.partner;
    browser = utils.get_browser_name((_ref = req.headers) != null ? _ref['user-agent'] : void 0);
    console.log("new session request: " + partner + ":" + instid);
    if (!instid || !partner) {
      return res.send('n_e_data', 400);
    } else {
      _ref1 = utils.get_ts_and_day_ts(new Date()), cts = _ref1[0], day_ts = _ref1[1];
      db = utils.get_db_client();
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
          db.incr("" + partner + "." + day_ts + ".u_count");
          return db.incr("" + partner + "." + day_ts + "." + browser + ".u_count");
        }
      });
      return res.send('ok');
    }
  });

  app.get('/bar_stat/action/:action/:partner/', function(req, res, next) {
    var action, cts, day_ts, db, partner, _ref,
      _this = this;
    partner = req.params.partner;
    action = req.params.action;
    console.log("new action request: " + partner + ":" + action);
    if (!action || !partner) {
      return res.send('n_e_data', 400);
    } else {
      _ref = utils.get_ts_and_day_ts(new Date()), cts = _ref[0], day_ts = _ref[1];
      db = utils.get_db_client();
      return db.incr("" + partner + "." + day_ts + "." + action + ".count", function(err, reply) {
        return res.send('ok');
      });
    }
  });

  app.get('/bar_stat/panel/:partner/', function(req, res, next) {
    var needs_auth;
    needs_auth = utils.check_if_needs_auth(req);
    return res.render('index.html', {
      partner: req.params.partner,
      needs_auth: needs_auth
    });
  });

  app.get('/bar_stat/api/login/:partner/', function(req, res, next) {
    var db, partner, secret;
    partner = req.params.partner;
    secret = req.query.secret;
    if (!secret) {
      return res.send('nosecret', 400);
    } else {
      console.log("" + partner + " login attempt");
      db = utils.get_db_client();
      return db.hget("partner.creds." + partner, 'hsecret', function(err, reply) {
        var success;
        if (!reply) {
          return res.send('nouser', 400);
        } else {
          success = bcrypt.compareSync(secret, reply);
          if (success) {
            req.session.user = partner;
            req.session.loggedin = true;
            return res.send('ok');
          } else {
            req.session.loggedin = false;
            return res.send('badsecret', 401);
          }
        }
      });
    }
  });

  app.get('/bar_stat/api/:partner/usage', function(req, res, next) {
    var day_ts, db, get_partner_stats, partner, sum_reply, ts, _ref,
      _this = this;
    partner = req.params.partner;
    if (utils.check_if_needs_auth(req)) {
      return res.send('denied', 401);
    } else {
      _ref = utils.get_ts_and_day_ts(new Date()), ts = _ref[0], day_ts = _ref[1];
      db = utils.get_db_client();
      sum_reply = {
        u_count_total: 0,
        u_count: 0,
        nu_count: 0,
        s_count: 0,
        click_count: 0,
        chrome_count: 0,
        ff_count: 0,
        opera_count: 0
      };
      get_partner_stats = function(partner, cb) {
        var multi;
        multi = db.multi();
        multi.scard("" + partner + ".users");
        multi.get("" + partner + "." + day_ts + ".u_count");
        multi.get("" + partner + "." + day_ts + ".nu_count");
        multi.get("" + partner + "." + day_ts + ".s_count");
        multi.get("" + partner + "." + day_ts + ".click.count");
        multi.get("" + partner + "." + day_ts + ".chrome.u_count");
        multi.get("" + partner + "." + day_ts + ".ff.u_count");
        multi.get("" + partner + "." + day_ts + ".opera.u_count");
        return multi.exec(function(err, replies) {
          if (err) {
            cb(err);
          }
          sum_reply.u_count_total += parseInt(replies[0] || 0);
          sum_reply.u_count += parseInt(replies[1] || 0);
          sum_reply.nu_count += parseInt(replies[2] || 0);
          sum_reply.s_count += parseInt(replies[3] || 0);
          sum_reply.click_count += parseInt(replies[4] || 0);
          sum_reply.chrome_count += parseInt(replies[5] || 0);
          sum_reply.ff_count += parseInt(replies[6] || 0);
          sum_reply.opera_count += parseInt(replies[7] || 0);
          return cb();
        });
      };
      return db.smembers("partners", function(err, partners) {
        if (err) {
          console.error(err);
          return res.send('error');
        } else {
          if (partner !== 'overall') {
            partners = [partner];
          }
          return async.forEach(partners, get_partner_stats, function(err) {
            if (err) {
              console.error(err);
              return res.send('error', 500);
            } else {
              return res.send(sum_reply);
            }
          });
        }
      });
    }
  });

  app.get('/bar_stat/api/:partner/graphdata', function(req, res, next) {
    var d, daily_stats, dates, db, get_daily_stats, i, partner;
    partner = req.params.partner;
    if (utils.check_if_needs_auth(req)) {
      return res.send('denied', 401);
    } else {
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
      db = utils.get_db_client();
      get_daily_stats = function(date, cb) {
        var day_ts, multi, ts, _ref,
          _this = this;
        _ref = utils.get_ts_and_day_ts(date), ts = _ref[0], day_ts = _ref[1];
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
          return res.send('error', 500);
        } else {
          return res.send(daily_stats);
        }
      });
    }
  });

  app.get('/bar_stat/api/:partner/sumgraphdata', function(req, res, next) {
    var d, daily_stats, dates, db, get_daily_common_stats, i, partner, partners,
      _this = this;
    partner = 'overall';
    if (utils.check_if_needs_auth(req)) {
      return res.send('denied', 401);
    } else {
      d = new Date();
      dates = (function() {
        var _i, _results;
        _results = [];
        for (i = _i = 14; _i >= 1; i = --_i) {
          _results.push(moment().subtract('days', i).toDate());
        }
        return _results;
      })();
      partners = [];
      daily_stats = [];
      db = utils.get_db_client();
      get_daily_common_stats = function(date, cb) {
        var day_ts, multi, p, ts, _i, _len, _ref,
          _this = this;
        _ref = utils.get_ts_and_day_ts(date), ts = _ref[0], day_ts = _ref[1];
        multi = db.multi();
        for (_i = 0, _len = partners.length; _i < _len; _i++) {
          p = partners[_i];
          multi.get("" + p + "." + day_ts + ".u_count");
        }
        return multi.exec(function(err, replies) {
          var d_data, i, _j, _ref1;
          if (err) {
            throw err;
          }
          d_data = {
            name: moment(date).format("MMM Do 'YY"),
            data: []
          };
          for (i = _j = 0, _ref1 = partners.length - 1; 0 <= _ref1 ? _j <= _ref1 : _j >= _ref1; i = 0 <= _ref1 ? ++_j : --_j) {
            d_data.data.push({
              partner: partners[i],
              val: parseInt(replies[i]) || 0
            });
          }
          daily_stats.push(d_data);
          return cb();
        });
      };
      return db.smembers("partners", function(err, partners_list) {
        if (err) {
          console.error(err);
          return res.send('error');
        } else {
          partners = partners_list;
          return async.forEach(dates, get_daily_common_stats, function(err) {
            if (err) {
              console.error(err);
              return res.send('error', 500);
            } else {
              return res.send(daily_stats);
            }
          });
        }
      });
    }
  });

  app.get('/mtrss/', function(req, res, next) {
    var db;
    db = utils.get_db_client();
    return db.get('mtrss', function(err, reply) {
      res.set('Content-Type', 'application/rss+xml');
      return res.send(reply);
    });
  });

  combine_mt_feed = function() {
    var feed_extractor, feeds, item_template, result, rss_template;
    feeds = ['http://smi.mirtesen.ru/blog/rss', 'http://klikabol.mirtesen.ru/blog/rss', 'http://showbiz.mirtesen.ru/blog/rss', 'http://zanimatsyaseksom.mirtesen.ru/blog/rss', 'http://sam.mirtesen.ru/blog/rss', 'http://sdelaisam.mirtesen.ru/blog/rss', 'http://mobilochko.ru/blog/rss', 'http://strasti.mirtesen.ru/blog/rss', 'http://turprikol.mirtesen.ru/blog/rss', 'http://mylenta.mirtesen.ru/blog/rss'];
    result = '';
    rss_template = __.template('<?xml version="1.0"?> \n<rss version="2.0">\n<channel>\n    <%= articles %>\n</channel>\n</rss>');
    item_template = __.template('<item>\n    <title><%=title%></title>\n    <date><%=date%></date>\n    <link><%=link%></link>\n</item>');
    feed_extractor = function(url, cb) {
      var parser;
      parser = new FeedParser();
      return parser.parseUrl(url, function(error, meta, articles) {
        var a;
        a = articles[0];
        result += item_template({
          'date': a.date,
          'link': a.link,
          'title': a.title
        });
        return cb();
      });
    };
    return async.forEach(feeds, feed_extractor, function(err) {
      var db;
      result = rss_template({
        articles: result
      });
      db = utils.get_db_client();
      return db.set('mtrss', result);
    });
  };

  launch = function() {
    app.listen(1337);
    console.log('barstat started', new Date());
    exports.RUNNING = true;
    combine_mt_feed();
    return setTimeout(combine_mt_feed, 600000);
  };

  if (!module.parent) {
    launch();
  } else {
    exports.launch = launch;
  }

  process.on('uncaughtException', function(err) {
    return console.error(err.stack);
  });

}).call(this);
