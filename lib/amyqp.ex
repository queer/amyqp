defmodule AmyQP do
  use GenServer
  use AMQP

  def start_link(opts) do
    GenServer.start_link __MODULE__, opts, __MODULE__
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
    case Connection.open("amqp://#{opts[:username]}:#{opts[:password]}@#{opts[:host]}") do
      {:ok, conn} ->
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
        :timer.sleep 1000
        rabbitmq_connect opts
    end
  end

  def handle_info({:DOWN, _, :process, _pid, _reason}, state) do
    {:ok, chan} = rabbitmq_connect state[:opts]
    {:noreply, %{state | chan: chan}}
  end

  # Confirmation sent by the broker after registering this process as a consumer
  def handle_info({:basic_consume_ok, %{consumer_tag: consumer_tag}}, state) do
    {:noreply, state}
  end

  # Sent by the broker when the consumer is unexpectedly cancelled (such as after a queue deletion)
  def handle_info({:basic_cancel, %{consumer_tag: consumer_tag}}, state) do
    {:stop, :normal, state}
  end

  # Confirmation sent by the broker to the consumer process after a Basic.cancel
  def handle_info({:basic_cancel_ok, %{consumer_tag: consumer_tag}}, state) do
    {:noreply, state}
  end

  def handle_info({:basic_deliver, payload, %{delivery_tag: tag, redelivered: redelivered}}, state) do
    spawn fn -> consume(state, tag, redelivered, payload) end
    {:noreply, state}
  end

  defp consume(channel, tag, redelivered, payload) do
    try do
      number = String.to_integer payload
      if number <= 10 do
        Basic.ack channel, tag
        IO.puts "Consumed a #{number}."
      else
        Basic.reject channel, tag, requeue: false
        IO.puts "#{number} is too big and was rejected."
      end

    rescue
      # Requeue unless it's a redelivered message.
      # This means we will retry consuming a message once in case of exception
      # before we give up and have it moved to the error queue
      #
      # You might also want to catch :exit signal in production code.
      # Make sure you call ack, nack or reject otherwise comsumer will stop
      # receiving messages.
      exception ->
        Basic.reject channel, tag, requeue: not redelivered
        IO.puts "Error converting #{payload} to integer"
    end
  end
end
