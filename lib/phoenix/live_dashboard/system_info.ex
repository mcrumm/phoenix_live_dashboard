defmodule Phoenix.LiveDashboard.SystemInfo do
  # Helpers for fetching and formatting system info.
  @moduledoc false

  # These structs are not loaded into remote nodes, but they can be used as structs
  # because they are expanded at compile-time
  defmodule ProcessDetails do
    @moduledoc false
    defstruct [:pid, :name_or_initial_call, :initial_call]
  end

  defmodule PortDetails do
    @moduledoc false
    defstruct [:port, :description]
  end

  def node_capabilities(node, requirements) do
    case :rpc.call(node, :code, :is_loaded, [__MODULE__]) do
      {:file, _} ->
        maybe_replace(node, fetch_capabilities(node, requirements), requirements)

      false ->
        load(node, requirements)

      {:error, reason} ->
        raise("Failed to load #{__MODULE__} on #{node}: #{inspect(reason)}")
    end
  end

  defp maybe_replace(node, capabilities, requirements) do
    if not capabilities.dashboard_running? and
         capabilities.system_info != __MODULE__.__info__(:md5) do
      load(node, requirements)
    else
      capabilities
    end
  end

  defp load(node, requirements) do
    {_module, binary, filename} = :code.get_object_code(__MODULE__)
    :rpc.call(node, :code, :load_binary, [__MODULE__, filename, binary])
    fetch_capabilities(node, requirements)
  end

  ## Fetchers

  def fetch_processes(node, search, sort_by, sort_dir, limit, prev_reductions \\ nil) do
    search = search && String.downcase(search)

    :rpc.call(node, __MODULE__, :processes_callback, [
      search,
      sort_by,
      sort_dir,
      limit,
      prev_reductions
    ])
  end

  def fetch_ets(node, search, sort_by, sort_dir, limit) do
    search = search && String.downcase(search)
    :rpc.call(node, __MODULE__, :ets_callback, [search, sort_by, sort_dir, limit])
  end

  def fetch_sockets(node, search, sort_by, sort_dir, limit) do
    search = search && String.downcase(search)
    :rpc.call(node, __MODULE__, :sockets_callback, [search, sort_by, sort_dir, limit])
  end

  def fetch_socket_info(port) do
    :rpc.call(node(port), __MODULE__, :socket_info_callback, [port])
  end

  def fetch_process_info(pid) do
    :rpc.call(node(pid), __MODULE__, :process_info_callback, [pid])
  end

  def fetch_ports(node, search, sort_by, sort_dir, limit) do
    search = search && String.downcase(search)
    :rpc.call(node, __MODULE__, :ports_callback, [search, sort_by, sort_dir, limit])
  end

  def fetch_applications(node, search, sort_by, sort_dir, limit) do
    :rpc.call(node, __MODULE__, :applications_info_callback, [search, sort_by, sort_dir, limit])
  end

  def fetch_port_info(port) do
    :rpc.call(node(port), __MODULE__, :port_info_callback, [port])
  end

  def fetch_ets_info(node, ref) do
    :rpc.call(node, __MODULE__, :ets_info_callback, [ref])
  end

  def fetch_system_info(node, keys, app) do
    :rpc.call(node, __MODULE__, :info_callback, [keys, app])
  end

  def fetch_system_usage(node) do
    :rpc.call(node, __MODULE__, :usage_callback, [])
  end

  def fetch_os_mon_info(node) do
    :rpc.call(node, __MODULE__, :os_mon_callback, [])
  end

  def fetch_capabilities(node, requirements) do
    :rpc.call(node, __MODULE__, :capabilities_callback, [requirements])
  end

  def fetch_app_tree(node, application) do
    :rpc.call(node, __MODULE__, :app_tree_callback, [application])
  end

  def fetch_memory_allocators(node, max_carrier_sizes) do
    :rpc.call(node, __MODULE__, :memory_allocators_callback, [max_carrier_sizes])
  end

  ## System callbacks

  @doc false
  def info_callback(keys, app) do
    %{
      system_info: %{
        banner: :erlang.system_info(:system_version),
        elixir_version: System.version(),
        phoenix_version: Application.spec(:phoenix, :vsn) || "None",
        app_version: Application.spec(app, :vsn) || "None",
        system_architecture: :erlang.system_info(:system_architecture)
      },
      system_limits: %{
        atoms: :erlang.system_info(:atom_limit),
        ports: :erlang.system_info(:port_limit),
        processes: :erlang.system_info(:process_limit)
      },
      system_usage: usage_callback(),
      environment: env_info_callback(keys)
    }
  end

  @doc false
  def usage_callback do
    %{
      atoms: :erlang.system_info(:atom_count),
      ports: :erlang.system_info(:port_count),
      processes: :erlang.system_info(:process_count),
      io: io(),
      uptime: :erlang.statistics(:wall_clock) |> elem(0),
      memory: memory(),
      total_run_queue: :erlang.statistics(:total_run_queue_lengths_all),
      cpu_run_queue: :erlang.statistics(:total_run_queue_lengths)
    }
  end

  @doc false
  def capabilities_callback(requirements) do
    %{
      system_info: __MODULE__.__info__(:md5),
      dashboard_running?: is_pid(Process.whereis(Phoenix.LiveDashboard.DynamicSupervisor)),
      applications: capabilities_callback_applications(requirements),
      modules: capabilities_callback_modules(requirements),
      processes: capabilities_callback_processes(requirements)
    }
  end

  defp capabilities_callback_applications(requirements) do
    for {:application, app} <- requirements, Application.get_application(app), do: app
  end

  defp capabilities_callback_modules(requirements) do
    for {:module, mod} <- requirements, Code.ensure_loaded?(mod), do: mod
  end

  defp capabilities_callback_processes(requirements) do
    for {:process, process} <- requirements, Process.whereis(process), do: process
  end

  defp io() do
    {{:input, input}, {:output, output}} = :erlang.statistics(:io)
    {input, output}
  end

  defp memory() do
    memory = :erlang.memory()
    total = memory[:total]
    process = memory[:processes]
    atom = memory[:atom]
    binary = memory[:binary]
    code = memory[:code]
    ets = memory[:ets]

    %{
      total: total,
      process: process,
      atom: atom,
      binary: binary,
      code: code,
      ets: ets,
      other: total - process - atom - binary - code - ets
    }
  end

  def memory_allocators_callback(old_max_carrier_sizes) do
    allocs = :erlang.system_info(:alloc_util_allocators)

    :erlang.system_info({:allocator_sizes, allocs})
    |> Enum.map(fn {type, allocator_sizes} ->
      {type, calc_allocator_sizes(allocator_sizes)}
    end)
    |> prepend_total()
    |> Enum.map(fn {type, {block, current_cs, max_cs}} ->
      %{
        name: type,
        block_size: block,
        carrier_size: current_cs,
        max_carrier_size: max_cs
      }
    end)
    |> calc_max_carrier_sizes(old_max_carrier_sizes)
  end

  defp calc_allocator_sizes(allocator_sizes) do
    Enum.reduce(allocator_sizes, {0, 0, 0}, fn instance_sizes, {block_size, current_cs, max_cs} ->
      {ins_block_size, ins_current_cs, ins_max_cs} = calc_instance_sizes(instance_sizes)
      {block_size + ins_block_size, current_cs + ins_current_cs, max_cs + ins_max_cs}
    end)
  end

  defp calc_instance_sizes({:instance, _, sizes}) do
    {block_size_1, current_cs_1, max_cs_1} = calc_block_and_carrier_sizes(sizes[:mbcs])
    {block_size_2, current_cs_2, max_cs_2} = calc_block_and_carrier_sizes(sizes[:sbcs])
    {block_size_1 + block_size_2, current_cs_1 + current_cs_2, max_cs_1 + max_cs_2}
  end

  defp calc_instance_sizes(_), do: {0, 0, 0}

  defp calc_block_and_carrier_sizes(sizes) when is_list(sizes) do
    block_size = List.keyfind(sizes, :blocks, 0) |> calc_block_size()
    {current, max} = List.keyfind(sizes, :carriers_size, 0) |> calc_carrier_size()
    {block_size, current, max}
  end

  defp calc_block_and_carrier_sizes(_), do: {0, 0, 0}

  defp calc_block_size({:blocks, [{_, [{:size, current, _, _}]}]}), do: current
  defp calc_block_size({:blocks, [{_, [{:size, current}]}]}), do: current
  defp calc_block_size(_), do: 0

  defp calc_carrier_size({:carriers_size, current, _local, max}), do: {current, max}
  defp calc_carrier_size({:carriers_size, int}) when is_integer(int), do: {int, 0}
  defp calc_carrier_size(_), do: {0, 0}

  defp prepend_total(allocator_sizes) do
    total =
      {:total,
       Enum.reduce(allocator_sizes, {0, 0, 0}, fn {_type, sizes}, acc ->
         {block_cs, current_cs, max_cs} = sizes
         {acc_block_cs, acc_current_cs, acc_max_cs} = acc
         {acc_block_cs + block_cs, acc_current_cs + current_cs, acc_max_cs + max_cs}
       end)}

    [total | allocator_sizes]
  end

  defp calc_max_carrier_sizes(allocators, old_max_carrier_sizes) do
    Enum.map_reduce(allocators, old_max_carrier_sizes || %{}, fn allocator, max_carrier_sizes ->
      %{name: name, carrier_size: current} = allocator
      max = Enum.max([old_max_carrier_sizes[name] || 0, current])
      {Map.put(allocator, :max_carrier_size, max), Map.put(max_carrier_sizes, name, max)}
    end)
  end

  ## Process Callbacks

  @processes_keys [
    :memory,
    :reductions,
    :message_queue_len,
    :current_function
  ]

  @doc false
  def processes_callback(search, sort_by, sort_dir, limit, prev_reductions) do
    multiplier = sort_dir_multiplier(sort_dir)
    constants = {prev_reductions, search, sort_by, multiplier, limit}
    reduce_processes(Process.list(), constants)
  end

  defp reduce_processes(pids, {prev_reductions, search, sort_by, multiplier, limit}) do
    reduce_processes(pids, {prev_reductions, search, sort_by, multiplier, limit}, {[], 0, %{}})
  end

  defp reduce_processes([], _, {processes, count, next_state}) do
    {processes |> Enum.map(&elem(&1, 1)) |> Enum.reverse(), count, next_state}
  end

  defp reduce_processes(
         [pid | pids],
         {prev_reductions, search, sort_by, multiplier, limit} = constants,
         {processes, count, next_state}
       ) do
    acc =
      if info = process_info(pid, prev_reductions[pid]) do
        sorter = info[sort_by] * multiplier * -1
        show_process? = show_process?(info, search)
        count = if show_process?, do: count + 1, else: count
        next_state = Map.put(next_state, info[:pid], info[:reductions])

        processes =
          case {count, limit, show_process?} do
            {_, _, false} -> processes
            {0, limit, _} when limit > 0 -> insert_sorted({sorter, info}, [])
            {count, limit, _} when count > limit -> tl(insert_sorted({sorter, info}, processes))
            {_, _, _} -> insert_sorted({sorter, info}, processes)
          end

        {processes, count, next_state}
      else
        {processes, count, next_state}
      end

    reduce_processes(pids, constants, acc)
  end

  defp insert_sorted({key, val}, []), do: [{key, val}]
  defp insert_sorted({key, val}, list), do: insert_sorted({key, val}, list, [])
  defp insert_sorted(nil, list, []), do: list
  defp insert_sorted(nil, list, [hd | tl]), do: insert_sorted(nil, [hd | list], tl)
  defp insert_sorted({key, val}, [], hd), do: insert_sorted(nil, [{key, val}], hd)

  defp insert_sorted({key, val}, [{low_key, _} | _] = list, hd) when key < low_key do
    insert_sorted(nil, [{key, val} | list], hd)
  end

  defp insert_sorted({key, val}, [{low_key, low_val} | tl], hd) when key >= low_key do
    insert_sorted({key, val}, tl, [{low_key, low_val} | hd])
  end

  defp process_info(pid, prev_reductions) do
    if info = Process.info(pid, @processes_keys) do
      diff = info[:reductions] - (prev_reductions || 0)

      details = to_process_details(pid)

      [
        pid: pid,
        name_or_initial_call: details.name_or_initial_call,
        reductions_diff: diff
      ] ++ info
    end
  end

  defp show_process?(_, nil) do
    true
  end

  defp show_process?(info, search) do
    pid = info[:pid] |> :erlang.pid_to_list() |> List.to_string()
    name_or_call = info[:name_or_initial_call] || ""
    pid =~ search or String.downcase(name_or_call) =~ search
  end

  @process_info_keys [
    :dictionary,
    :links,
    :monitors,
    :monitored_by,
    :registered_name,
    :current_function,
    :status,
    :message_queue_len,
    :trap_exit,
    :error_handler,
    :priority,
    :group_leader,
    :total_heap_size,
    :heap_size,
    :stack_size,
    :reductions,
    :garbage_collection,
    :suspending,
    :current_stacktrace
  ]

  def process_info_callback(pid) do
    case Process.info(pid, @process_info_keys) do
      nil ->
        :error

      info ->
        details = to_process_details(pid)

        {:ok,
         info
         |> Enum.map(&process_info_callback_key/1)
         |> Keyword.put(:initial_call, details.initial_call)}
    end
  end

  defp process_info_callback_key({:links, links}),
    do: {:links, Enum.map(links, &pid_or_port_details/1)}

  defp process_info_callback_key({:monitors, monitors}) do
    {:monitors,
     monitors
     |> Enum.map(fn {_label, pid_or_port} -> pid_or_port end)
     |> Enum.map(&pid_or_port_details/1)}
  end

  defp process_info_callback_key({:monitored_by, monitored_by}),
    do: {:monitored_by, Enum.map(monitored_by, &pid_or_port_details/1)}

  defp process_info_callback_key({:group_leader, group_leader}),
    do: {:group_leader, pid_or_port_details(group_leader)}

  defp process_info_callback_key({:dictionary, dictionary}) do
    {:ancestors,
     Keyword.get(dictionary, :"$ancestors", [])
     |> Enum.map(&pid_or_port_details/1)}
  end

  defp process_info_callback_key({key, value}), do: {key, value}

  ## Applications callbacks

  def applications_info_callback(search, sort_by, sort_dir, limit) do
    sorter = if sort_dir == :asc, do: &<=/2, else: &>=/2
    started_apps_set = started_apps_set()

    apps =
      for {name, desc, version} <- Application.loaded_applications(),
          description = List.to_string(desc),
          version = List.to_string(version),
          show_application?(name, description, version, search) do
        {state, tree?} =
          if name in started_apps_set,
            do: {:started, is_pid(:application_controller.get_master(name))},
            else: {:loaded, false}

        [name: name, description: description, version: version, state: state, tree?: tree?]
      end

    count = length(apps)
    apps = apps |> Enum.sort_by(&Keyword.fetch!(&1, sort_by), sorter) |> Enum.take(limit)
    {apps, count}
  end

  defp show_application?(_, _, _, nil) do
    true
  end

  defp show_application?(name, desc, version, search) do
    Atom.to_string(name) =~ search or String.downcase(desc) =~ search or version =~ search
  end

  defp started_apps_set() do
    Application.started_applications()
    |> Enum.map(fn {name, _, _} -> name end)
    |> MapSet.new()
  end

  def app_tree_callback(app) do
    case :application_controller.get_master(app) do
      :undefined ->
        :error

      master ->
        {child, _app} = :application_master.get_child(master)
        {children, seen} = sup_tree(child, %{master => true, child => true})
        {children, _seen} = links_tree(children, master, seen)

        case get_ancestor(child) do
          nil ->
            {{:master, master, []}, to_wrapped_node(:supervisor, child, children)}

          ancestor ->
            {{:master, master, []},
             [{{:ancestor, ancestor, []}, to_wrapped_node(:supervisor, child, children)}]}
        end
    end
  end

  defp get_ancestor(master) do
    {_, dictionary} = :erlang.process_info(master, :dictionary)

    case Keyword.get(dictionary, :"$ancestors") do
      [parent] -> parent
      _ -> nil
    end
  end

  defp sup_tree(pid, seen) do
    try do
      :supervisor.which_children(pid)
    catch
      _, _ -> {[], seen}
    else
      children ->
        children
        |> Enum.reverse()
        |> Enum.flat_map_reduce(seen, fn {_id, child, type, _modules}, seen ->
          if is_pid(child) do
            {children, seen} = if type == :worker, do: {[], seen}, else: sup_tree(child, seen)
            {[{type, child, children}], put_child(seen, child)}
          else
            {[], seen}
          end
        end)
    end
  end

  defp links_tree(nodes, master, seen) do
    Enum.flat_map_reduce(nodes, seen, fn {type, pid, children}, seen ->
      {children, seen} =
        if children == [], do: links_children(type, pid, master, seen), else: {children, seen}

      {children, seen} = links_tree(children, master, seen)
      {to_wrapped_node(type, pid, children), seen}
    end)
  end

  defp links_children(parent_type, pid, master, seen) do
    # If the parent type is a supervisor and we have no children,
    # then this may be a supervisor bridge, so we tag its children
    # as workers, otherwise they are links.
    type = if parent_type == :supervisor, do: :worker, else: :link

    case Process.info(pid, :links) do
      {:links, children} ->
        children
        |> Enum.reverse()
        |> Enum.flat_map_reduce(seen, fn child, seen ->
          if is_pid(child) and not has_child?(seen, child) and has_leader?(child, master) do
            {[{type, child, []}], put_child(seen, child)}
          else
            {[], seen}
          end
        end)

      _ ->
        {[], seen}
    end
  end

  defp to_wrapped_node(type, pid, children) do
    case Process.info(pid, :registered_name) do
      {:registered_name, registered_name} ->
        [{{type, pid, registered_name}, children}]

      _ ->
        []
    end
  end

  defp has_child?(seen, child), do: Map.has_key?(seen, child)
  defp put_child(seen, child), do: Map.put(seen, child, true)

  defp has_leader?(pid, gl),
    do: Process.info(pid, :group_leader) == {:group_leader, gl}

  ## Ports callbacks

  @inet_ports [~c"tcp_inet", ~c"udp_inet", ~c"sctp_inet"]

  @doc false
  def ports_callback(search, sort_by, sort_dir, limit) do
    multiplier = sort_dir_multiplier(sort_dir)

    ports =
      for port <- Port.list(), port_info = port_info(port), show_port?(port_info, search) do
        sorter = port_info[sort_by]
        sorter = if is_integer(sorter), do: sorter * multiplier, else: 0
        {sorter, port_info}
      end

    count = length(ports)
    ports = ports |> Enum.sort() |> Enum.take(limit) |> Enum.map(&elem(&1, 1))
    {ports, count}
  end

  @doc false
  def port_info_callback(port) do
    case Port.info(port) do
      [_ | _] = info ->
        {:ok,
         info
         |> Keyword.update!(:links, fn links -> Enum.map(links, &pid_or_port_details/1) end)
         |> Keyword.update!(:connected, &pid_or_port_details/1)}

      nil ->
        :error
    end
  end

  defp port_info(port) do
    info = Port.info(port)

    if info && info[:name] not in @inet_ports do
      [port: port] ++ info
    end
  end

  defp show_port?(_, nil) do
    true
  end

  defp show_port?(info, search) do
    port = info[:port] |> :erlang.port_to_list() |> List.to_string()
    port =~ search or String.downcase(List.to_string(info[:name])) =~ search
  end

  ## ETS callbacks

  def ets_callback(search, sort_by, sort_dir, limit) do
    multiplier = sort_dir_multiplier(sort_dir)

    tables =
      for ref <- :ets.all(), info = ets_info(ref), show_ets?(info, search) do
        sorter = info[sort_by] * multiplier
        {sorter, info}
      end

    count = length(tables)
    tables = tables |> Enum.sort() |> Enum.take(limit) |> Enum.map(&elem(&1, 1))
    {tables, count}
  end

  defp ets_info(ref) do
    case :ets.info(ref) do
      :undefined -> nil
      info -> [name: inspect(info[:name])] ++ Keyword.delete(info, :name)
    end
  end

  defp show_ets?(_, nil) do
    true
  end

  defp show_ets?(info, search) do
    String.downcase(info[:name]) =~ search
  end

  def ets_info_callback(ref) do
    case :ets.info(ref) do
      :undefined ->
        :error

      info ->
        {:ok,
         info
         |> Keyword.update!(:owner, &pid_or_port_details/1)
         |> Keyword.update!(:heir, fn
           :none -> nil
           heir -> pid_or_port_details(heir)
         end)}
    end
  end

  ## Socket callbacks

  def sockets_callback(search, sort_by, sort_dir, limit) do
    sorter = if sort_dir == :asc, do: &<=/2, else: &>=/2
    sockets = Port.list() ++ gen_tcp_sockets() ++ gen_udp_sockets()

    sockets = for port <- sockets, info = socket_info(port), show_socket?(info, search), do: info

    count = length(sockets)
    sockets = sockets |> Enum.sort_by(&Keyword.fetch!(&1, sort_by), sorter) |> Enum.take(limit)
    {sockets, count}
  end

  def socket_info_callback(port) do
    case socket_info(port) do
      nil ->
        :error

      info ->
        {:ok,
         info
         |> Keyword.update!(:connected, &pid_or_port_details/1)}
    end
  end

  defp gen_tcp_sockets() do
    if function_exported?(:gen_tcp_socket, :which_sockets, 0) do
      apply(:gen_tcp_socket, :which_sockets, [])
    else
      []
    end
  end

  defp gen_udp_sockets() do
    if function_exported?(:gen_udp_socket, :which_sockets, 0) do
      apply(:gen_udp_socket, :which_sockets, [])
    else
      []
    end
  end

  defp socket_info({:"$inet", gen_socket_mod, {pid, {:"$socket", _ref}}} = socket) do
    with info when not is_nil(info) <- gen_socket_mod.info(socket),
         port <- get_socket_fd(socket, gen_socket_mod) do
      [
        module: gen_socket_mod,
        port: port,
        local_address: format_address(gen_socket_mod.sockname(socket)),
        foreign_address: format_address(gen_socket_mod.peername(socket)),
        state: format_socket_state(info[:rstates]),
        type: info[:type],
        connected: pid,
        send_oct: info[:counters][:send_oct],
        recv_oct: info[:counters][:recv_oct]
      ]
    else
      _ -> nil
    end
  end

  defp socket_info(port) do
    with info when not is_nil(info) <- Port.info(port),
         true <- info[:name] in @inet_ports,
         {:ok, stat} <- :inet.getstat(port, [:send_oct, :recv_oct]),
         {:ok, state} <- :prim_inet.getstatus(port),
         {:ok, {_, type}} <- :prim_inet.gettype(port),
         module <- inet_module_lookup(port) do
      [
        module: module,
        port: port,
        local_address: format_address(:inet.sockname(port)),
        foreign_address: format_address(:inet.peername(port)),
        state: format_socket_state(state),
        type: type,
        connected: info[:connected]
      ] ++ stat
    else
      _ -> nil
    end
  end

  defp get_socket_fd(socket, gen_socket_mod) do
    case gen_socket_mod.getopts(socket, [:fd]) do
      {:ok, [fd: fd]} -> "esock[#{fd}]"
      _ -> "esock"
    end
  end

  defp show_socket?(_info, nil), do: true

  defp show_socket?(info, search) do
    info[:local_address] =~ search || info[:foreign_address] =~ search
  end

  defp inet_module_lookup(port) do
    case :inet_db.lookup_socket(port) do
      {:ok, module} -> module
      _ -> "prim_inet"
    end
  end

  ### OS_Mon callbacks

  def os_mon_callback() do
    cpu_per_core =
      case :cpu_sup.util([:detailed, :per_cpu]) do
        {:all, 0, 0, []} -> []
        cores -> Enum.map(cores, fn {n, busy, non_b, _} -> {n, Map.new(busy ++ non_b)} end)
      end

    disk =
      case :disksup.get_disk_data() do
        [{~c"none", 0, 0}] -> []
        other -> other
      end

    %{
      cpu_avg1: :cpu_sup.avg1(),
      cpu_avg5: :cpu_sup.avg5(),
      cpu_avg15: :cpu_sup.avg15(),
      cpu_nprocs: :cpu_sup.nprocs(),
      cpu_per_core: cpu_per_core,
      disk: disk,
      system_mem: :memsup.get_system_memory_data()
    }
  end

  ### Environment info callbacks

  def env_info_callback(nil), do: nil

  def env_info_callback(keys) do
    Enum.map(keys, fn key -> {key, System.get_env(key)} end)
  end

  ## Helpers

  # The address is formatted based on the implementation of `:inet.fmt_addr/2`
  defp format_address({:error, :enotconn}), do: "*:*"
  defp format_address({:error, _}), do: " "

  defp format_address({:ok, address}) do
    case address do
      {{0, 0, 0, 0}, port} -> "*:#{port}"
      {{0, 0, 0, 0, 0, 0, 0, 0}, port} -> "*:#{port}"
      {{127, 0, 0, 1}, port} -> "localhost:#{port}"
      {{0, 0, 0, 0, 0, 0, 0, 1}, port} -> "localhost:#{port}"
      {:local, path} -> "local:#{path}"
      {ip, port} -> "#{:inet.ntoa(ip)}:#{port}"
    end
  end

  # See `:inet.fmt_status`
  defp format_socket_state(flags) do
    case Enum.sort(flags) do
      [:accepting | _] -> "ACCEPTING"
      [:bound, :busy, :connected | _] -> "BUSY"
      [:bound, :connected | _] -> "CONNECTED"
      [:bound, :listen, :listening | _] -> "LISTENING"
      [:bound, :listen | _] -> "LISTEN"
      [:bound, :connecting | _] -> "CONNECTING"
      [:bound, :open] -> "BOUND"
      [:bound, :selected] -> "CONNECTED"
      [:connected, :open] -> "CONNECTED"
      [:open] -> "IDLE"
      [] -> "CLOSED"
      sorted -> inspect(sorted)
    end
  end

  defp sort_dir_multiplier(:asc), do: 1
  defp sort_dir_multiplier(:desc), do: -1

  defp pid_or_port_details(pid) when is_pid(pid), do: to_process_details(pid)
  defp pid_or_port_details(name) when is_atom(name), do: to_process_details(name)
  defp pid_or_port_details(port) when is_port(port), do: to_port_details(port)
  defp pid_or_port_details(reference) when is_reference(reference), do: reference

  def to_process_details(pid) when is_pid(pid) and node(pid) == node() do
    {name, initial_call} =
      case Process.info(pid, [:initial_call, :dictionary, :registered_name]) do
        [{:initial_call, initial_call}, {:dictionary, dictionary}, {:registered_name, name}] ->
          initial_call = Keyword.get(dictionary, :"$initial_call", initial_call)

          name =
            format_registered_name(name) ||
              format_process_label(Keyword.get(dictionary, :"$process_label")) ||
              format_initial_call(initial_call)

          {name, initial_call}

        _ ->
          {nil, nil}
      end

    %ProcessDetails{pid: pid, name_or_initial_call: name, initial_call: initial_call}
  end

  def to_process_details(pid) when is_pid(pid) do
    %ProcessDetails{pid: pid, name_or_initial_call: nil, initial_call: nil}
  end

  def to_process_details(name) when is_atom(name) do
    Process.whereis(name)
    |> to_process_details()
  end

  defp format_process_label(nil), do: nil
  defp format_process_label(label) when is_binary(label), do: label
  defp format_process_label(label), do: inspect(label)

  defp format_registered_name([]), do: nil
  defp format_registered_name(name), do: inspect(name)

  defp format_initial_call({:supervisor, mod, arity}), do: Exception.format_mfa(mod, :init, arity)
  defp format_initial_call({m, f, a}), do: Exception.format_mfa(m, f, a)
  defp format_initial_call(nil), do: nil

  def to_port_details(port) when is_port(port) do
    description =
      case Port.info(port, :name) do
        {:name, name} -> name
        _ -> port
      end

    %PortDetails{port: port, description: description}
  end
end
