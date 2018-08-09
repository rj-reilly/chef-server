require 'chef_server_ctl/log'

# ChefServerCtl::Config is a global configuration class for
# ChefServerCtl subcommands.
#
# We use a global at the moment to avoid too much upheaval in the
# various subcommands.
#
# Configuration is based on environment variables to make it easy to
# implement wrappers in our Habitat packaged versions of chef-server.
#
# If the environment variables become too unwieldy, we can change them
# as long as we remember to go fix the Habitat wrappers.
#
# TODO(ssd) 2018-08-08: Maybe use a configuration file instead?  I've
# opted against it for now to avoid having to write yet-another-file
# out during reconfiugration.
module ChefServerCtl
  module Config
    DEFAULT_KNIFE_CONFIG_FILE = "/etc/opscode/pivotal.rb".freeze
    DEFAULT_KNIFE_BIN = "/opt/opscode/embedded/bin/knife".freeze
    DEFAULT_LB_URL = "https://127.0.0.1".freeze
    DEFAULT_FIPS_LB_URL = "http://127.0.0.1".freeze
    DEFAULT_RABBITMQCTL_BIN = "/opt/opscode/embedded/service/rabbitmq/sbin/rabbitmqctl".freeze
    DEFAULT_ERCHEF_REINDEX_SCRIPT = "/opt/opscode/embedded/service/opscode-erchef/bin/reindex-opc-organization".freeze

    def self.init(ctl)
      @@ctl = ctl
      Log.debug("Using KNIFE_CONFIG_FILE=#{self.knife_config_file}")
      Log.debug("Using KNIFE_BIN=#{self.knife_bin}")
      Log.debug("Using BIFROST_URL=#{self.bifrost_url}")
      Log.debug("Using LB_URL=#{self.lb_url}")
      Log.debug("Using HABITAT_MODE=#{self.habitat_mode}")
    end

    # knife_config should be the path to a configuration file that
    # allows the `knife` executable to run with pivotal permissions.
    def self.knife_config_file
      if ENV['CSC_KNIFE_CONFIG_FILE']
        ENV['CSC_KNIFE_CONFIG_FILE']
      else
        DEFAULT_KNIFE_CONFIG_FILE
      end
    end

    # knife_bin is the command used to execute knife.
    def self.knife_bin
      if ENV['CSC_KNIFE_BIN']
        ENV['CSC_KNIFE_BIN']
      else
        DEFAULT_KNIFE_BIN
      end
    end

    # rabbitmqctl_bin is the command used to execute rabbitmqctl. This
    # is used for the --wait flag of the reindex command.
    def self.rabbitmqctl_bin
      if ENV['CSC_RABBITMQCTL_BIN']
        ENV['CSC_RABBITMQCTL_BIN']
      else
        DEFAULT_RABBITMQCTL_BIN
      end
    end

    # fips_enabled indicates whether the chef-server is running in
    # fips mode.
    def self.fips_enabled
      if ENV['CSC_FIPS_ENABLED']
        ENV['CSC_FIPS_ENABLED'] == "true"
      else
        @ctl.running_config["private_chef"]["fips_enabled"]
      end
    end

    # The lb_url should be an HTTP address that supports the Chef
    # Server API.
    def self.lb_url
      if ENV['CSC_LB_URL']
        ENV['CSC_LB_URL']
      elsif self.fips_enabled
        DEFAULT_FIPS_LB_URL
      else
        DEFAULT_LB_URL
      end
    end

    # The bifrost_superuser_id is a shared secret of the bifrost
    # service that allows us to make requests without access controls.
    def self.bifrost_superuser_id
      @@bifrost_superuser_id ||= if ENV['CSC_BIFROST_SUPERUSER_ID']
                                   ENV['CSC_BIFROST_SUPERUSER_ID']
                                 else
                                   @@ctl.credentials.get('oc_bifrost', 'superuser_id')
                                 end
    end

    # bifrost_url is an HTTP url for the Bifrost authentication
    # service.
    def self.bifrost_url
      @@bifrost_url ||= if ENV['CSC_BIFROST_URL']
                          ENV['CSC_BIFROST_URL']
                        else
                          bifrost_config = @@ctl.running_service_config('oc_bifrost')
                          vip = bifrost_config['vip']
                          port = bifrost_config['port']
                          "http://#{vip}:#{port}"
                        end
    end

    # bifrost_sql_connuri returns a string in the libpq connection URI
    # format. This string is suitable for passing directly to
    # ::PGConn.open.
    def self.bifrost_sql_connuri
      @@bifrost_connuri ||= if ENV['CSC_BIFROST_DB_URI']
                              ENV['CSC_BIFROST_DB_URI']
                            else
                              bifrost_config = running_service_config('oc_bifrost')
                              user = bifrost_config['sql_user']
                              password = @@ctl.credentials.get('oc_bifrost', 'sql_password')
                              make_connection_string('bifrost', user, password)
                            end
    end

    # erchef_sql_connuri returns a string in the libpq connection URI
    # format. This string is suitable for passing directly to
    # ::PGConn.open.
    def self.erchef_sql_connuri
      @@erchef_connuri ||= if ENV['CSC_ERCHEF_DB_URI']
                             ENV['CSC_ERCHEF_DB_URI']
                           else
                             erchef_config = running_service_config('opscode-erchef')
                             user = echef_config['sql_user']
                             password = @@ctl.credentials.get('opscode_erchef', 'sql_password')
                             make_connection_string('opscode_chef', user, password)
                           end
    end

    # erchef_reindex_script is a command to execute to run the erchef
    # reindex RPC calls. This is an RPC script that is part of the
    # erchef application.
    def self.erchef_reindex_script
      if ENV['CSC_ERCHEF_REINDEX_SCRIPT']
        ENV['CSC_ERCHEF_REINDEX_SCRIPT']
      else
        DEFAULT_ERCHEF_REINDEX_SCRIPT
      end
    end

    # habitat_mode is a boolean that is true if running in habitat
    # mode.
    def self.habitat_mode
      ENV['CSC_HABITAT_MODE'] == "true"
    end

    def self.make_connection_string(dbname, db_user, db_password)
      pg_config = @@ctl.running_service_config('postgresql')
      host = pg_config['vip']
      port = pg_config['port']
      "postgresql://#{db_user}:#{db_password}@#{host}:#{port}/#{db_name}"
    end
  end
end
