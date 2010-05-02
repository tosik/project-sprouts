
module Sprout::User

  # The abstract base class for all supported user/platform types.
  # In general, users are created by calling the +create+ factory method
  # on the +User+ module.
  #     
  #     User.create
  #
  # Assuming you call the create method, you should wind up with
  # a concrete user that matches your system, and these concrete
  # users will generally be derived from this base class.
  #
  class BaseUser

    ##
    # Get the home path for a user on a particular operating system.
    #
    # This path will be different, depending on which user owns
    # the curren process, and which operating system they are on.
    #
    def home
      @home ||= find_home
    end

    ##
    # Set the home path for a user on a particular operating system.
    # 
    # If you request the home path before setting it, we will
    # attempt to determine the home path of the current user for
    # the current operating system.
    #
    # This is just a simple way to override the default behavior.
    #
    def home=(home)
      @home = home
    end

    ##
    # Some operating systems (like OS X and Windows) have a 
    # specific location where applications are expected to store
    # files for a particular user. This location is generally
    # a subdirectory of +home+.
    # 
    # The value of this location will usually be overridden in
    # concrete User classes.
    #
    def library
      return home
    end

    ##
    # Instantiate and return a new Sprout::ProcessRunner so
    # that we can execute it.
    #
    def get_process_runner
      Sprout::ProcessRunner.new
    end

    ##
    # Get a process runner and execute the provided +tool+,
    # with the provided +options+.
    #
    # +tool+ String path to the external executable file.
    #
    # +options+ String commandline options to send to the +tool+.
    #
    def get_and_execute_process_runner tool, options=nil
      runner = get_process_runner
      runner.execute_open4 tool, options
      runner
    end

    ##
    # Creates a new process, executes the command
    # and returns whatever the process wrote to stdout, or stderr.
    #
    # Raises a +Sprout::Errors::ExecutionError+ if the process writes to stderr
    #
    def execute(tool, options='')
      Sprout::Log.puts(">> Execute: #{tool} #{options}")
      tool   = clean_path(tool)
      runner = get_and_execute_process_runner(tool, options)
      error  = runner.read_err
      result = runner.read

      if(result.size > 0)
        Sprout::Log.puts result
      end

      if(error.size > 0)
        raise Sprout::Errors::ExecutionError.new("[ERROR] #{error}")
      end

      result || error
    end

    ##
    # Creates and returns the process without
    # attempting to read or write to the stream.
    # This is useful for interacting with
    # long-lived CLI processes like FCSH or FDB.
    #
    def execute_silent(tool, options='')
      tool = clean_path(tool)
      return get_and_execute_process_runner(tool, options)
    end

    ##
    # Execute a new process in a separate thread.
    # This can be useful for processes that take
    # an especially long time to execute.
    #
    # Threads are complicated - use with caution...
    #
    def execute_thread(tool, options='')
      return Thread.new do
        execute(tool, options)
      end
    end

    ##
    # Clean the provided +path+ String for the current
    # operating system.
    #
    # Each operating system behaves differently when we
    # attempt to execute a file with spaces in the +path+
    # to the file.
    # 
    # Subclasses will generally override this method and
    # clean the path appropriately for their operating 
    # system.
    #
    def clean_path(path)
    end

    ##
    # Different operating systems will store Application data
    # different default locations.
    #
    # Subclasses will generally override this method and 
    # return the appropriate location for their operating system.
    #
    # +name+ String value of the Application name for which we'd
    # like to store data.
    #
    def application_home(name)
      return File.join(library, format_application_name(name.to_s));
    end

    ##
    # Template method that should be overridden by
    # subclasses.
    #
    def format_application_name(name)
      name
    end

    protected

    def env_homedrive
      ENV['HOMEDRIVE']
    end

    def env_homepath
      ENV['HOMEPATH']
    end

    def env_homedrive_and_homepath
      drive = env_homedrive
      path = env_homepath
      "#{drive}:#{path}" if drive && path
    end

    def env_userprofile
      ENV['USERPROFILE']
    end

    def env_home
      ENV['HOME']
    end

    def tilde_home
      File.expand_path("~")
    end

    def alt_separator?
      File::ALT_SEPARATOR
    end

    def worst_case_home
      return "C:\\" if alt_separator?
      return "/"
    end

    def find_home
      [:env_userprofile, :env_home, :env_homedrive_and_homepath].each do |key|
        value = self.send(key)
        return value unless value.nil?
      end

      begin
        return tilde_home
      rescue StandardError
        worst_case_home
      end
    end
  end
end

