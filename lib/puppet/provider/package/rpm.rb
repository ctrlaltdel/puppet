require 'puppet/provider/package'
# RPM packaging.  Should work anywhere that has rpm installed.
Puppet::Type.type(:package).provide :rpm, :source => :rpm, :parent => Puppet::Provider::Package do
    desc "RPM packaging support; should work anywhere with a working ``rpm``
        binary."

    # The query format by which we identify installed packages
    NVRFORMAT = "%{NAME}-%{VERSION}-%{RELEASE}"

    VERSIONSTRING = "%{VERSION}-%{RELEASE}"

    commands :rpm => "rpm"

    if command('rpm')
        confine :true => begin
                rpm('-ql', 'rpm')
           rescue Puppet::ExecutionFailure
               false
           else
               true
           end
    end

    def self.instances
        packages = []

        # list out all of the packages
        begin
            execpipe("#{command(:rpm)} -qa --nosignature --nodigest --qf '%{NAME} #{VERSIONSTRING}\n'") { |process|
                # our regex for matching dpkg output
                regex = %r{^(\S+)\s+(\S+)}
                fields = [:name, :ensure]

                # now turn each returned line into a package object
                process.each { |line|
                    if match = regex.match(line)
                        hash = {}
                        fields.zip(match.captures) { |field,value|
                            hash[field] = value
                        }
                        hash[:provider] = self.name
                        packages << new(hash)
                    else
                        raise "failed to match rpm line %s" % line
                    end
                }
            }
        rescue Puppet::ExecutionFailure
            raise Puppet::Error, "Failed to list packages"
        end

        return packages
    end

    # Find the fully versioned package name and the version alone. Returns
    # a hash with entries :instance => fully versioned package name, and 
    # :ensure => version-release
    def query
        cmd = ["-q", @resource[:name], "--nosignature", "--nodigest", "--qf", "#{NVRFORMAT} #{VERSIONSTRING}\n"]

        begin
            output = rpm(*cmd)
        rescue Puppet::ExecutionFailure
            return nil
        end

        regex = %r{^(\S+)\s+(\S+)}
        fields = [:instance, :ensure]
        attrs = {}
        if match = regex.match(output)
            fields.zip(match.captures) { |field,value|
                attrs[field] = value
            }
        else
            raise Puppet::DevError,
                "Failed to match rpm output '%s'" %
                output
        end

        @nvr = attrs[:instance]

        return attrs
    end

    # Here we just retrieve the version from the file specified in the source.
    def latest
        unless source = @resource[:source]
            @resource.fail "RPMs must specify a package source"
        end
        
        cmd = [command(:rpm), "-q", "--qf", "#{VERSIONSTRING}", "-p", "#{@resource[:source]}"]
        version = execfail(cmd, Puppet::Error)
        return version
    end

    def install
        source = nil
        unless source = @resource[:source]
            @resource.fail "RPMs must specify a package source"
        end
        # RPM gets pissy if you try to install an already 
        # installed package
        if @resource.should(:ensure) == @property_hash[:ensure] or
            @resource.should(:ensure) == :latest && @property_hash[:ensure] == latest
            return
        end

        flag = "-i"
        if @property_hash[:ensure] and @property_hash[:ensure] != :absent
            flag = "-U"
        end

        rpm flag, "--oldpackage", source
    end

    def uninstall
        rpm "-e", nvr
    end

    def update
        self.install
    end

    def nvr
        query unless @nvr
        @nvr
    end
end

# $Id$
