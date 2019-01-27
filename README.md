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

Normally, keys stay on redis for 24 hours.  If you want to change this behavior, use `MEESEEKER_EXPIRE_KEYS` and specify the new value in seconds, for example:

```bash
MEESEEKER_EXPIRE_KEYS=10 meeseeker sync
```

### Usage

When `meeseeker sync` starts for the first time, it initializes from the last irreversible block number.  If the sync is interrupted, it will resume from the last block sync'd unless that block is older than `MEESEEKER_EXPIRE_KEYS` in which case it will skip to the last irreversible block number.

#### Using `SCAN`

From the redis manual:

> Since these commands allow for incremental iteration, returning only a small number of elements per call, they can be used in production without the downside of commands like KEYS or SMEMBERS that may block the server for a long time (even several seconds) when called against big collections of keys or elements.
> 
> However while blocking commands like SMEMBERS are able to provide all the elements that are part of a Set in a given moment, The SCAN family of commands only offer limited guarantees about the returned elements since the collection that we incrementally iterate can change during the iteration process.

See: https://redis.io/commands/scan

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

## Get in touch!

If you're using Radiator, I'd love to hear from you.  Drop me a line and tell me what you think!  I'm @inertia on STEEM.
  
## License

I don't believe in intellectual "property".  If you do, consider Radiator as licensed under a Creative Commons [![CC0](http://i.creativecommons.org/p/zero/1.0/80x15.png)](http://creativecommons.org/publicdomain/zero/1.0/) License.
