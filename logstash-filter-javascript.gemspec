Gem::Specification.new do |s|

  s.name            = 'logstash-filter-javascript'
  s.version         = '0.1.0'
  s.licenses        = ['Apache License (2.0)']
  s.summary         = "Execute Javascript code in LS to process events"
  s.description     = "This gem is a Logstash plugin required to be installed on top of the Logstash using $LS_HOME/bin/logstash-plugin install logstash-filter-javascript"
  s.authors         = ["Karol Bucek"]
  s.email           = 'self@kares.org'
  s.homepage        = "http://www.elastic.co/guide/en/logstash/current/index.html"
  s.require_paths = ["lib"]

  # Files
  s.files = Dir["lib/**/*","spec/**/*","*.gemspec","*.md","CONTRIBUTORS","Gemfile","LICENSE","NOTICE.TXT", "vendor/jar-dependencies/**/*.jar", "vendor/jar-dependencies/**/*.rb", "VERSION", "docs/**/*"]

  # Tests
  s.test_files = s.files.grep(%r{^(test|spec|features)/})

  # Special flag to let us know this is actually a logstash plugin
  s.metadata = { "logstash_plugin" => "true", "logstash_group" => "filter" }

  s.required_ruby_version = '>= 2.3' # LS >= 6.x

  # Gem dependencies
  s.add_runtime_dependency "logstash-core-plugin-api", ">= 1.60", "<= 2.99"

  s.add_development_dependency 'logstash-devutils'
  s.add_development_dependency 'logstash-filter-date'

end

