# -*- encoding: utf-8 -*-
lib = File.expand_path('../lib/', __FILE__)
$:.unshift lib unless $:.include?(lib)

require 'right_aws'

Gem::Specification.new do |s|
  s.name        = "rightaws"
  s.version     = RightAws::VERSION::STRING
  s.platform    = Gem::Platform::RUBY
	s.author 			= "RightScale, Inc."
	s.email   		= "support@rightscale.com"
  s.homepage    = "http://github.com/rightscale/right_aws"
	s.summary     = "RightScale Amazon Web Services Ruby Gems"
  s.description = "Interface classes for the Amazon EC2, SQS, and S3 Web Services" 

  s.required_rubygems_version = ">= 1.3.6"
  s.rubyforge_project         = "right_aws"

  s.add_development_dependency "rcov"
	s.add_dependency 'right_http_connection', '>= 1.2.1'

  s.files        = Dir.glob("{bin,lib}/**/*") + %w(History.txt README.txt Manifest.txt)
  s.require_path = 'lib'
end

