%%--------------------------------------------------------------------
%% Copyright (c) 2018-2025 EMQ Technologies Co., Ltd. All Rights Reserved.
%%
%% Licensed under the Apache License, Version 2.0 (the "License");
%% you may not use this file except in compliance with the License.
%% You may obtain a copy of the License at
%%
%%     http://www.apache.org/licenses/LICENSE-2.0
%%
%% Unless required by applicable law or agreed to in writing, software
%% distributed under the License is distributed on an "AS IS" BASIS,
%% WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
%% See the License for the specific language governing permissions and
%% limitations under the License.
%%--------------------------------------------------------------------

-module(emqx_access_control_metrics_sup).

-include("emqx.hrl").

-behaviour(supervisor).

-export([start_link/0]).

-export([init/1]).

start_link() ->
    supervisor:start_link({local, ?MODULE}, ?MODULE, []).

init([]) ->
    AccessControlMetrics = emqx_metrics_worker:child_spec(
        ?MODULE,
        ?ACCESS_CONTROL_METRICS_WORKER,
        [
            {'client.authenticate', [{hist, total_latency}]},
            {'client.authorize', [{hist, total_latency}]}
        ]
    ),
    {ok,
        {
            {one_for_one, 10, 100},
            [AccessControlMetrics]
        }}.
