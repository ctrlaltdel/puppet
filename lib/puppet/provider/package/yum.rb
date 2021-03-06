Puppet::Type.type(:package).provide :yum, :parent => :rpm, :source => :rpm do
    desc "Support via ``yum``."

    has_feature :versionable

    commands :yum => "yum", :rpm => "rpm"

    if command('rpm')
        confine :true => begin
                rpm('-ql', 'rpm')
           rescue Puppet::ExecutionFailure
               false
           else
               true
           end
    end

    defaultfor :operatingsystem => [:fedora, :centos, :redhat]

    def install

        should = @resource.should(:ensure)
        self.debug "Ensuring => #{should}"
        wanted = @resource[:name]

        # XXX: We don't actually deal with epochs here.
        case should
        when true, false, Symbol
            # pass
        else
            # Add the package version
            wanted += "-%s" % should
        end

        output = yum "-d", "0", "-e", "0", "-y", :install, wanted

        unless self.query
            raise Puppet::Error.new(
                "Could not find package %s" % self.name
            )
        end
    end

    # What's the latest package version available?
    def latest
        output = yum "-d", "0", "-e", "0", :list, :available, @resource[:name]

        if output =~ /^#{Regexp.escape(@resource[:name])}\S+\s+(\S+)\s/
            return $1
        else
            # Yum didn't find updates, pretend the current
            # version is the latest
            unless properties[:ensure] != :absent
                raise Puppet::DevError, "Tried to get latest on a missing package"
            end
            return @property_hash[:ensure]
        end
    end

    def update
        # Install in yum can be used for update, too
        self.install
    end
end

# $Id$
