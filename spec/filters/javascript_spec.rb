# encoding: utf-8
require_relative '../spec_helper'
require "logstash/filters/javascript"
require "logstash/filters/date"

describe LogStash::Filters::Javascript do

  let(:event) do
    LogStash::Event.new "message" => "hello javascript"
  end

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
      subject(:filter) { ::LogStash::Filters::Javascript.new('code' => "if (true) throw new Error('a message')") }
      before(:each) { filter.register }

      it "should handle (standard) Error" do
        expect( filter.logger ).to receive(:error).
            with('could not process event due:', hash_including(
                :javascript_error => 'Error: a message',
                :javascript_line => 1 + 1, :javascript_column => 10)
            ) #.and_call_original

        new_events = filter.multi_filter([event])
        expect(new_events.length).to eq 1
        expect(new_events[0]).to equal(event)
        expect( event.get('tags') ).to eql ["_javascriptexception"]
      end
    end

    describe "throwing object" do
      subject(:filter) { ::LogStash::Filters::Javascript.new('code' => "\n throw 42") }
      before(:each) { filter.register }

      it "should handle (standard) error" do
        expect( filter.logger ).to receive(:error).
            with('could not process event due:', hash_including(
                :javascript_error => 42,
                :javascript_line => 2 + 1, :javascript_column => 1)
            ) #.and_call_original

        new_events = filter.multi_filter([event])
        expect(new_events.length).to eq 1
        expect(new_events[0]).to equal(event)
        expect( event.get('tags') ).to eql ["_javascriptexception"]
      end
    end

    describe "invalid script" do
      subject(:filter) { ::LogStash::Filters::Javascript.new('code' => "if (true) { 'okay' }\nif (false) invalid syntax {;") }

      it "should error out during register" do
        expect { filter.register }.to raise_error(Java::JavaxScript::ScriptException)
      end

      it "reports correct error line" do
        begin
          filter.register
          fail('syntax error expected')
        rescue Java::JavaxScript::ScriptException => e
          expect( e.cause.message ).to include "Expected ; but found syntax\nif (false) invalid syntax {;"
        end
      end
    end

    # describe "with new event block" do
    #   subject(:filter) { ::LogStash::Filters::Javascript.new('code' => 'new_event_block.call(event.clone)') }
    #   before(:each) { filter.register }
    #
    #   it "creates new event" do
    #     event = LogStash::Event.new "message" => "hello world", "mydate" => "2014-09-23T00:00:00-0800"
    #     new_events = filter.multi_filter([event])
    #     expect(new_events.length).to eq 2
    #     expect(new_events[0]).to equal(event)
    #     expect(new_events[1]).not_to eq(event)
    #     expect(new_events[1].to_hash).to eq(event.to_hash)
    #   end
    # end

    # describe "allow to replace event by another one" do
    #   config <<-CONFIG
    #     filter {
    #       ruby {
    #         code => "new_event_block.call(event.clone);
    #                  event.cancel;"
    #         add_tag => ["ok"]
    #       }
    #     }
    #   CONFIG
    #
    #   sample("message" => "hello world", "mydate" => "2014-09-23T00:00:00-0800") do
    #     expect(subject.get("message")).to eq("hello world");
    #     expect(subject.get("mydate")).to eq("2014-09-23T00:00:00-0800");
    #   end
    # end
  end
end
