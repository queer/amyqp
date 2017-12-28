defmodule AmyQP do
  use GenServer
  use AMQP

  def start_link(opts) do
    GenServer.start_link __MODULE__, opts, name: __MODULE__
  end

  # Config
  # %{
  #   exchange: "",
  #   queue: "",
  #   queue_error: "",
  #   username: "",
  #   password: "",
  #   host: "",
  #   client_pid: "whatever",
  # }

  def init(opts) do
    {:ok, chan} = rabbitmq_connect opts
    state = %{
      opts: opts,
      chan: chan,
    }

    {:ok, state}
  end

  defp rabbitmq_connect(opts) do
    Logger.info "Connecting to RMQ..."
    case Connection.open("amqp://#{opts[:username]}:#{opts[:password]}@#{opts[:host]}") do
      {:ok, conn} ->
        Logger.info "OK!"
        # Get notifications when the connection goes down
        Process.monitor conn.pid

        {:ok, chan} = Channel.open conn
        Basic.qos chan, prefetch_count: 10
        Queue.declare chan, opts[:queue_error], durable: true
        Queue.declare chan, opts[:queue], durable: true,
                                    arguments: [{"x-dead-letter-exchange", :longstr, ""},
                                                {"x-dead-letter-routing-key", :longstr, opts[:queue_error]}]

        Exchange.fanout chan, opts[:exchange], durable: true
        Queue.bind chan, opts[:queue], opts[:exchange]
        {:ok, _consumer_tag} = Basic.consume chan, opts[:queue]
        {:ok, chan}
      {:error, _} ->
        # Reconnection loop
        Logger.info "Can't connect, retrying..."
        :timer.sleep 1000
        rabbitmq_connect opts
    end
  end

  # Handle sending messages to the queue
  def handle_info({:dispatch, message}, state) do
    output_msg = unless is_binary message do
      message |> Poison.encode!
    else
      message
    end
    Basic.publish state[:chan], state[:opts][:exchange], state[:opts][:queue], output_msg
    {:noreply, state}
  end

  def handle_info({:DOWN, _, :process, _pid, _reason}, state) do
    {:ok, chan} = rabbitmq_connect state[:opts]
    {:noreply, %{state | chan: chan}}
  end

  # Confirmation sent by the broker after registering this process as a consumer
  def handle_info({:basic_consume_ok, %{consumer_tag: _consumer_tag}}, state) do
    {:noreply, state}
  end

  # Sent by the broker when the consumer is unexpectedly cancelled (such as after a queue deletion)
  def handle_info({:basic_cancel, %{consumer_tag: _consumer_tag}}, state) do
    {:stop, :normal, state}
  end

  # Confirmation sent by the broker to the consumer process after a Basic.cancel
  def handle_info({:basic_cancel_ok, %{consumer_tag: _consumer_tag}}, state) do
    {:noreply, state}
  end

  def handle_info({:basic_deliver, payload, %{delivery_tag: tag, redelivered: redelivered}} = _meta, state) do
    #spawn fn -> consume(state, tag, redelivered, payload) end
    send state[:opts][:client_pid], {:msg, payload, redelivered, tag}
    {:noreply, state}
  end
end
