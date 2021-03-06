#!/usr/bin/env ruby

$:.unshift("../lib").unshift("../../lib") if __FILE__ =~ /\.rb$/

require 'puppettest'
require 'puppet/parser/interpreter'
require 'puppet/parser/parser'
require 'puppettest/resourcetesting'
require 'puppettest/parsertesting'
require 'puppettest/support/collection'

class TestAST < Test::Unit::TestCase
    include PuppetTest::ParserTesting
    include PuppetTest::ResourceTesting
    include PuppetTest::Support::Collection

    def test_if
        astif = nil
        astelse = nil
        fakeelse = FakeAST.new(:else)
        faketest = FakeAST.new(true)
        fakeif = FakeAST.new(:if)

        assert_nothing_raised {
            astelse = AST::Else.new(:statements => fakeelse)
        }
        assert_nothing_raised {
            astif = AST::IfStatement.new(
                :test => faketest,
                :statements => fakeif,
                :else => astelse
            )
        }

        # We initialized it to true, so we should get that first
        ret = nil
        assert_nothing_raised {
            ret = astif.evaluate(:scope => "yay")
        }
        assert_equal(:if, ret)

        # Now set it to false and check that
        faketest.evaluate = false
        assert_nothing_raised {
            ret = astif.evaluate(:scope => "yay")
        }
        assert_equal(:else, ret)
    end

    # Make sure our override object behaves "correctly"
    def test_override
        interp, scope, source = mkclassframing

        ref = nil
        assert_nothing_raised do
            ref = resourceoverride("resource", "yaytest", "one" => "yay", "two" => "boo")
        end

        ret = nil
        assert_nothing_raised do
            ret = ref.evaluate :scope => scope
        end

        assert_instance_of(Puppet::Parser::Resource, ret)

        assert(ret.override?, "Resource was not an override resource")

        assert(scope.overridetable[ret.ref].include?(ret),
            "Was not stored in the override table")
    end

    # make sure our resourcedefaults ast object works correctly.
    def test_resourcedefaults
        interp, scope, source = mkclassframing

        # Now make some defaults for files
        args = {:source => "/yay/ness", :group => "yayness"}
        assert_nothing_raised do
            obj = defaultobj "file", args
            obj.evaluate :scope => scope
        end

        hash = nil
        assert_nothing_raised do
            hash = scope.lookupdefaults("file")
        end

        hash.each do |name, value|
            assert_instance_of(Symbol, name) # params always convert
            assert_instance_of(Puppet::Parser::Resource::Param, value)
        end

        args.each do |name, value|
            assert(hash[name], "Did not get default %s" % name)
            assert_equal(value, hash[name].value)
        end
    end

    def test_node
        interp = mkinterp
        scope = mkscope(:interp => interp)

        # Define a base node
        basenode = interp.newnode "basenode", :code => AST::ASTArray.new(:children => [
            resourcedef("file", "/tmp/base", "owner" => "root")
        ])

        # Now define a subnode
        nodes = interp.newnode ["mynode", "othernode"],
            :code => AST::ASTArray.new(:children => [
                resourcedef("file", "/tmp/mynode", "owner" => "root"),
                resourcedef("file", "/tmp/basenode", "owner" => "daemon")
        ])

        assert_instance_of(Array, nodes)

        # Make sure we can find them all.
        %w{mynode othernode}.each do |node|
            assert(interp.nodesearch_code(node), "Could not find %s" % node)
        end
        mynode = interp.nodesearch_code("mynode")

        # Now try evaluating the node
        assert_nothing_raised do
            mynode.evaluate :scope => scope
        end

        # Make sure that we can find each of the files
        myfile = scope.findresource "File[/tmp/mynode]"
        assert(myfile, "Could not find file from node")
        assert_equal("root", myfile[:owner])

        basefile = scope.findresource "File[/tmp/basenode]"
        assert(basefile, "Could not find file from base node")
        assert_equal("daemon", basefile[:owner])

        # Now make sure we can evaluate nodes with parents
        child = interp.newnode(%w{child}, :parent => "basenode").shift

        newscope = mkscope :interp => interp
        assert_nothing_raised do
            child.evaluate :scope => newscope
        end

        assert(newscope.findresource("File[/tmp/base]"),
            "Could not find base resource")
    end

    def test_collection
        interp = mkinterp
        scope = mkscope(:interp => interp)

        coll = nil
        assert_nothing_raised do
            coll = AST::Collection.new(:type => "file", :form => :virtual)
        end

        assert_instance_of(AST::Collection, coll)

        ret = nil
        assert_nothing_raised do
            ret = coll.evaluate :scope => scope
        end

        assert_instance_of(Puppet::Parser::Collector, ret)

        # Now make sure we get it back from the scope
        assert_equal([ret], scope.collections)
    end

    def test_virtual_collexp
        @interp, @scope, @source = mkclassframing

        # make a resource
        resource = mkresource(:type => "file", :title => "/tmp/testing",
            :params => {:owner => "root", :group => "bin", :mode => "644"})

        run_collection_queries(:virtual) do |string, result, query|
            code = nil
            assert_nothing_raised do
                str, code = query.evaluate :scope => @scope
            end

            assert_instance_of(Proc, code)
            assert_nothing_raised do
                assert_equal(result, code.call(resource),
                    "'#{string}' failed")
            end
        end
    end
end

# $Id$
