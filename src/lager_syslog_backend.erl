%% Copyright (c) 2011 Basho Technologies, Inc.  All Rights Reserved.
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

-record(state, {server, ident, facility, level}).

-include_lib("lager/include/lager.hrl").

%% @private
init(Config) ->
    ok = ensure_running_syslog(Config),
    Level = proplists:get_value(level, Config, info),
    {ok, #state{server   = proplists:get_value(name, Config, syslog),
                ident    = proplists:get_value(ident, Config, node()),
                facility = proplists:get_value(facility, Config, local0),
                level    = lager_util:level_to_num(Level)}}.


%% @private
handle_call(get_loglevel, #state{level=Level} = State) ->
    {ok, Level, State};
handle_call({set_loglevel, Level}, State) ->
    {ok, ok, State#state{level=lager_util:level_to_num(Level)}};
handle_call(_Request, State) ->
    {ok, ok, State}.

%% @private
handle_event({log, Level, {_Date, _Time}, [_LevelStr, _Location, Message]}, State) ->
    %% @todo maybe include Location info in logged message?
    syslog:send(State#state.server, Message,
                [{ident, State#state.ident},
                 {facility, State#state.facility},
                 {level, convert_level(Level)}]),
    {ok, State};
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
