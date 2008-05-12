#!/usr/bin/env ruby

require File.dirname(__FILE__) + '/../lib/puppettest'

require 'puppet'
require 'puppettest'

class TestSELinux < Test::Unit::TestCase
        include PuppetTest

	def test_filecontext
		path = tempfile()
		file = nil
		context = nil

		file = Puppet.type(:file).create(
			:path => path,
			:ensure => "file"
		)

		assert_nothing_raised() {
			file[:seluser] = "foo_u"
		}
		assert_nothing_raised() {
			file[:selrole] = "bar_r"
		}
		assert_nothing_raised() {
			file[:seltype] = "baz_t"
		}
	end

	def test_seboolean
		bool = nil
		assert(
			bool = Puppet::Type.type(:selboolean)
		)
		assert(
			bool = {
				:name => 'foo',
				:value => 'off',
				:persistent => true
			}
		)
		assert(
			bool = {
				:name => 'bar',
				:value => 'on',
				:persistent => false
			}
		)
	end

	def test_semodule
		mod = nil
		assert(
			mod = Puppet::Type.type(:selmodule).create(
				:name => 'foo',
				:selmoduledir => '/some/path/here',
				:selmodulepath => '/some/path/here/foo.pp',
				:syncversion => 'true'
			)
		)

		assert(mod[:name] = 'bar')
		assert(mod[:selmoduledir] = '/some/other/path')
		assert(mod[:selmodulepath] = '/some/other/path/bar.pp')
		assert(mod[:syncversion] = 'false') #XXX: Bug here. False is not currently a valid value.
	end
end
