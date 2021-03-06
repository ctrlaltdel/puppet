#!/usr/bin/env ruby

$:.unshift("../../lib") if __FILE__ =~ /\.rb$/

require 'puppettest'
require 'mocha'
require 'puppet/network/client'

class TestClient < Test::Unit::TestCase
    include PuppetTest::ServerTest
    class FakeClient < Puppet::Network::Client
        @drivername = :Test
    end

    class FakeDriver
    end

    # a single run through of connect, auth, etc.
    def disabled_test_sslInitWithAutosigningLocalServer
        # autosign everything, for simplicity
        Puppet[:autosign] = true

        # create a server to which to connect
        mkserver()

        # create our client
        client = nil
        assert_nothing_raised {
            client = Puppet::Network::Client.master.new(
                :Server => "localhost",
                :Port => @@port
            )
        }

        # get our certs
        assert_nothing_raised {
            client.initcerts
        }

        # make sure all of our cert files exist
        certfile = File.join(Puppet[:certdir], [client.fqdn, "pem"].join("."))
        keyfile = File.join(Puppet[:privatekeydir], [client.fqdn, "pem"].join("."))
        publickeyfile = File.join(Puppet[:publickeydir], [client.fqdn, "pem"].join("."))

        assert(File.exists?(keyfile))
        assert(File.exists?(certfile))
        assert(File.exists?(publickeyfile))

        # verify we can retrieve the configuration
        assert_nothing_raised("Client could not retrieve configuration") {
            client.getconfig
        }

        # and apply it
        assert_nothing_raised("Client could not apply configuration") {
            client.apply
        }

        # and verify that it did what it was supposed to
        assert(FileTest.exists?(@createdfile),
            "Applied file does not exist")
    end


    # here we create two servers; we 
    def disabled_test_failureWithUntrustedCerts
        Puppet[:autosign] = true

        # create a pair of clients with no certs
        nonemaster = nil
        assert_nothing_raised {
            nonemaster = Puppet::Network::Client.master.new(
                :Server => "localhost",
                :Port => @@port
            )
        }

        nonebucket = nil
        assert_nothing_raised {
            nonebucket = Puppet::Network::Client.dipper.new(
                :Server => "localhost",
                :Port => @@port
            )
        }

        # create a ca so we can create a set of certs
        # make a new ssldir for it
        ca = nil
        assert_nothing_raised {
            ca = Puppet::Network::Client.ca.new(
                :CA => true, :Local => true
            )
            ca.requestcert
        }

        # initialize our clients with this set of certs
        certmaster = nil
        assert_nothing_raised {
            certmaster = Puppet::Network::Client.master.new(
                :Server => "localhost",
                :Port => @@port
            )
        }

        certbucket = nil
        assert_nothing_raised {
            certbucket = Puppet::Network::Client.dipper.new(
                :Server => "localhost",
                :Port => @@port
            )
        }

        # Create a new ssl root.
        confdir = tempfile()
        Puppet[:ssldir] = confdir
        Puppet.config.mkdir(:ssldir)
        Puppet.config.clearused
        Puppet.config.use(:ssl, :ca)

        mkserver

        # now verify that our client cannot do non-cert operations
        # because its certs are signed by a different CA
        assert_raise(Puppet::Error,
            "Client was allowed to call getconfig with no certs") {
            nonemaster.getconfig
        }
        assert_raise(Puppet::Error,
            "Client was allowed to call getconfig with untrusted certs") {
            certmaster.getconfig
        }

        assert_raise(Puppet::Network::XMLRPCClientError,
            "Client was allowed to call backup with no certs") {
            nonebucket.backup("/etc/passwd")
        }
        assert_raise(Puppet::Network::XMLRPCClientError,
            "Client was allowed to call backup with untrusted certs") {
            certbucket.backup("/etc/passwd")
        }
    end

    def test_classfile
        manifest = tempfile()

        File.open(manifest, "w") do |file|
            file.puts "class yaytest {}\n class bootest {}\n include yaytest, bootest"
        end

        master = client = nil
        assert_nothing_raised() {
            master = Puppet::Network::Handler.master.new(
                :Manifest => manifest,
                :UseNodes => false,
                :Local => false
            )
        }
        assert_nothing_raised() {
            client = Puppet::Network::Client.master.new(
                :Master => master
            )
        }

        # Fake that it's local, so it creates the class file
        client.local = false

        assert_nothing_raised {
            client.getconfig
        }

        assert(FileTest.exists?(Puppet[:classfile]), "Class file does not exist")

        classes = File.read(Puppet[:classfile]).split("\n")

        assert_equal(%w{bootest yaytest}, classes.sort)
    end

    def test_client_loading
        # Make sure we don't get a failure but that we also get nothing back
        assert_nothing_raised do
            assert_nil(Puppet::Network::Client.client(:fake),
                "Got something back from a missing client")
            assert_nil(Puppet::Network::Client.fake,
                "Got something back from missing client method")
        end
        # Make a fake client
        dir = tempfile()
        libdir = File.join([dir, %w{puppet network client}].flatten)
        FileUtils.mkdir_p(libdir)

        file = File.join(libdir, "faker.rb")
        File.open(file, "w") do |f|
            f.puts %{class Puppet::Network::Client
                class Faker < Client
                end
            end
            }
        end

        $: << dir
        cleanup { $:.delete(dir) if $:.include?(dir) }

        client = nil
        assert_nothing_raised do
            client = Puppet::Network::Client.client(:faker)
        end
        assert(client, "did not load client")
        assert_nothing_raised do
            assert_equal(client, Puppet::Network::Client.faker,
                "Did not get client back from client method")
        end

        # Now make sure the client behaves correctly
        assert_equal(:Faker, client.name, "name was not calculated correctly")
    end

    # Make sure we get a client class for each handler type.
    def test_loading_all_clients
        %w{ca dipper file master report resource runner status}.each do |name|
            client = nil
            assert_nothing_raised do
                client = Puppet::Network::Client.client(name)
            end
            assert(client, "did not get client for %s" % name)
            [:name, :handler, :drivername].each do |thing|
                assert(client.send(thing), "did not get %s for %s" % [thing, name])
            end
        end
    end

    # Make sure that reading the cert in also sets up the cert stuff for the driver
    def test_read_cert
        ca = Puppet::Network::Handler.ca.new
        caclient = Puppet::Network::Client.ca.new :CA => ca

        caclient.request_cert

        # First make sure it doesn't get called when the driver doesn't support :cert_setup
        client = FakeClient.new :Test => FakeDriver.new
        driver = client.driver

        assert_nothing_raised("Could not read cert") do
            client.read_cert
        end

        # And then that it does when the driver supports it
        client = FakeClient.new :Test => FakeDriver.new

        driver = client.driver
        driver.meta_def(:cert_setup) { |c| }
        driver.expects(:cert_setup).with(client)

        assert_nothing_raised("Could not read cert") do
            client.read_cert
        end
    end
end

# $Id$
