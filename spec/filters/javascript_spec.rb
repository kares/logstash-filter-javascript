# encoding: utf-8
require_relative '../spec_helper'
require "logstash/filters/javascript"
require "logstash/filters/date"

describe LogStash::Filters::Javascript do

  let(:event) do
    LogStash::Event.new "message" => "hello javascript"
  end

  subject(:plugin) { ::LogStash::Filters::Javascript.new(options) }

  let(:options) { fail 'let(:options) needs to be defined' }

  context "inline (code) script" do

    describe "using Java event API" do
      config <<-CONFIG
        filter {
          date {
            match => [ "date", "ISO8601" ]
            locale => "en"
            timezone => "UTC"
          }
          javascript {
            code => "var map = event.toMap(); var obj = {}; for each (var key in map.keySet()) obj[key] = map.get(key); event.setField('js.obj', obj)"
          }
        }
      CONFIG

      sample("message" => "hello", "date" => "2014-09-23T00:00:00-0800", "truthy" => true, "number" => 1.11) do
        js_obj = subject.get('js.obj') # LS event auto-converts map-like objects
        expect( js_obj['message'] ).to eql 'hello'
        expect( js_obj['number'] ).to eql 1.11
        expect( js_obj['truthy'] ).to eql true
      end
    end

    describe "returning new event" do
      let(:options) { { 'code' => "return event.clone()" } }
      before(:each) { plugin.register }

      it "proceeds with new event and cancels old" do
        events = plugin.multi_filter [ event ]
        expect( events.length ).to eq 2
        expect( event.cancelled? ).to be true
      end
    end

    describe "returning same event" do
      let(:options) { { 'code' => "return event" } }
      before(:each) { plugin.register }

      it "does not cancel event" do
        events = plugin.multi_filter [ event ]
        expect( events.length ).to eq 1
        expect( events[0] ).to equal(event)
        expect( event.cancelled? ).to be false
      end
    end

    describe "returning multiple events" do
      let(:options) { { 'code' => "return [event.clone(), event.clone(), event.clone()]" } }
      before(:each) { plugin.register }

      it "produces more events" do
        expect { |block| plugin.filter(event, &block) }.to yield_control.exactly(3).times
      end
    end

    # describe "catch all JS exceptions" do
    #   config <<-CONFIG
    #     filter {
    #       javascript {
    #         code => "throw 42"
    #       }
    #     }
    #   CONFIG
    #
    #   sample("message" => "hello", "date" => "2014-09-23T00:00:00-0800") do
    #     expect( subject.get("tags") ).to eql ["_javascriptexception"]
    #   end
    # end

    describe "throwing error" do
      let(:options) { { 'code' => "if (true) throw new Error('a message')" } }
      before(:each) { plugin.register }

      it "handles Error" do
        expect( plugin.logger ).to receive(:error).
            with('could not process event due:', hash_including(
                :javascript_error => 'Error: a message',
                :javascript_line => 1 + 1, :javascript_column => 10)
            ) #.and_call_original

        events = plugin.multi_filter [ event ]
        expect( events.length ).to eq 1
        expect( events[0] ).to equal(event)
        expect( event.get('tags') ).to eql ["_javascriptexception"]
      end
    end

    describe "throwing object" do
      let(:options) { { 'code' => "\n throw 42" } }
      before(:each) { plugin.register }

      it "handles (javascript) error" do
        expect( plugin.logger ).to receive(:error).
            with('could not process event due:', hash_including(
                :javascript_error => 42,
                :javascript_line => 2 + 1, :javascript_column => 1)
            ) #.and_call_original

        events = plugin.multi_filter [ event ]
        expect( events.length ).to eq 1
        expect( events[0] ).to equal(event)
        expect( event.get('tags') ).to eql ["_javascriptexception"]
      end
    end

    describe "unexpected return value" do
      let(:options) { { 'code' => "if (true) return false" } }

      it "raises script error" do
        plugin.register
        expect { plugin.multi_filter [ event ] }.to raise_error(LogStash::Filters::Javascript::ScriptError)
      end
    end

    describe "invalid script" do
      let(:options) { { 'code' => "if (true) { 'okay' }\nif (false) invalid syntax {;" } }
      before(:each) do
        expect( plugin.logger ).to receive(:error)
      end

      it "should error out during register" do
        expect { plugin.register }.to raise_error(Java::JavaxScript::ScriptException)
      end

      it "reports correct error line" do
        begin
          plugin.register
          fail('syntax error expected')
        rescue Java::JavaxScript::ScriptException => e
          expect( e.cause.message ).to include "Expected ; but found syntax\nif (false) invalid syntax {;"
        end
      end
    end

    context "path option" do
      let(:options) { { 'path' => "spec/fixtures/throwIfErrorFieldSet.js" } }
      before(:each) { plugin.register }

      it "works normally (wout return)" do
        plugin.multi_filter [ event ]
        expect( event.get('filtered') ).to be true
      end

      it "raises error" do
        event.set('error', 'FROM SPEC')
        plugin.multi_filter [ event ]
        expect( event.get('tags') ).to eql ["_javascriptexception"]
      end
    end

    context "non-readable path option" do
      let(:options) { { 'path' => "__INVALID__.js" } }

      it "raises configuration error" do
        expect { plugin.register }.to raise_error(LogStash::ConfigurationError)
      end
    end

    describe "init script" do
      let(:options) { { 'init' => 'var foo = "bar"', 'code' => "event.setField('foo', foo)" } }

      it "sets a variable in 'global' scope" do
        plugin.register
        plugin.multi_filter [ event ]
        expect( event.get('foo') ).to eql 'bar'
      end
    end

    describe "init parameters" do
      let(:options) { {
          'init_parameters' => { 'env' => 'debug', 'fieldName' => 'x', 'multiplier' => 10 },
          'path' => "spec/fixtures/field_multiplier.js"
      } }

      it "calculates x * multiplier" do
        plugin.register
        event.set('x', 4.2)
        plugin.multi_filter [ event ]
        expect( event.get('x') ).to eql 42.0
      end
    end

  end
end
