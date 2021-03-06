 # meeseeker

Redis based block follower is an efficient way for multiple apps to stream the Hive Blockchain.

[![Build Status](https://travis-ci.org/inertia186/meeseeker.svg?branch=master)](https://travis-ci.org/inertia186/meeseeker)

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

You can also specify am alternative Hive node:

```bash
MEESEEKER_NODE_URL=http://anyx.io meeseeker sync
```

You can also specify a Steem node instead of Hive (if that's your thing):

```bash
MEESEEKER_NODE_URL=https://api.steemit.com meeseeker sync[steem]
```

Or, you can have meeseeker automatically use random Hive nodes:

```bash
MEESEEKER_NODE_URL=shuffle meeseeker sync
```

To sync from the head block instead of the last irreversible block:

```bash
MEESEEKER_STREAM_MODE=head meeseeker sync
```

To ignore virtual operations (useful if the node doesn't enable `get_ops_in_blocks` or if you want to sync from the head block):

```bash
MEESEEKER_INCLUDE_VIRTUAL=false meeseeker sync
```

Normally, block headers are added to the `hive:block` channel.  This requires one additional API call for each block.  If you don't need block headers, you can configure the `hive:block` channel to only publish with the `block_num`:

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

Normally, sync will create keys until it uses up all available memory.  If you would like to only sync a certain number of keys, then sleep until those keys expire so it can pick up where it left off, set `MEESEEKER_MAX_KEYS` to a positive value:

```bash
MEESEEKER_MAX_KEYS=99 meeseeker sync
```

### Usage

When `meeseeker sync` starts for the first time, it initializes from the last irreversible block number.  If the sync is interrupted, it will resume from the last block sync'd unless that block is older than `MEESEEKER_EXPIRE_KEYS` in which case it will skip to the last irreversible block number.

#### Using `SUBSCRIBE`

For `redis-cli`, please see: https://redis.io/topics/pubsub

##### Sync

When running `meeseeker sync`, the following channels are available:

* `hive:block`
* `hive:transaction`
* `hive:op:vote`
* `hive:op:comment`
* `hive:op:comment_options`
* `hive:op:whatever` (replace "whatever" with the op you want)
* `hive:op:custom_json:whatever` (if enabled, replace "whatever" with the `custom_json.id` you want)

As mentioned in the first `whatever` example, for ops, [all operation types](https://developers.hive.io/apidefinitions/broadcast-ops) can be subscribed to as channels, including virtual operations, if enabled.

In the second `whatever` example, for `custom_json.id`, if you want to subscribe to the `follow` channel, use `hive:op:custom_json:follow`.  Or if you want to subscribe to the `sm_team_reveal` channel, use `hive:op:custom_json:sm_team_reveal`.  The `custom_json.id` channels are not enabled by default.  To enable it, set the `MEESEEKER_PUBLISH_OP_CUSTOM_ID` to `true` (see example below).

For example, from `redis-cli`, if we wanted to stream block numbers:

```bash
$ redis-cli
127.0.0.1:6379> subscribe hive:block
Reading messages... (press Ctrl-C to quit)
1) "subscribe"
2) "hive:block"
3) (integer) 1
1) "message"
2) "hive:block"
3) "{\"block_num\":29861068,\"previous\":\"01c7a4cb4424b4dc0cb0cc72fd36b1644f8aeba5\",\"timestamp\":\"2019-01-28T20:55:03\",\"witness\":\"ausbitbank\",\"transaction_merkle_root\":\"a318bb82625bd78af8d8b506ccd4f53116372c8e\",\"extensions\":[]}"
1) "message"
2) "hive:block"
3) "{\"block_num\":29861069,\"previous\":\"01c7a4cc1bed060876cab57476846a91568a9f8a\",\"timestamp\":\"2019-01-28T20:55:06\",\"witness\":\"followbtcnews\",\"transaction_merkle_root\":\"834e05d40b9666e5ef50deb9f368c63070c0105b\",\"extensions\":[]}"
1) "message"
2) "hive:block"
3) "{\"block_num\":29861070,\"previous\":\"01c7a4cd3bbf872895654765faa4409a8e770e91\",\"timestamp\":\"2019-01-28T20:55:09\",\"witness\":\"timcliff\",\"transaction_merkle_root\":\"b2366ce9134d627e00423b28d33cc57f1e6e453f\",\"extensions\":[]}"
```

In addition to general op channels, there's an additional channel for `custom_json.id`.  This option must be enabled:

```bash
MEESEEKER_PUBLISH_OP_CUSTOM_ID=true meeseeker sync
```

Which allows subscription to specific `id` patterns:

```
$ redis-cli
127.0.0.1:6379> subscribe hive:op:custom_json:sm_team_reveal
Reading messages... (press Ctrl-C to quit)
1) "subscribe"
2) "hive:op:custom_json:sm_team_reveal"
3) (integer) 1
1) "message"
2) "hive:op:custom_json:sm_team_reveal"
3) "{\"key\":\"hive:29890790:bcfa68d9be10b3587d81039b85fd0536ddeddffb:0:custom_json\"}"
1) "message"
2) "hive:op:custom_json:sm_team_reveal"
3) "{\"key\":\"hive:29890792:3f3b921ec6706bcd259f5cc6ac922dc59bbe2de5:0:custom_json\"}"
1) "message"
2) "hive:op:custom_json:sm_team_reveal"
3) "{\"key\":\"hive:29890792:4ceca16dd114b1851140086a82a5fb3a6eb6ec42:0:custom_json\"}"
1) "message"
2) "hive:op:custom_json:sm_team_reveal"
3) "{\"key\":\"hive:29890792:00930eff76b3f0af8ed7215e88cf351cc671490b:0:custom_json\"}"
1) "message"
2) "hive:op:custom_json:sm_team_reveal"
3) "{\"key\":\"hive:29890799:01483bd252ccadb05f546051bb20a4ba9afea243:0:custom_json\"}"
```

A `ruby` application can subscribe to a channel as well, using the `redis` gem:

```ruby
require 'redis'

url = 'redis://127.0.0.1:6379/0'
ctx = Redis.new(url: url)

Redis.new(url: url).subscribe('hive:op:comment') do |on|
  on.message do |channel, message|
    payload = JSON[message]
    comment = JSON[ctx.get(payload['key'])]
    
    puts comment['value']
  end
end
```

Many other clients are supported: https://redis.io/clients

##### Witness Schedule

When running `meeseeker witness:schedule`, the `hive:witness:schedule` channel is available.  This is offered as a separate command because most applications don't need to worry about this level of blockchain logistics.

For example, from `redis-cli`, if we wanted to subscribe to the witness schedule:

```
$ redis-cli
127.0.0.1:6379> subscribe hive:witness:schedule
Reading messages... (press Ctrl-C to quit)
1) "subscribe"
2) "hive:witness:schedule"
3) (integer) 1
1) "message"
2) "hive:witness:schedule"
3) "{\"id\":0,\"current_virtual_time\":\"415293532210075480213212125\",\"next_shuffle_block_num\":30035208,\"current_shuffled_witnesses\":[\"thecryptodrive\",\"timcliff\",\"utopian-io\",\"themarkymark\",\"aggroed\",\"smooth.witness\",\"someguy123\",\"gtg\",\"followbtcnews\",\"yabapmatt\",\"therealwolf\",\"ausbitbank\",\"curie\",\"clayop\",\"drakos\",\"blocktrades\",\"good-karma\",\"roelandp\",\"lukestokes.mhth\",\"liondani\",\"anyx\"],\"num_scheduled_witnesses\":21,\"elected_weight\":1,\"timeshare_weight\":5,\"miner_weight\":1,\"witness_pay_normalization_factor\":25,\"median_props\":{\"account_creation_fee\":{\"amount\":\"3000\",\"precision\":3,\"nai\":\"@@000000021\"},\"maximum_block_size\":65536,\"sbd_interest_rate\":0,\"account_subsidy_budget\":797,\"account_subsidy_decay\":347321},\"majority_version\":\"0.20.8\",\"max_voted_witnesses\":20,\"max_miner_witnesses\":0,\"max_runner_witnesses\":1,\"hardfork_required_witnesses\":17,\"account_subsidy_rd\":{\"resource_unit\":10000,\"budget_per_time_unit\":797,\"pool_eq\":157691079,\"max_pool_size\":157691079,\"decay_params\":{\"decay_per_time_unit\":347321,\"decay_per_time_unit_denom_shift\":36},\"min_decay\":0},\"account_subsidy_witness_rd\":{\"resource_unit\":10000,\"budget_per_time_unit\":996,\"pool_eq\":9384019,\"max_pool_size\":9384019,\"decay_params\":{\"decay_per_time_unit\":7293741,\"decay_per_time_unit_denom_shift\":36},\"min_decay\":257},\"min_witness_account_subsidy_decay\":0}"
```

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
redis-cli --scan --pattern 'hive:*:vote'
```

This returns the keys, for example:

```
hive:29811083:7fd2ea1c73e6cc08ab6e24cf68e67ff19a05896a:0:vote
hive:29811085:091c3df76322ec7f0dc51a6ed526ff9a9f69869e:0:vote
hive:29811085:24bfc199501779b6c2be2370fab1785f58062c5a:0:vote
hive:29811086:36761db678fe89df48d2c5d11a23cdafe57b2476:0:vote
hive:29811085:f904ac2e5e338263b03b640a4d1ff2d5fd01169e:0:vote
hive:29811085:44036fde09f20d91afda8fc2072b383935c0b615:0:vote
hive:29811086:570abf0fbeeeb0bb5c1e26281f0acb1daf175c39:0:vote
hive:29811083:e3ee518c4958a10f0d0c5ed39e3dc736048e8ec7:0:vote
hive:29811083:e06be9ade6758df59e179160b749d1ace3508044:0:vote
```

To get the actual vote operation for a particular key, use:

```bash
redis-cli get hive:29811085:f904ac2e5e338263b03b640a4d1ff2d5fd01169e:0:vote
```

If, on the other hand, you want `custom_json` only:

```bash
redis-cli --scan --pattern 'hive:*:custom_json'
```

This only returns the related keys, for example:

```
hive:29811084:43f1e1a367b97ea4e05fbd3a80a42146d97121a2:0:custom_json
hive:29811085:5795ff73234d64a11c1fb78edcae6f5570409d8e:0:custom_json
hive:29811083:2d6635a093243ef7a779f31a01adafe6db8c53c9:0:custom_json
hive:29811086:31ecb9c85e9eabd7ca2460fdb4f3ce4a7ca6ec32:0:custom_json
hive:29811083:7fbbde120aef339511f5af1a499f62464fbf4118:0:custom_json
hive:29811083:04a6ddc83a63d024b90ca13996101b83519ba8f5:0:custom_json
```

To get the actual custom json operation for a particular key, use:

```bash
redis-cli get hive:29811083:7fbbde120aef339511f5af1a499f62464fbf4118:0:custom_json
```

To get all transactions for a particular block number:

```bash
redis-cli --scan --pattern 'hive:29811085:*'
```

Or to get all ops for a particular transaction:

```bash
redis-cli --scan --pattern 'hive:*:31ecb9c85e9eabd7ca2460fdb4f3ce4a7ca6ec32:*'
```

### Hive Engine Support

As of `v0.0.6`, meeseeker can also follow the Hive Engine side-chain.  This is optional and requires a separate process.

To sync Hive Engine to your local redis source (also defaults to `redis://127.0.0.1:6379/0`):

```bash
meeseeker sync hive_engine
```

When running `meeseeker sync hive_engine`, the following channels are available:

* `hive_engine:block`
* `hive_engine:transaction`
* `hive_engine:virtual_transaction`
* `hive_engine:contract`
* `hive_engine:contract:deploy`
* `hive_engine:contract:update`
* `hive_engine:market`
* `hive_engine:market:buy`
* `hive_engine:market:cancel`
* `hive_engine:market:sell`
* `hive_engine:sscstore`
* `hive_engine:sscstore:buy`
* `hive_engine:steempegged`
* `hive_engine:steempegged:buy`
* `hive_engine:steempegged:removeWithdrawal`
* `hive_engine:steempegged:withdraw`
* `hive_engine:tokens`
* `hive_engine:tokens:checkPendingUnstake`
* `hive_engine:tokens:create`
* `hive_engine:tokens:enableStaking`
* `hive_engine:tokens:issue`
* `hive_engine:tokens:transfer`
* `hive_engine:tokens:transferOwnership`
* `hive_engine:tokens:unstake`
* `hive_engine:tokens:updateMetadata`
* `hive_engine:tokens:updateParams`
* `hive_engine:tokens:updateUrl`

The above "channel/action" patterns are the ones that are known that the time of writing.  In addition, if a new contract is added or updated, meeseeker will automatically publish to these corresponding channels as they appear, without needing to update or even restart meeseeker.

See main section on [Using `SUBSCRIBE`](#using-subscribe).

Once your HiveEngine sync has started, you can begin doing queries against redis, for example, in the `redis-cli`:

```bash
redis-cli --scan --pattern 'hive_engine:*:tokens:transfer'
```

This returns the keys, for example:

```
hive_engine:18000:d414373db84e6a642f289641ea1433fda22b8a4d:0:tokens:transfer
hive_engine:18004:c9e06c8449d2d04b4a0a31ec7b80d2f62009a5f0:0:tokens:transfer
hive_engine:17994:faf097391760ad896b19d5854e2822f62dee284b:0:tokens:transfer
```

See main section on [Using `SCAN`](#using-scan).

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

---

<center>
  <img src="https://i.imgur.com/Y3Sa2GW.jpg" />
</center>

See some of my previous Ruby How To posts in: [#radiator](https://hive.blog/created/radiator) [#ruby](https://hive.blog/created/ruby)

## Get in touch!

If you're using Radiator, I'd love to hear from you.  Drop me a line and tell me what you think!  I'm @inertia on Hive.
  
## License

I don't believe in intellectual "property".  If you do, consider Radiator as licensed under a Creative Commons [![CC0](http://i.creativecommons.org/p/zero/1.0/80x15.png)](http://creativecommons.org/publicdomain/zero/1.0/) License.
