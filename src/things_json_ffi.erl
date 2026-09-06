-module(things_json_ffi).
-export([prepare/0, dispatch/2, await_callback/2, cleanup/1, auth_token/0, run/3, sleep/1]).

%% OS plumbing only. JSON payloads, callback decoding and verification live in Gleam.
prepare() ->
    try
        Root = filename:join([os:getenv("HOME"), "Library", "Caches", "things-mcp", "callbacks"]),
        ok = filelib:ensure_dir(filename:join(Root, "placeholder")),
        ok = private_directory(filename:dirname(Root)),
        ok = private_directory(Root),
        Nonce = string:lowercase(binary:encode_hex(crypto:strong_rand_bytes(16))),
        Dir = filename:join(Root, Nonce),
        ok = file:make_dir(Dir),
        ok = file:change_mode(Dir, 8#700),
        ok = private_write(filename:join(Dir, "pending"), <<>>),
        {ok, {Nonce, unicode:characters_to_binary(Dir)}}
    catch _:_ -> {error, <<"Cannot create private Things callback request directory">>} end.

private_directory(Path) ->
    case file:read_link_info(Path) of
        {ok, Info} when element(3, Info) =:= directory -> file:change_mode(Path, 8#700);
        _ -> {error, unsafe_directory}
    end.

private_write(Path, Data) ->
    case file:open(Path, [write, binary, exclusive]) of
        {ok, F} ->
            Result = case file:change_mode(Path, 8#600) of
                ok -> file:write(F, Data);
                E -> E
            end,
            file:close(F), Result;
        E -> E
    end.

auth_token() ->
    case os:getenv("THINGS_AUTH_TOKEN") of
        false ->
            Path = case os:getenv("THINGS_AUTH_TOKEN_FILE") of
                false -> filename:join([os:getenv("HOME"), ".config", "things-mcp", "auth-token"]);
                P -> P
            end,
            case file:read_file(Path) of
                {ok, Data} -> validate_token(Data);
                _ -> {error, <<"Configure THINGS_AUTH_TOKEN or ~/.config/things-mcp/auth-token before JSON updates">>}
            end;
        Value -> validate_token(unicode:characters_to_binary(Value))
    end.

validate_token(Data) ->
    try
        case unicode:characters_to_binary(Data, utf8, utf8) of
            Valid when is_binary(Valid) ->
                case string:trim(Valid) of
                    <<>> -> {error, <<"Things URL authorization token is empty">>};
                    Token -> {ok, Token}
                end;
            _ -> {error, <<"Things URL authorization token is not valid UTF-8">>}
        end
    catch _:_ -> {error, <<"Things URL authorization token is invalid">>} end.

dispatch(Dir, Url) ->
    App = case os:getenv("THINGS_CALLBACK_APP") of
        false -> filename:absname("build/ThingsCallback.app");
        P -> P
    end,
    case filelib:is_dir(App) of
        false -> {error, <<"Build the callback relay first: sh scripts/build_callback.sh">>};
        true ->
            case run(<<"/usr/bin/open">>, [<<"-g">>, unicode:characters_to_binary(App)], 10000) of
                {ok, _} -> dispatch_url(Dir, Url);
                _ -> {error, <<"Could not start the Things callback relay; no write dispatched">>}
            end
    end.

dispatch_url(Dir, Url) ->
    Path = filename:join(Dir, <<"request.url">>),
    case private_write(Path, Url) of
        ok ->
            %% Pass only the private file path in argv, never a URL containing a token.
            Script = unicode:characters_to_binary("on run argv\nopen location (read POSIX file (item 1 of argv) as «class utf8»)\nend run"),
            Outcome = run(<<"/usr/bin/osascript">>, [<<"-e">>, Script, Path], 10000),
            file:delete(Path),
            case Outcome of
                {ok, _} -> {ok, nil};
                _ -> {error, <<"Things URL dispatch failed or timed out; completion is uncertain; do not retry automatically">>}
            end;
        _ -> {error, <<"Cannot store private Things URL request; no write dispatched">>}
    end.

await_callback(Dir, Timeout) ->
    poll(filename:join(Dir, <<"result.json">>), erlang:monotonic_time(millisecond) + Timeout).
poll(Path, Deadline) ->
    case file:read_file(Path) of
        {ok, Data} -> {ok, Data};
        {error, enoent} ->
            case erlang:monotonic_time(millisecond) >= Deadline of
                true -> {error, <<"Things callback timed out; completion is uncertain; do not retry automatically">>};
                false -> timer:sleep(50), poll(Path, Deadline)
            end;
        _ -> {error, <<"Cannot read Things callback; completion is uncertain">>}
    end.

cleanup(Dir) ->
    %% Remove the pending marker first: callbacks after the deadline must be ignored.
    file:delete(filename:join(Dir, <<"pending">>)),
    file:delete(filename:join(Dir, <<"request.url">>)),
    file:delete(filename:join(Dir, <<"result.json">>)),
    file:del_dir(Dir), nil.

sleep(Ms) -> timer:sleep(Ms), nil.

%% Bound every spawned command. Never include argv/output in synthesized errors.
run(Command, Args, Timeout) ->
    try
        Port = open_port({spawn_executable, binary_to_list(Command)},
            [binary, exit_status, use_stdio, stderr_to_stdout, {args, Args}]),
        collect(Port, erlang:monotonic_time(millisecond) + Timeout, <<>>)
    catch _:_ -> {error, <<"Could not start local command">>} end.
collect(Port, Deadline, Output) ->
    Remaining = max(0, Deadline - erlang:monotonic_time(millisecond)),
    receive
        {Port, {data, Data}} when byte_size(Output) + byte_size(Data) =< 1048576 ->
            collect(Port, Deadline, <<Output/binary, Data/binary>>);
        {Port, {data, _}} -> terminate(Port), {error, <<"Local command output exceeded limit">>};
        {Port, {exit_status, 0}} -> {ok, Output};
        {Port, {exit_status, _}} -> {error, <<"Local command failed">>}
    after Remaining -> terminate(Port), {error, <<"Local command timed out">>}
    end.

terminate(Port) ->
    case erlang:port_info(Port, os_pid) of
        {os_pid, Pid} ->
            %% Stop the direct executable before dropping the port. In production
            %% these are osascript/open, not an intervening shell process.
            os:cmd("/bin/kill -KILL " ++ integer_to_list(Pid));
        undefined -> ok
    end,
    try port_close(Port) catch _:_ -> ok end.
