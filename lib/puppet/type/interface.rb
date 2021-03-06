Puppet::Type.newtype(:interface) do
	require 'erb'

	@doc = "Create configuration for IP address aliases and loopback addresses."

	newparam(:name, :namevar => true) do
		desc "The ipaddress to add to alias or loopback/dummy interface"
	end

    ensurable

	newparam(:interface) do
		desc "The interface the IP should be added to"
	end

	newproperty(:interface_type) do
		desc "The interface type, loopback (also dummy) or alias"

        newvalue(:loopback)
        newvalue(:alias)
        newvalue(:normal)

        # Make dummy and loopback equivalent
        aliasvalue(:dummy, :loopback)

        defaultto :normal
	end

	newparam(:interface_desc) do
		desc "On Linux, the description / symbolic name you wish to refer to the 
              interface by. When absent, Redhat Linux defaults to uses the namevar
              which will be either the IP address, or hostname."
	end

	newproperty(:onboot) do
		desc "Whether the interface should be configured to come up on boot"
		newvalue(:true)
		newvalue(:false)
	end

	newproperty(:ifnum) do
		desc "If not automatically configuring the dummy interface or
              and alias. This is use to force a given number to be used"
	end

	newproperty(:ifopts) do
		desc "Interface options."
	end

    newparam(:target) do
        desc "The path to the file this resource creates."

        defaultto { @resource.provider.file_path }
    end
end

# $Id$
