 # meeseeker

Redis based block follower is an efficient way for multiple apps to stream the Steem Blockchain.

If you have multiple applications that need to perform actions as operations occur, `meeseeker` will allow your apps to each perform actions for specific operations without each app having to stream the entire blockchain.

*In a nutshell:* The overarching intent here is to provide a "live view" of the blockchain, *not* store the entire blockchain.  Apps can attach to your redis source and ask, "What *just* happened?"

## Purpose

Although Meeseeker tracks all operations, it is only intended to provide other applications signals that those operations have happened.  It is not intended to provide cryptographically verifiable events.

Possible uses:

* Notifications of events, suitable for push to mobile devices or web browsers.
* Invoke periodic updates on a threshold.
* Light-weight bots that only care about a limit set of operations, reducing the number of API calls.

## Why Redis?

Redis is a persistent key-value database, with built-in net interface.  See: https://redis.io/

It allows for quick storage and lookup of operations by key as well as the ability to automatically expire keys that are no longer needed.

### Installation

First, install redis:

On linux:

```bash
sudo apt install redis-server
```

On macOS:

```bash
brew install redis
```

Next, install ruby.  One way to do this is install [rvm](https://rvm.io/install).  Once ruby is installed, install `meeseeker` with the `gem` command:

```bash
gem install meeseeker
```

This installs meeseeker as a command available to the OS, e.g.:

```bash
meeseeker help
```

To do the actual sync to your local redis source (defaults assume `redis://127.0.0.1:6379/0`):

```bash
meeseeker sync
```

To specify an alternative redis source:

```bash
MEESEEKER_REDIS_URL=redis://:p4ssw0rd@10.0.1.1:6380/15 meeseeker sync
```

You can also specify an alternative Steem node:

```bash
MEESEEKER_NODE_URL=https://api.steemit.com meeseeker sync
```

To sync from the head block instead of the last irreversible block:

```bash
MEESEEKER_STREAM_MODE=head meeseeker sync
```

To ignore virtual operations (useful if the node doesn't enable `get_ops_in_blocks` or if you want to sync from the head block):

```bash
MEESEEKER_INCLUDE_VIRTUAL=false meeseeker sync
```

Normally, block headers are added to the `steem:block` channel.  This requires one additional API call for each block.  If you don't need block headers, you can configure the `steem:block` channel to only publish with the `block_num`:

```bash
MEESEEKER_INCLUDE_BLOCK_HEADER=false meeseeker sync
```

Normally, keys stay on redis for 24 hours.  If you want to change this behavior, use `MEESEEKER_EXPIRE_KEYS` and specify the new value in seconds, for example:

```bash
MEESEEKER_EXPIRE_KEYS=10 meeseeker sync
```

If you never want the keys to expire (not recommended), set
`MEESEEKER_EXPIRE_KEYS` to -1:

```bash
MEESEEKER_EXPIRE_KEYS=-1 meeseeker sync
```

### Usage

When `meeseeker sync` starts for the first time, it initializes from the last irreversible block number.  If the sync is interrupted, it will resume from the last block sync'd unless that block is older than `MEESEEKER_EXPIRE_KEYS` in which case it will skip to the last irreversible block number.

#### Using `SUBSCRIBE`

For `redis-cli`, please see: https://redis.io/topics/pubsub

Channels available for `meeseeker`:

* `steem:block`
* `steem:transaction`
* `steem:op:vote`
* `steem:op:comment`
* `steem:op:comment_options`
* `steem:op:whatever` (replace "whatever" with the op you want)
* `steem:op:custom_json:whatever` (if enabled, replace "whatever" with the `custom_json.id` you want)

As mentioned in the first `whatever` example, for ops, [all operation types](https://developers.steem.io/apidefinitions/broadcast-ops) can be subscribed to as channels, including virtual operations, if enabled.

In the second `whatever` example, for `custom_json.id`, if you want to subscribe to the `follow` channel, use `steem:op:custom_json:follow`.  Or if you want to subscribe to the `sm_team_reveal` channel, use `steem:op:custom_json:follow`.  The `custom_json.id` channels are not enabled by default.  To enable it, set the `MEESEEKER_PUBLISH_OP_CUSTOM_ID` to `true` (see example below).

For example, from `redis-cli`, if we wanted to stream block numbers:

```bash
$ redis-cli
127.0.0.1:6379> subscribe steem:block
Reading messages... (press Ctrl-C to quit)
1) "subscribe"
2) "steem:block"
3) (integer) 1
1) "message"
2) "steem:block"
3) "{\"block_num\":29861068,\"previous\":\"01c7a4cb4424b4dc0cb0cc72fd36b1644f8aeba5\",\"timestamp\":\"2019-01-28T20:55:03\",\"witness\":\"ausbitbank\",\"transaction_merkle_root\":\"a318bb82625bd78af8d8b506ccd4f53116372c8e\",\"extensions\":[]}"
1) "message"
2) "steem:block"
3) "{\"block_num\":29861069,\"previous\":\"01c7a4cc1bed060876cab57476846a91568a9f8a\",\"timestamp\":\"2019-01-28T20:55:06\",\"witness\":\"followbtcnews\",\"transaction_merkle_root\":\"834e05d40b9666e5ef50deb9f368c63070c0105b\",\"extensions\":[]}"
1) "message"
2) "steem:block"
3) "{\"block_num\":29861070,\"previous\":\"01c7a4cd3bbf872895654765faa4409a8e770e91\",\"timestamp\":\"2019-01-28T20:55:09\",\"witness\":\"timcliff\",\"transaction_merkle_root\":\"b2366ce9134d627e00423b28d33cc57f1e6e453f\",\"extensions\":[]}"
```

In addition to general op channels, there's an additional channel for `custom_json.id`.  This option must be enabled:

```bash
MEESEEKER_PUBLISH_OP_CUSTOM_ID=true meeseeker sync
```

Which allows subscription to specific `id` patterns:

```
$ redis-cli
127.0.0.1:6379> subscribe steem:op:custom_json:sm_team_reveal
Reading messages... (press Ctrl-C to quit)
1) "subscribe"
2) "steem:op:custom_json:sm_team_reveal"
3) (integer) 1
1) "message"
2) "steem:op:custom_json:sm_team_reveal"
3) "{\"key\":\"steem:29890790:bcfa68d9be10b3587d81039b85fd0536ddeddffb:0:custom_json\"}"
1) "message"
2) "steem:op:custom_json:sm_team_reveal"
3) "{\"key\":\"steem:29890792:3f3b921ec6706bcd259f5cc6ac922dc59bbe2de5:0:custom_json\"}"
1) "message"
2) "steem:op:custom_json:sm_team_reveal"
3) "{\"key\":\"steem:29890792:4ceca16dd114b1851140086a82a5fb3a6eb6ec42:0:custom_json\"}"
1) "message"
2) "steem:op:custom_json:sm_team_reveal"
3) "{\"key\":\"steem:29890792:00930eff76b3f0af8ed7215e88cf351cc671490b:0:custom_json\"}"
1) "message"
2) "steem:op:custom_json:sm_team_reveal"
3) "{\"key\":\"steem:29890799:01483bd252ccadb05f546051bb20a4ba9afea243:0:custom_json\"}"
```

A `ruby` application can subscribe to a channel as well, using the `redis` gem:

```ruby
require 'redis'

url = 'redis://127.0.0.1:6379/0'
ctx = Redis.new(url: url)

Redis.new(url: url).subscribe('steem:op:comment') do |on|
  on.message do |channel, message|
    payload = JSON[message]
    comment = JSON[ctx.get(payload['key'])]
    
    puts comment['value']
  end
end
```

Many other clients are supported: https://redis.io/clients

#### Using `SCAN`

From the redis manual:

> Since these commands allow for incremental iteration, returning only a small number of elements per call, they can be used in production without the downside of commands like KEYS or SMEMBERS that may block the server for a long time (even several seconds) when called against big collections of keys or elements.
> 
> However while blocking commands like SMEMBERS are able to provide all the elements that are part of a Set in a given moment, The SCAN family of commands only offer limited guarantees about the returned elements since the collection that we incrementally iterate can change during the iteration process.

See: https://redis.io/commands/scan

Keep in mind that `SCAN` requires pagination to get a complete result.  Redis implements pagination using a cursor based iterator.

See: https://redis.io/commands/scan#scan-basic-usage

Once your sync has started, you can begin doing queries against redis, for example, in the `redis-cli`:

```bash
redis-cli --scan --pattern 'steem:*:vote'
```

This returns the keys, for example:

```
steem:29811083:7fd2ea1c73e6cc08ab6e24cf68e67ff19a05896a:0:vote
steem:29811085:091c3df76322ec7f0dc51a6ed526ff9a9f69869e:0:vote
steem:29811085:24bfc199501779b6c2be2370fab1785f58062c5a:0:vote
steem:29811086:36761db678fe89df48d2c5d11a23cdafe57b2476:0:vote
steem:29811085:f904ac2e5e338263b03b640a4d1ff2d5fd01169e:0:vote
steem:29811085:44036fde09f20d91afda8fc2072b383935c0b615:0:vote
steem:29811086:570abf0fbeeeb0bb5c1e26281f0acb1daf175c39:0:vote
steem:29811083:e3ee518c4958a10f0d0c5ed39e3dc736048e8ec7:0:vote
steem:29811083:e06be9ade6758df59e179160b749d1ace3508044:0:vote
```

To get the actual vote operation for a particular key, use:

```bash
redis-cli get steem:29811085:f904ac2e5e338263b03b640a4d1ff2d5fd01169e:0:vote
```

If, on the other hand, you want `custom_json` only:

```bash
redis-cli --scan --pattern 'steem:*:custom_json'
```

This only returns the related keys, for example:

```
steem:29811084:43f1e1a367b97ea4e05fbd3a80a42146d97121a2:0:custom_json
steem:29811085:5795ff73234d64a11c1fb78edcae6f5570409d8e:0:custom_json
steem:29811083:2d6635a093243ef7a779f31a01adafe6db8c53c9:0:custom_json
steem:29811086:31ecb9c85e9eabd7ca2460fdb4f3ce4a7ca6ec32:0:custom_json
steem:29811083:7fbbde120aef339511f5af1a499f62464fbf4118:0:custom_json
steem:29811083:04a6ddc83a63d024b90ca13996101b83519ba8f5:0:custom_json
```

To get the actual custom json operation for a particular key, use:

```bash
redis-cli get steem:29811083:7fbbde120aef339511f5af1a499f62464fbf4118:0:custom_json
```

To get all transactions for a particular block number:

```bash
redis-cli --scan --pattern 'steem:29811085:*'
```

Or to get all ops for a particular transaction:

```bash
redis-cli --scan --pattern 'steem:*:31ecb9c85e9eabd7ca2460fdb4f3ce4a7ca6ec32:*'
```

---

<center>
  <img src="https://i.imgur.com/Y3Sa2GW.jpg" />
</center>

See some of my previous Ruby How To posts in: [#radiator](https://steemit.com/created/radiator) [#ruby](https://steemit.com/created/ruby)

### Docker

This will launch meeseeker in a docker container, so you can immediately attach to it on port 6380.

```bash
docker run -d -p 6380:6379 inertia/meeseeker:latest
redis-cli -p 6380
```

You can also pass any of the environment variables meeseeker accepts.  For example, this will launch meeseeker with `custom_json.id` channels enabled, but only keeps ops around for 5 minutes:

```bash
docker run \
  --env MEESEEKER_PUBLISH_OP_CUSTOM_ID=true \
  --env MEESEEKER_EXPIRE_KEYS=300 \
  -d -p 6380:6379 inertia/meeseeker:latest
```

Also see: https://hub.docker.com/r/inertia/meeseeker/

## Get in touch!

If you're using Radiator, I'd love to hear from you.  Drop me a line and tell me what you think!  I'm @inertia on STEEM.
  
## License

I don't believe in intellectual "property".  If you do, consider Radiator as licensed under a Creative Commons [![CC0](http://i.creativecommons.org/p/zero/1.0/80x15.png)](http://creativecommons.org/publicdomain/zero/1.0/) License.
