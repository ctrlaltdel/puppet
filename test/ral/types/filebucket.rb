#!/usr/bin/env ruby

$:.unshift("../../lib") if __FILE__ =~ /\.rb$/

require 'puppettest'
require 'fileutils'

class TestFileBucket < Test::Unit::TestCase
    include PuppetTest::FileTesting
    # hmmm
    # this is complicated, because we store references to the created
    # objects in a central store
    def mkfile(hash)
        file = nil
        assert_nothing_raised {
            file = Puppet.type(:file).create(hash)
        }
        return file
    end

    def mkbucket(name,path)
        bucket = nil
        assert_nothing_raised {
            bucket = Puppet.type(:filebucket).create(
                :name => name,
                :path => path
            )
        }

        @@tmpfiles.push path

        return bucket
    end

    def mktestfile
        # because luke's home directory is on nfs, it can't be used for testing
        # as root
        tmpfile = tempfile()
        File.open(tmpfile, "w") { |f| f.puts rand(100) }
        @@tmpfiles.push tmpfile
        mkfile(:name => tmpfile)
    end

    def setup
        super
        begin
            initstorage
        rescue
            system("rm -rf %s" % Puppet[:statefile])
        end
    end

    def initstorage
        Puppet::Util::Storage.init
        Puppet::Util::Storage.load
    end

    def clearstorage
        Puppet::Util::Storage.store
        Puppet::Util::Storage.clear
    end

    def test_simplebucket
        name = "yayness"
        bucketpath = tempfile()
        mkbucket(name, bucketpath)

        bucket = nil
        assert_nothing_raised {
            bucket = Puppet.type(:filebucket).bucket(name)
        }

        assert_instance_of(Puppet::Network::Client.dipper, bucket)

        md5 = nil
        newpath = tempfile()
        @@tmpfiles << newpath
        system("cp /etc/passwd %s" % newpath)
        assert_nothing_raised {
            md5 = bucket.backup(newpath)
        }

        assert(md5)

        dir, file, pathfile = Puppet::Network::Handler.filebucket.paths(bucketpath, md5)

        assert(FileTest.directory?(dir),
            "MD5 directory does not exist")

        newmd5 = nil

        # Just in case the file isn't writable
        File.chmod(0644, newpath)
        File.open(newpath, "w") { |f| f.puts ";lkjasdf;lkjasdflkjwerlkj134lkj" }

        assert_nothing_raised {
            newmd5 = bucket.backup(newpath)
        }

        assert(md5 != newmd5)

        assert_nothing_raised {
            bucket.restore(newpath, md5)
        }

        File.open(newpath) { |f| newmd5 = Digest::MD5.hexdigest(f.read) }

        assert_equal(md5, newmd5)
    end

    def test_fileswithbuckets
        name = "yayness"
        mkbucket(name, tempfile())

        bucket = nil
        assert_nothing_raised {
            bucket = Puppet.type(:filebucket).bucket(name)
        }

        file = mktestfile()
        assert_nothing_raised {
            file[:backup] = name
        }

        opath = tempfile()
        @@tmpfiles << opath
        File.open(opath, "w") { |f| f.puts "yaytest" }

        origmd5 = File.open(file.name) { |f| newmd5 = Digest::MD5.hexdigest(f.read) }

        file[:source] = opath
        #assert_nothing_raised {
        #    file[:backup] = true
        #}

        assert_apply(file)

        # so, we've now replaced the file with the opath file
        assert_equal(
            File.open(opath) { |f| newmd5 = Digest::MD5.hexdigest(f.read) },
            File.open(file.name) { |f| newmd5 = Digest::MD5.hexdigest(f.read) }
        )

        #File.chmod(0644, file.name)
        assert_nothing_raised {
            bucket.restore(file.name, origmd5)
        }

        assert_equal(
            origmd5,
            File.open(file.name) { |f| newmd5 = Digest::MD5.hexdigest(f.read) }
        )
    end
end

# $Id$
