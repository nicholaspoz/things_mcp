-module(applescript_test_ffi).
-export([timeout_stops_direct_process/0, protect/1]).

protect(Body) ->
    try Body() catch _:_ -> {error, <<"Test raised an exception; attempting fixture cleanup">>} end.

timeout_stops_direct_process() ->
    Path = filename:join("/tmp", "things-applescript-test-" ++
        binary_to_list(binary:encode_hex(crypto:strong_rand_bytes(16)))),
    try
        Script = <<"select undef, undef, undef, 1; "
                   "open my $file, '>', $ARGV[0] or die 'test file'; "
                   "print $file 'late write'; close $file;">>,
        Outcome = things_applescript_ffi:run(<<"/usr/bin/perl">>,
            [<<"-e">>, Script, unicode:characters_to_binary(Path)], 100),
        timer:sleep(1200),
        case {Outcome, filelib:is_file(Path)} of
            {{error, <<"AppleScript process timed out and was stopped; completion is uncertain">>}, false} -> {ok, nil};
            _ -> {error, <<"Timed-out direct executable continued running or did not time out">>}
        end
    after file:delete(Path) end.
