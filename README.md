# fluent-plugin-keen

> [Keen IO](https://keen.io) is an analytics API for modern developers. Track any event: signups, upgrades, impressions,
purchases, powerups, errors, shares… Use Keen IO to embed analytics in your site or white label analytics for your
customers. Keen IO is your new, lovingly crafted, massively scalable, event data backend in the cloud.

> [Fluentd](http://www.fluentd.org) is an open source data collector for unified logging layer that allows you to unify
data collection and consumption for a better use and understanding of data.

This plugin allows you to send data through a Fluent instance to the Keen API. The data will be buffered and slightly
delayed when it goes into Keen, but it'll reliably scale as spikes of incoming events come flooding in!

**Note:** This is a first production Ruby project, however it is in production use for
[Car Throttle](https://www.carthrottle.com), and of course we welcome any and all feedback and/or pull-requests! :wink:

**Also:** Various paths in this README point to `/etc/td-agent` rather than a `fluentd` folder since in production we're
using `td-agent`, which is the [stable packaged edition](http://docs.fluentd.org/articles/install-by-deb) of fluent.

**Finally,** this was inspired by the amazing [fluent-plugin-slack](https://github.com/sowawa/fluent-plugin-slack),
which is also used in production for [Car Throttle](https://www.carthrottle.com) to notify us if Fluent encounters
issues!

## Installation

Right now this plugin can't be downloaded via RubyGems, so the quickest way is to install with git:

```
git clone https://github.com/car-throttle/fluent-plugin-keen
ln -s fluent-plugin-keen/keen.rb /etc/td-agent/plugins/keen.rb
```

## Configuration

```
<source>
  @type forward
  bind 0.0.0.0
  port 24224
</source>

<match fluent.warn fluent.error fluent.fatal>
  @type slack
  webhook_url https://hooks.slack.com/services/a4f68d57/5f805d1f6e1/1c31dc5cfd4a3
  channel devops
  username fluent-bot
  icon_emoji :fluentd:
  color danger
  flush_interval 60s
</match>

<match analytics.carthrottle.**>
  @type keen
  project_id 691b237601b00f425d79b3a523f1b1d3
  write_key f4174f9f9b5589e8f9c04bce419b1aa2ddb89122fa93b38347c97712a4b980d4dc5e3ca7a48245623f9340ceabc2c282

  flush_interval 5s
  buffer_type file
  buffer_path /etc/td-agent/buffer-keen/
  buffer_chunk_limit 5m
  buffer_queue_limit 1024
</match>
<match analytics.catthrottle.**>
  @type keen
  project_id 43641d36d5887ba8a82cb294e4daba04
  write_key 8347c97712a4b980d4dc5e3ca7a48245623f9340ceabc2c282f4174f9f9b5589e8f9c04bce419b1aa2ddb89122fa93b3
</match>
<match analytics.**>
  @type null
</match>
```

In this example, we have two projects each using the Keen plugin, both receiving events from TCP/UDP 24224 and we also
have fluentd sending it's own logs to Slack in the event a `warn`, `error` or `fatal` are logged.

Since each project has a different set of credentials, they require two separate `match` blocks. The event names are
the last part of the tag, so sending `analytics.carthrottle.post_created` would result in a `post_created` event being
added to Keen.

This plugin supports buffering too, so adding any of the standard
[buffer parameters](http://docs.fluentd.org/articles/buffer-plugin-overview) is also supported. `file` buffers seem to
be the best, because they persist if the process is restarted! Once buffered the data will be sent in batches using the
Keen [multiple events API](https://keen.io/docs/api/#record-multiple-events) rather than one HTTP request per event.

## Usage

Go grab yourself whatever [client library](http://docs.fluentd.org/v0.12/categories/logging-from-apps) you desire, for
whatever language suits your needs, and start sending data to fluent:

```js
var fluentLogger = require('fluent-logger');

var analytics = fluentLogger.createFluentSender('analytics', {
  host: 'localhost',
  port: 24224,
  timeout: 3.0
});

analytics.on('error', function (err) {
  console.error(err); // Or something more appropriate in production?
});

analytics.emit('carthrottle.post_created', {
  post_id: 123456,
  content_type: 'image',
  permalink: '/post/nxvq79q/',
  score: 2376,
  comments: 105
});
```

So, what will actually happen here?

- [`fluent-logger`](https://www.npmjs.com/package/fluent-logger) will concatenate this tag to create
  `analytics.carthrottle.post_created`
- fluentd will receive it and buffer it as you specify
- This plugin will make a HTTP POST request to a URL similar to:
  `https://api.keen.io/3.0/projects/PROJECT_ID/events`
  (As specified in the Keen docs: https://keen.io/guides/getting-started/)
- If a response other than a 201 is returned, an error will be outputted to the fluentd logs (and to Slack, because of
  that fluent-slack-plugin) with appropriate information to assist in debugging

## Debugging

If you add `debug_keen true` to your fluent-plugin-keen config block, you'll be able to see debug information for your
events as they are sent to Keen. This is useful for confirming your setup is working, as well as seeing what events are
being sent and how many events are being sent too.

```
<match analytics.carthrottle.**>
  @type keen
  project_id 43641d36d5887ba8a82cb294e4daba04
  write_key 8347c97712a4b980d4dc5e3ca7a48245623f9340ceabc2c282f4174f9f9b5589e8f9c04bce419b1aa2ddb89122fa93b3
  debug_keen true
  flush_interval 5s
</match>
```

Your output will look similar to:

```
2016-03-03 11:34:29 +0000 [info]: Keen: debug_keen has been enabled
2016-03-03 11:34:29 +0000 [info]: Keen: Ready
2016-03-03 11:34:30 +0000 [info]: listening fluent socket on 0.0.0.0:24224
2016-03-03 11:34:35 +0000 [info]: Sending:
2016-03-03 11:34:35 +0000 [info]: - 166 post_created
2016-03-03 11:34:35 +0000 [info]: - 7 profile_view
2016-03-03 11:34:36 +0000 [info]: Sent batch!
2016-03-03 11:34:40 +0000 [info]: Sending:
2016-03-03 11:34:40 +0000 [info]: - 148 post_created
2016-03-03 11:34:40 +0000 [info]: - 1 profile_view
2016-03-03 11:34:40 +0000 [info]: Sent batch!
2016-03-03 11:34:45 +0000 [info]: Sending:
2016-03-03 11:34:45 +0000 [info]: - 157 post_created
2016-03-03 11:34:45 +0000 [info]: - 4 profile_view
2016-03-03 11:34:45 +0000 [info]: Sent batch!
```

## Changelog

- 03/03/2016
  - Events are sent to Keen in batches, to improve performance, using
    [this Keen endpoint](https://keen.io/docs/api/?shell#record-multiple-events)
  - Stability improvements for quicker shutdown times

- 02/03/2016
  - Initial version published

## Questions

Great! [Open an issue](https://github.com/car-throttle/fluent-plugin-keen/issues) or feel free to
[tweet JJ](https://twitter.com/jdrydn) and we'll get back to you!
