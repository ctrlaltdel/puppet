#!/usr/bin/env ruby

$:.unshift("../lib").unshift("../../lib") if __FILE__ =~ /\.rb$/

require 'puppet'
require 'puppettest'

class TestError < Test::Unit::TestCase
    include PuppetTest

    def test_errorisstring
        error = nil
        assert_nothing_raised {
            error = Puppet::ParseError.new("This is an error")
        }
        assert_instance_of(String, error.to_s)
    end
end

# $Id$
