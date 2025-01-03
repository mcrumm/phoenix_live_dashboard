defmodule Phoenix.LiveDashboard.SystemInfoTest do
  use ExUnit.Case, async: true
  alias Phoenix.LiveDashboard.SystemInfo

  describe "node_capabilities/2" do
    test "detects started applications" do
      requirements = [application: :logger, application: :non_existing_app]

      assert %{applications: [:logger]} = SystemInfo.node_capabilities(node(), requirements)
    end

    test "detects loaded modules" do
      requirements = [module: SystemInfo, module: NonExistingModule]

      assert %{modules: [SystemInfo]} = SystemInfo.node_capabilities(node(), requirements)
    end

    test "detects alive processes" do
      requirements = [process: Phoenix.LiveDashboard.DynamicSupervisor, process: NonExistingPid]

      assert %{processes: [Phoenix.LiveDashboard.DynamicSupervisor]} =
               SystemInfo.node_capabilities(node(), requirements)
    end

    test "returns if dashboard is running and module md5" do
      assert %{dashboard_running?: true, system_info: <<_::binary>>} =
               SystemInfo.node_capabilities(node(), [])
    end
  end

  describe "processes" do
    test "all with limit" do
      {processes, count, _} = SystemInfo.fetch_processes(node(), "", :memory, :asc, 5000)
      assert Enum.count(processes) == count
      {processes, count, _} = SystemInfo.fetch_processes(node(), "", :memory, :asc, 1)
      assert Enum.count(processes) == 1
      assert count > 1
    end

    test "all with search" do
      process =
        if System.otp_release() |> String.to_integer() >= 26, do: :user_drv_writer, else: :user

      {pids, _count, _} = SystemInfo.fetch_processes(node(), inspect(process), :memory, :asc, 100)

      assert [[pid, name | _]] = pids
      assert pid == {:pid, Process.whereis(process)}
      assert name == {:name_or_initial_call, inspect(process)}
    end

    if System.otp_release() |> String.to_integer() >= 27 do
      test "all with search by label" do
        {:ok, agent_pid} = Agent.start_link(fn -> Process.set_label("test label") end)

        {pids, _count, _} =
          SystemInfo.fetch_processes(node(), "test label", :memory, :asc, 100)

        assert [[pid, name | _]] = pids
        assert pid == {:pid, agent_pid}
        assert name == {:name_or_initial_call, "test label"}
      end

      test "all with search by name if both name and label are set" do
        {:ok, agent_pid} =
          Agent.start_link(fn -> Process.set_label("test label") end, name: :test_agent)

        {pids, _count, _} =
          SystemInfo.fetch_processes(node(), "test_agent", :memory, :asc, 100)

        assert [[pid, name | _]] = pids
        assert pid == {:pid, agent_pid}
        assert name == {:name_or_initial_call, ":test_agent"}
      end
    end

    test "allows previous reductions param" do
      {_pids, _count, state} =
        SystemInfo.fetch_processes(node(), ":user", :reductions_diff, :asc, 100)

      {_pids, _count, _state} =
        SystemInfo.fetch_processes(node(), ":user", :reductions_diff, :asc, 100, state)
    end

    test "info" do
      {:ok, info} = SystemInfo.fetch_process_info(Process.whereis(:user))
      assert info[:registered_name] == :user
      assert is_integer(info[:message_queue_len])

      expected =
        if System.otp_release() |> String.to_integer() >= 26,
          do: {:group, :server, 4},
          else: {:erlang, :apply, 2}

      assert info[:initial_call] == expected

      pid = Process.whereis(Phoenix.LiveDashboard.DynamicSupervisor)
      {:ok, info} = SystemInfo.fetch_process_info(pid)

      assert info[:registered_name] == Phoenix.LiveDashboard.DynamicSupervisor
      assert info[:initial_call] == {:supervisor, Supervisor.Default, 1}
    end
  end

  describe "ports" do
    test "all with limit" do
      {ports, count} = SystemInfo.fetch_ports(node(), "", :input, :asc, 100)
      assert Enum.count(ports) == count
      {ports, count} = SystemInfo.fetch_ports(node(), "", :input, :asc, 1)
      assert Enum.count(ports) == 1
      assert count > 1
    end

    test "all with search" do
      {ports, _count} = SystemInfo.fetch_ports(node(), "forker", :input, :asc, 100)
      assert [[port, name | _]] = ports
      assert port == {:port, hd(Port.list())}
      assert name == {:name, ~c"forker"}
    end

    test "info" do
      {:ok, port} = SystemInfo.fetch_port_info(hd(Port.list()))
      assert port[:name] == ~c"forker"

      connected_details = port[:connected]
      %module{pid: pid} = connected_details

      assert module == SystemInfo.ProcessDetails
      assert pid == :erlang.list_to_pid(~c"<0.0.0>")
    end
  end

  describe "ets" do
    test "all with limit" do
      {ets, count} = SystemInfo.fetch_ets(node(), "", :memory, :asc, 200)
      assert Enum.count(ets) == count
      {ets, count} = SystemInfo.fetch_ets(node(), "", :memory, :asc, 1)
      assert Enum.count(ets) == 1
      assert count > 1
    end

    test "all with search" do
      {ets, _count} = SystemInfo.fetch_ets(node(), "ac_tab", :memory, :asc, 100)
      assert [[name | _]] = ets
      assert name == {:name, ":ac_tab"}
    end

    test "info" do
      {:ok, ets} = SystemInfo.fetch_ets_info(node(), :ac_tab)
      assert ets[:name] == :ac_tab
    end
  end

  describe "sockets" do
    test "all with limit" do
      open_socket()
      open_socket()

      {sockets, count} = SystemInfo.fetch_sockets(node(), "", :send_oct, :asc, 100)
      assert Enum.count(sockets) == count
      {sockets, count} = SystemInfo.fetch_sockets(node(), "", :send_oct, :asc, 1)
      assert Enum.count(sockets) == 1
      assert count > 1
    end

    if Code.ensure_loaded?(:gen_tcp_socket) &&
         function_exported?(:gen_tcp_socket, :which_sockets, 0) do
      test "includes :gen_tcp_socket" do
        :gen_tcp.listen(0, inet_backend: :socket, ip: {127, 0, 0, 1})

        {sockets, _count} = SystemInfo.fetch_sockets(node(), "", :send_oct, :asc, 100)
        socket_mods = Enum.map(sockets, fn socket -> socket[:module] end)

        assert :gen_tcp_socket in socket_mods
      end
    end

    if Code.ensure_loaded?(:gen_udp_socket) &&
         function_exported?(:gen_udp_socket, :which_sockets, 0) do
      test "includes :gen_udp_socket" do
        :gen_udp.open(0, inet_backend: :socket, ip: {127, 0, 0, 1})

        {sockets, _count} = SystemInfo.fetch_sockets(node(), "", :send_oct, :asc, 100)
        socket_mods = Enum.map(sockets, fn socket -> socket[:module] end)

        assert :gen_udp_socket in socket_mods
      end
    end

    test "all with search" do
      open_socket()

      {[socket], _count} = SystemInfo.fetch_sockets(node(), "*:*", :send_oct, :asc, 100)
      assert socket[:foreign_address] == "*:*"
      {sockets, _count} = SystemInfo.fetch_sockets(node(), "impossible", :send_oct, :asc, 100)
      assert Enum.empty?(sockets)
    end

    defp open_socket() do
      {:ok, socket} = :gen_tcp.listen(0, ip: {127, 0, 0, 1})
      socket
    end
  end

  describe "os_mon" do
    test "gets all data" do
      assert %{
               cpu_avg1: cpu_avg1,
               cpu_avg5: cpu_avg5,
               cpu_avg15: cpu_avg15,
               cpu_nprocs: cpu_nprocs,
               cpu_per_core: cpu_per_core,
               disk: disk,
               system_mem: system_mem
             } = SystemInfo.fetch_os_mon_info(node())

      assert is_integer(cpu_avg1)
      assert is_integer(cpu_avg5)
      assert is_integer(cpu_avg15)
      assert is_integer(cpu_nprocs)
      assert is_list(cpu_per_core)
      assert is_list(disk)
      assert is_list(system_mem)
    end
  end

  describe "applications" do
    test "all with limit" do
      {applications, count} = SystemInfo.fetch_applications(node(), "", :name, :asc, 100)
      assert Enum.count(applications) == count
      {applications, count} = SystemInfo.fetch_applications(node(), "", :name, :asc, 1)
      assert Enum.count(applications) == 1
      assert count > 1
    end

    test "all with search" do
      {[application], _count} = SystemInfo.fetch_applications(node(), "stdlib", :name, :asc, 100)

      assert application[:name] == :stdlib
      assert application[:tree?] == false
      assert application[:state] == :started

      {[application], _count} = SystemInfo.fetch_applications(node(), "ex_unit", :name, :asc, 100)

      assert application[:name] == :ex_unit
      assert application[:tree?] == true
      assert application[:state] == :started

      {applications, _count} =
        SystemInfo.fetch_applications(node(), "impossible", :name, :asc, 100)

      assert applications == []
    end
  end

  describe "app tree" do
    test "returns error if there is no app or tree" do
      assert SystemInfo.fetch_app_tree(node(), :unknown) == :error
      assert SystemInfo.fetch_app_tree(node(), :stdlib) == :error
    end

    test "returns the tree for the given app" do
      assert {{:master, _, []},
              [{{:ancestor, _, []}, [{{:supervisor, _, :kernel_sup}, [_ | _]}]}]} =
               SystemInfo.fetch_app_tree(node(), :kernel)
    end
  end

  describe "fetch_memory_allocators" do
    test "handles when no max_carrier_sizes is given" do
      assert {list, max} = SystemInfo.fetch_memory_allocators(node(), nil)

      assert [
               %{name: :total, block_size: _, carrier_size: m1, max_carrier_size: m1},
               %{name: :temp_alloc, block_size: _, carrier_size: m2, max_carrier_size: m2},
               %{name: :sl_alloc, block_size: _, carrier_size: m3, max_carrier_size: m3},
               %{name: :std_alloc, block_size: _, carrier_size: m4, max_carrier_size: m4},
               %{name: :ll_alloc, block_size: _, carrier_size: m5, max_carrier_size: m5},
               %{name: :eheap_alloc, block_size: _, carrier_size: m6, max_carrier_size: m6},
               %{name: :ets_alloc, block_size: _, carrier_size: m7, max_carrier_size: m7},
               %{name: :fix_alloc, block_size: _, carrier_size: m8, max_carrier_size: m8},
               %{name: :literal_alloc, block_size: _, carrier_size: m9, max_carrier_size: m9},
               %{name: :binary_alloc, block_size: _, carrier_size: m10, max_carrier_size: m10},
               %{name: :driver_alloc, block_size: _, carrier_size: m11, max_carrier_size: m11}
             ] = list

      assert %{
               total: m1,
               temp_alloc: m2,
               sl_alloc: m3,
               std_alloc: m4,
               ll_alloc: m5,
               eheap_alloc: m6,
               ets_alloc: m7,
               fix_alloc: m8,
               literal_alloc: m9,
               binary_alloc: m10,
               driver_alloc: m11
             } == max

      for alloc <- list do
        assert is_atom(alloc[:name])
        assert is_integer(alloc[:block_size])
        assert is_integer(alloc[:carrier_size])
        assert is_integer(alloc[:max_carrier_size])
      end
    end

    test "handles max_carrier_sizes" do
      top = 999_999_999_999_999_999

      max = %{
        total: top,
        temp_alloc: top,
        sl_alloc: top,
        std_alloc: top,
        ll_alloc: top,
        eheap_alloc: top,
        ets_alloc: top,
        fix_alloc: top,
        literal_alloc: top,
        binary_alloc: top,
        driver_alloc: top
      }

      assert {list, ^max} = SystemInfo.fetch_memory_allocators(node(), max)

      assert [
               %{name: :total, block_size: _, carrier_size: _, max_carrier_size: ^top},
               %{name: :temp_alloc, block_size: _, carrier_size: _, max_carrier_size: ^top},
               %{name: :sl_alloc, block_size: _, carrier_size: _, max_carrier_size: ^top},
               %{name: :std_alloc, block_size: _, carrier_size: _, max_carrier_size: ^top},
               %{name: :ll_alloc, block_size: _, carrier_size: _, max_carrier_size: ^top},
               %{name: :eheap_alloc, block_size: _, carrier_size: _, max_carrier_size: ^top},
               %{name: :ets_alloc, block_size: _, carrier_size: _, max_carrier_size: ^top},
               %{name: :fix_alloc, block_size: _, carrier_size: _, max_carrier_size: ^top},
               %{name: :literal_alloc, block_size: _, carrier_size: _, max_carrier_size: ^top},
               %{name: :binary_alloc, block_size: _, carrier_size: _, max_carrier_size: ^top},
               %{name: :driver_alloc, block_size: _, carrier_size: _, max_carrier_size: ^top}
             ] = list
    end
  end

  describe "fetch_instrument_allocations" do
    test "works" do
      assert {:ok, {128, 0, allocs}} = SystemInfo.fetch_instrument_allocations(node())

      assert %{
               system: %{binary: binary_tuple, nif_internal: nif_tuple, port: port_tuple},
               prim_file: %{},
               tcp_inet: %{drv_internal: drv_tuple}
             } = allocs

      assert tuple_size(binary_tuple) == 18
      assert tuple_size(nif_tuple) == 18
      assert tuple_size(port_tuple) == 18
      assert tuple_size(drv_tuple) == 18
    end
  end
end
