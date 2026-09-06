-module(things_applescript_ffi).
-export([run/3, sleep/1]).

sleep(Ms) -> timer:sleep(Ms), nil.

%% No shell between the VM and osascript. Never retry a write.
run(Command, Args, Timeout) ->
    try
        Port = open_port({spawn_executable, binary_to_list(Command)},
            [binary, exit_status, use_stdio, stderr_to_stdout, {args, Args}]),
        collect(Port, erlang:monotonic_time(millisecond) + Timeout, <<>>)
    catch _:_ -> {error, <<"AppleScript process could not start; no command dispatched">>} end.

collect(Port, Deadline, Output) ->
    Remaining = max(0, Deadline - erlang:monotonic_time(millisecond)),
    receive
        {Port, {data, Data}} when byte_size(Output) + byte_size(Data) =< 1048576 ->
            collect(Port, Deadline, <<Output/binary, Data/binary>>);
        {Port, {data, _}} ->
            terminate(Port),
            {error, <<"AppleScript process output exceeded 1 MiB; completion is uncertain">>};
        {Port, {exit_status, 0}} -> {ok, Output};
        {Port, {exit_status, Code}} -> {error, diagnostic(Code, Output)}
    after Remaining ->
        terminate(Port),
        {error, <<"AppleScript process timed out and was stopped; completion is uncertain">>}
    end.

terminate(Port) ->
    case erlang:port_info(Port, os_pid) of
        {os_pid, Pid} ->
            %% Closing an Erlang port alone does not stop its OS process. Kill
            %% the direct executable; already delivered Apple events may finish.
            os:cmd("/bin/kill -KILL " ++ integer_to_list(Pid));
        undefined -> ok
    end,
    try port_close(Port) catch _:_ -> ok end.

%% Raw osascript errors may echo entire notes, names, URLs, or source literals.
%% Retain exit/AppleScript codes and safe explanations, never echoed user data.
diagnostic(Exit, Output) ->
    Prefix = <<"AppleScript execution failed (exit ", (integer_to_binary(Exit))/binary>>,
    case re:run(Output, <<"\\((-?[0-9]+)\\)\\s*$">>, [{capture, [1], binary}]) of
        {match, [Code]} ->
            Detail = explanation(Code),
            <<Prefix/binary, ", AppleScript code ", Code/binary, "): ", Detail/binary>>;
        nomatch -> <<Prefix/binary, "); diagnostic text omitted to protect item contents">>
    end.

explanation(<<"-1728">>) -> <<"Object not found; check the item or destination ID">>;
explanation(<<"-1700">>) -> <<"Value cannot be converted to the required property type">>;
explanation(<<"-1743">>) -> <<"Automation permission denied; allow access to Things in macOS Privacy & Security">>;
explanation(<<"-1712">>) -> <<"Apple event timed out; Things may still finish the operation">>;
explanation(<<"-600">>) -> <<"Application is not running">>;
explanation(<<"-10810">>) -> <<"Application could not be launched">>;
explanation(<<"-2740">>) -> <<"AppleScript syntax error">>;
explanation(<<"-2741">>) -> <<"AppleScript syntax error">>;
explanation(<<"-10006">>) -> <<"Property cannot be set by this operation">>;
explanation(<<"-10000">>) -> <<"Things rejected the Apple event">>;
explanation(<<"301">>) -> <<"Things rejected the operation for this item or destination; check its status and target list">>;
explanation(_) -> <<"AppleScript reported an error; echoed item contents omitted">>.
