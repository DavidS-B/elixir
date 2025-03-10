defmodule Logger do
  @moduledoc ~S"""
  A logger for Elixir applications.

  It includes many features:

    * Provides debug, info, warn, and error levels.

    * Supports multiple backends which are automatically
      supervised when plugged into `Logger`.

    * Formats and truncates messages on the client
      to avoid clogging `Logger` backends.

    * Alternates between sync and async modes to remain
      performant when required but also apply backpressure
      when under stress.

    * Integrates with Erlang's [`:logger`](`:logger`)
      to convert terms to Elixir syntax.

    * Allows overriding the logging level for a specific module,
      application or process.

  Logging is useful for tracking when an event of interest happens in your
  system. For example, it may be helpful to log whenever a user is deleted.

      def delete_user(user) do
        Logger.info("Deleting user from the system: #{inspect(user)}")
        # ...
      end

  The `Logger.info/2` macro emits the provided message at the `:info`
  level. Note the arguments given to `info/2` will only be evaluated
  if a message is logged. For instance, if the Logger level is
  set to `:warning`, `:info` messages are never logged and therefore
  the arguments given above won't even be executed.

  There are additional macros for other levels.

  Logger also allows log commands to be removed altogether via the
  `:compile_time_purge_matching` option (see below).

  For dynamically logging messages, see `bare_log/3`. But note that
  `bare_log/3` always evaluates its arguments (unless the argument
  is an anonymous function).

  ## Levels

  The supported levels, ordered by importance, are:

    * `:emergency` - when system is unusable, panics
    * `:alert` - for alerts, actions that must be taken immediately,
      ex. corrupted database
    * `:critical` - for critical conditions
    * `:error` - for errors
    * `:warning` - for warnings
    * `:notice` - for normal, but significant, messages
    * `:info` - for information of any kind
    * `:debug` - for debug-related messages

  For example, `:info` takes precedence over `:debug`. If your log
  level is set to `:info`, then all `:info`, `:notice` and above will
  be passed to backends. If your log level is set to `:alert`, only
  `:alert` and `:emergency` will be printed.

  ## Message

  Logger can be used for logging both unstructured and structured data.

  Unstructured data is a string or a list of strings:

      Logger.info("hello world!")
      Logger.info(["hello ", "world!"])

  Structured data, also known as reports, are keyword lists and maps:

      Logger.info([new_user: user.id, account_type: :admin])
      Logger.info(%{new_user: user.id, account_type: :admin})

  Log functions also accept a zero-arity anonymous function as a message:

      Logger.info(fn -> "hello world!" end)

  The anonymous function can return a message or a tuple containing
  the message and additional metadata (to be described in the next
  section).

  In all cases, the arguments given to the `Logger` macros are only
  evaluated if required by the current log level. The exception is
  the `bare_log/3` function, which is the raw mechanism for logging.

  ## Metadata

  Whenever a message is logged, additional information can be given
  via metadata. Each log operation, such as `Logger.info/2`, allows
  metadata to be given as an argument.

  Furthermore, metadata can be set per process with `Logger.metadata/1`.

  Some metadata, however, is always added automatically by Logger
  whenever possible. Those are:

    * `:application` - the current application

    * `:mfa` - the current module, function and arity

    * `:file` - the current file

    * `:line` - the current line

    * `:pid` - the current process identifier

    * `:initial_call` - the initial call that started the process

    * `:registered_name` - the process registered name as an atom

    * `:domain` - a list of domains for the logged message. For example,
      all Elixir reports default to `[:elixir]`. Erlang reports may start
      with `[:otp]` or `[:sasl]`

    * `:crash_reason` - a two-element tuple with the throw/error/exit reason
      as first argument and the stacktrace as second. A throw will always be
      `{:nocatch, term}`. An error is always an `Exception` struct. All other
      entries are exits. The console backend ignores this metadata by default
      but it can be useful to other backends, such as the ones that report
      errors to third-party services

  Note that all metadata is optional and may not always be available.
  The `:mfa`, `:file`, `:line`, and similar metadata are automatically
  included when using `Logger` macros. `Logger.bare_log/3` does not include
  any metadata beyond the `:pid` by default. Other metadata, such as
  `:crash_reason`, `:initial_call`, and `:registered_name` are available
  only inside behaviours such as GenServer, Supervisor, and others.

  For example, you might wish to include a custom `:error_code` metadata in
  your logs:

      Logger.error("We have a problem", [error_code: :pc_load_letter])

  You might need to configure your logger backends to handle those metadata
  values. For the default `:console` backend there's an example in
  `Logger.Backends.Console`.

  ## Configuration

  `Logger` supports a wide range of configurations.

  This configuration is split in three categories:

    * Application configuration - must be set before the `:logger`
      application is started

    * Runtime configuration - can be set before the `:logger`
      application is started, but may be changed during runtime

    * Erlang configuration - options that handle integration with
      Erlang's logging facilities

  ### Application configuration

  The following configuration must be set via config files (such as
  `config/config.exs`) before the `:logger` application is started.

    * `:backends` - the backends to be used. Defaults to `[:console]`.
      See the "Backends" section for more information.

    * `:compile_time_application` - sets the `:application` metadata value
      to the configured value at compilation time. This configuration is
      automatically set by Mix and made available as metadata when logging.

    * `:compile_time_purge_matching` - purges *at compilation time* all calls
      that match the given conditions. This means that `Logger` calls with
      level lower than this option will be completely removed at compile time,
      accruing no overhead at runtime. This configuration expects a list of
      keyword lists. Each keyword list contains a metadata key and the matching
      value that should be purged. Some special keys are supported:

        * `:level_lower_than` - purges all messages with a lower logger level
        * `:module` - purges all messages with the matching module
        * `:function` - purges all messages with the "function/arity"

      Remember that if you want to purge log calls from a dependency, the
      dependency must be recompiled.

    * `:start_options` - passes start options to Logger's main process, such
      as `:spawn_opt` and `:hibernate_after`. All options in `t:GenServer.option/0`
      are accepted, except `:name`.

  For example, to configure the `:backends` and purge all calls that happen
  at compile time with level lower than `:info` in a `config/config.exs` file:

      config :logger,
        backends: [:console],
        compile_time_purge_matching: [
          [level_lower_than: :info]
        ]

  If you want to purge all log calls from an application named `:foo` and only
  keep errors from `Bar.foo/3`, you can set up two different matches:

      config :logger,
        compile_time_purge_matching: [
          [application: :foo],
          [module: Bar, function: "foo/3", level_lower_than: :error]
        ]

  ### Runtime Configuration

  All configuration below can be set via config files (such as
  `config/config.exs`) but also changed dynamically during runtime via
  `Logger.configure/1`.

    * `:level` - the logging level. Attempting to log any message
      with severity less than the configured level will simply
      cause the message to be ignored. Keep in mind that each backend
      may have its specific level, too. In addition to levels mentioned
      above it also supports 2 "meta-levels":

        - `:all` - all messages will be logged, conceptually identical to
          `:debug`
        - `:none` - no messages will be logged at all

    * `:utc_log` - when `true`, uses UTC in logs. By default it uses
      local time (i.e., it defaults to `false`).

    * `:truncate` - the maximum message size to be logged (in bytes).
      Defaults to 8192 bytes. Note this configuration is approximate.
      Truncated messages will have `" (truncated)"` at the end.
      The atom `:infinity` can be passed to disable this behavior.

    * `:sync_threshold` - if the `Logger` manager has more than
      `:sync_threshold` messages in its queue, `Logger` will change
      to *sync mode*, to apply backpressure to the clients.
      `Logger` will return to *async mode* once the number of messages
      in the queue is reduced to one below the `sync_threshold`.
      Defaults to 20 messages. `:sync_threshold` can be set to `0` to
      force *sync mode*.

    * `:discard_threshold` - if the `Logger` manager has more than
      `:discard_threshold` messages in its queue, `Logger` will change
      to *discard mode* and messages will be discarded directly in the
      clients. `Logger` will return to *sync mode* once the number of
      messages in the queue is reduced to one below the `discard_threshold`.
      Defaults to 500 messages.

    * `:discard_threshold_periodic_check` - a periodic check that
      checks and reports if logger is discarding messages. It logs a warning
      message whenever the system is (or continues) in discard mode and
      it logs a warning message whenever if the system was discarding messages
      but stopped doing so after the previous check. By default it runs
      every `30_000` milliseconds.

    * `:translator_inspect_opts` - when translating OTP reports and
      errors, the last message and state must be inspected in the
      error reports. This configuration allow developers to change
      how much and how the data should be inspected.

  For example, to configure the `:level` and `:truncate` options in a
  `config/config.exs` file:

      config :logger,
        level: :warning,
        truncate: 4096

  ### Erlang/OTP integration

  From Elixir v1.10, Elixir's Logger is fully integrated with Erlang's
  logger. They share the same `Logger.level/0`, any metadata set with
  `Logger.metadata/1` applies to both, and so on.

  Elixir also supports formatting Erlang reports using Elixir syntax.
  This can be controlled with two configurations:

    * `:handle_otp_reports` - redirects OTP reports to `Logger` so
      they are formatted in Elixir terms. This effectively disables
      Erlang standard logger. Defaults to `true`.

    * `:handle_sasl_reports` - redirects supervisor, crash and
      progress reports to `Logger` so they are formatted in Elixir
      terms. Your application must guarantee `:sasl` is started before
      `:logger`. This means you may see some initial reports written
      in Erlang syntax until the Logger application kicks in.
      Defaults to `false`. This option only has an effect if
      `:handle_otp_reports` is true.

  For example, to configure `Logger` to redirect all Erlang messages using a
  `config/config.exs` file:

      config :logger,
        handle_otp_reports: true,
        handle_sasl_reports: true

  Furthermore, `Logger` allows messages sent by Erlang to be translated
  into an Elixir format via translators. Translators can be added at any
  time with the `add_translator/1` and `remove_translator/1` APIs. Check
  `Logger.Translator` for more information.

  ## Backends

  `Logger` supports different backends where log messages are written to.

  The available backends by default are:

    * `:console` - logs messages to the console (enabled by default).
      `:console` is simply a shortcut for `Logger.Backends.Console`
      (see its documentation for more information)

  Developers may also implement their own backends, an option that
  is explored in more detail below.

  The initial backends are loaded via the `:backends` configuration,
  which must be set before the `:logger` application is started.
  However, by the time the Logger application starts, the code for your
  own and third-party backends may not yet be available. For this reason,
  it is preferred to add and remove backends via `add_backend/2` and
  `remove_backend/2` functions. This is often done in your
  `c:Application.start/2` callback:

      @impl true
      def start(_type, _args) do
        Logger.add_backend(MyCustomBackend)

  The backend can be configured either on the `add_backend/2` call:

      @impl true
      def start(_type, _args) do
        Logger.add_backend(MyCustomBackend, some_config: ...)

  Or in your config files:

      config :logger, MyCustomBackend,
        some_config: ...

  ### Elixir custom backends

  Any developer can create their own `Logger` backend. Since `Logger`
  is an event manager powered by `:gen_event`, writing a new backend
  is a matter of creating an event handler, as described in the
  [`:gen_event`](`:gen_event`) documentation.

  From now on, we will be using the term "event handler" to refer
  to your custom backend, as we head into implementation details.

  Once the `:logger` application starts, it installs all event handlers
  listed under the `:backends` configuration into the `Logger` event
  manager. The event manager and all added event handlers are automatically
  supervised by `Logger`.

  Note that if a backend fails to start by returning `{:error, :ignore}`
  from its `init/1` callback, then it's not added to the backends but
  nothing fails. If a backend fails to start by returning `{:error, reason}`
  from its `init/1` callback, the `:logger` application will fail to start.

  Once initialized, the handler should be designed to handle the
  following events:

    * `{level, group_leader, {Logger, message, timestamp, metadata}}` where:
      * `level` is one of `:debug`, `:info`, `:warn`, or `:error`, as previously
        described (for compatibility with pre 1.10 backends the `:notice` will
        be translated to `:info` and all messages above `:error` will be translated
        to `:error`)
      * `group_leader` is the group leader of the process which logged the message
      * `{Logger, message, timestamp, metadata}` is a tuple containing information
        about the logged message:
        * the first element is always the atom `Logger`
        * `message` is the actual message (as chardata)
        * `timestamp` is the timestamp for when the message was logged, as a
          `{{year, month, day}, {hour, minute, second, millisecond}}` tuple
        * `metadata` is a keyword list of metadata used when logging the message

    * `:flush`

  It is recommended that handlers ignore messages where the group
  leader is in a different node than the one where the handler is
  installed. For example:

      def handle_event({_level, gl, {Logger, _, _, _}}, state)
          when node(gl) != node() do
        {:ok, state}
      end

  In the case of the event `:flush` handlers should flush any pending
  data. This event is triggered by `Logger.flush/0`.

  Furthermore, backends can be configured via the `configure_backend/2`
  function which requires event handlers to handle calls of the
  following format:

      {:configure, options}

  where `options` is a keyword list. The result of the call is the result
  returned by `configure_backend/2`. The recommended return value for
  successful configuration is `:ok`. For example:

      def handle_call({:configure, options}, state) do
        new_state = reconfigure_state(state, options)
        {:ok, :ok, new_state}
      end

  It is recommended that backends support at least the following configuration
  options:

    * `:level` - the logging level for that backend
    * `:format` - the logging format for that backend
    * `:metadata` - the metadata to include in that backend

  Check the `Logger.Backends.Console` implementation in Elixir's codebase
  for examples on how to handle the recommendations in this section and
  how to process the existing options.

  ### Erlang/OTP handlers

  While Elixir Logger provides backends, Erlang/OTP logger provides handlers.
  They represent the same concept: the ability to integrate into the logging
  system to handle each logged message/event.

  However, implementation-wise, they have the following differences:

    * Elixir backends run in a separate process which comes with overload
      protection. However, because this process is a single GenEvent, any
      long running action should be avoided, as it can lead to bottlenecks
      in the system

    * Erlang handlers run in the same process as the process logging the
      message/event. This gives developers more flexibility but they should
      avoid performing any long running action in such handlers, as it may
      slow down the action being executed considerably. At the moment, there
      is no built-in overload protection for Erlang handlers, so it is your
      responsibility to implement it

  The good news is that developers can use third-party implementations of
  both Elixir backends and Erlang handlers. We have already covered Elixir
  backends, so let's see how to add Erlang/OTP handlers.

  Erlang/OTP handlers must be listed under your own application:

      config :my_app, :logger, [
        {:handler, :name_of_the_handler, ACustomHandler, configuration = %{}}
      ]

  And then, explicitly attached in your `c:Application.start/2` callback:

      :logger.add_handlers(:my_app)

  Note we do not recommend configuring Erlang/OTP's logger directly under
  the `:kernel` application in your `config/config.exs`, like this:

      # Not recommended:
      config :kernel, :logger, ...

  This is because by the time Elixir starts, Erlang's kernel has already
  been started, which means the configuration above would have no effect.
  """

  @type level ::
          :emergency | :alert | :critical | :error | :warning | :warn | :notice | :info | :debug
  @type backend :: :gen_event.handler()
  @type report :: map() | keyword()
  @type message :: :unicode.chardata() | String.Chars.t() | report()
  @type metadata :: keyword()
  @levels [:emergency, :alert, :critical, :error, :warning, :notice, :info, :debug]

  @metadata :logger_level
  @compile {:inline, enabled?: 1}

  @doc """
  Alters the current process metadata according to the given keyword list.

  This function will merge the given keyword list into the existing metadata,
  with the exception of setting a key to `nil`, which will remove that key
  from the metadata.

  Note not all keys can be set as metadata. The metadata automatically added
  by Logger, as declared in the module documentation, will always override
  custom one.
  """
  @spec metadata(metadata) :: :ok
  def metadata(keyword) do
    case :logger.get_process_metadata() do
      :undefined ->
        reset_metadata(keyword)

      map when is_map(map) ->
        metadata =
          Enum.reduce(keyword, map, fn
            {k, nil}, acc -> Map.delete(acc, k)
            {k, v}, acc -> Map.put(acc, k, v)
          end)

        :ok = :logger.set_process_metadata(metadata)
    end
  end

  @doc """
  Reads the current process metadata.
  """
  @spec metadata() :: metadata
  def metadata() do
    case :logger.get_process_metadata() do
      :undefined -> []
      map when is_map(map) -> Map.to_list(map)
    end
  end

  @doc """
  Resets the current process metadata to the given keyword list.
  """
  @spec reset_metadata(metadata) :: :ok
  def reset_metadata(keyword \\ []) do
    :ok = :logger.set_process_metadata(filter_out_nils(keyword))
  end

  defp filter_out_nils(keyword) do
    for {_k, v} = elem <- keyword, v != nil, into: %{}, do: elem
  end

  @doc """
  Enables logging for the current process.

  Currently the only accepted PID is `self()`.

  Equivalent of:

      delete_process_level(pid)
  """
  # TODO: Deprecate me on v1.18
  @doc deprecated: "Use Logger.delete_process_level(pid) instead"
  @spec enable(pid) :: :ok
  def enable(pid) when pid == self() do
    delete_process_level(pid)
  end

  @doc """
  Disables logging for the current process.

  Currently the only accepted PID is `self()`.

  Equivalent of:

      put_process_level(pid, :none)
  """
  # TODO: Deprecate me on v1.18
  @doc deprecated: "Use Logger.put_process_level(pid, :none) instead"
  @spec disable(pid) :: :ok
  def disable(pid) when pid == self() do
    put_process_level(pid, :none)
  end

  @doc """
  Returns whether the logging is enabled for a given process.

  Currently the only accepted PID is `self()`.
  """
  # TODO: Deprecate me on v1.18
  @doc deprecated: "Use Logger.get_process_level(pid) instead"
  @spec enabled?(pid) :: boolean
  def enabled?(pid) when pid == self() do
    get_process_level(pid) != :none
  end

  @doc """
  Retrieves the `Logger` level.

  The `Logger` level can be changed via `configure/1`.
  """
  @spec level() :: level()
  def level() do
    %{level: level} = :logger.get_primary_config()

    level
  end

  @doc """
  Compares log levels.

  Receives two log levels and compares the `left` level
  against the `right` level and returns:

    * `:lt` if `left` is less than `right`
    * `:eq` if `left` and `right` are equal
    * `:gt` if `left` is greater than `right`

  ## Examples

      iex> Logger.compare_levels(:debug, :warning)
      :lt
      iex> Logger.compare_levels(:error, :info)
      :gt

  """
  @spec compare_levels(level, level) :: :lt | :eq | :gt
  def compare_levels(left, right) do
    :logger.compare_levels(
      Logger.Handler.elixir_level_to_erlang_level(left),
      Logger.Handler.elixir_level_to_erlang_level(right)
    )
  end

  @doc """
  Configures the logger.

  See the "Runtime Configuration" section in the `Logger` module
  documentation for the available options. The changes done here
  are automatically persisted to the `:logger` application
  environment.
  """
  @valid_options [
    :compile_time_application,
    :compile_time_purge_level,
    :compile_time_purge_matching,
    :sync_threshold,
    :truncate,
    :level,
    :utc_log,
    :discard_threshold,
    :translator_inspect_opts
  ]
  @spec configure(keyword) :: :ok
  def configure(options) do
    options = Keyword.take(options, @valid_options)

    # We serialize the writes
    Logger.Config.configure(options)

    # Then we can read from the writes
    :ok = :logger.update_handler_config(Logger, :config, :refresh)
  end

  @doc """
  Flushes the logger.

  This guarantees all messages sent to `Logger` prior to this call will
  be processed. This is useful for testing and it should not be called
  in production code.
  """
  @spec flush :: :ok
  def flush do
    :gen_event.sync_notify(Logger, :flush)
  end

  @doc """
  Puts logging level for given module.

  This will take priority over the primary level set, so it can be
  used to increase or decrease verbosity of some parts of the project.

  ## Example

      defmodule Foo do
        require Logger

        def log, do: Logger.debug("foo")
      end

      Logger.configure(level: :error)
      Logger.put_module_level(Foo, :all)

      Foo.log()
      # This will print the message even if global level is :error

  """
  @doc since: "1.11.0"
  @spec put_module_level(module() | [module()], level() | :all | :none) :: :ok | {:error, term()}
  defdelegate put_module_level(mod, level), to: :logger, as: :set_module_level

  @doc """
  Gets logging level for given module.

  The returned value will be the effective value used. If no value
  was set for a given module, then it will not be present in
  the returned list.
  """
  @doc since: "1.11.0"
  @spec get_module_level(module() | [module()]) :: [{module(), level() | :all | :none}]
  defdelegate get_module_level(mod), to: :logger

  @doc """
  Resets the logging level for a given module to the primary level.
  """
  @doc since: "1.11.0"
  @spec delete_module_level(module() | [module()]) :: :ok
  defdelegate delete_module_level(module), to: :logger, as: :unset_module_level

  @doc """
  Resets the logging level for all modules to the primary level.
  """
  @doc since: "1.11.0"
  @spec delete_all_module_levels() :: :ok
  defdelegate delete_all_module_levels(), to: :logger, as: :unset_module_level

  @doc """
  Puts logging level for modules in a given application.

  This will take priority over the primary level set, so it can be
  used to increase or decrease verbosity of some parts of the project.

  Equivalent of:

      appname |> Application.spec(:modules) |> Logger.put_module_level(level)
  """
  @doc since: "1.13.0"
  @spec put_application_level(atom(), level() | :all | :none) :: :ok | {:error, :not_loaded}
  defdelegate put_application_level(appname, level), to: :logger, as: :set_application_level

  @doc """
  Resets logging level for all modules in the given application to the primary level.

  Equivalent of:

      appname |> Application.spec(:modules) |> Logger.delete_module_level()
  """
  @doc since: "1.13.0"
  @spec delete_application_level(application) :: :ok | {:error, {:not_loaded, application}}
        when application: atom()
  defdelegate delete_application_level(appname), to: :logger, as: :unset_application_level

  @doc """
  Puts logging level for the current process.

  Currently the only accepted PID is `self()`.

  This will take priority over the primary level set, so it can be
  used to increase or decrease verbosity of some parts of the running system.
  """
  @spec put_process_level(pid(), level() | :all | :none) :: :ok
  def put_process_level(pid, level) when pid == self() do
    Process.put(@metadata, Logger.Handler.elixir_level_to_erlang_level(level))
    :ok
  end

  @doc """
  Gets logging level for the current process.

  Currently the only accepted PID is `self()`.

  The returned value will be the effective value used. If no value
  was set for a given process, then `nil` is returned.
  """
  @spec get_process_level(pid) :: level() | :all | :none | nil
  def get_process_level(pid) when pid == self() do
    Process.get(@metadata, nil)
  end

  @doc """
  Resets logging level for the current process to the primary level.

  Currently the only accepted PID is `self()`.
  """
  @spec delete_process_level(pid()) :: :ok
  def delete_process_level(pid) when pid == self() do
    Process.delete(@metadata)
    :ok
  end

  @doc """
  Adds a new backend.

  Adding a backend calls the `init/1` function in that backend
  with the name of the backend as its argument. For example,
  calling

      Logger.add_backend(MyBackend)

  will call `MyBackend.init(MyBackend)` to initialize the new
  backend. If the backend's `init/1` callback returns `{:ok, _}`,
  then this function returns `{:ok, pid}`. If the handler returns
  `{:error, :ignore}` from `init/1`, this function still returns
  `{:ok, pid}` but the handler is not started. If the handler
  returns `{:error, reason}` from `init/1`, this function returns
  `{:error, {reason, info}}` where `info` is more information on
  the backend that failed to start.

  Backends added by this function are not persisted. Therefore
  if the Logger application or supervision tree is restarted,
  the backend won't be available. If you need this guarantee,
  then configure the backend via the application environment:

      config :logger, :backends, [MyBackend]

  ## Options

    * `:flush` - when `true`, guarantees all messages currently sent
      to `Logger` are processed before the backend is added

  ## Examples

      {:ok, _pid} = Logger.add_backend(MyBackend, flush: true)

  """
  @spec add_backend(backend, keyword) :: Supervisor.on_start_child()
  def add_backend(backend, opts \\ []) do
    _ = if opts[:flush], do: flush()

    case Logger.BackendSupervisor.watch(backend) do
      {:ok, _} = ok ->
        ok

      {:error, {:already_started, _pid}} ->
        {:error, :already_present}

      {:error, _} = error ->
        error
    end
  end

  @doc """
  Removes a backend.

  ## Options

    * `:flush` - when `true`, guarantees all messages currently sent
      to `Logger` are processed before the backend is removed

  """
  @spec remove_backend(backend, keyword) :: :ok | {:error, term}
  def remove_backend(backend, opts \\ []) do
    _ = if opts[:flush], do: flush()
    Logger.BackendSupervisor.unwatch(backend)
  end

  @doc """
  Adds a new translator.
  """
  @spec add_translator({module, function :: atom}) :: :ok
  def add_translator({mod, fun} = translator) when is_atom(mod) and is_atom(fun) do
    update_translators(&[translator | List.delete(&1, translator)])
  end

  @doc """
  Removes a translator.
  """
  @spec remove_translator({module, function :: atom}) :: :ok
  def remove_translator({mod, fun} = translator) when is_atom(mod) and is_atom(fun) do
    update_translators(&List.delete(&1, translator))
  end

  defp update_translators(updater) do
    :elixir_config.serial(fn ->
      with %{filters: filters} <- :logger.get_primary_config(),
           {{_, {fun, config}}, filters} <- List.keytake(filters, :logger_translator, 0) do
        config = update_in(config.translators, updater)
        :ok = :logger.set_primary_config(:filters, filters ++ [logger_translator: {fun, config}])
      end
    end)

    :ok
  end

  @doc """
  Configures the given backend.

  The backend needs to be started and running in order to
  be configured at runtime.
  """
  @spec configure_backend(backend, keyword) :: term
  def configure_backend(backend, options) when is_list(options) do
    backend = Logger.BackendSupervisor.translate_backend(backend)
    :gen_event.call(Logger, backend, {:configure, options})
  end

  @doc """
  Logs a message dynamically.

  Opposite to `log/3`, `debug/2`, `info/2`, and friends, the arguments
  given to `bare_log/3` are always evaluated. However, you can pass
  anonymous functions to `bare_log/3` and they will only be evaluated
  if there is something to be logged.
  """
  @spec bare_log(level, message | (-> message | {message, keyword}), keyword) :: :ok
  def bare_log(level, message_or_fun, metadata \\ []) do
    case __should_log__(level, nil) do
      nil -> :ok
      level -> __do_log__(level, message_or_fun, %{}, Map.new(metadata))
    end
  end

  @doc false
  def __should_log__(level, module) do
    level = Logger.Handler.elixir_level_to_erlang_level(level)

    if :logger.allow(level, module) do
      level
    end
  end

  defguardp is_msg(msg) when is_binary(msg) or is_list(msg) or is_map(msg)

  @doc false
  def __do_log__(level, fun, location, metadata)
      when is_function(fun, 0) and is_map(location) and is_map(metadata) do
    case fun.() do
      {msg, meta} ->
        __do_log__(level, msg, location, Enum.into(meta, metadata))

      msg ->
        __do_log__(level, msg, location, metadata)
    end
  end

  def __do_log__(level, msg, location, metadata)
      when level in @levels and is_map(location) and is_map(metadata) do
    if is_msg(msg) do
      :logger.macro_log(location, level, msg, add_elixir_domain(metadata))
    else
      IO.warn(
        "passing #{inspect(msg)} to Logger is deprecated, expected a map, a keyword list, " <>
          "a string, a list of strings, or a zero-arity anonymous function"
      )

      :logger.macro_log(location, level, to_string(msg), add_elixir_domain(metadata))
    end
  end

  defp add_elixir_domain(%{domain: domain} = metadata) when is_list(domain) do
    %{metadata | domain: [:elixir | domain]}
  end

  defp add_elixir_domain(metadata), do: Map.put(metadata, :domain, [:elixir])

  translations = %{
    emergency: :error,
    alert: :error,
    critical: :error,
    notice: :info
  }

  for level <- @levels do
    report = [something: :reported, this: level]

    extra =
      if translation = translations[level] do
        """


        This is reported as \"#{translation}\" in Elixir's
        logger backends for backwards compatibility reasons.

        """
      end

    @doc """
    Logs a #{level} message.

    Returns `:ok`.#{extra}

    ## Examples

    Logging a message (string or iodata):

        Logger.#{level}("this is a #{level} message")

    Report message (maps or keywords):

        # as keyword list
        Logger.#{level}(#{inspect(report)})

        # as map
        Logger.#{level}(#{inspect(Map.new(report))})

    """
    @doc since: "1.11.0"
    defmacro unquote(level)(message_or_fun, metadata \\ []) do
      maybe_log(unquote(level), message_or_fun, metadata, __CALLER__)
    end
  end

  @deprecated "Use Logger.warning/2 instead"
  defmacro warn(message_or_fun, metadata \\ []) do
    maybe_log(:warning, message_or_fun, metadata, __CALLER__)
  end

  @doc """
  Logs a message with the given `level`.

  Returns `:ok`.

  The macros `debug/2`, `info/2`, `notice/2`, `warning/2`,
  `error/2`, `critical/2`, `alert/2`, and `emergency/2` are
  preferred over this macro as they can automatically eliminate
  the call to `Logger` altogether at compile time if desired
  (see the documentation for the `Logger` module).
  """
  defmacro log(level, message_or_fun, metadata \\ []) do
    macro_log(level, message_or_fun, metadata, __CALLER__)
  end

  defp macro_log(level, data, metadata, caller) do
    {maybe_application, file} = compile_time_application_and_file(caller)

    location =
      case caller do
        %{module: module, function: {fun, arity}, line: line} ->
          %{mfa: {module, fun, arity}, file: file, line: line}

        _ ->
          %{}
      end

    {compile_metadata, quoted_metadata} =
      if Keyword.keyword?(metadata) do
        metadata = Keyword.merge(maybe_application, metadata)
        {Map.merge(location, Map.new(metadata)), escape_metadata(metadata)}
      else
        {%{},
         quote do
           Enum.into(unquote(metadata), unquote(escape_metadata(maybe_application)))
         end}
      end

    compile_level = if is_atom(level), do: level, else: :error

    if compile_time_purge_matching?(compile_level, compile_metadata) do
      no_log(data, quoted_metadata)
    else
      quote do
        case Logger.__should_log__(unquote(level), __MODULE__) do
          nil ->
            :ok

          level ->
            Logger.__do_log__(
              level,
              unquote(data),
              unquote(Macro.escape(location)),
              unquote(quoted_metadata)
            )
        end
      end
    end
  end

  defp escape_metadata(metadata) do
    {_, metadata} =
      Keyword.get_and_update(metadata, :mfa, fn
        nil -> :pop
        mfa -> {mfa, Macro.escape(mfa)}
      end)

    {:%{}, [], metadata}
  end

  defp compile_time_application_and_file(%{file: file}) do
    if app = Application.get_env(:logger, :compile_time_application) do
      {[application: app], file |> Path.relative_to_cwd() |> String.to_charlist()}
    else
      {[], String.to_charlist(file)}
    end
  end

  defp compile_time_purge_matching?(level, compile_metadata) do
    matching = Application.get_env(:logger, :compile_time_purge_matching, [])

    if not is_list(matching) do
      bad_compile_time_purge_matching!(matching)
    end

    Enum.any?(matching, fn filter ->
      if not is_list(filter) do
        bad_compile_time_purge_matching!(matching)
      end

      Enum.all?(filter, fn
        {:level_lower_than, min_level} ->
          compare_levels(level, min_level) == :lt

        {:module, module} ->
          match?({:ok, {^module, _, _}}, Map.fetch(compile_metadata, :mfa))

        {:function, func} ->
          case Map.fetch(compile_metadata, :mfa) do
            {:ok, {_, f, a}} -> "#{f}/#{a}" == func
            _ -> false
          end

        {k, v} when is_atom(k) ->
          Map.fetch(compile_metadata, k) == {:ok, v}

        _ ->
          bad_compile_time_purge_matching!(matching)
      end)
    end)
  end

  defp bad_compile_time_purge_matching!(matching) do
    raise "expected :compile_time_purge_matching to be a list of keyword lists, " <>
            "got: #{inspect(matching)}"
  end

  defp maybe_log(level, data, metadata, caller) do
    min_level =
      if env_level = Application.get_env(:logger, :compile_time_purge_level) do
        IO.warn(
          ":compile_time_purge_level option for the :logger application is deprecated, " <>
            "use :compile_time_purge_matching instead",
          Macro.Env.stacktrace(caller)
        )

        env_level
      else
        :debug
      end

    if compare_levels(level, min_level) != :lt do
      macro_log(level, data, metadata, caller)
    else
      no_log(data, metadata)
    end
  end

  defp no_log(data, metadata) do
    # We wrap the contents in an anonymous function
    # to avoid unused variable warnings.
    quote do
      _ = fn -> {unquote(data), unquote(metadata)} end
      :ok
    end
  end
end
