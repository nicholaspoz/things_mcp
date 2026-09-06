-module(transport_test_ffi).
-export([invalid_token_is_sanitized/0, timeout_stops_direct_process/0]).

temporary_path() ->
    filename:join("/tmp", "things-transport-test-" ++
        binary_to_list(binary:encode_hex(crypto:strong_rand_bytes(16)))).

%% Run token validation in an isolated VM with explicit synthetic configuration.
%% Never inspect or modify the test runner's actual authorization environment.
invalid_token_is_sanitized() ->
    Path = temporary_path(),
    try
        ok = file:write_file(Path, <<"synthetic-secret", 255>>),
        BeamDirectory = filename:dirname(code:which(things_json_ffi)),
        Erl = os:find_executable("erl"),
        Check = <<"case things_json_ffi:auth_token() of "
                  "{error, <<\"Things URL authorization token is not valid UTF-8\">>} -> halt(0); "
                  "_ -> halt(1) end.">>,
        case things_json_ffi:run(<<"/usr/bin/env">>,
            [<<"-u">>, <<"THINGS_AUTH_TOKEN">>,
             unicode:characters_to_binary("THINGS_AUTH_TOKEN_FILE=" ++ Path),
             unicode:characters_to_binary(Erl), <<"+S">>, <<"1:1">>, <<"-noshell">>,
             <<"-pa">>, unicode:characters_to_binary(BeamDirectory), <<"-eval">>, Check], 3000) of
            {ok, <<>>} -> {ok, nil};
            _ -> {error, <<"Isolated token validation did not return the expected sanitized error">>}
        end
    after file:delete(Path) end.

%% Use the system Perl executable directly: no shell descendants or macOS
%% application services, and no Things application is contacted.
timeout_stops_direct_process() ->
    Path = temporary_path(),
    try
        Script = <<"select undef, undef, undef, 1; "
                   "open my $file, '>', $ARGV[0] or die 'test file'; "
                   "print $file 'late write'; close $file;">>,
        Outcome = things_json_ffi:run(<<"/usr/bin/perl">>,
            [<<"-e">>, Script, unicode:characters_to_binary(Path)], 100),
        timer:sleep(1200),
        case {Outcome, filelib:is_file(Path)} of
            {{error, <<"Local command timed out">>}, false} -> {ok, nil};
            _ -> {error, <<"Timed-out direct executable continued running or did not time out">>}
        end
    after file:delete(Path) end.
