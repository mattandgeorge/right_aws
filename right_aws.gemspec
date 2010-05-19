# -*- encoding: utf-8 -*-
lib = File.expand_path('../lib/', __FILE__)
$:.unshift lib unless $:.include?(lib)

require 'right_aws'

Gem::Specification.new do |s|
  s.name        = "right_aws"
  s.version     = RightAws::VERSION::STRING
  s.platform    = Gem::Platform::RUBY
	s.author 			= "Dane Jensen"
	s.email   		= "careo@fastmail.fm"
  s.homepage    = "http://github.com/rightscale/right_aws"
	s.summary     = "RightScale Amazon Web Services Ruby Gems"
  s.description = "The RightScale AWS gems have been designed to provide a robust, fast, and secure interface to Amazon EC2, EBS, S3, SQS, SDB, and CloudFront."
 
	

  s.required_rubygems_version = ">= 1.3.6"
  s.rubyforge_project         = "right_aws"

  s.add_development_dependency "rcov"

  s.files        = Dir.glob("{bin,lib}/**/*") + %w(History.txt README.txt Manifest.txt)
  s.require_path = 'lib'
end

