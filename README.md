# Logstash Javascript Filter

[![Travis Build Status](https://travis-ci.com/kares/logstash-filter-javascript.svg)](https://travis-ci.com/kares/logstash-filter-javascript)

This is a plugin for [Logstash](https://www.elastic.co/guide/en/logstash/current/introduction.html), compatible with LS 
versions **>= 6.8**, that allows you to interact with pipeline events using scripts written in Javascript. 
It works in a similar way as Logstash's (official) [Ruby filter](https://www.elastic.co/guide/en/logstash/current/plugins-filters-ruby.html). 

**Only Java 8 - 13 is supported**, running LS on Java 15 or later won't work due the removal of the Nashorn Javascript engine.

**DISCLAIMER: Plugin is considered a (working) experiment and is no way as battle tested as (official) Logstash plugins supported 
by [Elastic](https://www.elastic.co/support/matrix#matrix_logstash_plugins).** 

In general, performance wise, you can expect the same throughput as with the Ruby filter.
Also, performance of the Nashorn Javascript engine *might* vary between Java versions.

## Usage

To inline Javascript in your filter, place all code in the `code` option. This code will be executed for every event the 
filter receives. For example, to cancel 90% of events, you can do this:
```javascript
  filter {
    javascript {
      code => "if (java.lang.Math.random() <= 0.9) event.cancel()"
    }
  }
```

You can also place JS code in the `init` option - it will be executed only once during the plugin's initialization phase.
This is a great place to "feature validate" the Javascript engine:

```javascript
  filter {
    javascript {
      init => "if (Number.MIN_VALUE <= 0) throw new Error(0); if (parseInt('f*ck', 16) !== 15) throw 'f*ck'"
      code => 'event.setField("message", "b" + "a" + +"a" + "a")'
    }
  }
```

### Installing

`$LS_HOME/bin/logstash-plugin install logstash-filter-javascript`

### Configuration

TO-BE-CONTINUED...

### Differences from Ruby filter

Unlike the Ruby filter, which allows you to hook into the LS execution runtime, the Javascript filter starts an isolated
JS engine on every filter use.

There's no `new_event_block` callback hook implemented in the Javascript filter, this one (if requested) deserves more 
thought as it just felt a bit "hacky" to copy what the Ruby filter does. 

The Javascript filter does not expose a `register` function (with `script_params`), instead you can use `init_parameters` 
to set variables in the global scope which will than be accessible from within the `filter` function. 

### Tips & Tricks

Nashorn defaults to ECMAScript 5.1 by default which lacks the compact arrow `arg => ...` syntax or the `let` keyword.
There's (incomplete) support for ECMA 6 but requires setting a system properly, navigate to *config/jvm.options* and add :
```
-Dnashorn.args=--language=es6
```

Be aware of scripting Java types with Nashorn as not all native Javascript APIs will handle those seamlessly and 
might lead to surprising results e.g.

```javascript
var json = JSON.stringify(event.toMap()); // undefined
// as JSON does not handle a java.util.Map returned from the LS event

// one can instead convert Java types to native JS objects e.g.
var map = event.toMap()
var obj = {}
for each (var key in map.keySet()) obj[key] = map.get(key) // Nashorn for-each extension for Java arrays/collections
```

You can set plain-old Javascript objects as values on the event, LS will see them as maps and convert them accordingly:

```javascript
var obj = { foo: "bar", truthy: true, aNull: null, number: 11.1 }
event.setField('js.values', obj)
// be aware when JS values contain function types as they might lead to issues
```

```javascript
// using JS types with a Java type system might lead to issues e.g. setting it on an event e.g.
event.setField('unexpected-value', undefined); // LS will complain not being able to handle :
// Missing Converter handling for full class name=jdk.nashorn.internal.runtime.Undefined
```

There's no `console.log` with Nashorn, however you could use Java's system output for debugging purposes :
```javascript
function puts(msg) {
  java.lang.System.out.println(msg)  
}

puts('event: ' + event.toMap());

// or simply the built-in print method :
print('event: ', event)
```
**NOTE**: be aware to remove such debugging statements in production to not fill up LS' standard output!

## Developing

### 1. Plugin Development and Testing

#### Code

- To get started, you'll need JRuby (>= 9.1) with the Bundler gem installed.

- Install dependencies
```sh
jruby -S bundle
```

#### Test

```sh
jruby -rbundler/setup -S rspec
```

### 2. Running your unpublished Plugin in Logstash

- Edit Logstash's `Gemfile` and add the local plugin path e.g.:
```ruby
gem "logstash-filter-javascript", :path => "path/to/local/logstash-filter-javascript"
```
- Install plugin
```sh
bin/logstash-plugin install --no-verify
```
- Run Logstash with your plugin
```sh
bin/logstash -e "filter { javascript { code => \"print('Hello from JS: ' + event.getField('message'))\" } }"
```
At this point any modifications to the plugin code will be applied to this local Logstash setup. After modifying the plugin, simply rerun Logstash.

#### 2.2 Run in an installed Logstash

You can use the same **2.1** method to run your plugin in an installed Logstash by editing its `Gemfile` and pointing the `:path` to your local plugin development directory or you can build the gem and install it using:

- Build your plugin gem
```sh
gem build logstash-filter-awesome.gemspec
```
- Install the plugin from the Logstash home
```sh
# Logstash 2.3 and higher
bin/logstash-plugin install --no-verify

# Prior to Logstash 2.3
bin/plugin install --no-verify

```
- Start Logstash and proceed to test the plugin

## Copyright

(c) 2020 [Karol Bucek](https://github.com/kares).
See LICENSE (http://www.apache.org/licenses/LICENSE-2.0) for details.
