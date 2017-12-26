# Amyqp

**TODO: Add description**

## Installation

Add `amyqp` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:amyqp, github: "queer/amyqp"}
  ]
end
```

## Configuration

```Elixir
%{
  exchange: "",
  queue: "",
  queue_error: "",
  username: "",
  password: "",
  host: "",
  client_pid: "whatever",
}
```

The client pid needs to be able to `handle_info` messages of the form `{:msg, payload, redelivered, tag}`