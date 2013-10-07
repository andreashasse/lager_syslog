%% Copyright (c) 2011-2012 Basho Technologies, Inc.  All Rights Reserved.
%%
%% This file is provided to you under the Apache License,
%% Version 2.0 (the "License"); you may not use this file
%% except in compliance with the License.  You may obtain
%% a copy of the License at
%%
%%   http://www.apache.org/licenses/LICENSE-2.0
%%
%% Unless required by applicable law or agreed to in writing,
%% software distributed under the License is distributed on an
%% "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
%% KIND, either express or implied.  See the License for the
%% specific language governing permissions and limitations
%% under the License.

%% @doc Syslog backend for lager.

-module(lager_syslog_backend).

-behaviour(gen_event).

-export([init/1, handle_call/2, handle_event/2, handle_info/2, terminate/2,
        code_change/3]).

-record(state, {ident, facility, host, server, level,
                handle, id}).

-include_lib("lager/include/lager.hrl").

init(Config) ->
    ok = ensure_running_syslog(Config),
    {ok, Host} = inet:gethostname(),
    Level = proplists:get_value(level, Config, info),
    {ok, #state{server   = proplists:get_value(name, Config, syslog),
                host     = proplists:get_value(host, Config, Host),
                ident    = proplists:get_value(ident, Config, node()),
                facility = proplists:get_value(facility, Config, local0),
                level    = parse_level(Level)}}.

%% @private
handle_call(get_loglevel, #state{level=Level} = State) ->
    {ok, Level, State};
handle_call({set_loglevel, Level}, State) ->
    try parse_level(Level) of
        Lvl ->
            {ok, ok, State#state{level=Lvl}}
    catch
        _:_ ->
            {ok, {error, bad_log_level}, State}
    end;
handle_call(_Request, State) ->
    {ok, ok, State}.

%% @private
handle_event({log, Level, {_Date, _Time}, [_LevelStr, Location, Message]},
             #state{level = LogLevel} = State)
  when Level =< LogLevel ->
    syslog:send(State#state.server, [Location, Message],
                [{host, State#state.host},
                 {ident, State#state.ident},
                 {facility, State#state.facility},
                 {level, convert_level(Level)}]),
    {ok, State};
handle_event({log, Message}, #state{level=Level} = State) ->
    PidList = maybe_pid_to_list(
                proplists:get_value(pid, lager_msg:metadata(Message))),
    case lager_util:is_loggable(Message, Level, State#state.id) of
        true ->
            syslog:send(State#state.server,
                        [PidList, lager_msg:message(Message)],
                        [{host, State#state.host},
                         {ident, State#state.ident},
                         {facility, State#state.facility},
                         {level, lager_msg:severity(Message)}
                        ]),
            {ok, State};
        false ->
            {ok, State}
    end;
handle_event(_Event, State) ->
    {ok, State}.

%% @private
handle_info(_Info, State) ->
    {ok, State}.

%% @private
terminate(_Reason, _State) ->
    ok.

%% @private
code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

ensure_running_syslog(Config) ->
    Name = proplists:get_value(name, Config, syslog),
    case whereis(Name) of
        undefined ->
            {ok, _Pid} =
                syslog:start_link(
                    Name,
                    proplists:get_value(ip, Config),
                    proplists:get_value(port, Config)),
            ok;
        Pid when is_pid(Pid) ->
            ok
    end.

convert_level(?DEBUG) -> debug;
convert_level(?INFO) -> info;
convert_level(?NOTICE) -> notice;
convert_level(?WARNING) -> warning;
convert_level(?ERROR) -> err;
convert_level(?CRITICAL) -> crit;
convert_level(?ALERT) -> alert;
convert_level(?EMERGENCY) -> emergency.

parse_level(Level) ->
    try lager_util:config_to_mask(Level) of
        Res ->
            Res
    catch
        error:undef ->
            %% must be lager < 2.0
            lager_util:level_to_num(Level)
    end.

maybe_pid_to_list(undefined) -> "";
maybe_pid_to_list(Pid) when is_list(Pid)-> Pid;
maybe_pid_to_list(Pid) when is_pid(Pid)-> pid_to_list(Pid).
