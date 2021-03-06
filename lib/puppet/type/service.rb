# This is our main way of managing processes right now.
#
# a service is distinct from a process in that services
# can only be managed through the interface of an init script
# which is why they have a search path for initscripts and such

module Puppet

    newtype(:service) do
        @doc = "Manage running services.  Service support unfortunately varies
            widely by platform -- some platforms have very little if any
            concept of a running service, and some have a very codified and
            powerful concept.  Puppet's service support will generally be able
            to make up for any inherent shortcomings (e.g., if there is no
            'status' command, then Puppet will look in the process table for a
            command matching the service name), but the more information you
            can provide the better behaviour you will get.  Or, you can just
            use a platform that has very good service support.
	    
            Note that if a ``service`` receives an event from another resource,
            the service will get restarted. The actual command to restart the
            service depends on the platform. You can provide a special command
            for restarting with the ``restart`` attribute."
        
        feature :refreshable, "The provider can restart the service.",
            :methods => [:restart]
        
        feature :enableable, "The provider can enable and disable the service",
            :methods => [:disable, :enable, :enabled?]

        attr_reader :stat

        newproperty(:enable) do
            attr_reader :runlevel
            desc "Whether a service should be enabled to start at boot.
                This property behaves quite differently depending on the platform;
                wherever possible, it relies on local tools to enable or disable
                a given service."

            newvalue(:true, :event => :service_enabled) do
                unless provider.respond_to?(:enable)
                    raise Puppet::Error, "Service %s does not support enabling" %
                        @resource.name
                end
                provider.enable
            end

            newvalue(:false, :event => :service_disabled) do
                unless provider.respond_to?(:disable)
                    raise Puppet::Error, "Service %s does not support enabling" %
                        @resource.name
                end
                provider.disable
            end

            def retrieve
                unless provider.respond_to?(:enabled?)
                    raise Puppet::Error, "Service %s does not support enabling" %
                        @resource.name
                end
                return provider.enabled?
            end

            validate do |value|
                unless value =~ /^\d+/
                    super(value)
                end
            end

            munge do |should|
                @runlevel = nil
                if should =~ /^\d+$/
                    arity = @resource.method(:enable)
                    if @runlevel and arity != 1
                        raise Puppet::Error,
                            "Services on %s do not accept runlevel specs" %
                                @resource.type
                    elsif arity != 0
                        raise Puppet::Error,
                            "Services on %s must specify runlevels" %
                                @resource.type
                    end
                    @runlevel = should
                    return :true
                else
                    super(should)
                end
            end

            def sync
                case self.should
                when :true
                    if @runlevel
                        provider.enable(@runlevel)
                    else
                        provider.enable()
                    end
                    return :service_enabled
                when :false
                    provider.disable
                    return :service_disabled
                end
            end
        end

        # Handle whether the service should actually be running right now.
        newproperty(:ensure) do
            desc "Whether a service should be running."

            newvalue(:stopped, :event => :service_stopped) do
                provider.stop
            end

            newvalue(:running, :event => :service_started) do
                provider.start
            end

            aliasvalue(:false, :stopped)
            aliasvalue(:true, :running)

            def retrieve
                return provider.status
            end

            def sync
                event = super()
#                case self.should
#                when :running
#                    provider.start
#                    event = :service_started
#                when :stopped
#                    provider.stop
#                    event = :service_stopped
#                else
#                    self.debug "Not running '%s' and shouldn't be running" %
#                        self
#                end

                if property = @resource.property(:enable)
                    val = property.retrieve
                    unless property.insync?(val)
                        property.sync
                    end
                end

                return event
            end
        end

        # Produce a warning, rather than just failing.
        newparam(:running) do
            desc "A place-holder parameter that wraps ``ensure``, because
                ``running`` is deprecated.  You should use ``ensure`` instead
                of this, but using this will still work, albeit with a
                warning."

            munge do |value|
                @resource.warning "'running' is deprecated; please use 'ensure'"
                @resource[:ensure] = value
            end
        end

        newparam(:binary) do
            desc "The path to the daemon.  This is only used for
                systems that do not support init scripts.  This binary will be
                used to start the service if no ``start`` parameter is
                provided."
        end

        newparam(:hasstatus) do
            desc "Declare the the service's init script has a
                functional status command.  Based on testing, it was found
                that a large number of init scripts on different platforms do
                not support any kind of status command; thus, you must specify
                manually whether the service you are running has such a
                command (or you can specify a specific command using the
                ``status`` parameter).
                
                If you do not specify anything, then the service name will be
                looked for in the process table."
        end
        newparam(:name) do
            desc "The name of the service to run.  This name
                is used to find the service in whatever service subsystem it
                is in."
            isnamevar
        end

        newparam(:type) do
            desc "Deprecated form of ``provider``."

            munge do |value|
                warning "'type' is deprecated; use 'provider' instead"
                @resource[:provider] = value
            end
        end

        newparam(:path) do
            desc "The search path for finding init scripts."

            munge do |value|
                paths = []
                if value.is_a?(Array)
                    paths += value.flatten.collect { |p|
                        p.split(":")
                    }.flatten
                else
                    paths = value.split(":")
                end

                paths.each do |path|
                    if FileTest.directory?(path)
                        next
                    end
                    if FileTest.exists?(path)
                        unless FileTest.directory?(path)
                            @resource.debug "Search path %s is not a directory" %
                                [path]
                        end
                    else
                        @resource.debug("Search path %s does not exist" % [path])
                    end
                    paths.delete(path)
                end

                paths
            end
        end
        newparam(:pattern) do
            desc "The pattern to search for in the process table.
                This is used for stopping services on platforms that do not
                support init scripts, and is also used for determining service
                status on those service whose init scripts do not include a status
                command.
                
                If this is left unspecified and is needed to check the status
                of a service, then the service name will be used instead.
                
                The pattern can be a simple string or any legal Ruby pattern."

            defaultto {
                @resource[:binary] || @resource[:name]
            }
        end
        newparam(:restart) do
            desc "Specify a *restart* command manually.  If left
                unspecified, the service will be stopped and then started."
        end
        newparam(:start) do
            desc "Specify a *start* command manually.  Most service subsystems
                support a ``start`` command, so this will not need to be
                specified."
        end
        newparam(:status) do
            desc "Specify a *status* command manually.  If left
                unspecified, the status method will be determined
                automatically, usually by looking for the service in the
                process table."
        end

        newparam(:stop) do
            desc "Specify a *stop* command manually."
        end

        newparam :hasrestart do
            desc "Specify that an init script has a ``restart`` option.  Otherwise,
                the init script's ``stop`` and ``start`` methods are used."
            newvalues(:true, :false)
        end

        # Add a new path to our list of paths that services could be in.
        def self.newpath(type, path)
            type = type.intern if type.is_a? String
            @paths ||= {}
            @paths[type] ||= []

            unless @paths[type].include? path
                @paths[type] << path
            end
        end

        def self.paths(type)
            type = type.intern if type.is_a? String
            @paths ||= {}
            @paths[type] ||= []

            @paths[type].dup
        end

        # Initialize the service.  This is basically responsible for merging
        # in the right module.
        def initialize(hash)
            super

            # and then see if it needs to be checked
            if self.respond_to?(:configchk)
                self.configchk
            end

            unless @parameters.include?(:ensure) or @parameters.include?(:enable)
                warning "No properties specified; 'enable' or 'ensure' should be specified"
            end
        end

        # Basically just a synonym for restarting.  Used to respond
        # to events.
        def refresh
            # Only restart if we're supposed to be running
            
            if ens = @parameters[:ensure] and ens.should == :running and ens.retrieve == :running
                provider.restart
            else
                debug "Skipping restart; 'ensure' is not set to 'running'"
            end
        end
    end
end

# $Id$
