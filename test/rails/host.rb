#!/usr/bin/env ruby

$:.unshift("../lib").unshift("../../lib") if __FILE__ =~ /\.rb$/

require 'puppet'
require 'puppet/rails'
require 'puppet/parser/interpreter'
require 'puppet/parser/parser'
require 'puppet/network/client'
require 'puppettest'
require 'puppettest/parsertesting'
require 'puppettest/resourcetesting'
require 'puppettest/railstesting'

class TestRailsHost < PuppetTest::TestCase
    confine "Missing ActiveRecord" => Puppet.features.rails?
    include PuppetTest::ParserTesting
    include PuppetTest::ResourceTesting
    include PuppetTest::RailsTesting

    def setup
        super
        railsinit if Puppet.features.rails?
    end

    def teardown
        railsteardown if Puppet.features.rails?
        super
    end

    def test_includerails
        assert_nothing_raised {
            require 'puppet/rails'
        }
    end

    def test_store
        @interp, @scope, @source = mkclassframing
        # First make some objects
        resources = []
        4.times { |i|
            # Make a file
            resources << mkresource(:type => "file",
                :title => "/tmp/file#{i.to_s}",
                :params => {:owner => "user#{i}"})

            # And an exec, so we're checking multiple types
            resources << mkresource(:type => "exec",
                :title => "/bin/echo file#{i.to_s}",
                :params => {:user => "user#{i}"})
        }

        # Now collect our facts
        facts = {"hostname" => Facter.value(:hostname), "test1" => "funtest",
            "ipaddress" => Facter.value(:ipaddress)}

        # Now try storing our crap
        host = nil
        assert_nothing_raised {
            host = Puppet::Rails::Host.store(
                :resources => resources,
                :facts => facts,
                :name => facts["hostname"],
                :classes => ["one", "two::three", "four"]
            )
        }

        assert(host, "Did not create host")

        host = nil
        assert_nothing_raised {
            host = Puppet::Rails::Host.find_by_name(facts["hostname"])
        }
        assert(host, "Could not find host object")

        assert(host.resources, "No objects on host")

        facts.each do |fact, value|
            assert_equal(value, host.fact(fact)[0].value, "fact %s is wrong" % fact)
        end
        assert_equal(facts["ipaddress"], host.ip, "IP did not get set")

        count = 0
        host.resources.each do |resource|
            assert_equal(host, resource.host)
            count += 1
            i = nil
            if resource[:title] =~ /file([0-9]+)/
                i = $1
            else
                raise "Got weird resource %s" % resource.inspect
            end
            assert(resource[:restype] != "", "Did not get a type from the resource")
            case resource["restype"]
            when "file":
                assert_equal("user#{i}", resource.parameter("owner"),
                    "got no owner for %s" % resource.ref)
            when "exec":
                assert_equal("user#{i}", resource.parameter("user"),
                    "got no user for %s" % resource.ref)
            else
                raise "Unknown type %s" % resource[:restype].inspect
            end
        end

        assert_equal(8, count, "Did not get enough resources")

        # Now remove a couple of resources
        resources.reject! { |r| r.title =~ /file3/ }

        # Change a few resources
        resources.find_all { |r| r.title =~ /file2/ }.each do |r|
            r.set("loglevel", "notice", r.source)
        end

        # And add a new resource
        resources << mkresource(:type => "file",
            :title => "/tmp/file_added",
            :params => {:owner => "user_added"})

        # And change some facts
        facts["test2"] = "yaytest"
        facts["test3"] = "funtest"
        facts["test1"] = "changedfact"
        facts.delete("ipaddress")
        host = nil
        assert_nothing_raised {
            host = Puppet::Rails::Host.store(
                :resources => resources,
                :facts => facts,
                :name => facts["hostname"],
                :classes => ["one", "two::three", "four"]
            )
        }

        # Make sure it sets the last_compile time
        assert_nothing_raised do
            assert_instance_of(Time, host.last_compile, "did not set last_compile")
        end

        assert_equal(0, host.fact('ipaddress').size, "removed fact was not deleted")
        facts.each do |fact, value|
            assert_equal(value, host.fact(fact)[0].value, "fact %s is wrong" % fact)
        end

        # And check the changes we made.
        assert(! host.resources.find(:all).detect { |r| r.title =~ /file3/ },
            "Removed resources are still present")

        res = host.resources.find_by_title("/tmp/file_added")
        assert(res, "New resource was not added")
        assert_equal("user_added", res.parameter("owner"), "user info was not stored")

        host.resources.find(:all, :conditions => [ "title like ?", "%file2%"]).each do |r|
            assert_equal("notice", r.parameter("loglevel"),
                "loglevel was not added")
        end
    end

    def test_freshness_connect_update
        Puppet::Rails.init
        Puppet[:storeconfigs] = true

        # this is the default server setup
        master = Puppet::Network::Handler.master.new(
            :Code => "",
            :UseNodes => true,
            :Local => true
        )

        # Create a host
        Puppet::Rails::Host.new(:name => "test", :ip => "192.168.0.3").save

        assert_nothing_raised("Failed to update last_connect for unknown host") do
            master.freshness("created",'192.168.0.1')
        end
        
        # Make sure it created the host
        created = Puppet::Rails::Host.find_by_name("created")
        assert(created, "Freshness did not create host")
        assert(created.last_freshcheck,
            "Did not set last_freshcheck on created host")
        assert_equal("192.168.0.1", created.ip,
            "Did not set IP address on created host")

        # Now check on the existing host
        assert_nothing_raised("Failed to update last_connect for unknown host") do
            master.freshness("test",'192.168.0.2')
        end

        # Recreate it, so we're not using the cached object.
        host = Puppet::Rails::Host.find_by_name("test")
        
        # Make sure it created the host
        assert(host.last_freshcheck,
            "Did not set last_freshcheck on existing host")
        assert_equal("192.168.0.3", host.ip,
            "Overrode IP on found host")
    end
end

# $Id$
