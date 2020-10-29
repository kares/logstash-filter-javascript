# encoding: utf-8
require "logstash/filters/base"
require "logstash/namespace"

# Execute JS code.
#
# For example, to cancel 90% of events, you can do this:
# [source,ruby]
#     filter {
#       javascript {
#         # Cancel 90% of events
#         code => "if (java.lang.Math.random() <= 0.9) event.cancel()"
#       }
#     }
module LogStash module Filters class Javascript < Base

  java_import 'java.util.Map'
  java_import 'jdk.nashorn.api.scripting.NashornException'
  java_import 'jdk.nashorn.api.scripting.ScriptObjectMirror'
  JEvent = org.logstash.Event
  private_constant :JEvent

  class ScriptError < StandardError; end

  config_name "javascript"

  # Any code to execute at plugin startup-time
  config :init, :validate => :string

  # The code to execute for every event.
  # You will have an `event` variable available that is the event itself.
  config :code, :validate => :string

  # Path to the script.js
  config :path, :validate => :path

  # Parameters for this specific script
  config :init_params, :type => :hash, :default => {} # TODO set these on this vs custom bindings?

  # Tag to add to events that cause an exception in the script filter
  config :tag_on_exception, :type => :string, :default => "_javascriptexception"

  # Flag for add exception message to tag_on_exception
  #config :tag_with_exception_message, :type => :boolean, :default => false

  def initialize(*params)
    super(*params)
    @script = Script.new(nil, init_params, logger)
    @script.js_eval @init if @init
    @js_filter = nil
  end

  def register
    if @code && @path.nil?
      @js_filter = @script.js_eval(@code) { "(function filter(event) {\n#{@code} } )" }
      # jdk.nashorn.api.scripting.JSObject
    elsif @path && @code.nil?
      @script.js_eval(::File.read(@path), path: @path)
      @js_filter = @script.get('filter') # `expecting a `function filter(event) {}`
      raise ScriptError, "script at '#{@path}' does not define a filter(event) function" if @js_filter.nil?
      if @js_filter.is_a?(ScriptObjectMirror)
        unless @js_filter.isFunction
          raise ScriptError, "script at '#{@path}' defines a 'filter' property that isn't a function (got type: #{@js_filter.getClassName})"
        end
      else
        raise ScriptError, "script at '#{@path}' defines a 'filter' property that isn't a function (got value: #{@js_filter.inspect})"
      end
    else
      msg = "You must either use an inline script with the \"code\" option or a script file using \"path\"."
      @logger.error(msg)
      raise LogStash::ConfigurationError, msg
    end

    @script.verify
  end

  def filter(event, &block)
    java_event = event.to_java
    begin
      js_return = @js_filter.call(@script.context, java_event)
      filter_matched(event)
    rescue => e
      @logger.error("could not process event due:", error_details(e))
      tag_exception(event, e)
      return event
    end
    event.cancel unless filter_results(java_event, js_return, &block)
  end

  private

  # @param results (JS array) in a `jdk.nashorn.api.scripting.ScriptObjectMirror`
  def filter_results(event, js_return)
    if js_return.nil? # explicit `return null`
      # drop event (return false)
    elsif ScriptObjectMirror.isUndefined(js_return) # jdk.nashorn.internal.runtime.Undefined
      return true # do not drop (assume it's been dealt with e.g. `event.cancel()`)
    elsif js_return.is_a?(ScriptObjectMirror)
      if js_return.isArray
        i = 0; returned_original = false
        while i < js_return.size
          evt = js_return.getSlot(i)
          if event.equal?(evt)
            returned_original = true
          else
            yield wrap_event(evt)
          end
          i += 1
        end
        return returned_original
      else
        begin
          evt = wrap_event(js_return) # JSObject implement Map interface
        rescue => e
          raise e # TODO we should attempt to provide a better exception here if we can not convert the JS (map) object
          # raise ScriptError, "javascript did not return an event/array (or null) from 'filter', got: #{js_return.getClassName}"
        else
          yield evt
        end
      end
    elsif js_return.is_a?(JEvent) || js_return.is_a?(Map)
      return true if event.equal?(js_return)
      yield wrap_event(js_return)
    else
      raise ScriptError, "javascript did not return an event/array (or null) from 'filter', got: #{js_return.inspect}"
    end
    false # script did not return original event
  end

  # NOTE: JS code is expected to work with Java event API
  # @param js_event a org.logstash.Event or simply a plain-old (map-like) JS object
  def wrap_event(js_event)
    js_event = JEvent.new(js_event) unless js_event.is_a?(JEvent)
    Event.new(js_event)
  end

  def tag_exception(event, e)
    if @tag_with_exception_message && e.message
      event.tag("#{@tag_on_exception}: #{e.message}")
    end
    event.tag(@tag_on_exception) if @tag_on_exception
  end

  def error_details(e)
    details = { :exception => e.class, :message => e.message }
    if e.is_a?(NashornException)
      details[:message] = e.toString
      details[:backtrace] = e.backtrace if logger.debug?
      js_error = e.getEcmaError
      js_error = js_error.toString if js_error.is_a?(ScriptObjectMirror)
      details[:javascript_error] = js_error
      details[:javascript_file] = e.getFileName # '<eval>' for incline code
      details[:javascript_line] = e.getLineNumber # inline code lines are +1
      details[:javascript_column] = e.getColumnNumber
      details[:javascript_trace] = NashornException.getScriptFrames(e)
    else
      details[:backtrace] = e.backtrace
    end
    details
  end

  class Script

    FILENAME = javax.script.ScriptEngine::FILENAME
    ENGINE_SCOPE = javax.script.ScriptContext::ENGINE_SCOPE

    attr_reader :context

    # @param context the JS this context for the filter function
    # @param params additional JS (key-value) parameters to set 'globally'
    def initialize(context, params, logger)
      @logger = logger
      @engine = javax.script.ScriptEngineManager.new.getEngineByName("nashorn")
      @context = context

      factory = @engine.getFactory
      logger.debug "initialized javascript (#{factory.getLanguageVersion}) engine:", name: factory.getEngineName, version: factory.getEngineVersion

      context = @engine.getContext
      params.each { |name, value| context.setAttribute name, value, ENGINE_SCOPE }
    end

    def js_eval(code, path: nil)
      filename = @engine.get(FILENAME)
      @engine.put(FILENAME, path)
      @engine.eval block_given? ? yield : code
    rescue => e # (non-checked) Java::JavaxScript::ScriptException, e.g.
      # Java::JavaxScript::ScriptException (TypeError: Cannot read property "far" from undefined in <eval> at line number 2)
      @logger.error "failed to evaluate javascript code:", code_hint(code, path).merge(message: e.message)
      raise e
    ensure
      @engine.put(FILENAME, filename)
    end

    # @return nil if no such property
    def get(name)
      @engine.eval(name)
    end

    def verify
      true # NOTE can we do more JS code checks?
    end

    private

    MAX_LINE_LENGTH = 50

    def code_hint(code, path)
      return { path: path } if path
      lines = code.split("\n")
      code = lines.find { |line| ! line.strip.empty? }
      if code.length <= MAX_LINE_LENGTH
        code = "#{code}..." if lines.size > 1
      else
        code = "#{code[0, MAX_LINE_LENGTH - 3]}..."
      end
      { code: code }
    end

  end

end end end
