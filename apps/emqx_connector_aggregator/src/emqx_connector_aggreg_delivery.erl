%%--------------------------------------------------------------------
%% Copyright (c) 2022-2024 EMQ Technologies Co., Ltd. All Rights Reserved.
%%--------------------------------------------------------------------

%% This module takes aggregated records from a buffer and delivers them to a blob storage
%% backend, wrapped in a configurable container (though currently there's only CSV).
-module(emqx_connector_aggreg_delivery).

-include_lib("snabbkaffe/include/trace.hrl").
-include("emqx_connector_aggregator.hrl").

-export([start_link/3]).

%% Internal exports
-export([
    init/4,
    loop/3
]).

%% Sys
-export([
    system_continue/3,
    system_terminate/4,
    format_status/2
]).

-record(delivery, {
    name :: _Name,
    callback_module :: module(),
    container :: emqx_connector_aggreg_csv:container(),
    reader :: emqx_connector_aggreg_buffer:reader(),
    transfer :: transfer_state(),
    empty :: boolean()
}).

-type state() :: #delivery{}.

-type init_opts() :: #{
    callback_module := module(),
    any() => term()
}.

-type transfer_state() :: term().

-callback init_transfer_state(buffer_map(), map()) -> transfer_state().

-callback process_append(iodata(), transfer_state()) -> transfer_state().

-callback process_write(transfer_state()) -> {ok, transfer_state()} | {error, term()}.

-callback process_complete(transfer_state()) -> {ok, term()}.

%%

start_link(Name, Buffer, Opts) ->
    proc_lib:start_link(?MODULE, init, [self(), Name, Buffer, Opts]).

%%

-spec init(pid(), _Name, buffer(), init_opts()) -> no_return().
init(Parent, Name, Buffer, Opts) ->
    ?tp(connector_aggreg_delivery_started, #{action => Name, buffer => Buffer}),
    Reader = open_buffer(Buffer),
    Delivery = init_delivery(Name, Reader, Buffer, Opts#{action => Name}),
    _ = erlang:process_flag(trap_exit, true),
    ok = proc_lib:init_ack({ok, self()}),
    loop(Delivery, Parent, []).

init_delivery(
    Name,
    Reader,
    Buffer,
    Opts = #{
        container := ContainerOpts,
        callback_module := Mod
    }
) ->
    BufferMap = emqx_connector_aggregator:buffer_to_map(Buffer),
    #delivery{
        name = Name,
        callback_module = Mod,
        container = mk_container(ContainerOpts),
        reader = Reader,
        transfer = Mod:init_transfer_state(BufferMap, Opts),
        empty = true
    }.

open_buffer(#buffer{filename = Filename}) ->
    case file:open(Filename, [read, binary, raw]) of
        {ok, FD} ->
            {_Meta, Reader} = emqx_connector_aggreg_buffer:new_reader(FD),
            Reader;
        {error, Reason} ->
            error({buffer_open_failed, Reason})
    end.

mk_container(#{type := csv, column_order := OrderOpt}) ->
    %% TODO: Deduplicate?
    ColumnOrder = lists:map(fun emqx_utils_conv:bin/1, OrderOpt),
    emqx_connector_aggreg_csv:new(#{column_order => ColumnOrder}).

%%

-spec loop(state(), pid(), [sys:debug_option()]) -> no_return().
loop(Delivery, Parent, Debug) ->
    %% NOTE: This function is mocked in tests.
    receive
        Msg -> handle_msg(Msg, Delivery, Parent, Debug)
    after 0 ->
        process_delivery(Delivery, Parent, Debug)
    end.

process_delivery(Delivery0 = #delivery{reader = Reader0}, Parent, Debug) ->
    case emqx_connector_aggreg_buffer:read(Reader0) of
        {Records = [#{} | _], Reader} ->
            Delivery1 = Delivery0#delivery{reader = Reader},
            Delivery2 = process_append_records(Records, Delivery1),
            Delivery = process_write(Delivery2),
            ?MODULE:loop(Delivery, Parent, Debug);
        {[], Reader} ->
            Delivery = Delivery0#delivery{reader = Reader},
            ?MODULE:loop(Delivery, Parent, Debug);
        eof ->
            process_complete(Delivery0);
        {Unexpected, _Reader} ->
            exit({buffer_unexpected_record, Unexpected})
    end.

process_append_records(
    Records,
    Delivery = #delivery{
        callback_module = Mod,
        container = Container0,
        transfer = Transfer0
    }
) ->
    {Writes, Container} = emqx_connector_aggreg_csv:fill(Records, Container0),
    Transfer = Mod:process_append(Writes, Transfer0),
    Delivery#delivery{
        container = Container,
        transfer = Transfer,
        empty = false
    }.

process_write(Delivery = #delivery{callback_module = Mod, transfer = Transfer0}) ->
    case Mod:process_write(Transfer0) of
        {ok, Transfer} ->
            Delivery#delivery{transfer = Transfer};
        {error, Reason} ->
            %% Todo: handle more gracefully?  Retry?
            error({transfer_failed, Reason})
    end.

process_complete(#delivery{name = Name, empty = true}) ->
    ?tp(connector_aggreg_delivery_completed, #{action => Name, transfer => empty}),
    exit({shutdown, {skipped, empty}});
process_complete(#delivery{
    name = Name, callback_module = Mod, container = Container, transfer = Transfer0
}) ->
    Trailer = emqx_connector_aggreg_csv:close(Container),
    Transfer = Mod:process_append(Trailer, Transfer0),
    {ok, Completed} = Mod:process_complete(Transfer),
    ?tp(connector_aggreg_delivery_completed, #{action => Name, transfer => Completed}),
    ok.

%%

handle_msg({system, From, Msg}, Delivery, Parent, Debug) ->
    sys:handle_system_msg(Msg, From, Parent, ?MODULE, Debug, Delivery);
handle_msg({'EXIT', Parent, Reason}, Delivery, Parent, Debug) ->
    system_terminate(Reason, Parent, Debug, Delivery);
handle_msg(_Msg, Delivery, Parent, Debug) ->
    ?MODULE:loop(Parent, Debug, Delivery).

-spec system_continue(pid(), [sys:debug_option()], state()) -> no_return().
system_continue(Parent, Debug, Delivery) ->
    ?MODULE:loop(Delivery, Parent, Debug).

-spec system_terminate(_Reason, pid(), [sys:debug_option()], state()) -> _.
system_terminate(_Reason, _Parent, _Debug, #delivery{callback_module = Mod, transfer = Transfer}) ->
    Mod:process_terminate(Transfer).

-spec format_status(normal, Args :: [term()]) -> _StateFormatted.
format_status(_Normal, [_PDict, _SysState, _Parent, _Debug, Delivery]) ->
    #delivery{callback_module = Mod} = Delivery,
    Delivery#delivery{
        transfer = Mod:process_format_status(Delivery#delivery.transfer)
    }.
