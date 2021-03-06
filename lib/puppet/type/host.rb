module Puppet
    newtype(:host) do
        ensurable

        newproperty(:ip) do
            desc "The host's IP address, IPv4 or IPv6."
        end

        newproperty(:alias) do
            desc "Any alias the host might have.  Multiple values must be
                specified as an array.  Note that this state has the same name
                as one of the metaparams; using this state to set aliases will
                make those aliases available in your Puppet scripts and also on
                disk."

           def insync?(is)
                is == @should
            end
            
            def is_to_s(currentvalue = @is)
                currentvalue = [currentvalue] unless currentvalue.is_a? Array
                currentvalue.join(" ")
            end

            def retrieve
                is = super
                case is
                when String
                    is = is.split(/\s*,\s*/)
                when Symbol:
                    is = [is]
                when Array
                    # nothing
                else
                    raise Puppet::DevError, "Invalid @is type %s" % is.class
                end
                return is
            end

            # We actually want to return the whole array here, not just the first
            # value.
            def should
                if defined? @should
                    if @should == [:absent]
                        return :absent
                    else
                        return @should
                    end
                else
                    return nil
                end
            end

            def should_to_s(newvalue = @should)
                newvalue.join(" ")
            end

            validate do |value|
                if value =~ /\s/
                    raise Puppet::Error, "Aliases cannot include whitespace"
                end
            end
        end

        newproperty(:target) do
            desc "The file in which to store service information.  Only used by
                those providers that write to disk (i.e., not NetInfo)."

            defaultto { if @resource.class.defaultprovider.ancestors.include?(Puppet::Provider::ParsedFile)
                    @resource.class.defaultprovider.default_target
                else
                    nil
                end
            }
        end

        newparam(:name) do
            desc "The host name."

            isnamevar
        end

        @doc = "Installs and manages host entries.  For most systems, these
            entries will just be in ``/etc/hosts``, but some systems (notably OS X)
            will have different solutions."
    end
end

# $Id$
