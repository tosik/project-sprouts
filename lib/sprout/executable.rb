require 'sprout/executable/parser'
require 'sprout/executable/param'
require 'sprout/executable/collection_param'
require 'sprout/executable/boolean_param'
require 'sprout/executable/number_param'
require 'sprout/executable/string_param'
require 'sprout/executable/strings_param'
require 'sprout/executable/file_param'
require 'sprout/executable/files_param'
require 'sprout/executable/path_param'
require 'sprout/executable/paths_param'
require 'sprout/executable/symbols_param'
require 'sprout/executable/url_param'
require 'sprout/executable/urls_param'

module Sprout
  module Executable

    DEFAULT_FILE_EXPRESSION = '/**/**/*'

    extend Sprout::Concern

    module ClassMethods

      # +add_param+ is the workhorse of the Task.
      # This method is used to add new shell parameters to the executable interface.
      #
      # +name+ is a symbol or string that represents the parameter that you would like to add
      # such as :debug or :source_path.
      # +type+ is usually sent as a Ruby symbol and can be one of the following:
      #
      # [:string]   Any string value
      # [:boolean]  true or false
      # [:number]   Any number
      # [:file]     Path to a file
      # [:url]      Basic URL
      # [:path]     Path to a directory
      # [:files]    Collection of files
      # [:paths]    Collection of directories
      # [:strings]  Collection of arbitrary strings
      # [:urls]     Collection of URLs
      #
      # Be sure to check out the Sprout::Executable::Param class to learn more about
      # block editing the parameters.
      #
      # Once parameters have been added using the +add_param+ method, clients
      # can set and get those parameters from any newly created executable instance.
      #
      # Parameters will be sent to the commandline executable in the order they are
      # added using +add_param+.
      #
      def add_param(name, type, options=nil) # :yields: Sprout::Executable::Param
        if(block_given?)
          raise Sprout::Errors::UsageError.new("[DEPRECATED] add_param no longer uses closures, you can provide the same values as a hash in the optional last argument.")
        end

        raise Sprout::Errors::UsageError.new "The first parameter (name:SymbolOrString) is required" if name.nil?
        raise Sprout::Errors::UsageError.new "The second parameter (type:Class) is required" if type.nil?

        options ||= {}
        options[:name] = name
        options[:type] = type

        class_declarations << options
        create_class_accessors name
      end
      
      def add_param_alias new_name, old_name
        create_class_accessors new_name, old_name
      end

      def class_declarations
        @class_declarations ||= []
      end

      def set name, value
        instance_accessors name, value
      end

      private

      def create_class_accessors name, real_name=nil
        real_name ||= name

        # define the setter:
        define_method("#{name.to_s}=") do |value|
          param_hash[real_name].value = value
        end

        # define the getter:
        define_method(name) do     
          param_hash[real_name].value
        end
      end

      def instance_accessors name, default
        define_method("#{name.to_s}=") do |value|
          param_hash[name] = value
        end

        define_method(name) do
          param_hash[name] ||= default
        end
      end

    end

    module InstanceMethods

      attr_reader :param_hash
      attr_reader :params
      attr_reader :name
      # attr_reader :preprocessor
      attr_reader :prerequisites

      def initialize
        super
        @appended_args  = nil
        @prepended_args = nil
        # @preprocessed_path = nil

        @param_hash     = {}
        @params         = []
        @prerequisites  = []
        initialize_parameters
      end

      def parse options
      end

      ##
      # Called from enclosing Rake::Task after
      # initialization and before any tasks are
      # executed.
      #
      # It is within this function that we can
      # define other, new Tasks and/or manipulate
      # our prerequisites.
      #
      def define
      end

      ##
      # Actually call the provided executable.
      #
      def execute *args
        exe = Sprout.load_executable executable, pkg_name, pkg_version
        Sprout.current_system.execute exe
      end

      # Create a string that represents this configured executable for shell execution
      def to_shell
        return @to_shell_proc.call(self) if(!@to_shell_proc.nil?)

        result = []
        result << @prepended_args unless @prepended_args.nil?
        params.each do |param|
          if(param.visible?)
            result << param.to_shell
          end
        end
        result << @appended_args unless @appended_args.nil?
        return result.join(' ')
      end

      ##
      # Called by Parameters like :path and :paths
      #
      def default_file_expression
        @default_file_expression ||= Sprout::Executable::DEFAULT_FILE_EXPRESSION
      end

      ##
      # The default RubyGem that we will use when requesting our executable.
      #
      # Classes that include the Executable can set the default value for this property
      # at the class level with:
      #
      #     set :pkg_name, 'sprout-sometoolname'
      #
      # But that value can be overridden on each instance like:
      #
      #     executable = SomeToolTask.new
      #     executable.pkg_name = 'sprout-othertoolname'
      #
      # This parameter is required - either from the including class or instance
      # configuration.
      #
      attr_accessor :pkg_name

      ##
      # The default RubyGem version that we will use when requesting our executable.
      #
      # Classes that include the Task can set the default value for this property
      # at the class level with:
      #
      #     set :pkg_version, '>= 1.0.3'
      #
      # But that value can be overriden on each instance like:
      #
      #     executable = SomeToolTask.new
      #     too.pkg_version = '>= 2.0.0'
      #
      # This parameter is required - either from the including class or instance
      # configuration.
      #
      attr_accessor :pkg_version

      ##
      # The default Sprout executable that we will use for this executable.
      #
      # Classes that include the Task can set the default value for this property
      # at the class level with:
      #
      #     set :executable, :mxmlc
      #
      # But that value can be overriden on each instance like:
      #
      #     executable = SomeToolTask.new
      #     too.executable :compc
      #
      # This parameter is required - either from the including class or instance
      # configuration.
      #
      attr_accessor :executable

      private

      def initialize_parameters
        self.class.class_declarations.each do |declaration|
          initialize_parameter declaration
        end
      end

      def initialize_parameter declaration
        name    = declaration[:name]
        type    = declaration[:type]

        name_s = name.to_s

        # First ensure the named accessor doesn't yet exist...
        if(parameter_hash_includes? name)
          raise Sprout::Errors::ToolError.new("ToolTask.add_param called with existing parameter name: #{name_s}")
        end

        create_parameter declaration
      end

      def create_parameter declaration
        param = declaration[:type].new 
        param.belongs_to = self
          
        begin
          declaration.each_pair do |key, value|
            param.send "#{key}=", value
          end
        rescue ArgumentError
          raise Sprout::Errors::UsageError.new "Unexpected parameter option encountered with: #{key} and value: #{value}"
        end

        raise Sprout::Errors::UsageError.new "Parameter name is required" if(param.name.nil?)

        param_hash[param.name.to_sym] = param
        params << param
      end

      def parameter_hash_includes? name
        param_hash.has_key? name.to_sym
      end

      def validate
        params.each do |param|
          param.validate
        end
      end
    end

  end
end

