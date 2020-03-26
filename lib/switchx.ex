defmodule SwitchX do
  ## API ##

  @doc """
  Tells FreeSWITCH not to close the socket connection when a channel hangs up.
  Instead, it keeps the socket connection open until the last event related
  to the channel has been received by the socket client.

  Returns
  ```
    {:ok, "Lingering"}
  ```

  ## Examples

      iex> SwitchX.linger(context.conn)
      {:ok, "Lingering"}
  """
  @spec linger(conn :: Pid) :: term
  def linger(conn), do: :gen_statem.call(conn, {:linger})

  @doc """
  Reply the auth/request package from FreeSWITCH.

  Returns
  ```
    {:ok, "Accepted"} | {:error, "Denied"}
  ```

  ## Examples
      iex> SwitchX.auth(conn, "ClueCon")
      {:ok, "Accepted"}

      iex> SwitchX.auth(conn, "Incorrect")
      {:error, "Denied"}
  """
  @spec auth(conn :: Pid, password :: String) :: {:ok, term} | {:error, term}
  def auth(conn, password), do: :gen_statem.call(conn, {:auth, password})

  @doc """
  Send a FreeSWITCH API command.

  Returns
  ```
    {:ok, term}
  ```

  ## Examples

      iex> SwitchX.api(
            conn,
            "uuid_getvar a1024ff5-a5b3-4c0a-abd3-fd4a89508b5b current_application"
           )
      %SwitchX.Event{
        body: "park",
        headers: %{"Content-Length" => "4", "Content-Type" => "api/response"}
      }
  """
  @spec api(conn :: Pid, args :: String) :: {:ok, term}
  def api(conn, args), do: :gen_statem.call(conn, {:api, args})

  @doc """
  Enable or disable events by class or all.

  Returns
  ```
    :ok
  ```

  ## Examples

      iex> SwitchX.listen_event(conn, "BACKGROUND_JOB")
      :ok
  """
  @spec listen_event(conn :: Pid, event_name :: String) :: :ok
  def listen_event(conn, event_name), do: :gen_statem.call(conn, {:listen_event, event_name})

  @doc """
  Send an event into the event system (multi line input for headers).
  ```
  sendevent <event-name>
  <headers>

  <body>
  ```

  Returns
  ```
    {:ok, term}
  ```

  ## Examples

      iex>  event_headers =
        SwitchX.Event.Headers.new(%{
          "profile": "external",
        })
      event = SwitchX.Event.new(event_headers, "")
      SwitchX.send_event(conn, "SEND_INFO", event)
      {:ok, response}
  """
  @spec send_event(conn :: Pid, event_name :: String, event :: SwitchX.Event) :: {:ok, term}
  def send_event(conn, event_name, event) do
    send_event(conn, event_name, event, nil)
  end

  @spec send_event(
          conn :: Pid,
          event_name :: String,
          event :: SwitchX.Event,
          event_uuid :: String
        ) :: :ok | :error
  def send_event(conn, event_name, event, event_uuid) do
    :gen_statem.call(conn, {:sendevent, event_name, event, event_uuid})
  end

  @doc """
  sendmsg is used to control the behavior of FreeSWITCH.
  UUID is mandatory when conn is inbound mode, and it refers to a specific call
  (i.e., a channel or call leg or session).

  Returns a payload with an command/reply event

  ## Examples

      iex> message = SwitchX.Event.Headers.new(%{
          "call-command": "hangup",
          "hangup-cause": "NORMAL_CLEARING",
        }) |> SwitchX.Event.new()

        SwitchX.send_message(conn, uuid, message)
        {:ok, event}
  """
  @spec send_message(conn :: Pid, uuid :: String, event :: SwitchX.Event) :: {:ok, term}
  def send_message(conn, uuid, event) when is_binary(uuid) do
    :gen_statem.call(conn, {:sendmsg, uuid, event})
  end

  @spec send_message(conn :: Pid, event :: SwitchX.Event) :: {:ok, term}
  def send_message(conn, event) do
    :gen_statem.call(conn, {:sendmsg, event})
  end

  @doc """
  execute is used to invoke dialplan applications,

  ## Examples

      iex> SwitchX.execute(conn, uuid, "playback", "ivr/ivr-welcome_to_freeswitch.wav")
  """
  @spec execute(conn :: Pid, uuid :: String, application :: String, args :: String) ::
          event :: SwitchX.Event
  def execute(conn, uuid, application, args) do
    execute(conn, uuid, application, args, SwitchX.Event.new())
  end

  @spec execute(
          conn :: Pid,
          uuid :: String,
          application :: String,
          args :: String,
          event :: SwitchX.Event
        ) :: event :: SwitchX.Event
  def execute(conn, uuid, application, arg, event) do
    event = put_in(event.headers, Map.put(event.headers, "call-command", "execute"))
    event = put_in(event.headers, Map.put(event.headers, "execute-app-name", application))
    event = put_in(event.headers, Map.put(event.headers, "execute-app-arg", arg))
    event = put_in(event.headers, Map.put(event.headers, "execute-app-arg", arg))
    event = put_in(event.headers, Map.put(event.headers, "Event-UUID", UUID.uuid4()))
    send_message(conn, uuid, event)
  end

  @doc """
  The 'myevents' subscription allows your socket to receive all related events from a outbound socket session
  """
  @spec my_events(conn :: Pid) :: :ok | {:error, term}
  def my_events(conn), do: my_events(conn, nil)

  @doc """
  The 'myevents' subscription allows your inbound socket connection to behave like an outbound socket connect.
  It will "lock on" to the events for a particular uuid and will ignore all other events
  """
  @spec my_events(conn :: Pid, uuid :: String) :: :ok | {:error, term}
  def my_events(conn, uuid), do: :gen_statem.call(conn, {:myevents, uuid})

  def originate(conn, aleg, bleg, :expand) do
    perform_originate(conn, "expand originate #{aleg} #{bleg}")
  end

  def originate(conn, aleg, bleg) do
    perform_originate(conn, "originate #{aleg} #{bleg}")
  end

  defp perform_originate(conn, command) do
    {:ok, response} = api(conn, command)

    parsed_body =
      response.body
      |> String.trim("\n")
      |> String.split(" ", parts: 2)

    case parsed_body do
      ["-ERR", term] -> {:error, term}
      ["+OK", uuid] -> {:ok, uuid}
      _ -> {:error, :unknown}
    end
  end
end
