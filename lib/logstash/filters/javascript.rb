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
#
class LogStash::Filters::Javascript < LogStash::Filters::Base

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
  end

  def register
    if @code && @path.nil?
      @handler = @script.js_eval(@code) { "(function filter(event) {\n#{@code} } )" }
      # jdk.nashorn.api.scripting.JSObject
    elsif @path && @code.nil?
      @script.js_eval(@code, path: @path)
      @handler = @script.get('filter') # `expecting a `function filter(event) {}`
      raise ScriptError, "script at '#{@path}' does not define a filter(event) function" unless @handler
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
      results = @script.js_run @handler, java_event
      filter_matched(event)
    rescue => e
      @logger.error("could not process event due:", error_details(e))
      #puts "\n  #{e.backtrace.join("\n  ")}" #if $VERBOSE
      tag_exception(event, e)
      return event
    end
    event.cancel unless filter_results(java_event, results, &block)
  end

  private

  # @param results (JS array) in a `jdk.nashorn.api.scripting.ScriptObjectMirror`
  def filter_results(event, results)
    returned_original = false
    if results.nil? # explicit `return null`
      # drop event (returned_original = false)
    elsif 'Undefined'.eql?(results.getClassName) # jdk.nashorn.internal.runtime.Undefined
      returned_original = true # do not drop (assume it's been dealt with e.g. `event.cancel()`)
    elsif results.isArray
      i = 0
      while i < results.size
        evt = results.getSlot(i)
        if event.equal? evt
          returned_original = true
        else
          yield wrap_event(evt) # JS code is expected to work with Java event API
        end
        i += 1
      end
    else
      raise ScriptError, "script did not return an array (or null) from 'filter', got #{results.getClassName}"
    end
    returned_original
  end

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

    # @param context the JS this context for the filter function
    # @param params additional JS (key-value) parameters to set 'globally'
    def initialize(context, params, logger)
      @logger = logger
      @engine = javax.script.ScriptEngineManager.new.getEngineByName("nashorn")
      @context = context

      factory = @engine.getFactory
      logger.debug "initialized javascript (#{factory.getLanguageVersion}) engine:", name: factory.getEngineName, version: factory.getEngineVersion

      context = @engine.getContext
      params.each { |name, value| context.setAttribute name, value, javax.script.ScriptContext::ENGINE_SCOPE }
    end

    def js_eval(code, path: nil)
      @engine.eval block_given? ? yield : code
    rescue => e # (non-checked) Java::JavaxScript::ScriptException, e.g.
      # Java::JavaxScript::ScriptException (TypeError: Cannot read property "far" from undefined in <eval> at line number 2)
      @logger.error "failed to evaluate javascript code:", code_hint(code, path).merge(message: e.message)
      raise e
    end

    # @return nil if no such property
    def get(name)
      @engine.getContext.getAttribute(name)
    end

    def verify
      true # NOTE can we do more JS code checks?
    end

    def js_run(callable, event)
      callable.call(@context, event)
    # rescue NashornException => e
    #   raise e
    # rescue => e
    #   raise e
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

    # def test
    #   results = @context.execute_tests
    #   logger.info("Test run complete", :path => path, :results => results)
    #   if results[:failed] > 0 || results[:errored] > 0
    #     raise ScriptError.new("Script '#{path}' had #{results[:failed] + results[:errored]} failing tests! Check the error log for details.")
    #   end
    # end
  end

end
